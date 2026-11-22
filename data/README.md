# Bible Dataset

Place your Bible JSON file here as `bible.json`.

## Expected Schema

```json
{
  "Genesis 1:1": "In the beginning, God created the heavens and the earth.",
  "Genesis 1:2": "The earth was without form and void...",
  ...
}
```

The array-of-objects format is also accepted:

```json
[
  { "book": "Genesis", "chapter": 1, "verse": 1, "text": "In the beginning..." },
  ...
]
```

## Recommended Sources

- **ESV (personal use):** https://github.com/acbellini/esv-json
- **Multi-translation:** https://github.com/scrollmapper/bible_databases

Place the downloaded file here and rename it to `bible.json`, or point `setup()` to any path:

```lua
require("bible_ref").setup({
  json_path = "/path/to/your/bible.json",
})
```
