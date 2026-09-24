#!/bin/bash
# Point git at the hooks in scripts/hooks for this checkout (or the one given).
#
#   scripts/install-hooks.sh [path-to-checkout]
#
# core.hooksPath is per-worktree-safe: it is stored in the shared config, so
# one install covers every worktree of this repo.
source "$(dirname "$0")/common.sh"
target="${1:-$ROOT}"
git -C "$target" config core.hooksPath scripts/hooks || die "could not set core.hooksPath"
chmod +x "$ROOT"/scripts/hooks/* "$ROOT"/scripts/*.sh
ok "hooks installed for $(git -C "$target" rev-parse --show-toplevel)"
