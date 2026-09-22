#!/bin/bash
# Pre-upload checks for Sortd.
#
#   scripts/preflight.sh              before a TestFlight build
#   scripts/preflight.sh --appstore   before an App Store submission
#
# The App Store mode fails if the beta Pro unlock is still compiled in.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

PBX=Spend.xcodeproj/project.pbxproj
MODE=${1:-testflight}
fail=0

say()  { printf '%s\n' "$1"; }
bad()  { printf 'FAIL  %s\n' "$1"; fail=1; }
ok()   { printf 'ok    %s\n' "$1"; }
warn() { printf 'note  %s\n' "$1"; }

version=$(grep -m1 'MARKETING_VERSION' "$PBX" | tr -d ' \t;' | cut -d= -f2)
build=$(grep -m1 'CURRENT_PROJECT_VERSION' "$PBX" | tr -d ' \t;' | cut -d= -f2)
say "Sortd $version ($build)  —  $MODE"
say ""

# 1. The beta Pro unlock must not reach the App Store.
if grep -q 'SORTD_BETA' "$PBX"; then
  if [ "$MODE" = "--appstore" ]; then
    bad "SORTD_BETA is still in $PBX. Remove it from the Release config, or"
    say "      App Review never sees the paywall and Pro is free to everyone in review."
  else
    ok "SORTD_BETA on — TestFlight testers get Pro without buying."
  fi
else
  if [ "$MODE" = "--appstore" ]; then
    ok "SORTD_BETA removed."
  else
    warn "SORTD_BETA is off. Testers will hit an empty paywall unless the"
    say "      three products exist in App Store Connect."
  fi
fi

# 1b. Sentry crash reports are for TestFlight only. The App Store label says
#     "Data Not Collected", and Sentry's privacy manifest declares crash data.
if grep -q 'sentry-cocoa' "$PBX"; then
  if [ "$MODE" = "--appstore" ]; then
    bad "Sentry is still linked. Remove the sentry-cocoa package and CrashReporting.swift,"
    say "      or change the App Privacy label to Crash Data (not linked) first — see CrashReporting.swift."
  elif grep -q 'static let dsn = ""' Spend/Services/CrashReporting.swift 2>/dev/null; then
    warn "Sentry DSN is empty — beta crash reports are off. Paste it in CrashReporting.swift."
  else
    ok "Sentry crash reports on for TestFlight."
  fi
fi

# 1c. Gmail ships in v1, which only works for the public once Google has verified the scope.
if grep -q 'SORTD_GMAIL' "$PBX" && [ "$MODE" = "--appstore" ]; then
  warn "Gmail is on. Submit only after Google has verified gmail.readonly"
  say "      (docs/GoogleVerification.md). Before that, only 100 test users can connect."
fi

# 2. Build number must be unique per upload; remind, don't guess.
warn "Build number is $build. Every upload needs a new one."

# 3. Nothing enormous about to be committed.
big=$(git ls-files -z 2>/dev/null | xargs -0 -I{} find {} -size +50M 2>/dev/null)
if [ -n "$big" ]; then bad "tracked files over 50 MB:"; say "$big"; else ok "no tracked file over 50 MB."; fi

# 4. Debug escapes stay inside #if DEBUG.
flagfile=$(mktemp "${TMPDIR:-/tmp}/sortd_flags.XXXXXX") || { bad "could not create a temp file for the debug-flag check."; flagfile=""; }
if [ -n "$flagfile" ]; then
  trap 'rm -f "$flagfile"' EXIT
  awk '
    function parent_dbg() { return depth > 0 ? dbg[depth] : 0 }
    {
      raw = $0
      if (raw ~ /^[ \t]*#if[ \t]+DEBUG[ \t]*$/) {
        depth++; isDebugIf[depth] = 1; dbg[depth] = 1; next
      }
      if (raw ~ /^[ \t]*#elseif[ \t]+DEBUG[ \t]*$/) {
        if (depth > 0) { isDebugIf[depth] = 1; dbg[depth] = 1 }
        next
      }
      if (raw ~ /^[ \t]*#(if|ifdef|ifndef)([ \t]|$)/) {
        p = parent_dbg(); depth++; isDebugIf[depth] = 0; dbg[depth] = p; next
      }
      if (raw ~ /^[ \t]*#elseif([ \t]|$)/) {
        if (depth > 0) { isDebugIf[depth] = 0; dbg[depth] = parent_dbg() }
        next
      }
      if (raw ~ /^[ \t]*#else([ \t]|$)/) {
        if (depth > 0 && isDebugIf[depth] == 1) dbg[depth] = 0
        next
      }
      if (raw ~ /^[ \t]*#endif([ \t]|$)/) {
        if (depth > 0) depth--
        next
      }
      cur = depth > 0 ? dbg[depth] : 0
      code = raw
      sub(/\/\/.*/, "", code)
      if (cur == 0 && code ~ /SPEND_DEMO|SPEND_PRO|SPEND_PAYWALL_DEMO|SPEND_REEL_TAP|SPEND_BETA|SPEND_SYNC_DEMO/) {
        print FILENAME ":" FNR ":" raw
      }
    }
  ' $(find Spend -name '*.swift') > "$flagfile" 2>/dev/null
  if [ -s "$flagfile" ]; then
    bad "a DEBUG-only flag is used outside #if DEBUG:"
    while IFS= read -r line; do say "      $line"; done < "$flagfile"
  else
    ok "debug flags (SPEND_DEMO, SPEND_PRO, SPEND_PAYWALL_DEMO, SPEND_REEL_TAP, SPEND_BETA, SPEND_SYNC_DEMO) all stay inside #if DEBUG."
  fi
fi

say ""
if [ "$fail" -eq 0 ]; then say "Ready."; else say "Not ready."; fi
exit "$fail"
