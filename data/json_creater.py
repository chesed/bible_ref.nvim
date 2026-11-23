import json
import re
from pathlib import Path

TEXT_DIR = Path("SBLGNT/data/sblgnt/text")
OUT_FILE = Path("bible_sblgnt.json")

BOOK_NAMES = {
    "Matt": "Matthew",
    "Mark": "Mark",
    "Luke": "Luke",
    "John": "John",
    "Acts": "Acts",
    "Rom": "Romans",
    "1Cor": "1 Corinthians",
    "2Cor": "2 Corinthians",
    "Gal": "Galatians",
    "Eph": "Ephesians",
    "Phil": "Philippians",
    "Col": "Colossians",
    "1Thess": "1 Thessalonians",
    "2Thess": "2 Thessalonians",
    "1Tim": "1 Timothy",
    "2Tim": "2 Timothy",
    "Titus": "Titus",
    "Phlm": "Philemon",
    "Heb": "Hebrews",
    "Jas": "James",
    "1Pet": "1 Peter",
    "2Pet": "2 Peter",
    "1John": "1 John",
    "2John": "2 John",
    "3John": "3 John",
    "Jude": "Jude",
    "Rev": "Revelation",
}

LINE_RE = re.compile(r"^(\S+)\s+(\d+):(\d+)\s+(.*)$")


def main() -> None:
    bible_map: dict[str, str] = {}

    for txt_path in sorted(TEXT_DIR.glob("*.txt")):
        for raw_line in txt_path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line:
                continue

            match = LINE_RE.match(line)
            if not match:
                # Skip uppercase Greek book titles and non-verse lines without ':'
                if ":" not in line:
                    continue
                raise ValueError(f"Unexpected line in {txt_path.name}: {line!r}")

            abbr, chapter, verse, text = match.groups()
            book = BOOK_NAMES.get(abbr, abbr)
            key = f"{book} {int(chapter)}:{int(verse)}"
            bible_map[key] = text.strip()

    OUT_FILE.write_text(
        json.dumps(bible_map, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(bible_map)} verses to {OUT_FILE}")


if __name__ == "__main__":
    main()
