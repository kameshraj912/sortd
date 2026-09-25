#!/bin/bash
# One simulator per worktree.
#
#   scripts/sim.sh ensure   make "Sortd-<branch>" if missing, print its UDID
#   scripts/sim.sh boot     ensure + boot, print UDID
#   scripts/sim.sh delete   shut down and delete this worktree's simulator
#   scripts/sim.sh list     all Sortd-* simulators
#   scripts/sim.sh screenshot <file.png>   save what is on screen (boots if needed)
#   scripts/sim.sh appearance dark|light   switch the simulator's appearance
#   scripts/sim.sh shutdown                shut this worktree's simulator down
#   scripts/sim.sh install                 install the app built by build.sh
#   scripts/sim.sh launch [KEY=VALUE ...]  launch it with env vars (e.g. SPEND_DEMO=1)
#   scripts/sim.sh terminate               stop the running app
#
# The clone is made from "iPhone 18 Pro" on iOS 27 (see common.sh). Sharing a
# simulator between sessions gives "Invalid device state" and "server died";
# that is a fight over the device, not a code failure.
source "$(dirname "$0")/common.sh"

cmd="${1:-ensure}"
name="$(sim_name)"

case "$cmd" in
  ensure|boot)
    udid="$(sim_udid "$name" || true)"
    if [ -z "$udid" ]; then
      base="$(base_udid)" || die "no '$BASE_DEVICE' on $BASE_RUNTIME_PREFIX. Install the runtime in Xcode > Settings > Components."
      udid="$(xcrun simctl clone "$base" "$name")" || die "could not clone $BASE_DEVICE"
      warn "made simulator $name ($udid)" >&2
    fi
    if [ "$cmd" = boot ]; then
      xcrun simctl boot "$udid" 2>/dev/null || true
      xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
    fi
    printf '%s\n' "$udid"
    ;;
  delete)
    udid="$(sim_udid "$name" || true)"
    [ -z "$udid" ] && { warn "no simulator named $name"; exit 0; }
    xcrun simctl shutdown "$udid" 2>/dev/null || true
    xcrun simctl delete "$udid" && ok "deleted simulator $name"
    ;;
  list)
    xcrun simctl list devices available | grep -E '^\s+Sortd-' || say "(none)"
    ;;
  screenshot)
    out="${2:-}"; [ -n "$out" ] || die "usage: sim.sh screenshot <file.png>"
    udid="$("$0" boot)" || exit 1
    mkdir -p "$(dirname "$out")"
    xcrun simctl io "$udid" screenshot "$out" >/dev/null 2>&1 || die "screenshot failed"
    printf '%s\n' "$out"
    ;;
  shutdown)
    udid="$(sim_udid "$name" || true)"
    [ -z "$udid" ] && { warn "no simulator named $name"; exit 0; }
    xcrun simctl shutdown "$udid" 2>/dev/null || true; ok "$name shut down"
    ;;
  install)
    udid="$("$0" boot)" || exit 1
    app="$(find "$DERIVED/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name '*.app' 2>/dev/null | head -1)"
    [ -n "$app" ] || die "no built app; run scripts/build.sh first"
    xcrun simctl install "$udid" "$app" && ok "installed $(basename "$app") on $name"
    ;;
  launch)
    shift
    udid="$("$0" boot)" || exit 1
    app="$(find "$DERIVED/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name '*.app' 2>/dev/null | head -1)"
    [ -n "$app" ] || die "no built app; run scripts/build.sh first"
    bundle="$(defaults read "$PWD/$app/Info.plist" CFBundleIdentifier 2>/dev/null || defaults read "$app/Info.plist" CFBundleIdentifier)"
    xcrun simctl install "$udid" "$app" >/dev/null
    xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
    for kv in "$@"; do export "SIMCTL_CHILD_$kv"; done
    xcrun simctl launch "$udid" "$bundle" >/dev/null && ok "launched $bundle on $name${*:+ with $*}"
    ;;
  terminate)
    udid="$(sim_udid "$name" || true)"; [ -z "$udid" ] && exit 0
    app="$(find "$DERIVED/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name '*.app' 2>/dev/null | head -1)"
    bundle="$(defaults read "$app/Info.plist" CFBundleIdentifier 2>/dev/null)"
    [ -n "$bundle" ] && xcrun simctl terminate "$udid" "$bundle" 2>/dev/null; ok "stopped"
    ;;
  appearance)
    mode="${2:-}"; case "$mode" in dark|light) ;; *) die "usage: sim.sh appearance dark|light" ;; esac
    udid="$("$0" boot)" || exit 1
    xcrun simctl ui "$udid" appearance "$mode" && ok "$(sim_name) is now $mode"
    ;;
  *) die "usage: sim.sh ensure|boot|delete|list|shutdown|install|launch [K=V..]|terminate|screenshot <file>|appearance dark|light" ;;
esac
