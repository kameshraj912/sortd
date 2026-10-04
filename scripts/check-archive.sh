#!/bin/bash
# Check a built archive before uploading it.
#
#   scripts/check-archive.sh path/to/Sortd.xcarchive
#
# Reads the App Intents metadata App Store Connect reads
# (Sortd.app/Metadata.appintents/extract.actionsdata) and fails if any text in
# it says "Apple". Build 1.0 (1) was refused at processing for that on
# 4 Oct 2026: ITMS-90626 "Invalid Siri Support - App Intent description ...
# cannot contain 'apple'". Apple publishes no list of refused words, so this
# checks every string in the file, not only descriptions.
set -uo pipefail
archive="${1:-}"
[ -d "$archive" ] || { echo "usage: check-archive.sh <path.xcarchive>"; exit 2; }
app=$(find "$archive/Products/Applications" -maxdepth 1 -name "*.app" | head -1)
[ -n "$app" ] || { echo "FAIL  no .app in $archive"; exit 1; }
meta="$app/Metadata.appintents/extract.actionsdata"
[ -f "$meta" ] || { echo "FAIL  no App Intents metadata at $meta"; exit 1; }

printf 'archive %s %s (%s)\n' \
  "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")" \
  "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist")" \
  "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist")"

python3 - "$meta" <<'PY'
import json, re, sys
hits = []
def walk(o, path=""):
    if isinstance(o, dict):
        for k, v in o.items(): walk(v, path + "/" + k)
    elif isinstance(o, list):
        for v in o: walk(v, path + "[]")
    elif isinstance(o, str) and re.search(r"apple", o, re.I):
        hits.append((path, o))
walk(json.load(open(sys.argv[1])))
if hits:
    print('FAIL  App Intents metadata says "Apple" (ITMS-90626). Reword:')
    for path, text in hits: print("      " + path + ": " + text)
    sys.exit(1)
print('ok    App Intents metadata never says "Apple" (ITMS-90626).')
PY
