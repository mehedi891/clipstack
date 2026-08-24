#!/usr/bin/env python3
"""Stage a throwaway clipboard history for screenshots.

    ./scripts/seed-demo-history.py <directory>

Writes the same SQLite schema Clipstack uses, so the app can be pointed at the
result with CLIPSTACK_DEBUG_STORAGE and photographed without exposing whatever
was really on the clipboard. Entries are plausible-but-invented on purpose.

Only the standard library is used, so this runs on a stock macOS python3.
"""
import hashlib
import os
import shutil
import sqlite3
import subprocess
import time
import sys
import uuid

SCHEMA = """
CREATE TABLE IF NOT EXISTS items (
    id             TEXT PRIMARY KEY,
    kind           TEXT NOT NULL,
    text           TEXT,
    rtf            BLOB,
    imageFilename  TEXT,
    preview        TEXT NOT NULL,
    createdAt      REAL NOT NULL,
    pinned         INTEGER NOT NULL,
    sourceBundleID TEXT,
    contentHash    TEXT NOT NULL
);
"""

# createdAt is a Unix timestamp, matching Date.timeIntervalSince1970 in
# Persistence.swift. Ages are relative to when this runs, so the panel shows "5m ago" rather than
# a date. That makes runs differ slightly, which matters less than the labels
# looking live.
NOW = time.time()

# (text, source bundle id, pinned, age in seconds)
ENTRIES = [
    ("https://github.com/mehedi891/clipstack", "com.apple.Safari", True, 40),
    ("#0F172A", "com.microsoft.VSCode", True, 5 * 60),
    ("Meeting moved to Thursday 3pm — conference room B", "com.apple.Notes", False, 12 * 60),
    ("npm run build --workspace=@acme/design-system", "com.apple.Terminal", True, 26 * 60),
    ("Thanks for the quick turnaround — I have forwarded it to accounts.",
     "com.apple.mail", False, 48 * 60),
    ("docker compose up -d --build", "com.apple.Terminal", False, 70 * 60),
    ("SELECT id, email FROM users WHERE created_at > now() - interval '7 days';",
     "com.apple.Terminal", True, 95 * 60),
    ("⇧⌘V", "com.microsoft.VSCode", True, 3 * 3600),
    ("The quarterly report is in the shared drive under /2026/Q3.",
     "com.google.Chrome", False, 4 * 3600),
    ("git rebase -i origin/main", "com.apple.Terminal", False, 5 * 3600),
    ("mehedi@example.com", "org.mozilla.firefox", True, 6 * 3600),
    ("Clipboard history for macOS, the way Win+V does it.",
     "com.microsoft.VSCode", False, 7 * 3600),
]

# An image entry, so the list shows a thumbnail alongside the text rows.
IMAGE_SOURCE = "Assets/icon-1024.png"
IMAGE_BUNDLE = "com.apple.Preview"
IMAGE_AGE = 18 * 60


def png_size(path):
    out = subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", path],
        capture_output=True, text=True, check=True,
    ).stdout
    values = {}
    for line in out.splitlines():
        parts = line.strip().split(": ")
        if len(parts) == 2:
            values[parts[0]] = parts[1]
    return int(values["pixelWidth"]), int(values["pixelHeight"])


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)

    directory = os.path.abspath(os.path.expanduser(sys.argv[1]))
    images = os.path.join(directory, "images")
    shutil.rmtree(directory, ignore_errors=True)
    os.makedirs(images)

    db = sqlite3.connect(os.path.join(directory, "history.sqlite"))
    db.executescript(SCHEMA)

    rows = []
    for text, bundle, pinned, age in ENTRIES:
        rows.append((
            str(uuid.uuid4()), "text", text, None, None, text,
            NOW - age, int(pinned), bundle,
            hashlib.sha256(text.encode()).hexdigest(),
        ))

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    source = os.path.join(root, IMAGE_SOURCE)
    if os.path.exists(source):
        filename = "demo-image.png"
        shutil.copyfile(source, os.path.join(images, filename))
        width, height = png_size(source)
        rows.append((
            str(uuid.uuid4()), "image", None, None, filename,
            f"{width} × {height}", NOW - IMAGE_AGE, 0,
            IMAGE_BUNDLE, hashlib.sha256(filename.encode()).hexdigest(),
        ))
    else:
        print(f"  ! {IMAGE_SOURCE} missing, skipping the image entry")

    db.executemany("INSERT INTO items VALUES (?,?,?,?,?,?,?,?,?,?)", rows)
    db.commit()
    db.close()
    print(f"Seeded {len(rows)} entries in {directory}")


if __name__ == "__main__":
    main()
