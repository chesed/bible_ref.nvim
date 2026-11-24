# Bible Dataset

Place Bible JSON files here. Files are discovered automatically — no
configuration required.

## Naming

| File               | Tag     | Notes                                     |
|--------------------|---------|-------------------------------------------|
| `bible_<tag>.json` | `<TAG>` | A translation (hyphens allowed)           |

`bible_kjv.json` → `KJV`, `bible_web.json` → `WEB`, `bible_wlc-sblgnt.json` →
`WLC-SBLGNT`.

**Default dataset:** when `default_version` is not set, the version tagged
`WEB` is selected if present — otherwise the first dataset in the registry
(alphabetical by filename).

## Private translations

Licensed translations (ESV, NIV, NLT, CSB, …) must **not** be committed. Keep
them in `user/`:

```
data/
├── bible_kjv.json         ← shipped, public domain
├── bible_web.json         ← shipped, public domain (built-in default)
├── bible_wlc-sblgnt.json
└── user/                  ← gitignored, private
    ├── bible_csb.json
    ├── bible_esv.json
    └── ...
```

A file in `user/` with the same name as one directly above it **shadows** the
shipped copy (same name ⇒ same tag), with a one-time warning. Alternatively,
point `setup({ data_dir = "…" })` at a directory anywhere on disk, or list
datasets explicitly with `setup({ versions = { … } })`.

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

Public domain (safe to commit):

- **KJV, ASV, WEB, YLT, BBE:** https://github.com/scrollmapper/bible_databases
- **WLC (Hebrew OT) + SBLGNT (Greek NT):** see `bible_wlc-sblgnt.json`

Licensed (personal use, keep in `user/`):

- **ESV:** https://github.com/acbellini/esv-json
- **NIV, NLT, CSB:** via your publisher account
