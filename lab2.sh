#!/bin/bash
# Test CHANGE_MODE (switchPortForLog). Output: ~/zte_web/out2.txt
M=http://192.168.0.1; H="Referer: $M/index.html"; C=$(mktemp); OUT=~/zte_web/out2.txt
MODE=${MODE:-1}
[ -z "$PW" ] && { read -s -p "Admin password: " PW; echo; }
exec > >(tee "$OUT") 2>&1
usb(){ system_profiler SPUSBDataType 2>/dev/null | grep -B2 -A14 -i -E "zte|mobile broadband|19d2" ; }
echo "== $(date)  change_mode=$MODE"
R=$(curl -s -m 10 -c $C -b $C -H "$H" --data-urlencode "isTest=false" --data-urlencode "goformId=LOGIN" --data-urlencode "password=$(printf %s "$PW" | base64)" $M/goform/goform_set_cmd_process); echo "login: $R"
case "$R" in *'"0"'*|*'"4"'*) ;; *) echo "LOGIN FAILED - stopping"; exit 1;; esac
echo "== USB BEFORE"; usb
echo "== adb BEFORE"; adb devices 2>&1
echo "== CHANGE_MODE"; curl -s -m 10 -b $C -H "$H" --data-urlencode "isTest=false" --data-urlencode "goformId=CHANGE_MODE" --data-urlencode "change_mode=$MODE" $M/goform/goform_set_cmd_process; echo
echo "waiting 20s for USB to re-enumerate..."; sleep 20
echo "== USB AFTER"; usb
echo "== adb AFTER"; adb devices 2>&1
echo "== serial ports"; ls /dev/cu.* /dev/tty.usb* 2>/dev/null
echo "== en6"; ifconfig en6 2>&1 | head -5
echo "== web still reachable?"; curl -s -m 5 -H "$H" "$M/goform/goform_get_cmd_process?isTest=false&cmd=wa_inner_version"; echo
echo "== done"; rm -f $C
