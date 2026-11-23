--- lua/bible_ref/ui/float.lua
--- LSP-style floating window for Bible verse previews with version cycling.
---
--- Keymaps inside the float (normal mode):
---   <Space> / <Tab>   next version
---   <S-Tab>           previous version
---   l                 open reference on logos.com
---   q / <Esc>         close

local M = {}

local logos = require("bible_ref.logos")

local FOOTER = "[Space/Tab] Next Version  [S-Tab] Prev Version  [l] Logos  [q/Esc] Close"

-- ---------------------------------------------------------------------------
-- Wrap `text` to lines of at most `width` characters.
---@param text string
---@param width number
---@return string[]
local function wrap(text, width)
  local lines = {}
  local current = ""
  for word in text:gmatch("%S+") do
    if #current == 0 then
      current = word
    elseif #current + 1 + #word <= width then
      current = current .. " " .. word
    else
      table.insert(lines, current)
      current = word
    end
  end
  if #current > 0 then
    table.insert(lines, current)
  end
  return lines
end

-- ---------------------------------------------------------------------------
-- Argument normalization
-- ---------------------------------------------------------------------------

--- Normalize the supported call signatures into a common shape:
---   M.show(ref_table, initial_version_idx?)     — structured reference
---   M.show(ref_str, verse_text)                 — v1 backward-compat
---   M.show(ref_str, book, chapter, verse, initial_version_idx?)  — v1 multi-arg
---@return table { ref?, ref_str, preset_text?, initial_idx? }
local function normalize_args(arg1, arg2, arg3, arg4, arg5)
  local sbl = require("bible_ref.sbl")

  if type(arg1) == "table" then
    local ref = arg1
    return {
      ref         = ref,
      ref_str     = sbl.format({
        book = ref.book, chapter = ref.chapter,
        verse_start = ref.verse_start, verse_end = ref.verse_end,
      }),
      initial_idx = arg2,
    }
  end

  if type(arg2) == "string" and (arg3 == nil or type(arg3) ~= "number") then
    -- v1: M.show(ref_str, verse_text)
    return { ref_str = arg1, preset_text = arg2, initial_idx = nil }
  end

  -- v1: M.show(ref_str, book, chapter, verse, initial_version_idx?)
  local ref = { book = arg2, chapter = arg3, verse_start = arg4 }
  return {
    ref         = ref,
    ref_str     = arg1,
    initial_idx = arg5,
  }
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Open the floating verse preview.
---
--- Preferred:  M.show({ book, chapter, verse_start, verse_end? }, initial_version_idx?)
--- Compat:     M.show(ref_str, verse_text)
---
---@param arg1 table|string  reference table, or SBL reference string
---@param arg2 any           see module docs
function M.show(arg1, arg2, arg3, arg4, arg5)
  local cfg = require("bible_ref.config")
  local db  = require("bible_ref.db")

  local spec = normalize_args(arg1, arg2, arg3, arg4, arg5)
  local ref  = spec.ref

  -- Resolve the starting version (accepts index, tag, or nil = current)
  local versions = cfg.get_versions()
  local start_idx
  if type(spec.initial_idx) == "string" then
    start_idx = cfg.find_version_index(spec.initial_idx) or cfg.get_current_version_index()
  elseif type(spec.initial_idx) == "number" and spec.initial_idx >= 1
      and spec.initial_idx <= #versions then
    start_idx = spec.initial_idx
  else
    start_idx = cfg.get_current_version_index()
  end
  local start_version = cfg.get_version(start_idx)

  -- Fetch the verse (or range) text for the starting version
  local function verse_text_for(tag)
    if ref.verse_end and ref.verse_end ~= ref.verse_start then
      return db.lookup_range(tag, ref.book, ref.chapter, ref.verse_start, ref.verse_end)
    end
    return db.lookup(tag, ref.book, ref.chapter, ref.verse_start)
  end

  local max_content_width = math.min(80, vim.o.columns - 4)

  --- Build the full content lines + window dimensions for a given version.
  local function build_content(text, version)
    local body   = wrap(text or "", max_content_width - 2)
    local header
    if version then
      header = spec.ref_str .. "  [Version: " .. tostring(version.tag) .. "]"
    else
      header = spec.ref_str
    end

    local content = { " " .. header, "" }
    for _, line in ipairs(body) do
      content[#content + 1] = " " .. line
    end
    content[#content + 1] = ""
    content[#content + 1] = " " .. (ref and FOOTER or "[l] Logos    [q/Esc] Close")

    -- Dynamic width: fit the longest line, clamped to sane bounds
    local longest = #header
    for _, line in ipairs(body) do
      if #line > longest then longest = #line end
    end
    local width = math.max(40, math.min(longest + 4, max_content_width))
    return content, width, #content
  end

  local start_text
  if spec.preset_text then
    start_text = spec.preset_text
  elseif ref then
    start_text = verse_text_for(start_version.tag)
  else
    start_text = ""
  end

  local content, width, height = build_content(start_text, start_version)

  -- Scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.api.nvim_set_option_value("bufhidden", "wipe",     { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false,     { buf = buf })
  vim.api.nvim_set_option_value("filetype", "bible_ref", { buf = buf })

  -- Buffer-local state for the keymaps
  vim.b[buf].version_index = start_idx
  vim.b[buf].bible_ref_ref = ref
  vim.b[buf].bible_ref_str = spec.ref_str

  -- Floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor",
    row      = 1,
    col      = 0,
    width    = width,
    height   = height,
    style    = "minimal",
    border   = "rounded",
    zindex   = 50,
  })

  vim.api.nvim_set_option_value("wrap",       true,  { win = win })
  vim.api.nvim_set_option_value("cursorline", false, { win = win })
  vim.api.nvim_set_option_value("foldenable", false, { win = win })

  -- Highlight the header line
  vim.api.nvim_buf_add_highlight(buf, -1, "Title", 0, 0, 1)

  -- Close
  local close = function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set("n", "q",     close, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true, silent = true })

  -- Logos
  vim.keymap.set("n", "l", function()
    close()
    logos.open(spec.ref_str)
  end, { buffer = buf, nowait = true, silent = true })

  -- Version cycling (only possible when we have a structured reference)
  if ref then
    local function cycle(direction)
      local n = #versions
      if n < 2 then
        vim.notify("[bible_ref] Only one dataset is available", vim.log.levels.INFO)
        return
      end
      local cur = vim.b[buf].version_index or cfg.get_current_version_index()
      local next_idx = direction > 0
        and cfg.next_version_index(cur)
        or cfg.prev_version_index(cur)
      local v    = cfg.get_version(next_idx)
      local text = verse_text_for(v.tag)

      local new_content, new_width, new_height = build_content(text, v)

      vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_content)
      vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

      vim.b[buf].version_index = next_idx
      cfg.set_current_version_index(next_idx) -- keep global state in sync

      vim.api.nvim_win_set_config(win, {
        width  = new_width,
        height = new_height,
      })
    end

    vim.keymap.set("n", "<Space>", function() cycle(1)  end,
      { buffer = buf, nowait = true, silent = true, desc = "bible_ref: next version" })
    vim.keymap.set("n", "<Tab>",   function() cycle(1)  end,
      { buffer = buf, nowait = true, silent = true, desc = "bible_ref: next version" })
    vim.keymap.set("n", "<S-Tab>", function() cycle(-1) end,
      { buffer = buf, nowait = true, silent = true, desc = "bible_ref: previous version" })
  end

  -- Auto-close when focus leaves the float
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    once   = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })
end

return M
