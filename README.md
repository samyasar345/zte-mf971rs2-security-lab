# ZTE MF971RS2 (Optus Portable Modem) - Security Lab Notes

Hands-on security assessment of a consumer 4G mobile hotspot, done on my own device in an isolated lab.

> **Disclaimer:** All testing was carried out in a controlled lab environment, in accordance with applicable Australian laws and regulations. The device under test is my own, connected only to my own laptop over USB. No carrier network, SIM card or third-party systems were accessed or tested, and no radio transmissions were altered. This work is for educational and research purposes only. Identifiers such as the IMEI, MAC address, SSID and credentials have been redacted.

**Status:** In progress (last updated 25 Nov 2026)

---

## 1. Device

| Item | Value |
|---|---|
| Retail name | Optus Portable Modem (prepaid) |
| Manufacturer / model | ZTE MF971RS2 (revision of MF971RS) |
| Firmware (`wa_inner_version`) | `MF971RS2_T03` |
| Web UI build | August 2021 (from asset timestamps) |
| Web UI platform | ZTE "ufi/mf9xx" (jQuery, RequireJS, Knockout) |
| Web server | `WebServer-Webs` (GoAhead-style embedded server) |
| DNS / DHCP | dnsmasq 2.78 |
| Radio | LTE Cat 6, bands B1/B3/B7/B8/B28/B40 |
| Wi-Fi | 802.11ac dual band, 2x2 |
| Network lock | Locked to Optus |
| Cost | AUD 9 (clearance) |

## 2. Lab setup

- **Host:** MacBook Air (Apple Silicon, macOS)
- **Connection:** USB. macOS detects the modem natively as "ZTE Mobile Broadband" (USB network interface `en6`).
- **Modem LAN:** `192.168.0.0/24`, modem at `192.168.0.1`, host gets a DHCP lease.
- **Internet:** host stays on a separate Wi-Fi network (`192.168.1.0/24`) for tooling. The modem has no SIM and no internet.
- **Tools:** nmap, curl, tcpdump, Python 3, Homebrew

### Setup lessons learned
- **Check for subnet clashes first.** Before touching `192.168.0.1`, confirm no other network on the host uses the same range. Otherwise requests may hit the wrong router.
- **Service order matters on macOS.** With the modem higher in the network service order, the host routed all internet traffic to the modem, which has no internet, and package installs timed out. Fix: System Settings > Network > Set Service Order, with Wi-Fi above the modem. Traffic to `192.168.0.0/24` still goes over USB.
- **Login lockout is 5 attempts.** Typing the password into a hidden prompt caused a failed login. The test scripts now take the password from an environment variable and stop immediately if login fails.

## 3. Reconnaissance

### TCP (full port scan, `nmap -sS -sV -p-`)

| Port | State | Service |
|---|---|---|
| 22 | filtered | ssh |
| 23 | filtered | telnet |
| 53 | open | dnsmasq 2.78 |
| 80 | open | WebServer-Webs (HTTP only, no HTTPS) |
| 5555 | filtered | ADB over TCP (default port) |

All other ports return RST (closed). Ports 22, 23 and 5555 are silently dropped instead, which suggests specific firewall rules for services that exist in the firmware but are blocked from the LAN.

### UDP (top 50 ports)

| Port | State | Service |
|---|---|---|
| 53 | open | DNS |
| 67 | open | DHCP |

No UPnP, SNMP, TFTP or TR-069 exposed.

## 4. Web API analysis

The web UI is a single-page app that talks to two endpoints:

- `GET /goform/goform_get_cmd_process?cmd=<names>&multi_data=1` reads values by name
- `POST /goform/goform_set_cmd_process` with `goformId=<COMMAND>` performs actions

Method: downloaded the web UI JavaScript modules and templates with a small Python crawler, then read `js/service.js` (API client) and `js/config/config.js` (feature flags).

Key observations from the client code:
- **Login:** `goformId=LOGIN` with `password=Base64(password)`. `PASSWORD_ENCODE: true`, and the newer hashed scheme is not used (`LD` token is empty).
- **Request signing ("AD" token):** the code computes `AD = md5(md5(wa_inner_version + cr_version) + RD)`, but `ACCESSIBLE_ID_SUPPORT: false` on this build, so the token is not required.
- **Hidden API surface:** `service.js` exports functions with no caller in the visible UI, including `setNV` (`SET_NV`) and `switchPortForLog` (`CHANGE_MODE`).
- **Developer file shipped:** `js/simulate.js` (ZTE's offline API simulator) is served in production. It lists further command IDs, including `SYSLOG`, `setTR069Config`, `SNTP`, `URL_FILTER_ADD` and SIP/VoIP commands.

## 5. Findings

| ID | Finding | Severity (my rating) |
|---|---|---|
| F1 | Unauthenticated information disclosure | Low |
| F2 | Admin password sent Base64-encoded over plain HTTP | Medium |
| F3 | Admin password retrievable in reversible form via the API | Medium |
| F4 | Outdated dnsmasq (2.78) | Medium (exploitability not verified) |
| F5 | Developer simulation file shipped in production | Low / Informational |
| F6 | Request-signing token disabled | Low (CSRF impact not yet tested) |
| F7 | Malformed redirect `Location` header | Informational |

### F1 - Unauthenticated information disclosure
Without logging in, the read endpoint returns the IMEI, Wi-Fi SSID, firmware version, modem state, network type, the remaining login attempts and the lockout timer.
```
curl -s -H "Referer: http://192.168.0.1/index.html" \
 "http://192.168.0.1/goform/goform_get_cmd_process?isTest=false&multi_data=1&cmd=imei,SSID1,wa_inner_version,psw_fail_num_str,login_lock_time"
```
The Wi-Fi passphrase, LAN and MAC details were correctly withheld until login.

### F2 - Weak login transport
The admin password is only Base64-encoded and sent over HTTP. Anyone able to observe LAN traffic, for example another client on the hotspot's Wi-Fi, can recover it trivially.

### F3 - Admin password readable via the API
After login, requesting `cmd=admin_Password` returns the admin password Base64-encoded, which means it is stored in a reversible form. Combined with any CSRF or XSS issue, this would allow the credential to be stolen rather than just a session.

### F4 - Outdated dnsmasq
nmap identifies dnsmasq 2.78 (2017). Versions before 2.83 are affected by the DNSpooq vulnerabilities (CVE-2020-25681 to CVE-2020-25687). Not verified on this device; vendor backports are possible.

### F5 - `simulate.js` in production
The offline API simulator documents hidden command IDs and default values, which makes mapping the attack surface easier.

### F6 - AD token disabled
`ACCESSIBLE_ID_SUPPORT: false`. A settings change succeeded with only the session cookie. Whether the server enforces the `Referer` header (the remaining CSRF defence) has not been tested yet.

### F7 - Redirect bug
`GET /` returns `302` with `Location: http:///index.html` (empty host).

## 6. Hardening observed (things that held up)

| Test | Result |
|---|---|
| Pre-auth ADB switch (`USB_MODE_SWITCH`, `usb_mode=6`) | Rejected |
| Same, after login | Rejected |
| `SET_DEVICE_MODE`, `debug_enable=1` (after login) | Rejected |
| Command injection via `URL_FILTER_ADD` (5 payload styles, tcpdump ping canary) | Handler removed; even a benign URL is rejected |
| `SNTP` settings change (control with unchanged values) | Rejected |
| `SET_NV` raw settings write (2 parameter formats) | Rejected |
| Wi-Fi passphrase before login | Not disclosed |
| TR-069 remote management | Not configured |
| Login brute force | Locked after 5 failed attempts |
| SSH / Telnet / ADB from LAN | Firewalled |

Compared with older ZTE hotspots (MF910, MF920 series), this Optus build has removed most of the debug and injection paths that were previously public.

## 7. Next steps

- [ ] Test `CHANGE_MODE` (`switchPortForLog`) and watch for new USB interfaces (ADB, serial or diagnostic)
- [ ] Test whether the `Referer` check is enforced (CSRF)
- [ ] Look for this model's GPL source package on opensource.ztedevices.com
- [ ] Identify the SoC from the FCC ID SRQ-MF971R internal photos, or by teardown
- [ ] Hardware: locate UART pads and capture the boot log with a 3.3 V USB-to-serial adapter
- [ ] Firmware dump and analysis with binwalk (needs shell or flash access)
- [ ] Use the modem as an LTE uplink for a Raspberry Pi / pfSense network lab

## 8. Repository contents

| File | Purpose |
|---|---|
| `README.md` | These notes |
| `lab.sh` | Login, SNTP control test, `SET_NV` test, hidden setting reads |
| `lab2.sh` | `CHANGE_MODE` test with USB before/after comparison (not run yet) |

Scripts read the admin password from the `PW` environment variable or prompt for it, and never store it:
```
PW='<admin password>' bash lab.sh
```

The downloaded web UI files (`js/`, `tmpl/`) are ZTE's code and are not included in this repository.

## 9. Disclosure

These findings are on a consumer device sold in Australia. Before publishing details beyond this summary, I plan to report them to ZTE's PSIRT.
