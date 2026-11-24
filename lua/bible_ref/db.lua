--- lua/bible_ref/db.lua
--- JSON Bible loader, lazy per-version indexer, verse lookup, and range assembly.
---
--- Every dataset is keyed by its version tag (e.g. "ESV", "KJV", "SBLGNT").
--- Datasets are read and indexed only the first time a tag is queried —
--- never at plugin load, never all-at-once.

local M = {}

-- Internal state (populated lazily, per version tag)
local _indices = {} -- { [tag] = { ["Book|ch|v"] = "verse text", ... } }
local _loaded  = {} -- { [tag] = true }
local _paths   = {} -- { [tag] = "/abs/path/to/bible_<tag>.json" }
local _sizes   = {} -- { [tag] = { [book] = { chapters = n, verses = { [ch] = max_v } } }

local function config()
  return require("bible_ref.config")
end

-- ---------------------------------------------------------------------------
-- Path registration
-- ---------------------------------------------------------------------------

--- Register dataset paths keyed by version tag. Resets any cached indices.
---@param paths table { [tag] = "/abs/path.json", ... }
function M.set_paths(paths)
  _paths = {}
  for tag, path in pairs(paths or {}) do
    _paths[tag] = path
  end
  _indices = {}
  _loaded  = {}
  _sizes   = {}
end

--- Set the dataset path for the currently active version (v1 backward-compat).
---@param path string
function M.set_path(path)
  local v = config().get_current_version()
  M.set_paths({ [v and v.tag or "DEFAULT"] = path })
end

-- ---------------------------------------------------------------------------
-- JSON reading & indexing
-- ---------------------------------------------------------------------------

--- Build the internal lookup index from decoded JSON.
--- Supports both schemas:
---   1. Flat map:          { "Genesis 1:1": "text", ... }
---   2. Array of objects:  [ { book, chapter, verse, text }, ... ]
---@param idx table target index table (to be filled)
---@param decoded any raw decoded Lua value
local function build_index(idx, decoded)
  if type(decoded) ~= "table" then return end

  if vim.islist and (vim.islist(decoded) or (#decoded > 0 and decoded[1] ~= nil)) then
    -- Array-of-objects schema
    for _, entry in ipairs(decoded) do
      if entry.book and entry.chapter and entry.verse and entry.text then
        local key = string.format("%s|%d|%d", entry.book, tonumber(entry.chapter), tonumber(entry.verse))
        idx[key] = entry.text
      end
    end
  else
    -- Flat map schema
    for ref_str, text in pairs(decoded) do
      local book, ch, v = ref_str:match("^(.-)%s+(%d+):(%d+)$")
      if book and ch and v then
        local key = string.format("%s|%d|%d", book, tonumber(ch), tonumber(v))
        idx[key] = text
      end
    end
  end
end

--- Read, parse, and index one dataset. Safe to call repeatedly; loads once.
--- Missing files or parse failures produce a notification and an empty index,
--- never a runtime error.
---@param tag string
local function load_version(tag)
  if _loaded[tag] then return end

  local idx = {}
  local path = _paths[tag] or config().version_path(tag)
  if path and vim.fn.filereadable(path) == 1 then
    local ok, err = pcall(function()
      local f = io.open(path, "r")
      if not f then error("cannot open " .. tostring(path)) end
      local raw = f:read("*a")
      f:close()
      local decoded = vim.json.decode(raw)
      build_index(idx, decoded)
    end)
    if not ok then
      vim.notify("[bible_ref] Failed to load dataset '" .. tag
        .. "': " .. tostring(err), vim.log.levels.ERROR)
    end
  elseif path then
    vim.notify("[bible_ref] Dataset for '" .. tag .. "' not found: " .. path,
      vim.log.levels.WARN)
  end

  _indices[tag] = idx
  _loaded[tag]  = true
end

--- Resolve a version argument (tag string, 1-based index, or nil = current)
--- to a version tag.
---@param arg string|number|nil
---@return string tag
local function resolve_tag(arg)
  local cfg = config()
  if arg == nil then
    local v = cfg.get_current_version()
    return v and v.tag or "DEFAULT"
  end
  if type(arg) == "number" then
    local v = cfg.get_version(arg)
    return v and v.tag or tostring(arg)
  end
  local v = cfg.get_version(arg)
  if v then return v.tag end
  return tostring(arg):upper()
end

-- ---------------------------------------------------------------------------
-- Lookup API
-- ---------------------------------------------------------------------------

--- Lookup a single verse.
---
--- Dual signature:
---   M.lookup(book, chapter, verse)                          -- active version
---   M.lookup(version_tag_or_idx, book, chapter, verse)      -- explicit version
---
---@param arg1 string|number  book (3-arg form) or version tag/index (4-arg form)
---@param arg2 string|number  chapter (3-arg) or book (4-arg)
---@param arg3 number         verse (3-arg) or chapter (4-arg)
---@param arg4 number|nil     verse (4-arg form only)
---@return string verse text, or a graceful "not present" message
function M.lookup(arg1, arg2, arg3, arg4)
  local tag, book, chapter, verse
  if arg4 ~= nil then
    tag, book, chapter, verse = resolve_tag(arg1), arg2, arg3, arg4
  else
    tag, book, chapter, verse = resolve_tag(nil), arg1, arg2, arg3
  end

  load_version(tag)
  local ch = tonumber(chapter) or 0
  local v  = tonumber(verse) or 0
  local key = string.format("%s|%d|%d", tostring(book), ch, v)

  local text = _indices[tag] and _indices[tag][key]
  if text then return text end
  return string.format("[%s %d:%d — not present in %s]", tostring(book), ch, v, tag)
end

--- Lookup a verse range. Concatenates verses with a space separator.
---
--- Dual signature:
---   M.lookup_range(book, chapter, v_start, v_end)                   -- active version
---   M.lookup_range(version_tag_or_idx, book, chapter, v_start, v_end)
---
---@param arg1 string|number  book (4-arg) or version tag/index (5-arg)
---@param arg2 string|number  chapter (4-arg) or book (5-arg)
---@param arg3 number         v_start (4-arg) or chapter (5-arg)
---@param arg4 number         v_end (4-arg) or v_start (5-arg)
---@param arg5 number|nil     v_end (5-arg form only)
---@return string
function M.lookup_range(arg1, arg2, arg3, arg4, arg5)
  local tag, book, chapter, v_start, v_end
  if arg5 ~= nil then
    tag, book, chapter, v_start, v_end = resolve_tag(arg1), arg2, arg3, arg4, arg5
  else
    tag, book, chapter, v_start, v_end = resolve_tag(nil), arg1, arg2, arg3, arg4
  end

  load_version(tag)
  local idx = _indices[tag] or {}
  local ch  = tonumber(chapter) or 0
  local vs  = tonumber(v_start) or 0
  local ve  = tonumber(v_end) or vs
  if ve < vs then vs, ve = ve, vs end

  local parts   = {}
  local missing = 0
  for v = vs, ve do
    local text = idx[string.format("%s|%d|%d", tostring(book), ch, v)]
    if text then
      parts[#parts + 1] = string.format("[%d] %s", v, text)
    else
      parts[#parts + 1] = string.format("[%d] (verse not found)", v)
      missing = missing + 1
    end
  end

  if missing == (ve - vs + 1) then
    -- Entire range absent (e.g. an OT reference against the NT-only SBLGNT)
    return string.format("[%s %d:%d–%d — not present in %s]", tostring(book), ch, vs, ve, tag)
  end
  return table.concat(parts, " ")
end

--- Return all entries for a version, sorted in canonical book order.
---@param version_tag_or_idx string|number|nil
---@return table[] { key, label, ref = {book,chapter,verse_start}, text }
function M.all_entries(version_tag_or_idx)
  local tag = resolve_tag(version_tag_or_idx)
  load_version(tag)
  local idx = _indices[tag] or {}

  local sbl   = require("bible_ref.sbl")
  local order = sbl.book_order or {}

  local results = {}
  for key, text in pairs(idx) do
    local book, ch, v = key:match("^(.-)|(%d+)|(%d+)$")
    if book then
      local ref = { book = book, chapter = tonumber(ch), verse_start = tonumber(v) }
      results[#results + 1] = {
        key   = key,
        ref   = ref,
        text  = text,
        label = sbl.format(ref) .. " — " .. text:sub(1, 80),
      }
    end
  end

  table.sort(results, function(a, b)
    local oa = order[a.ref.book:lower()] or 999
    local ob = order[b.ref.book:lower()] or 999
    if oa ~= ob then return oa < ob end
    if a.ref.chapter ~= b.ref.chapter then return a.ref.chapter < b.ref.chapter end
    return a.ref.verse_start < b.ref.verse_start
  end)
  return results
end

-- ---------------------------------------------------------------------------
-- Canonical size & verse stepping (F2)
-- ---------------------------------------------------------------------------

--- Per-tag book/chapter sizes derived from the dataset's index.
--- Built lazily on first use and cached; cleared by set_paths().
---@param tag string
local function sizes_for(tag)
  if _sizes[tag] then return _sizes[tag] end
  local idx = _indices[tag] or {}
  local map = {}
  for key in pairs(idx) do
    local book, ch, v = key:match("^(.-)|(%d+)|(%d+)$")
    if book then
      ch, v = tonumber(ch), tonumber(v)
      local b = map[book]
      if not b then
        b = { chapters = 0, verses = {} }
        map[book] = b
      end
      if ch > b.chapters then b.chapters = ch end
      if v > (b.verses[ch] or 0) then b.verses[ch] = v end
    end
  end
  _sizes[tag] = map
  return map
end

--- Highest chapter number for `book` in a dataset, or nil if the book is
--- absent from the dataset entirely.
---@param book string canonical book name, e.g. "James"
---@param tag string|number|nil version tag/index (default: active version)
---@return number|nil
function M.max_chapter(book, tag)
  local t = resolve_tag(tag)
  load_version(t)
  local b = sizes_for(t)[tostring(book)]
  return b and b.chapters or nil
end

--- Highest verse number for `book` chapter in a dataset, or nil if the
--- chapter is absent from the dataset.
---@param book string canonical book name, e.g. "James"
---@param chapter number
---@param tag string|number|nil version tag/index (default: active version)
---@return number|nil
function M.max_verse(book, chapter, tag)
  local t = resolve_tag(tag)
  load_version(t)
  local b = sizes_for(t)[tostring(book)]
  return b and b.verses[tonumber(chapter) or 0] or nil
end

--- The canonical verse after `ref` within a dataset.
---
--- A range steps from its end: 3:1–3 → 3:4. Chapter boundaries step to the
--- next chapter's first verse. Returns nil at the last verse of a book (or
--- when the book is absent from the dataset) — callers notify.
---
---@param ref { book: string, chapter: number, verse_start: number, verse_end?: number }
---@param tag string|number|nil version tag/index (default: active version)
---@return { book: string, chapter: number, verse_start: number }|nil
function M.next_verse(ref, tag)
  local t  = resolve_tag(tag)
  load_version(t)
  local book = tostring(ref.book)
  local ch   = tonumber(ref.chapter) or 0
  local ve   = tonumber(ref.verse_end or ref.verse_start) or 0
  local b    = sizes_for(t)[book]
  if not b then return nil end

  local mv = b.verses[ch]
  if mv and ve < mv then
    return { book = book, chapter = ch, verse_start = ve + 1 }
  end
  if ch < b.chapters then
    return { book = book, chapter = ch + 1, verse_start = 1 }
  end
  return nil
end

--- The canonical verse before `ref` within a dataset.
---
--- A range steps to the verse before its start: 3:2–4 → 3:1. Chapter
--- boundaries step to the last verse of the previous chapter. Returns nil
--- at the first verse of a book (or when the book is absent from the
--- dataset) — callers notify.
---
---@param ref { book: string, chapter: number, verse_start: number, verse_end?: number }
---@param tag string|number|nil version tag/index (default: active version)
---@return { book: string, chapter: number, verse_start: number }|nil
function M.prev_verse(ref, tag)
  local t  = resolve_tag(tag)
  load_version(t)
  local book = tostring(ref.book)
  local ch   = tonumber(ref.chapter) or 0
  local vs   = tonumber(ref.verse_start) or 0
  local b    = sizes_for(t)[book]
  if not b then return nil end

  if vs > 1 then
    return { book = book, chapter = ch, verse_start = vs - 1 }
  end
  if ch > 1 then
    local mv = b.verses[ch - 1]
    if mv then
      return { book = book, chapter = ch - 1, verse_start = mv }
    end
  end
  return nil
end

--- Return true if the dataset for a version has been loaded.
---@param version_tag_or_idx string|number|nil
---@return boolean
function M.is_loaded(version_tag_or_idx)
  local tag = resolve_tag(version_tag_or_idx)
  return _loaded[tag] == true
end

return M
