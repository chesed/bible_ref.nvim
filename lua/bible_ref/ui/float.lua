--- lua/bible_ref/ui/float.lua
--- LSP-style floating window for Bible verse previews with version cycling
--- and citation / canonical-verse navigation.
---
--- Keymaps inside the float (normal mode):
---   <Space> / <Tab>   next version
---   <S-Tab>           previous version
---   h                 previous citation in the source document
---   l                 next citation in the source document
---   j                 next canonical verse (wraps chapters, stops at book edge)
---   k                 previous canonical verse (wraps chapters, stops at book edge)
---   H                 jump cursor to the previous citation (float re-anchors)
---   L                 jump cursor to the next citation (float re-anchors)
---   o                 open reference (Logos)
---   q / <Esc>         close

local M = {}

local logos = require("bible_ref.logos")

local FOOTER    = "[Space/Tab] Version  [h/l] Citation  [j/k] Verse  [H/L] Jump  [o] Open  [q/Esc] Close"
local FOOTER_V1 = "[h/l] Citation  [o] Open  [q/Esc] Close"

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
  local cfg   = require("bible_ref.config")
  local db    = require("bible_ref.db")
  local sbl   = require("bible_ref.sbl")
  local parse = require("bible_ref.parse")

  local spec = normalize_args(arg1, arg2, arg3, arg4, arg5)
  local ref  = spec.ref

  -- Source-document tracking (F2): the buffer the float was opened from and
  -- the position of the citation currently displayed. h/l/H/L navigate the
  -- document relative to this position, so repeated presses step through
  -- the document coherently rather than always relative to the original
  -- cursor.
  local src_buf = vim.api.nvim_get_current_buf()
  local sline   = vim.api.nvim_win_get_cursor(0)[1]
  local scol    = vim.api.nvim_win_get_cursor(0)[2]

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

  --- Verse (or range) text for a given version tag and reference.
  local function verse_text_for(tag, r)
    if r.verse_end and r.verse_end ~= r.verse_start then
      return db.lookup_range(tag, r.book, r.chapter, r.verse_start, r.verse_end)
    end
    return db.lookup(tag, r.book, r.chapter, r.verse_start)
  end

  local max_content_width = math.min(80, vim.o.columns - 4)

  --- Build the full content lines + window dimensions for a given version.
  local function build_content(ref_str, text, version)
    local body   = wrap(text or "", max_content_width - 2)
    local header
    if version then
      header = ref_str .. "  [Version: " .. tostring(version.tag) .. "]"
    else
      header = ref_str
    end

    local content = { " " .. header, "" }
    for _, line in ipairs(body) do
      content[#content + 1] = " " .. line
    end
    content[#content + 1] = ""
    content[#content + 1] = " " .. (ref and FOOTER or FOOTER_V1)

    -- Dynamic width: fit the longest line, clamped to sane bounds
    local longest = #ref_str
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
    start_text = verse_text_for(start_version.tag, ref)
  else
    start_text = ""
  end

  local content, width, height = build_content(spec.ref_str, start_text, start_version)

  -- Scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.api.nvim_set_option_value("bufhidden", "wipe",     { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false,     { buf = buf })
  vim.api.nvim_set_option_value("filetype", "bible_ref", { buf = buf })

  -- Buffer-local state for the keymaps
  vim.b[buf].version_index     = start_idx
  vim.b[buf].bible_ref_ref     = ref
  vim.b[buf].bible_ref_str     = spec.ref_str
  vim.b[buf].bible_ref_src_buf = src_buf
  vim.b[buf].bible_ref_pos     = { line = sline, col = scol }

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

  --- Replace the float's content for a new displayed reference, preserving
  --- the currently cycled version. `new_pos` updates the tracked document
  --- position so continued h/l/H/L stepping stays coherent.
  local function update_display(new_ref, new_ref_str, new_pos)
    local idx  = vim.b[buf].version_index
    local v    = cfg.get_version(idx)
    local text
    if new_ref == ref and spec.preset_text then
      text = spec.preset_text
    elseif new_ref then
      text = verse_text_for(v.tag, new_ref)
    else
      text = ""
    end

    local new_content, new_width, new_height = build_content(new_ref_str, text, v)
    vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_content)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_config(win, {
        width  = new_width,
        height = new_height,
      })
    end

    if new_ref then
      vim.b[buf].bible_ref_ref = new_ref
      vim.b[buf].bible_ref_str = new_ref_str
    end
    if new_pos then
      vim.b[buf].bible_ref_pos = new_pos
    end
  end

  --- h/l: step to the previous/next citation in the source document.
  local function nav_citation(direction)
    local src = vim.b[buf].bible_ref_src_buf
    local pos = vim.b[buf].bible_ref_pos
    if not src or not vim.api.nvim_buf_is_valid(src) or not pos then
      vim.notify("[bible_ref] No source document to navigate", vim.log.levels.INFO)
      return
    end
    local target = parse.find_ref_near(src, pos.line, pos.col, direction)
    if not target then
      vim.notify("[bible_ref] No more " .. (direction > 0 and "next" or "previous")
        .. " citation in document", vim.log.levels.INFO)
      return
    end
    update_display(target.ref, sbl.format(target.ref),
      { line = target.line, col = target.col })
  end

  --- j/k: step one canonical verse (wraps chapters, stops at book edges).
  local function nav_verse(direction)
    local r = vim.b[buf].bible_ref_ref or ref
    if not r then
      vim.notify("[bible_ref] Verse stepping needs a structured reference",
        vim.log.levels.INFO)
      return
    end
    local v  = cfg.get_version(vim.b[buf].version_index)
    local nr
    if direction > 0 then
      nr = db.next_verse(r, v.tag)
    else
      nr = db.prev_verse(r, v.tag)
    end
    if not nr then
      vim.notify("[bible_ref] " .. (direction > 0 and "End" or "Beginning") .. " of "
        .. tostring(r.book), vim.log.levels.INFO)
      return
    end
    update_display(nr, sbl.format(nr), nil)
  end

  --- H/L: jump the cursor to the previous/next citation. The float closes
  --- (BufLeave) and reopens anchored at the new citation, version preserved.
  local function jump_citation(direction)
    local src     = vim.b[buf].bible_ref_src_buf
    local pos     = vim.b[buf].bible_ref_pos
    local cur_idx = vim.b[buf].version_index
    if not src or not vim.api.nvim_buf_is_valid(src) or not pos then
      vim.notify("[bible_ref] No source document to navigate", vim.log.levels.INFO)
      return
    end
    local target = parse.find_ref_near(src, pos.line, pos.col, direction)
    if not target then
      vim.notify("[bible_ref] No more " .. (direction > 0 and "next" or "previous")
        .. " citation in document", vim.log.levels.INFO)
      return
    end
    local wins = {}
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(w) == src then wins[#wins + 1] = w end
    end
    if #wins == 0 then
      vim.notify("[bible_ref] Source buffer is not visible", vim.log.levels.WARN)
      return
    end

    -- Move the cursor in the source window; focus leaving the float closes
    -- it via the BufLeave autocmd.
    local swin = wins[1]
    vim.api.nvim_set_current_win(swin)
    pcall(vim.api.nvim_win_set_cursor, swin, { target.line, target.col })
    vim.cmd("normal! zz")
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end

    -- Reopen anchored at the new citation, keeping the cycled version.
    M.show(target.ref, cur_idx)
    -- Restore the exact (unclamped) anchor position for continued stepping.
    local nbuf = vim.api.nvim_get_current_buf()
    vim.b[nbuf].bible_ref_pos = { line = target.line, col = target.col }
  end

  -- Keymaps
  vim.keymap.set("n", "q", close,
    { buffer = buf, nowait = true, silent = true, desc = "bible_ref: close" })
  vim.keymap.set("n", "<Esc>", close,
    { buffer = buf, nowait = true, silent = true, desc = "bible_ref: close" })

  -- Open (Logos, until the Open-logic item ships)
  vim.keymap.set("n", "o", function()
    local rs = vim.b[buf].bible_ref_str or spec.ref_str
    close()
    logos.open(rs)
  end, { buffer = buf, nowait = true, silent = true, desc = "bible_ref: open reference" })

  -- Citation navigation in the source document (h/l)
  vim.keymap.set("n", "h", function() nav_citation(-1) end,
    { buffer = buf, nowait = true, silent = true, desc = "bible_ref: previous citation" })
  vim.keymap.set("n", "l", function() nav_citation(1) end,
    { buffer = buf, nowait = true, silent = true, desc = "bible_ref: next citation" })

  -- Cursor jumps (H/L)
  vim.keymap.set("n", "H", function() jump_citation(-1) end,
    { buffer = buf, nowait = true, silent = true, desc = "bible_ref: jump to previous citation" })
  vim.keymap.set("n", "L", function() jump_citation(1) end,
    { buffer = buf, nowait = true, silent = true, desc = "bible_ref: jump to next citation" })

  if ref then
    -- Canonical verse stepping (j/k)
    vim.keymap.set("n", "j", function() nav_verse(1) end,
      { buffer = buf, nowait = true, silent = true, desc = "bible_ref: next verse" })
    vim.keymap.set("n", "k", function() nav_verse(-1) end,
      { buffer = buf, nowait = true, silent = true, desc = "bible_ref: previous verse" })

    -- Version cycling (only possible when we have a structured reference)
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
      vim.b[buf].version_index = next_idx
      cfg.set_current_version_index(next_idx) -- keep global state in sync
      update_display(vim.b[buf].bible_ref_ref or ref,
        vim.b[buf].bible_ref_str or spec.ref_str, nil)
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
