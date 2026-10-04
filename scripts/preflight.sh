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

# 1b. Sentry crash reports run in the live app (overhaul sub-spec 2b): scrubbed,
#     under the analytics consent switch, user = the salted hash. The label must
#     say Crash Data, Performance Data and Other Diagnostic Data, "linked to you"
#     (App Functionality), matching PrivacyInfo.xcprivacy. The DSN comes from
#     Secrets.xcconfig like the PostHog key: empty is a note for TestFlight and
#     a FAIL for the App Store, where the label promises crash reports.
if grep -q 'sentry-cocoa' "$PBX"; then
  warn "Crash reports on (Sentry). App Privacy label: Crash Data, Performance Data, Other Diagnostic Data — linked to you."
  dsn=""
  [ -f Secrets.xcconfig ] && dsn=$(grep -m1 '^SENTRY_DSN' Secrets.xcconfig | cut -d= -f2- | tr -d ' \t')
  [ -z "$dsn" ] && dsn=$(grep -m1 '^SENTRY_DSN' Config.xcconfig 2>/dev/null | cut -d= -f2- | tr -d ' \t')
  # Read it as Xcode does: "//" starts a comment, so a DSN pasted without the
  # $() reads back as "https:"; then the $() drops out. Set means what is left
  # still has the scheme, the key and the ingest host.
  [ -n "$dsn" ] && dsn=$(printf '%s' "$dsn" | sed 's#//.*$##; s/\$()//g')
  if [ -z "$dsn" ] || printf '%s' "$dsn" | grep -q 'replace_me' \
     || ! { printf '%s' "$dsn" | grep -q '://' && printf '%s' "$dsn" | grep -q '@' && printf '%s' "$dsn" | grep -q 'ingest'; }; then
    if [ "$MODE" = "--appstore" ]; then
      bad "SENTRY_DSN is empty or not a DSN (needs https:/\$()/<key>@<org>.ingest.sentry.io/<id>). See Secrets.xcconfig.example."
    else
      warn "SENTRY_DSN is empty or not a DSN: this build sends no crash reports (see Secrets.xcconfig.example)."
    fi
  else
    ok "Sentry DSN set."
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

# 1d. Session replay is for TestFlight only. An App Store build must not carry the flag.
if grep -q 'SORTD_REPLAY' "$PBX" && [ "$MODE" = "--appstore" ]; then
  bad "SORTD_REPLAY is still in the Release build settings. Remove it before an App Store build (replay is TestFlight only)."
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

# 5. App Intent descriptions must not say "Apple". App Store Connect refuses the
#    binary at processing (ITMS-90626 "Invalid Siri Support ... cannot contain
#    'apple'"): build 1.0 (1) was turned away for "Apple Pay" on 4 Oct 2026.
siri=$(grep -rniE -A2 'IntentDescription\(' Spend SortdWidget 2>/dev/null | grep -i 'apple' || true)
if [ -n "$siri" ]; then
  bad "an App Intent description says \"Apple\" (ITMS-90626); reword it:"
  printf '%s\n' "$siri" | while IFS= read -r line; do say "      $line"; done
else
  ok "no App Intent description says \"Apple\" (ITMS-90626)."
fi

say ""
if [ "$fail" -eq 0 ]; then say "Ready."; else say "Not ready."; fi
exit "$fail"
