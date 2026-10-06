#!/usr/bin/env bash
# Installs APKs on the running emulator, launches each app and checks that it
# is still alive after start-up. Usage: emulator-install-test.sh <out-dir> <apk>=<package> ...
set -uo pipefail
out="$1"; shift
mkdir -p "$out"
sdk=$(adb shell getprop ro.build.version.sdk | tr -d '\r')
abi=$(adb shell getprop ro.product.cpu.abi | tr -d '\r')
echo "Emulator: API $sdk, ABI $abi"
aapt=$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)/aapt2
failed=0
for pair in "$@"; do
  apk="${pair%%=*}"; pkg="${pair##*=}"
  echo "::group::$pkg ($(basename "$apk"))"
  "$aapt" dump badging "$apk" | grep -E "^(package|sdkVersion|targetSdkVersion|native-code|application-label):" || true
  result=$(adb install -r "$apk" 2>&1); echo "$result"
  if ! grep -q "^Success" <<<"$result"; then
    echo "::error::$pkg: adb install failed on API $sdk — $result"
    failed=1; echo "::endgroup::"; continue
  fi
  adb logcat -c
  adb shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 > /dev/null
  sleep 20
  pid=$(adb shell pidof "$pkg" | tr -d '\r')
  adb logcat -d > "$out/logcat-$pkg-api$sdk.txt"
  adb exec-out screencap -p > "$out/screen-$pkg-api$sdk.png" || true
  if [ -z "$pid" ]; then
    echo "::error::$pkg is not running 20 s after launch on API $sdk"
    grep -E "FATAL EXCEPTION|AndroidRuntime|Process: $pkg" -A25 "$out/logcat-$pkg-api$sdk.txt" | head -80
    failed=1
  else
    echo "$pkg running (pid $pid) on API $sdk"
    grep -E "AndroidRuntime|FATAL" "$out/logcat-$pkg-api$sdk.txt" | head -20 || true
  fi
  echo "::endgroup::"
done
exit $failed
