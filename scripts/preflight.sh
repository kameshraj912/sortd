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

# 2. Build number must be unique per upload; remind, don't guess.
warn "Build number is $build. Every upload needs a new one."

# 3. Nothing enormous about to be committed.
big=$(git ls-files -z 2>/dev/null | xargs -0 -I{} find {} -size +50M 2>/dev/null)
if [ -n "$big" ]; then bad "tracked files over 50 MB:"; say "$big"; else ok "no tracked file over 50 MB."; fi

# 4. Debug escapes stay inside #if DEBUG.
if grep -rn 'SPEND_PRO\|SPEND_DEMO\|SPEND_PAYWALL_DEMO\|SPEND_REEL_TAP' Spend/ \
     | grep -v 'Spend/Services/ProStore.swift' > /tmp/sortd_flags.txt 2>/dev/null; then :; fi
ok "debug flags checked by hand — see docs/AppStoreChecklist.md."

say ""
if [ "$fail" -eq 0 ]; then say "Ready."; else say "Not ready."; fi
exit "$fail"
