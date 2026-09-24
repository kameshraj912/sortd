#!/bin/bash
# Shared helpers for the Sortd scripts. Source it; do not run it.
#
# Every script in scripts/ is deterministic: same input, same result, exit 0
# on success and non-zero on failure. Agents call these instead of typing
# xcodebuild or simctl by hand, so the rules in CLAUDE.md are enforced by
# code, not memory.

set -uo pipefail

# The repo root of THIS checkout. Each worktree has its own, which is the
# point: builds and simulators never cross worktrees.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Spend.xcodeproj"
SCHEME="Spend"

# Build products live inside the checkout so `worktree-done.sh` can delete
# them with the worktree. Gitignored.
DERIVED="${SORTD_DERIVED:-$ROOT/.build/DerivedData}"

# One simulator per worktree, named after the branch. Override with SORTD_SIM
# (a name or a UDID) when you need a specific device.
BASE_DEVICE="${SORTD_BASE_DEVICE:-iPhone 18 Pro}"
# StoreKit tests need iOS 27; see HANDOVER.md "StoreKit tests are simulator-dependent".
BASE_RUNTIME_PREFIX="${SORTD_BASE_RUNTIME:-iOS 27}"

say()  { printf '%s\n' "$*"; }
ok()   { printf 'ok    %s\n' "$*"; }
warn() { printf 'note  %s\n' "$*"; }
die()  { printf 'FAIL  %s\n' "$*" >&2; exit 1; }

branch_name() { git -C "$ROOT" branch --show-current 2>/dev/null || echo detached; }

# Simulator name for this checkout: "Sortd-<branch>", or SORTD_SIM if set.
sim_name() {
  if [ -n "${SORTD_SIM:-}" ]; then printf '%s' "$SORTD_SIM"; return; fi
  printf 'Sortd-%s' "$(branch_name)"
}

# UDID of a simulator by name (first match) or pass a UDID straight through.
sim_udid() {
  local name="$1"
  if [[ "$name" =~ ^[0-9A-F-]{36}$ ]]; then printf '%s' "$name"; return; fi
  xcrun simctl list devices available -j \
    | python3 -c 'import json,sys; n=sys.argv[1]
d=json.load(sys.stdin)["devices"]
for rt,devs in d.items():
    for x in devs:
        if x["name"]==n: print(x["udid"]); sys.exit(0)
sys.exit(1)' "$name"
}

# UDID of the base device on the newest matching runtime.
base_udid() {
  xcrun simctl list devices available -j \
    | python3 -c 'import json,sys; dev=sys.argv[1]; rt=sys.argv[2]
d=json.load(sys.stdin)["devices"]
best=None
for key,devs in d.items():
    for x in devs:
        if x["name"]==dev and rt.replace(" ","-") in key: best=x["udid"]
print(best or ""); sys.exit(0 if best else 1)' "$BASE_DEVICE" "$BASE_RUNTIME_PREFIX"
}
