#!/usr/bin/env bash
# Installs App.app on an iPhone simulator, launches it and checks that it is
# still running after start-up. With a color check it also verifies that the
# web page was rendered: <channel> (red|green|blue) must dominate in the region
# x0..x1, y0..y1 (fractions of the screenshot).
# Usage: ios-simulator-test.sh <App.app> <bundle-id> <out-dir> [<channel> <x0> <y0> <x1> <y1>]
set -uo pipefail
app="$1"; bundle="$2"; out="$3"; channel="${4:-}"
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
# Read the whole list first: `grep -q` closing the pipe early fails under pipefail.
services=$(xcrun simctl spawn "$udid" launchctl list)
if grep -q "UIKitApplication:$bundle" <<< "$services"; then
  echo "$bundle is running on the simulator"
else
  echo "::error::$bundle is not running 20 s after launch"
  grep -iE "fault|crash|error" "$out/simulator-$bundle.log" | tail -40
  exit 1
fi
[ -z "$channel" ] && exit 0

# Rendered page check: BMP from sips is easy to read without extra packages.
sips -s format bmp "$out/simulator-$bundle.png" --out "$out/simulator-$bundle.bmp" > /dev/null
python3 - "$out/simulator-$bundle.bmp" "$channel" "$5" "$6" "$7" "$8" <<'PY'
import sys
path, channel = sys.argv[1], sys.argv[2]
x0, y0, x1, y1 = (float(v) for v in sys.argv[3:7])
b = open(path, 'rb').read()
offset = int.from_bytes(b[10:14], 'little')
width = int.from_bytes(b[18:22], 'little', signed=True)
height = int.from_bytes(b[22:26], 'little', signed=True)
bpp = int.from_bytes(b[28:30], 'little')
row = ((bpp * width + 31) // 32) * 4
step = bpp // 8
top_down = height < 0
height = abs(height)
index = {'red': 2, 'green': 1, 'blue': 0}[channel]
hits = total = 0
for y in range(int(y0 * height), int(y1 * height)):
    r = y if top_down else height - 1 - y
    base = offset + r * row
    for x in range(int(x0 * width), int(x1 * width), 2):
        px = b[base + x * step: base + x * step + 3]
        main = px[index]
        others = [px[i] for i in range(3) if i != index]
        total += 1
        if all(main >= o + 40 for o in others):
            hits += 1
share = hits / max(total, 1)
print(f"{channel} pixels in region: {share:.1%} of {total} ({width}x{height})")
if share < 0.005:
    print(f"::error::The web page was not rendered: no {channel} element in the checked region")
    sys.exit(1)
PY
