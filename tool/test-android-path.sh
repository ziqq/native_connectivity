#!/usr/bin/env bash
set -euo pipefail

device=${1:?Usage: test-android-path.sh DEVICE cold-start\|handoff}
scenario=${2:?Choose cold-start or handoff}
[[ $scenario == cold-start || $scenario == handoff ]]

if [[ $device != emulator-* ]]; then
  adb devices -l | awk -v device="$device" '$1 == device && / usb:/ { found=1 } END { exit !found }' || {
    echo 'Connect the Android device over USB.' >&2
    exit 1
  }
fi

on_device() { timeout 10 adb -s "$device" "$@"; }
setting() { on_device shell settings get global "$1" | tr -d '\r'; }
original_wifi=$(setting wifi_on)
original_data=$(setting mobile_data)
[[ $original_wifi =~ ^[01]$ && $original_data =~ ^[01]$ && $(setting airplane_mode_on) == 0 ]]
[[ $original_wifi == 1 || $original_data == 1 ]]

restore_network() {
  local wifi=disable data=disable result=0
  [[ $original_wifi == 0 ]] || wifi=enable
  [[ $original_data == 0 ]] || data=enable
  on_device shell svc wifi "$wifi" || result=1
  on_device shell svc data "$data" || result=1
  return "$result"
}

log=$(mktemp)
test_pid=
network_changed=0
cleanup() {
  if [[ -n $test_pid ]] && kill -0 "$test_pid" 2>/dev/null; then
    kill "$test_pid" 2>/dev/null || true
  fi
  if ((network_changed)); then restore_network || echo 'Could not restore Android network settings.' >&2; fi
  cat "$log"
  rm -f "$log"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

check_path() {
  on_device shell dumpsys connectivity | awk -v phase="$1" '
    /Active default network:/ { route=$NF; sub(/\r$/, "", route) }
    /NetworkAgentInfo\{network\{/ {
      id=$0; sub(/^.*NetworkAgentInfo\{network\{/, "", id); sub(/\}.*/, "", id)
      if (/Transports: WIFI/) wifi[id]=1
      if (/Transports: CELLULAR/ && /Capabilities:.*INTERNET/ && /ni\{MOBILE.* CONNECTED/) {
        mobile[id]=1; has_mobile=1
      }
    }
    END {
      if (phase == "offline") exit !(route == "none")
      if (phase == "online") exit !(route ~ /^[0-9]+$/)
      if (phase == "handoff-ready") exit !(wifi[route] && has_mobile)
      exit !mobile[route]
    }
  '
}

wait_for_path() {
  local phase=$1 deadline=$((SECONDS + 25))
  until check_path "$phase"; do
    if ((SECONDS >= deadline)); then
      printf 'Android did not reach the %s route condition.\n' "$phase" >&2
      return 1
    fi
    sleep 0.2
  done
  printf 'Verified Android route: %s\n' "$phase"
}

cd "$(dirname "$0")/../example"
if [[ $scenario == cold-start ]]; then
  wait_for_path online
  network_changed=1
  on_device shell svc data disable
  on_device shell svc wifi disable
  wait_for_path offline
  marker=restore
else
  wait_for_path handoff-ready
  marker=switch-to-cellular
fi

timeout 240 flutter test --no-pub --reporter=expanded -d "$device" \
  --dart-define="ANDROID_PATH_TEST=$scenario" integration_test/android_network_paths_test.dart > "$log" 2>&1 &
test_pid=$!

until grep -Fq "android_network_paths_test: $marker" "$log"; do
  if ! kill -0 "$test_pid" 2>/dev/null; then
    wait "$test_pid"
    printf 'Android test stopped before reaching %s.\n' "$marker" >&2
    exit 1
  fi
  sleep 0.2
done

if [[ $scenario == cold-start ]]; then
  restore_network
  wait_for_path online
else
  network_changed=1
  on_device shell svc wifi disable
  wait_for_path cellular
fi
wait "$test_pid"
test_pid=
if [[ $scenario == handoff ]]; then
  restore_network
  wait_for_path handoff-ready
fi
[[ $(setting wifi_on) == "$original_wifi" && $(setting mobile_data) == "$original_data" ]]
network_changed=0
printf 'Restored Android Wi-Fi=%s and mobile data=%s\n' "$original_wifi" "$original_data"
