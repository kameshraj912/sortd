#!/bin/bash
# Pre-upload checks for Sortd.
#
#   scripts/preflight.sh              before a TestFlight build
#   scripts/preflight.sh --appstore   before an App Store submission
#
# Both modes fail if the old beta Pro unlock (SORTD_BETA) comes back.
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

# 1. The whole app is free. SORTD_BETA (the old beta Pro unlock) is gone
#    and must stay gone: nothing in the code reads it any more.
if grep -q 'SORTD_BETA' "$PBX"; then
  bad "SORTD_BETA is back in $PBX. The app is free; remove it from the Release config."
else
  ok "SORTD_BETA absent."
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

# 1d. Usage analytics (PostHog) are on in every build that has a key. The App
#     Privacy label must say Product Interaction, User ID and Device ID, all
#     "linked to you" (Analytics, App Functionality), matching PrivacyInfo.xcprivacy.
#     The key comes from Secrets.xcconfig (gitignored; never in a fresh
#     worktree). No key means no events: a note for TestFlight, a FAIL for
#     the App Store, where the label promises analytics that would not run.
if grep -q 'posthog-ios' "$PBX"; then
  warn "Analytics on (PostHog). App Privacy label: Product Interaction, User ID, Device ID — linked to you."
  key=""
  [ -f Secrets.xcconfig ] && key=$(grep -m1 '^POSTHOG_API_KEY' Secrets.xcconfig | cut -d= -f2- | tr -d ' \t')
  [ -z "$key" ] && key=$(grep -m1 '^POSTHOG_API_KEY' Config.xcconfig 2>/dev/null | cut -d= -f2- | tr -d ' \t')
  if [ -z "$key" ] || [ "$key" = "phc_replace_me" ]; then
    if [ "$MODE" = "--appstore" ]; then
      bad "POSTHOG_API_KEY is empty. Copy Secrets.xcconfig.example to Secrets.xcconfig and paste the phc_ key."
    else
      warn "POSTHOG_API_KEY is empty: this build sends no analytics (see Secrets.xcconfig.example)."
    fi
  else
    ok "PostHog key set."
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
      if (cur == 0 && code ~ /SPEND_[A-Z_]+/) {
        print FILENAME ":" FNR ":" raw
      }
    }
  ' $(find Spend -name '*.swift') > "$flagfile" 2>/dev/null
  if [ -s "$flagfile" ]; then
    bad "a DEBUG-only flag is used outside #if DEBUG:"
    while IFS= read -r line; do say "      $line"; done < "$flagfile"
  else
    ok "debug flags (every SPEND_*) all stay inside #if DEBUG."
  fi
fi

say ""
if [ "$fail" -eq 0 ]; then say "Ready."; else say "Not ready."; fi
exit "$fail"
