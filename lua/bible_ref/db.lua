--- lua/bible_ref/db.lua
--- JSON Bible loader, lazy indexer, verse lookup, and range assembly.
--- Supports multiple datasets (versions) simultaneously.

local M = {}

-- Internal state (populated lazily on first use per version)
local _index      = {} -- { [version_index] = { ["Book|ch|v"] = "verse text", ... } }
local _loaded     = {} -- { [version_index] = true }
local _json_paths = {} -- set by init.lua via M.set_paths() or M.set_path()

-- ---------------------------------------------------------------------------
-- Set the JSON dataset paths for all versions.
--- @param paths table  { [version_index] = path, ... }
--- Example: M.set_paths({ [1] = "data/bible.json", [2] = "data/bible_kjv.json" })
function M.set_paths(paths)
  _json_paths = paths or {}
  _index      = {}
  _loaded     = {}
end

--- Set the JSON dataset path for the primary version (backward-compatible).
--- @param path string
function M.set_path(path)
  M.set_paths({ [1] = path })
end

-- ---------------------------------------------------------------------------
-- Read and parse the JSON file.  Dies loudly if the file is missing.
--- @param path string
--- @return table  raw decoded Lua value
local function read_json(path)
  if not path then
    error("[bible_ref] No JSON dataset path configured.")
  end
  local f, err = io.open(path, "r")
  if not f then
    error("[bible_ref] Cannot open Bible dataset: " .. tostring(err))
  end
  local raw = f:read("*a")
  f:close()
  -- vim.json.decode is available in Neovim 0.6+
  local ok, decoded = pcall(vim.json.decode, raw)
  if not ok then
    error("[bible_ref] Failed to parse Bible JSON: " .. tostring(decoded))
  end
  return decoded
end

-- ---------------------------------------------------------------------------
-- Build the internal lookup index from decoded JSON.
--- @param version_index number
--- @param decoded any   raw decoded Lua value
local function build_index(version_index, decoded)
  _index[version_index] = {}

  if type(decoded) == "table" then
    -- Detect schema
    if vim.islist and (vim.islist(decoded) or (#decoded > 0 and decoded[1] ~= nil)) then
      -- Array-of-objects schema: [{book, chapter, verse, text}, ...]
      for _, entry in ipairs(decoded) do
        if entry.book and entry.chapter and entry.verse and entry.text then
          local key = string.format("%s|%d|%d", entry.book, tonumber(entry.chapter), tonumber(entry.verse))
          _index[version_index][key] = entry.text
        end
      end
    else
      -- Flat map schema: { "Genesis 1:1": "text", ... }
      for ref_str, text in pairs(decoded) do
        local book, ch, v = ref_str:match("^(.-)%s+(%d+):(%d+)$")
        if book and ch and v then
          local key = string.format("%s|%d|%d", book, tonumber(ch), tonumber(v))
          _index[version_index][key] = text
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Lazy-load: only called once per version.
--- @param version_index number|nil
local function ensure_loaded(version_index)
  version_index = version_index or 1
  if _loaded[version_index] then return end
  local ok, err = pcall(function()
    local path = _json_paths[version_index]
    local decoded = read_json(path)
    build_index(version_index, decoded)
  end)
  _loaded[version_index] = true -- mark loaded even on error so we don't retry every call
  if not ok then
    vim.notify("[bible_ref] " .. tostring(err), vim.log.levels.ERROR)
  end
end

-- ---------------------------------------------------------------------------
-- Lookup a single verse. Returns the verse text or a fallback string.
--- Accepts either:
---   M.lookup(book, chapter, verse)
---   M.lookup(version_index, book, chapter, verse)
--- @param arg1 number|string  version_index (number) or book (string)
--- @param arg2 string|number  book (string) or chapter (number)
--- @param arg3 number         chapter (number) or verse (number)
--- @param arg4 number|nil     verse (number, when version_index is passed)
--- @return string
function M.lookup(arg1, arg2, arg3, arg4)
  local version_index, book, chapter, verse
  if type(arg1) == "string" then
    version_index = 1
    book = arg1
    chapter = arg2
    verse = arg3
  else
    version_index = arg1 or 1
    book = arg2
    chapter = arg3
    verse = arg4
  end

  ensure_loaded(version_index)
  if not _index then return "[bible_ref: dataset not loaded]" end
  local key = string.format("%s|%d|%d", book, tonumber(chapter) or 0, tonumber(verse) or 0)
  return (_index[version_index] or {})[key] or string.format("[%s %s:%s — not found in dataset]", tostring(book), tostring(chapter), tostring(verse))
end

-- ---------------------------------------------------------------------------
--- Lookup a verse range. Concatenates verses with a space separator.
--- Accepts either:
---   M.lookup_range(book, chapter, verse_start, verse_end)
---   M.lookup_range(version_index, book, chapter, verse_start, verse_end)
--- @param arg1 number|string  version_index (number) or book (string)
--- @param arg2 string|number  book (string) or chapter (number)
--- @param arg3 number         chapter (number) or verse_start (number)
--- @param arg4 number         verse_start (number) or verse_end (number)
--- @param arg5 number|nil     verse_end (number, when version_index is passed)
--- @return string
function M.lookup_range(arg1, arg2, arg3, arg4, arg5)
  local version_index, book, chapter, verse_start, verse_end
  if type(arg1) == "string" then
    version_index = 1
    book = arg1
    chapter = arg2
    verse_start = arg3
    verse_end = arg4
  else
    version_index = arg1 or 1
    book = arg2
    chapter = arg3
    verse_start = arg4
    verse_end = arg5
  end

  ensure_loaded(version_index)
  if not _index then return "[bible_ref: dataset not loaded]" end

  local parts = {}
  local v_start = tonumber(verse_start) or 0
  local v_end   = tonumber(verse_end) or 0
  for v = v_start, v_end do
    local key  = string.format("%s|%d|%d", book, tonumber(chapter) or 0, v)
    local text = (_index[version_index] or {})[key]
    if text then
      table.insert(parts, string.format("[%d] %s", v, text))
    else
      table.insert(parts, string.format("[%d] (verse not found)", v))
    end
  end

  if #parts == 0 then
    return string.format("[%s %s:%s–%s — not found in dataset]", tostring(book), tostring(chapter), tostring(verse_start), tostring(verse_end))
  end
  return table.concat(parts, " ")
end

-- ---------------------------------------------------------------------------
--- Return all indexed verse keys in sorted order.
--- @param version_index number|nil
--- @return string[]  entries formatted "SBL_ref — verse text" for display
function M.all_entries(version_index)
  version_index = version_index or 1
  ensure_loaded(version_index)
  if not _index or not _index[version_index] then return {} end

  local sbl = require("bible_ref.sbl")
  local results = {}
  for key, text in pairs(_index[version_index]) do
    local book, ch, v = key:match("^(.-)|(%d+)|(%d+)$")
    if book then
      local ref = { book = book, chapter = tonumber(ch), verse_start = tonumber(v) }
      local label = sbl.format(ref) .. " — " .. text:sub(1, 80)
      table.insert(results, { key = key, label = label, ref = ref, text = text })
    end
  end

  -- Sort by book order, then chapter, then verse
  table.sort(results, function(a, b) return a.key < b.key end)
  return results
end

-- ---------------------------------------------------------------------------
--- Return true if the dataset has been loaded.
--- @param version_index number|nil
function M.is_loaded(version_index)
  version_index = version_index or 1
  return (_loaded[version_index] == true) and (_index[version_index] ~= nil)
end

return M
