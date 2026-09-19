"""Checks App Store listing fields against Apple's character limits."""
import re, sys
t = open('AppStoreListing.md').read()
def field(label):
    m = re.search(r'\*\*' + re.escape(label) + r'\*\* \(\d+\): (.+)', t)
    return m.group(1).strip() if m else ''
def section(title):
    m = re.search(r'## ' + re.escape(title) + r'.*?\n\n(.*?)(?=\n## )', t, re.S)
    return m.group(1).strip() if m else ''
checks = {
    'Name': (field('Name'), 30), 'Subtitle': (field('Subtitle'), 30),
    'Promotional text': (section('Promotional text'), 170),
    'Description': (section('Description'), 4000),
    'Keywords': (section('Keywords'), 100),
    "What's New": (section("What's New"), 4000),
}
ok = True
for k, (v, lim) in checks.items():
    n = len(v); flag = 'OK' if 0 < n <= lim else 'TOO LONG' if n > lim else 'EMPTY'
    ok &= flag == 'OK'
    print(f'{k:18} {n:5} / {lim}  {flag}')
sys.exit(0 if ok else 1)
