#!/bin/bash
# Print the set-up guide to the three PDFs the site serves.
#   docs/setup-guide/make-pdfs.sh
# Needs Google Chrome. guide.html#26 / #27 hide the other iOS.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
site="$here/../../site"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
print() {  # <hash or ""> <output>
  "$chrome" --headless --no-pdf-header-footer --virtual-time-budget=4000 \
    --print-to-pdf="$2" "file://$here/guide.html$1" 2>/dev/null
  echo "wrote $2"
}
print ""    "$site/setup-guide.pdf"
print "#26" "$site/setup-guide-ios26.pdf"
print "#27" "$site/setup-guide-ios27.pdf"
