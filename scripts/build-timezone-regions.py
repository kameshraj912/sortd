#!/usr/bin/env python3
"""Builds Spend/Services/TimeZoneRegions.swift: which country each time zone is in.

    scripts/build-timezone-regions.py

Sortd guesses a tap's currency from where the phone is, and the phone only
tells us its time zone ("Asia/Tokyo"). This writes the lookup from time zone to
country, from this Mac's own copy of the IANA time zone database
(/usr/share/zoneinfo). Run it again after a macOS update to pick up new zones.

- zone.tab gives the country of every current zone.
- Old names iPhones still report ("Asia/Calcutta", "Europe/Kiev") are not in
  zone.tab. One is matched to a country when its data file is byte-for-byte
  the same as zones of exactly one country; otherwise it is left out and the
  app falls back to the phone's region.
"""
import hashlib
import pathlib
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parent.parent
ZONEINFO = pathlib.Path("/usr/share/zoneinfo")
OUT = ROOT / "Spend/Services/TimeZoneRegions.swift"

country = {}
for line in (ZONEINFO / "zone.tab").read_text().splitlines():
    if line.startswith("#") or not line.strip():
        continue
    code, _coords, zone = line.split("\t")[:3]
    country[zone] = code


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


by_data = defaultdict(set)
for zone, code in country.items():
    f = ZONEINFO / zone
    if f.is_file():
        by_data[digest(f)].add(code)

aliases = 0
for f in sorted(ZONEINFO.rglob("*")):
    name = f.relative_to(ZONEINFO).as_posix()
    if not f.is_file() or "/" not in name or name in country or name.startswith(("Etc/", "posix/", "right/")):
        continue
    if f.read_bytes()[:4] != b"TZif":
        continue
    codes = by_data.get(digest(f), set())
    if len(codes) == 1:
        country[name] = next(iter(codes))
        aliases += 1

# Old names iPhones still report whose data now matches zones of two
# countries (Toronto's is shared with Nassau, Yangon's with the Cocos Islands),
# so the match above leaves them out. Set by hand.
OLD_NAMES = {
    "America/Montreal": "CA", "America/Nipigon": "CA", "America/Thunder_Bay": "CA",
    "Asia/Rangoon": "MM", "Pacific/Ponape": "FM", "Pacific/Truk": "FM",
}
for zone, code in OLD_NAMES.items():
    country.setdefault(zone, code)

zones = defaultdict(list)
for zone, code in country.items():
    zones[code].append(zone)

version = (ZONEINFO / "+VERSION").read_text().strip() if (ZONEINFO / "+VERSION").exists() else "unknown"
rows = "\n".join(f"    {code} {' '.join(sorted(zones[code]))}" for code in sorted(zones))
OUT.write_text(f'''import Foundation

// Made by scripts/build-timezone-regions.py from the IANA time zone database
// {version}. Don't edit by hand: change the script and run it again.

/// Which country a time zone is in ("Asia/Tokyo" is Japan). The phone sets its
/// time zone by itself when it travels, so this says where the phone is
/// without asking for location. `LocalCurrency` turns the country into money.
nonisolated enum TimeZoneRegions {{
    /// The ISO country code for a time zone name, or nil when the zone has no
    /// single country (UTC, a ship's "Etc/GMT+8", a name newer than this list).
    static func region(for identifier: String) -> String? {{ table[identifier] }}

    private static let table: [String: String] = {{
        var out: [String: String] = [:]
        for row in rows.split(separator: "\\n") {{
            let parts = row.split(separator: " ")
            guard let code = parts.first else {{ continue }}
            for zone in parts.dropFirst() {{ out[String(zone)] = String(code) }}
        }}
        return out
    }}()

    /// One country per line: its code, then every zone name in it.
    private static let rows = """
{rows}
    """
}}
''')
print(f"{len(country)} zones in {len(zones)} countries ({aliases} old names), tz {version} -> {OUT.relative_to(ROOT)}")
