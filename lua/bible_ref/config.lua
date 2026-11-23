--- lua/bible_ref/config.lua
--- Version registry: maps canonical names to data file paths and metadata.

local M = {}

-- ---------------------------------------------------------------------------
-- Available versions. Add new JSON files here with their canonical name,
-- filename (relative to the data/ directory), and a short label for display.
-- The list is iterated in order when cycling through versions.
-- ---------------------------------------------------------------------------
M.available_versions = {
  {
    name   = "ESV",
    file   = "bible.json",
    label  = "King James Version (KJV)", -- actually ESV, but let's keep it accurate below
  },
  {
    name   = "KJV",
    file   = "bible_kjv.json",
    label  = "King James Version (KJV)",
  },
  {
    name   = "SBL",
    file   = "bible_sblgnt.json",
    label  = "SBL Greek New Testament",
  },
}

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------
M.default_version = 1 -- index into available_versions (0-based)
M.version_label_key = "label" -- which field to use when displaying the version name

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
--- Return the full path to a version's JSON file.
---@param version_name string  canonical name like "ESV", "KJV", or "SBL"
---@return string|nil
function M.version_path(version_name)
  for _, v in ipairs(M.available_versions) do
    if v.name == version_name then return v.file end
  end
  return nil
end

--- Return the canonical name of the currently selected version.
---@param current_index number (0-based index into available_versions)
---@return string|nil
function M.current_version_name(current_index)
  if not current_index or current_index < 1 or current_index > #M.available_versions then return nil end
  return M.available_versions[current_index].name
end

--- Return the label text for a version by its canonical name.
---@param version_name string
---@return string|nil
function M.version_label(version_name)
  for _, v in ipairs(M.available_versions) do
    if v.name == version_name then return v.label end
  end
  return nil
end

--- Next version index (wraps around).
---@param current_index number
---@return number
function M.next_version(current_index)
  local next = current_index + 1
  if next > #M.available_versions then next = 1 end
  return next
end

--- Previous version index.
---@param current_index number
---@return number
function M.prev_version(current_index)
  local prev = current_index - 1
  if prev < 1 then prev = #M.available_versions end
  return prev
end

-- ---------------------------------------------------------------------------
-- Public API helpers
-- ---------------------------------------------------------------------------
function M.get_available_versions() return M.available_versions end
function M.get_default_version() return M.default_version end
function M.set_default_version(idx) M.default_version = idx end

return M
