#!/usr/bin/env python3
"""Generate Sources/ClipstackCore/Resources/emoji.json.

Built from Python's bundled Unicode database, so it needs no network and no
third-party emoji package. Category ranges follow the ordering used by the
Windows emoji panel; official names become the search keywords.

Run after a Python upgrade to pick up newly assigned emoji:
    python3 scripts/generate-emoji.py
"""
import json
import sys
import unicodedata
from pathlib import Path

# (category, [(first, last), ...]) — inclusive codepoint ranges.
CATEGORIES = [
    ("Smileys", [
        (0x1F600, 0x1F64F), (0x1F910, 0x1F92F), (0x1F970, 0x1F97A),
        (0x1FAE0, 0x1FAE8), (0x263A, 0x263B), (0x2639, 0x2639),
    ]),
    ("People", [
        (0x1F464, 0x1F487), (0x1F9B0, 0x1F9B3), (0x1F9D0, 0x1F9DF),
        (0x1F44A, 0x1F450), (0x270A, 0x270D), (0x1F918, 0x1F91F),
        (0x1F930, 0x1F93A), (0x1FAF0, 0x1FAF8), (0x1F595, 0x1F596),
    ]),
    ("Animals & Nature", [
        (0x1F400, 0x1F43F), (0x1F980, 0x1F9AE), (0x1F330, 0x1F344),
        (0x1F337, 0x1F33F), (0x1F308, 0x1F30C), (0x2600, 0x2604),
        (0x26C4, 0x26C8), (0x1F324, 0x1F32C),
    ]),
    ("Food & Drink", [
        (0x1F345, 0x1F37F), (0x1F32D, 0x1F32F), (0x1F950, 0x1F96F),
        (0x1F9C0, 0x1F9CB), (0x1FAD0, 0x1FADF),
    ]),
    ("Travel & Places", [
        (0x1F680, 0x1F6C5), (0x1F30D, 0x1F320), (0x1F3D4, 0x1F3F0),
        (0x1F5FA, 0x1F5FF), (0x26F0, 0x26F5), (0x2708, 0x2708),
    ]),
    ("Activities", [
        (0x1F3A0, 0x1F3CA), (0x1F3CF, 0x1F3D3), (0x1F945, 0x1F94C),
        (0x26BD, 0x26BE), (0x1F396, 0x1F39F), (0x1F947, 0x1F94F),
    ]),
    ("Objects", [
        (0x1F4A1, 0x1F4FF), (0x1F50B, 0x1F53D), (0x1F5A5, 0x1F5B2),
        (0x1F6E0, 0x1F6E5), (0x1F9F0, 0x1F9FF), (0x231A, 0x231B),
        (0x1F587, 0x1F58D), (0x2702, 0x2702), (0x270F, 0x2712),
    ]),
    ("Symbols", [
        (0x2764, 0x2764), (0x1F493, 0x1F4A0), (0x1F500, 0x1F50A),
        (0x2705, 0x2705), (0x274C, 0x274E), (0x2795, 0x2797),
        (0x2714, 0x2716), (0x267B, 0x267F), (0x1F51F, 0x1F53A),
        (0x26A0, 0x26A1), (0x2B50, 0x2B50), (0x1F4AF, 0x1F4AF),
    ]),
]

# Common flags, built from ISO 3166 codes as regional-indicator pairs.
FLAG_CODES = [
    ("US", "United States"), ("GB", "United Kingdom"), ("CA", "Canada"),
    ("AU", "Australia"), ("DE", "Germany"), ("FR", "France"),
    ("ES", "Spain"), ("IT", "Italy"), ("PT", "Portugal"),
    ("NL", "Netherlands"), ("SE", "Sweden"), ("NO", "Norway"),
    ("DK", "Denmark"), ("FI", "Finland"), ("PL", "Poland"),
    ("RU", "Russia"), ("UA", "Ukraine"), ("TR", "Turkey"),
    ("IN", "India"), ("BD", "Bangladesh"), ("PK", "Pakistan"),
    ("CN", "China"), ("JP", "Japan"), ("KR", "South Korea"),
    ("SG", "Singapore"), ("MY", "Malaysia"), ("ID", "Indonesia"),
    ("TH", "Thailand"), ("VN", "Vietnam"), ("PH", "Philippines"),
    ("AE", "United Arab Emirates"), ("SA", "Saudi Arabia"),
    ("EG", "Egypt"), ("ZA", "South Africa"), ("NG", "Nigeria"),
    ("KE", "Kenya"), ("BR", "Brazil"), ("MX", "Mexico"),
    ("AR", "Argentina"), ("CL", "Chile"), ("NZ", "New Zealand"),
    ("IE", "Ireland"), ("CH", "Switzerland"), ("AT", "Austria"),
    ("BE", "Belgium"), ("GR", "Greece"), ("IL", "Israel"),
]

REGIONAL_INDICATOR_A = 0x1F1E6
VARIATION_SELECTOR_16 = "\uFE0F"

# Codepoints below this live in the legacy symbol blocks, which default to
# monochrome text presentation. VS16 forces the colour emoji glyph; it is
# harmless on those that are already emoji by default.
EMOJI_PRESENTATION_THRESHOLD = 0x1F000


def keywords_for(name: str) -> str:
    """Trim Unicode naming noise so searches match what people type."""
    cleaned = name.lower().replace("-", " ")
    for noise in ("face with ", "face ", "sign", "symbol", "emoji modifier"):
        cleaned = cleaned.replace(noise, " ")
    return " ".join(cleaned.split())


def build() -> dict:
    categories = []
    seen = set()

    for name, ranges in CATEGORIES:
        entries = []
        for first, last in ranges:
            for cp in range(first, last + 1):
                if cp in seen:
                    continue
                char = chr(cp)
                try:
                    unicode_name = unicodedata.name(char)
                except ValueError:
                    continue          # unassigned in this Python's UCD
                seen.add(cp)
                if cp < EMOJI_PRESENTATION_THRESHOLD:
                    char += VARIATION_SELECTOR_16
                entries.append({
                    "char": char,
                    "name": unicode_name.title(),
                    "keywords": keywords_for(unicode_name),
                })
        if entries:
            categories.append({"name": name, "emoji": entries})

    flags = [
        {
            "char": "".join(chr(REGIONAL_INDICATOR_A + ord(c) - ord("A")) for c in code),
            "name": country,
            "keywords": f"{country.lower()} flag {code.lower()}",
        }
        for code, country in FLAG_CODES
    ]
    categories.append({"name": "Flags", "emoji": flags})

    return {"categories": categories}


def main() -> int:
    data = build()
    out = Path(__file__).resolve().parent.parent / "Sources/ClipstackCore/Resources/emoji.json"
    out.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")

    total = sum(len(c["emoji"]) for c in data["categories"])
    print(f"Unicode {unicodedata.unidata_version}: {total} emoji in {len(data['categories'])} categories")
    for c in data["categories"]:
        print(f"  {c['name']:<18} {len(c['emoji']):>4}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
