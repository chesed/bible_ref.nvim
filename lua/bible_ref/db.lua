--- lua/bible_ref/db.lua
--- JSON Bible loader, lazy indexer, verse lookup, and range assembly.
---
--- Expected JSON schema (flat map, most common open-source format):
---   { "Genesis 1:1": "In the beginning...", "Genesis 1:2": "...", ... }
---
--- The module also handles the array-of-objects schema:
---   [ { "book": "Genesis", "chapter": 1, "verse": 1, "text": "..." }, ... ]
---
--- Schema is auto-detected on first load.

local M = {}

-- Internal state (populated lazily on first use)
local _index    = nil  -- { ["Book|ch|v"] = "verse text", ... }
local _loaded   = false
local _json_path = nil -- set by init.lua via M.set_path()

--- Set the path to the JSON Bible dataset.
---@param path string
function M.set_path(path)
  _json_path = path
  -- Reset so a new dataset can be loaded
  _loaded = false
  _index  = nil
end

--- Read and parse the JSON file.  Dies loudly if the file is missing.
---@return table  raw decoded Lua value
local function read_json()
  if not _json_path then
    error("[bible_ref] No JSON dataset path configured. Call setup({ json_path = '...' })")
  end
  local f, err = io.open(_json_path, "r")
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

--- Build the internal lookup index from decoded JSON.
---@param decoded any
local function build_index(decoded)
  _index = {}

  if type(decoded) == "table" then
    -- Detect schema
    if vim.islist and vim.islist(decoded) or (#decoded > 0 and decoded[1] ~= nil) then
      -- Array-of-objects schema: [{book,chapter,verse,text}, ...]
      for _, entry in ipairs(decoded) do
        if entry.book and entry.chapter and entry.verse and entry.text then
          local key = string.format("%s|%d|%d", entry.book, tonumber(entry.chapter), tonumber(entry.verse))
          _index[key] = entry.text
        end
      end
    else
      -- Flat map schema: { "Genesis 1:1": "text", ... }
      for ref_str, text in pairs(decoded) do
        -- Parse "Book Chapter:Verse"
        local book, ch, v = ref_str:match("^(.-)%s+(%d+):(%d+)$")
        if book and ch and v then
          local key = string.format("%s|%d|%d", book, tonumber(ch), tonumber(v))
          _index[key] = text
        end
      end
    end
  end
end

--- Lazy-load: only called once on first use.
local function ensure_loaded()
  if _loaded then return end
  local ok, err = pcall(function()
    local decoded = read_json()
    build_index(decoded)
  end)
  _loaded = true -- mark loaded even on error so we don't retry every call
  if not ok then
    vim.notify("[bible_ref] " .. tostring(err), vim.log.levels.ERROR)
  end
end

--- Lookup a single verse. Returns the verse text or a fallback string.
---@param book string    canonical book name, e.g. "1 Corinthians"
---@param chapter number
---@param verse number
---@return string
function M.lookup(book, chapter, verse)
  ensure_loaded()
  if not _index then return "[bible_ref: dataset not loaded]" end
  local key = string.format("%s|%d|%d", book, chapter, verse)
  return _index[key] or string.format("[%s %d:%d — not found in dataset]", book, chapter, verse)
end

--- Lookup a verse range.  Concatenates verses with a space separator and
--- prepends each verse number in superscript-style (⁽ⁿ⁾ notation not used;
--- just plain "[n] text" for compatibility).
---@param book string
---@param chapter number
---@param verse_start number
---@param verse_end number
---@return string
function M.lookup_range(book, chapter, verse_start, verse_end)
  ensure_loaded()
  if not _index then return "[bible_ref: dataset not loaded]" end

  local parts = {}
  for v = verse_start, verse_end do
    local key  = string.format("%s|%d|%d", book, chapter, v)
    local text = _index[key]
    if text then
      table.insert(parts, string.format("[%d] %s", v, text))
    else
      table.insert(parts, string.format("[%d] (verse not found)", v))
    end
  end

  if #parts == 0 then
    return string.format("[%s %d:%d–%d — not found in dataset]", book, chapter, verse_start, verse_end)
  end
  return table.concat(parts, " ")
end

--- Return all indexed verse keys in sorted order.
--- Used by the picker to populate the fuzzy list.
---@return string[]  entries formatted "SBL_ref — verse text" for display
function M.all_entries()
  ensure_loaded()
  if not _index then return {} end

  local sbl = require("bible_ref.sbl")
  local results = {}
  for key, text in pairs(_index) do
    local book, ch, v = key:match("^(.-)|(%d+)|(%d+)$")
    if book then
      local ref = { book = book, chapter = tonumber(ch), verse_start = tonumber(v) }
      local label = sbl.format(ref) .. " \u{2014} " .. text:sub(1, 80)
      table.insert(results, { key = key, label = label, ref = ref, text = text })
    end
  end

  -- Sort by book order, then chapter, then verse
  -- (Simple lexicographic on key is good enough for the picker display)
  table.sort(results, function(a, b) return a.key < b.key end)
  return results
end

--- Return true if the dataset has been loaded.
function M.is_loaded()
  return _loaded and _index ~= nil
end

return M
