#!/usr/bin/env bash
# Installs App.app on an iPhone simulator, launches it and checks that it is
# still running after start-up. Usage: ios-simulator-test.sh <App.app> <bundle-id> <out-dir>
set -uo pipefail
app="$1"; bundle="$2"; out="$3"
mkdir -p "$out"
udid=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    if "iOS" in runtime:
        for d in devices[runtime]:
            if d["name"].startswith("iPhone"):
                print(d["udid"]); sys.exit(0)
sys.exit(1)')
[ -n "$udid" ] || { echo "::error::No iPhone simulator available"; exit 1; }
echo "Simulator: $(xcrun simctl list devices | grep "$udid")"
xcrun simctl boot "$udid" 2> /dev/null || true
xcrun simctl bootstatus "$udid" -b > /dev/null
xcrun simctl install "$udid" "$app"
xcrun simctl launch "$udid" "$bundle"
sleep 20
xcrun simctl io "$udid" screenshot "$out/simulator-$bundle.png" > /dev/null
xcrun simctl spawn "$udid" log show --last 3m --style compact --predicate 'process == "App"' > "$out/simulator-$bundle.log" 2>&1 || true
if xcrun simctl spawn "$udid" launchctl list | grep -q "UIKitApplication:$bundle"; then
  echo "$bundle is running on the simulator"
else
  echo "::error::$bundle is not running 20 s after launch"
  grep -iE "fault|crash|error" "$out/simulator-$bundle.log" | tail -40
  exit 1
fi
