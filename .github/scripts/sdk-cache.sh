#!/usr/bin/env bash
# SDK cache of the "Inbox build" workflow: what a build downloads once (Android
# NDK, SDK platforms, Gradle, Gradle/pub/npm/CocoaPods packages) is kept by
# actions/cache and restored in the next runs, so later builds start faster.
#
#   sdk-cache.sh link              restored Android SDK parts → symlinks in $ANDROID_HOME
#   sdk-cache.sh collect           Android SDK parts downloaded by this run → ~/.appbuilder-sdk
#   sdk-cache.sh key <prefix>      cache key that changes only when something new was downloaded
set -euo pipefail
store="$HOME/.appbuilder-sdk"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
snapshot="${RUNNER_TEMP:-/tmp}/appbuilder-sdk-snapshot.txt"
parts=(ndk platforms build-tools cmake)

# Entries of <dir> at exactly <depth> levels, as "<tag>/<path>" (GNU and BSD find).
list() {
  local dir="$1" depth="$2" tag="$3"
  [ -d "$dir" ] || return 0
  (cd "$dir" && find . -mindepth "$depth" -maxdepth "$depth" -not -name '.*' | sed "s|^\./|$tag/|")
}

sha() { if command -v sha256sum > /dev/null; then sha256sum; else shasum -a 256; fi; }

case "${1:-}" in
  link)
    mkdir -p "$store"
    if [ -z "$sdk" ] || [ ! -d "$sdk" ]; then echo "Android SDK not found — nothing to link"; exit 0; fi
    linked=0
    for part in "${parts[@]}"; do
      [ -d "$store/$part" ] || continue
      mkdir -p "$sdk/$part"
      for dir in "$store/$part"/*; do
        [ -d "$dir" ] || continue
        target="$sdk/$part/$(basename "$dir")"
        if [ ! -e "$target" ]; then ln -s "$dir" "$target"; linked=$((linked + 1)); fi
      done
    done
    # What the runner image and the cache already provide: everything else is new.
    for part in "${parts[@]}"; do
      list "$sdk/$part" 1 "$part"
    done | sort > "$snapshot"
    echo "Linked from cache: $linked SDK component(s)"
    ;;
  collect)
    if [ -z "$sdk" ] || [ ! -f "$snapshot" ]; then exit 0; fi
    for part in "${parts[@]}"; do
      [ -d "$sdk/$part" ] || continue
      for dir in "$sdk/$part"/*; do
        [ -d "$dir" ] && [ ! -L "$dir" ] || continue
        name="$part/$(basename "$dir")"
        grep -qxF "$name" "$snapshot" && continue
        mkdir -p "$store/$part"
        rm -rf "${store:?}/$name"
        mv "$dir" "$store/$name"
        ln -s "$store/$name" "$dir"
        echo "New SDK component cached: $name ($(du -sh "$store/$name" | cut -f1))"
      done
    done
    ;;
  key)
    prefix="${2:?usage: sdk-cache.sh key <prefix>}"
    fingerprint=$(
      {
        list "$store" 2 sdk
        list "$HOME/.gradle/caches/modules-2/files-2.1" 3 gradle
        list "$HOME/.gradle/wrapper/dists" 2 wrapper
        list "$HOME/.pub-cache/hosted" 2 pub
        [ -d "$HOME/.npm/_cacache/index-v5" ] && echo "npm $(find "$HOME/.npm/_cacache/index-v5" -type f | wc -l | tr -d ' ')"
        list "$HOME/Library/Caches/CocoaPods/Pods" 3 pods
        true
      } | LC_ALL=C sort | sha | cut -c1-24
    )
    echo "key=$prefix$fingerprint" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    echo "Cache key: $prefix$fingerprint"
    ;;
  *)
    echo "usage: sdk-cache.sh link | collect | key <prefix>" >&2
    exit 2
    ;;
esac
