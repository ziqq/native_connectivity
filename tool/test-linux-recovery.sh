#!/usr/bin/env bash
set -euo pipefail

# Run from example/ on a Linux runner. The test owns an isolated routing table.
namespace="native-connectivity-$$"
log=$(mktemp)
test_pid=

cleanup() {
  if [[ -n $test_pid ]] && kill -0 "$test_pid" 2>/dev/null; then
    kill "$test_pid" 2>/dev/null || true
  fi
  sudo ip netns del "$namespace" 2>/dev/null || true
  cat "$log"
  rm -f "$log"
}
trap cleanup EXIT

sudo ip netns add "$namespace"
sudo ip -n "$namespace" link set lo up
sudo ip -n "$namespace" link add nc0 type veth peer name nc1
sudo ip -n "$namespace" link set nc0 up
sudo ip -n "$namespace" link set nc1 up
sudo ip -n "$namespace" addr add 192.0.2.2/24 dev nc0

restore_route() {
  sudo ip -n "$namespace" route replace default via 192.0.2.1 dev nc0
}
restore_route

flutter precache --linux
sudo ip netns exec "$namespace" sudo -u "$(id -un)" env \
  PATH="$PATH" HOME="$HOME" GIO_USE_NETWORK_MONITOR=netlink \
  timeout 220 xvfb-run -a flutter test --no-pub --reporter=expanded -d linux \
  --dart-define=VERIFY_NETWORK_SWITCH=true integration_test/native_connectivity_test.dart >"$log" 2>&1 &
test_pid=$!

await_marker() {
  local marker=$1 deadline=$((SECONDS + 180))
  until grep -Fq "native_connectivity_test: $marker" "$log"; do
    if ! kill -0 "$test_pid" 2>/dev/null || ((SECONDS >= deadline)); then
      printf 'Expected test marker %s\n' "$marker" >&2
      return 1
    fi
    sleep 1
  done
}

await_marker disconnect
sudo ip -n "$namespace" route del default
await_marker reconnect
restore_route
wait "$test_pid"
test_pid=
