#!/bin/bash
# One simulator per worktree.
#
#   scripts/sim.sh ensure   make "Sortd-<branch>" if missing, print its UDID
#   scripts/sim.sh boot     ensure + boot, print UDID
#   scripts/sim.sh delete   shut down and delete this worktree's simulator
#   scripts/sim.sh list     all Sortd-* simulators
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
  *) die "usage: sim.sh ensure|boot|delete|list" ;;
esac
