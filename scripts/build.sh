#!/bin/bash
# Compile the app for the simulator. No signing, no device.
#
#   scripts/build.sh            build
#   scripts/build.sh --clean    wipe this checkout's DerivedData first
#
# Output: only errors and the final BUILD line. Full log in .build/build.log.
source "$(dirname "$0")/common.sh"

[ "${1:-}" = "--clean" ] && rm -rf "$DERIVED"
mkdir -p "$ROOT/.build"
log="$ROOT/.build/build.log"

xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build > "$log" 2>&1
status=$?

grep -E 'error:' "$log" | sort -u | head -40
grep -E '\*\* BUILD' "$log"
[ $status -eq 0 ] || die "build failed; log: $log"
