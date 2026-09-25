#!/bin/bash
# Put the app on Raj's iPhone (free team: re-install every 7 days).
#
#   scripts/device.sh            build Debug for the paired phone, install, launch
#   scripts/device.sh --list     show paired phones
#
# Needs: the phone paired and unlocked, Developer Mode on (Settings > Privacy &
# Security > Developer Mode, then a restart), and Xcode signed in to Raj's Apple ID.
# Debug builds use Spend-Development.entitlements (app groups only), which a
# personal team can sign; Release keeps the paid capabilities.
source "$(dirname "$0")/common.sh"

if [ "${1:-}" = "--list" ]; then xcrun devicectl list devices | grep -i physical; exit 0; fi
udid="${SORTD_DEVICE:-$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /available/ {print $(NF-4)}' | head -1)}"
[ -n "$udid" ] || die "no paired iPhone found. Plug it in, unlock it, trust this Mac."
say "phone: $udid"

dd="$ROOT/.build/DerivedData-device"; mkdir -p "$ROOT/.build"; log="$ROOT/.build/device.log"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Debug \
  -destination "id=$udid" -derivedDataPath "$dd" -allowProvisioningUpdates build > "$log" 2>&1
status=$?
grep -E "error:|Developer Mode" "$log" | sort -u | head -8
[ $status -eq 0 ] || die "device build failed; log: $log"
app=$(find "$dd/Build/Products/Debug-iphoneos" -maxdepth 1 -name "*.app" | head -1)
xcrun devicectl device install app --device "$udid" "$app" | tail -1 || die "install failed (phone locked?)"
bundle=$(defaults read "$app/Info.plist" CFBundleIdentifier)
xcrun devicectl device process launch --device "$udid" "$bundle" | tail -1
ok "installed and launched $bundle"
