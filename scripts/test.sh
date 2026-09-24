#!/bin/bash
# Run the unit tests on this worktree's own simulator.
#
#   scripts/test.sh                       everything except known bugs and StoreKit
#   scripts/test.sh --known-bugs          also run the tests tagged as known bugs
#   scripts/test.sh --storekit            also run ProStoreTests (needs iOS 27 sim)
#   scripts/test.sh --only SomeTests      one suite, e.g. --only MoneyFixesTests
#   scripts/test.sh --all                 known bugs + StoreKit
#
# Known-bug tests are compiled always and skipped unless SORTD_KNOWN_BUGS=1
# reaches the test process (xcodebuild forwards TEST_RUNNER_* variables).
# That keeps CI green while the failing tests stay visible in the repo.
#
# Output: a pass/fail/skip count and the failing test names. Full log in
# .build/test.log, result bundle in .build/Test.xcresult.
source "$(dirname "$0")/common.sh"

known=0; storekit=0; only=""
while [ $# -gt 0 ]; do
  case "$1" in
    --known-bugs) known=1 ;;
    --storekit)   storekit=1 ;;
    --all)        known=1; storekit=1 ;;
    --only)       shift; only="$1" ;;
    *) die "unknown flag $1" ;;
  esac
  shift
done

udid="$("$ROOT/scripts/sim.sh" boot)" || exit 1
mkdir -p "$ROOT/.build"
log="$ROOT/.build/test.log"
bundle="$ROOT/.build/Test.xcresult"
rm -rf "$bundle"

args=(-project "$PROJECT" -scheme "$SCHEME" -destination "id=$udid"
      -derivedDataPath "$DERIVED" -resultBundlePath "$bundle" CODE_SIGNING_ALLOWED=NO)
[ $storekit -eq 1 ] || args+=(-skip-testing:SpendTests/ProStoreTests)
[ -n "$only" ] && args+=(-only-testing:"SpendTests/$only")
[ $known -eq 1 ] && export TEST_RUNNER_SORTD_KNOWN_BUGS=1

extra=""; [ -n "$only" ] && extra="$extra, only $only"; [ $known -eq 1 ] && extra="$extra, with known bugs"; [ $storekit -eq 1 ] && extra="$extra, with StoreKit"
say "Testing on $(sim_name) ($udid)$extra"
xcodebuild "${args[@]}" test > "$log" 2>&1
status=$?

# Swift Testing prints one summary line; XCTest prints "Executed N tests".
grep -E 'error:' "$log" | grep -v 'Testing failed' | sort -u | head -20
grep -E '✘|failed after|Test Suite .* failed|Executed [1-9][0-9]* tests' "$log" | sort -u | tail -40
grep -E 'Test run with [0-9]+ tests' "$log" | tail -1
grep -E '\*\* TEST' "$log"
[ $status -eq 0 ] || die "tests failed; log: $log"
