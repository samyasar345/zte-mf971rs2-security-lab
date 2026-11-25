#!/bin/bash
# ZTE MF971RS2 lab tests. Output goes to ~/zte_web/out.txt
M=http://192.168.0.1; H="Referer: $M/index.html"; C=$(mktemp); OUT=~/zte_web/out.txt
get(){ curl -s -m 10 -b $C -H "$H" "$M/goform/goform_get_cmd_process?isTest=false&multi_data=1&cmd=$1"; echo; }
set_(){ curl -s -m 10 -b $C -H "$H" --data-urlencode "isTest=false" "$@" $M/goform/goform_set_cmd_process; echo; }
[ -z "$PW" ] && { read -s -p "Admin password: " PW; echo; }
exec > >(tee "$OUT") 2>&1
echo "== $(date)"
echo "== attempts left"; get psw_fail_num_str,login_lock_time
echo "== login"; R=$(curl -s -m 10 -c $C -b $C -H "$H" --data-urlencode "isTest=false" --data-urlencode "goformId=LOGIN" --data-urlencode "password=$(printf %s "$PW" | base64)" $M/goform/goform_set_cmd_process); echo "$R"
case "$R" in *'"0"'*|*'"4"'*) ;; *) echo "LOGIN FAILED - stopping"; exit 1;; esac
echo "== loginfo"; get loginfo
echo "== SNTP control (same values)"
set_ --data-urlencode "goformId=SNTP" --data-urlencode "manualsettime=auto" --data-urlencode "sntp_server1_ip=time.windows.com" --data-urlencode "sntp_server2_ip=pool.ntp.org" --data-urlencode "sntp_server3_ip=europe.pool.ntp.org" --data-urlencode "sntp_other_server0=" --data-urlencode "sntp_other_server1=" --data-urlencode "sntp_other_server2=" --data-urlencode "timezone=10-1" --data-urlencode "DaylightEnabled=1"
echo "== SET_NV arbitrary key test (new harmless key)"
set_ --data-urlencode "goformId=SET_NV" --data-urlencode "zz_lab_test=hello"
get zz_lab_test
set_ --data-urlencode "goformId=SET_NV" --data-urlencode "nv_name=zz_lab_test2" --data-urlencode "nv_value=hello2"
get zz_lab_test2
echo "== SYSLOG current"; get syslog_mode,debug_level
echo "== fastboot + misc reads"; get mgmt_quicken_power_on,fast_boot,usb_mode,usb_port_mode,ADB,adb_mode,telnetd,telnet_enable,debug_mode,diag_mode,wan_mode,opms_wan_mode,os_url,Product_Model
echo "== done"; rm -f $C
