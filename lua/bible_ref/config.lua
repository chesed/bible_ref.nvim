--- lua/bible_ref/config.lua
--- Version registry: dynamic dataset discovery, labels, and stateful rotation.
---
--- Datasets live under a data directory (default: <plugin_root>/data/):
---   bible.json         → tag "ESV"  (primary / fallback dataset)
---   bible_<tag>.json   → tag = <tag>:upper()  (e.g. bible_kjv.json → "KJV")
---
--- Discovery is lazy: the directory is scanned on first use, never at module
--- load time.

local M = {}

-- ---------------------------------------------------------------------------
-- Human-readable labels for well-known tags. Unknown tags fall back to the
-- uppercase tag itself.
-- ---------------------------------------------------------------------------
local KNOWN_LABELS = {
  ESV      = "English Standard Version (ESV)",
  KJV      = "King James Version",
  SBLGNT   = "SBL Greek New Testament",
  SBL      = "SBL Greek New Testament",
  ASV      = "American Standard Version",
  WEB      = "World English Bible",
  NIV      = "New International Version",
  NRSV     = "New Revised Standard Version",
  NRSU     = "New Revised Standard Version (Updated)",
  RSV      = "Revised Standard Version",
  YLT      = "Young's Literal Translation",
  BBE      = "Bible in Basic English",
  CUV      = "Chinese Union Version",
  -- Tag keys with a hyphen are not valid Lua identifiers, so they must be
  -- quoted (bible_wlc-sblgnt.json → tag "WLC-SBLGNT").
  ["WLC-SBLGNT"] = "Westminster Leningrad Codex + SBL Greek NT",
}

-- ---------------------------------------------------------------------------
-- Internal state
-- ---------------------------------------------------------------------------
local _versions = nil -- ordered list of { tag, file, path, label, aliases }
local _current  = 1    -- 1-based index into _versions

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------

--- Resolve the default data directory: <plugin_root>/data.
---@return string
local function default_data_dir()
  -- config.lua → lua/bible_ref/config.lua → root is three levels up
  local src = debug.getinfo(1, "S").source:sub(2) -- strip leading "@"
  local root = vim.fn.fnamemodify(src, ":h:h:h")
  return root .. "/data"
end

-- ---------------------------------------------------------------------------
-- Discovery
-- ---------------------------------------------------------------------------

--- Build one version entry from a data filename.
---@param filename string
---@param data_dir string
---@return table
local function make_version(filename, data_dir)
  local path = data_dir .. "/" .. filename
  if filename == "bible.json" then
    return {
      tag     = "ESV",
      file    = filename,
      path    = path,
      label   = KNOWN_LABELS.ESV,
      aliases = { "DEFAULT", "PRIMARY" },
    }
  end
  local tag = filename:match("^bible_([%w_%-]+)%.json$"):upper()
  return {
    tag     = tag,
    file    = filename,
    path    = path,
    label   = KNOWN_LABELS[tag] or tag,
    aliases = {},
  }
end

--- Scan a data directory for Bible datasets.
--- Matches `bible.json` and `bible_<tag>.json` (tag: letters, digits,
--- underscores, hyphens). Returns an ordered list with `bible.json` first
--- and the remaining files in alphabetical order (deterministic across
--- sessions).
---@param data_dir string|nil
---@return table[]
function M.discover_versions(data_dir)
  data_dir = data_dir or default_data_dir()
  local names = {}
  if vim.fn.isdirectory(data_dir) == 1 then
    for _, name in ipairs(vim.fn.readdir(data_dir)) do
      if name == "bible.json" or name:match("^bible_[%w_%-]+%.json$") then
        table.insert(names, name)
      end
    end
  end
  -- "bible.json" sorts before "bible_*.json" because '.' (0x2E) < '_' (0x5F),
  -- so a plain sort already puts the primary dataset first.
  table.sort(names)

  local versions = {}
  for _, name in ipairs(names) do
    table.insert(versions, make_version(name, data_dir))
  end
  return versions
end

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------

--- Configure the version registry.
---
---@param opts table|nil {
---   data_dir?        string   directory to scan (default <plugin_root>/data),
---   versions?        table[]  explicit list of { tag|name, file?, path, label? };
---                             overrides directory discovery,
---   default_version? number|string  starting version (index or tag),
--- }
---@return table[] versions
function M.setup(opts)
  opts = opts or {}

  if opts.versions and #opts.versions > 0 then
    -- User-supplied explicit list (custom names, paths, ordering)
    _versions = {}
    for _, v in ipairs(opts.versions) do
      local tag = tostring(v.tag or v.name or "DEFAULT"):upper()
      table.insert(_versions, {
        tag     = tag,
        file    = v.file,
        path    = v.path,
        label   = v.label or tag,
        aliases = v.aliases or {},
      })
    end
  else
    _versions = M.discover_versions(opts.data_dir)
    if #_versions == 0 then
      -- No datasets found anywhere: register a single placeholder so the UI
      -- layer can report "not present in DEFAULT" instead of crashing.
      local dir = opts.data_dir or default_data_dir()
      _versions = {
        { tag = "DEFAULT", file = "bible.json", path = dir .. "/bible.json",
          label = "Default", aliases = { "ESV" } },
      }
    end
  end

  -- Resolve the starting version (tag/name or 1-based index)
  if type(opts.default_version) == "string" then
    local i = M.find_version_index(opts.default_version)
    if i then _current = i end
  elseif type(opts.default_version) == "number" then
    if opts.default_version >= 1 and opts.default_version <= #_versions then
      _current = opts.default_version
    end
  else
    _current = 1
  end

  return _versions
end

-- ---------------------------------------------------------------------------
-- Lookup helpers
-- ---------------------------------------------------------------------------

--- Find the 1-based index of a version by tag, alias, label, or filename.
--- Matching is case-insensitive.
---@param tag_or_name string
---@return number|nil
function M.find_version_index(tag_or_name)
  local s_up  = tostring(tag_or_name):upper()
  local s_low = tostring(tag_or_name):lower()
  for i, v in ipairs(M.get_versions()) do
    if v.tag == s_up then return i end
    for _, alias in ipairs(v.aliases or {}) do
      if tostring(alias):upper() == s_up then return i end
    end
    if (v.label or ""):lower() == s_low then return i end
    if v.file and v.file == tag_or_name then return i end
  end
  return nil
end

--- Clamp the current index into range (after lazy discovery).
local function clamp_current()
  local n = #M.get_versions()
  if _current < 1 or _current > n then _current = 1 end
  return _current
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Return the ordered list of registered versions (discovers on first call).
---@return table[]
function M.get_versions()
  if not _versions then M.setup({}) end
  return _versions
end

--- Retrieve a version entry by tag/name (string) or 1-based index (number).
---@param tag_or_idx string|number
---@return table|nil entry
---@return number|nil index
function M.get_version(tag_or_idx)
  if type(tag_or_idx) == "number" then
    local v = M.get_versions()
    if tag_or_idx >= 1 and tag_or_idx <= #v then return v[tag_or_idx], tag_or_idx end
    return nil
  end
  local i = M.find_version_index(tag_or_idx)
  if i then return M.get_versions()[i], i end
  return nil
end

--- Current active version index (1-based).
---@return number
function M.get_current_version_index()
  return clamp_current()
end

--- Set the active version by index or tag/name.
---@param idx number|string
---@return number resulting index
function M.set_current_version_index(idx)
  local n = #M.get_versions()
  if type(idx) == "string" then
    local i = M.find_version_index(idx)
    if i then idx = i end
  end
  if type(idx) == "number" and idx >= 1 and idx <= n then
    _current = idx
  end
  return M.get_current_version_index()
end

--- Next version index with wrap-around (1 → 2 → … → N → 1).
---@param current_idx number|nil
---@return number
function M.next_version_index(current_idx)
  local n = #M.get_versions()
  local c = current_idx or clamp_current()
  if n == 0 then return 1 end
  return c >= n and 1 or c + 1
end

--- Previous version index with wrap-around (N → N-1 → … → 1 → N).
---@param current_idx number|nil
---@return number
function M.prev_version_index(current_idx)
  local n = #M.get_versions()
  local c = current_idx or clamp_current()
  if n == 0 then return 1 end
  return c <= 1 and n or c - 1
end

--- Set the active version by tag or name.
---@param tag_or_name string
---@return boolean success
function M.set_version(tag_or_name)
  local i = M.find_version_index(tag_or_name)
  if not i then return false end
  _current = i
  return true
end

--- The currently active version entry.
---@return table|nil
function M.get_current_version()
  return M.get_version(M.get_current_version_index())
end

--- Full path to a version's JSON file.
---@param tag_or_name string
---@return string|nil
function M.version_path(tag_or_name)
  local v = M.get_version(tag_or_name)
  return v and v.path
end

-- ---------------------------------------------------------------------------
-- Backward compatibility (v1 API surface)
-- ---------------------------------------------------------------------------
function M.get_available_versions() return M.get_versions() end
function M.get_default_version()   return M.get_current_version_index() end
function M.set_default_version(idx) return M.set_current_version_index(idx) end
function M.next_version(idx)       return M.next_version_index(idx) end
function M.prev_version(idx)       return M.prev_version_index(idx) end
function M.version_label(name)     local v = M.get_version(name) return v and v.label end
function M.current_version_name(idx)
  local v = M.get_version(idx or M.get_current_version_index())
  return v and v.tag
end

return M
