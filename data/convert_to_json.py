import argparse
import json
from pathlib import Path
from typing import Any
from urllib.parse import urlparse
from urllib.request import urlopen


def load_source_json(source: str) -> Any:
    """Loads JSON from a local file path or an HTTP(S) URL (such as raw.githubusercontent.com)."""
    parsed = urlparse(source)
    if parsed.scheme in ("http", "https"):
        with urlopen(source, timeout=30) as resp:
            raw_bytes = resp.read()
        return json.loads(raw_bytes.decode("utf-8"))

    path = Path(source)
    return json.loads(path.read_text(encoding="utf-8"))


def normalize_to_map(data: Any) -> dict[str, str]:
    """
    Converts common Bible JSON shapes into:
      {"Genesis 1:1": "In the beginning...", ...}
    """
    result: dict[str, str] = {}

    if isinstance(data, dict):
        if data and all(isinstance(v, str) for v in data.values()):
            first_key = next(iter(data))
            if ":" in first_key:
                return {k.strip(): v.strip() for k, v in data.items()}

        for book, chapters in data.items():
            if isinstance(chapters, dict):
                for chapter, verses in chapters.items():
                    if isinstance(verses, dict):
                        for verse, text in verses.items():
                            if isinstance(text, str):
                                key = f"{book} {int(chapter)}:{int(verse)}"
                                result[key] = text.strip()
                    elif isinstance(verses, list):
                        for idx, v_item in enumerate(verses, start=1):
                            if isinstance(v_item, dict):
                                v_num = v_item.get("verse", idx)
                                v_text = v_item.get("text", "")
                                if isinstance(v_text, str) and v_text.strip():
                                    key = f"{book} {int(chapter)}:{int(v_num)}"
                                    result[key] = v_text.strip()
                            elif isinstance(v_item, str):
                                key = f"{book} {int(chapter)}:{idx}"
                                result[key] = v_item.strip()
            elif isinstance(chapters, list):
                for c_idx, c_item in enumerate(chapters, start=1):
                    if isinstance(c_item, dict):
                        c_num = c_item.get("chapter", c_idx)
                        verses = c_item.get("verses", [])
                        if isinstance(verses, dict):
                            for verse, text in verses.items():
                                if isinstance(text, str):
                                    key = f"{book} {int(c_num)}:{int(verse)}"
                                    result[key] = text.strip()
                        elif isinstance(verses, list):
                            for v_idx, v_item in enumerate(verses, start=1):
                                if isinstance(v_item, dict):
                                    v_num = v_item.get("verse", v_idx)
                                    v_text = v_item.get("text", "")
                                    if isinstance(v_text, str) and v_text.strip():
                                        key = f"{book} {int(c_num)}:{int(v_num)}"
                                        result[key] = v_text.strip()
                                elif isinstance(v_item, str):
                                    key = f"{book} {int(c_num)}:{v_idx}"
                                    result[key] = v_item.strip()

    elif isinstance(data, list):
        for item in data:
            if not isinstance(item, dict):
                continue
            book = item.get("book") or item.get("book_name")
            chapter = item.get("chapter")
            verse = item.get("verse")
            text = item.get("text")
            if (
                book is not None
                and chapter is not None
                and verse is not None
                and isinstance(text, str)
            ):
                key = f"{str(book).strip()} {int(chapter)}:{int(verse)}"
                result[key] = text.strip()

    if not result:
        raise ValueError("Could not parse any verses from the input JSON structure.")

    return result


def map_to_array(verse_map: dict[str, str]) -> list[dict[str, Any]]:
    """
    Converts {"Genesis 1:1": "Text"} into:
      [{"book": "Genesis", "chapter": 1, "verse": 1, "text": "Text"}, ...]
    """
    items: list[dict[str, Any]] = []
    for ref, text in verse_map.items():
        book_part, cv_part = ref.rsplit(" ", 1)
        chapter_str, verse_str = cv_part.split(":", 1)
        items.append(
            {
                "book": book_part,
                "chapter": int(chapter_str),
                "verse": int(verse_str),
                "text": text,
            }
        )
    return items


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Download (optional) and convert a Bible JSON file into the expected schema."
    )
    parser.add_argument(
        "source",
        help="Local JSON file path or raw file URL (e.g., https://raw.githubusercontent.com/...)",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("bible.json"),
        help="Output JSON file path (default: bible.json)",
    )
    parser.add_argument(
        "--format",
        choices=["map", "array"],
        default="map",
        help="Output schema: 'map' for {\"Book Chapter:Verse\": \"...\"} or 'array' for list of objects",
    )
    args = parser.parse_args()

    raw_data = load_source_json(args.source)
    verse_map = normalize_to_map(raw_data)
    output_data: Any = verse_map if args.format == "map" else map_to_array(verse_map)

    args.output.write_text(
        json.dumps(output_data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(verse_map)} verses ({args.format} format) to {args.output}")


if __name__ == "__main__":
    main()
