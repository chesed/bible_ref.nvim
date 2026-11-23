--- lua/bible_ref/ui/float.lua
--- LSP-style floating window for displaying Bible verse previews.
--- Supports multi-version cycling: press <space> inside the float to switch versions.

local M = {}

local logos = require("bible_ref.logos")

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
--- Open an LSP-style floating window showing the verse preview.
--- Supports both:
---   M.show(ref_str, verse_text)
---   M.show(ref_str, book, chapter, verse, version_index)
--- @param ref_str       string       SBL-formatted reference (e.g. "Jas 3:1")
--- @param arg2          string       verse_text or canonical book name
--- @param arg3          number|nil   chapter (if multi-arg)
--- @param arg4          number|nil   verse (if multi-arg)
--- @param arg5          number|nil   version_index (if multi-arg)
function M.show(ref_str, arg2, arg3, arg4, arg5)
  local verse_text, book, chapter, verse, version_index
  if type(arg2) == "string" and (arg3 == nil or type(arg3) ~= "number") then
    -- Called as M.show(ref_str, verse_text)
    verse_text    = arg2
    version_index = 1
  else
    book          = arg2
    chapter       = arg3
    verse         = arg4
    version_index = arg5 or 1
    local db      = require("bible_ref.db")
    verse_text    = db.lookup(version_index, book, chapter, verse)
  end

  -- Determine window size
  local max_width = math.min(70, vim.o.columns - 4)

  -- Build content lines
  local body_lines = wrap(verse_text or "", max_width - 2)

  -- Footer
  local footer = string.format("[%s] Open in Logos.com    [q/Esc] Close", ref_str)

  local content = {}
  table.insert(content, " " .. ref_str)                    -- header (indent 1)
  table.insert(content, "")                                 -- blank line before body
  for _, l in ipairs(body_lines) do
    table.insert(content, " " .. l)
  end
  table.insert(content, "")
  table.insert(content, " " .. footer)

  local height = #content
  local width  = max_width

  -- Create a scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.api.nvim_set_option_value("bufhidden", "wipe",     { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false,     { buf = buf })
  vim.api.nvim_set_option_value("filetype", "bible_ref", { buf = buf })

  -- Store version and reference info in buffer-local variables for keymap access
  vim.b[buf].bible_ref_version = version_index
  vim.b[buf].bible_ref_book    = book
  vim.b[buf].bible_ref_chapter = chapter
  vim.b[buf].bible_ref_verse   = verse
  vim.b[buf].bible_ref_str     = ref_str

  -- Open the floating window
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

  -- Window options
  vim.api.nvim_set_option_value("wrap",        true,  { win = win })
  vim.api.nvim_set_option_value("cursorline",  false, { win = win })
  vim.api.nvim_set_option_value("foldenable",  false, { win = win })

  -- Highlight header bold if possible
  vim.api.nvim_buf_add_highlight(buf, -1, "Title", 0, 0, -1)

  -- Keymaps: close
  local close = function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set("n", "q",     close, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true, silent = true })

  -- Keymaps: open in Logos
  vim.keymap.set("n", "l", function()
    close()
    logos.open(ref_str)
  end, { buffer = buf, nowait = true, silent = true })

  -- Keymaps: cycle versions on <Space> (when book/chapter/verse are known)
  vim.keymap.set("n", "<Space>", function()
    local b_book    = vim.b[buf].bible_ref_book
    local b_chapter = vim.b[buf].bible_ref_chapter
    local b_verse   = vim.b[buf].bible_ref_verse
    if not b_book or not b_chapter or not b_verse then
      return
    end

    local ver_idx = vim.b[buf].bible_ref_version or 1
    local ok_cfg, config = pcall(require, "bible_ref.config")
    local db = require("bible_ref.db")
    local next_ver = (ok_cfg and config.next_version) and config.next_version(ver_idx) or 1

    local new_text = db.lookup(next_ver, b_book, b_chapter, b_verse)
    if not new_text then
      vim.notify("[bible_ref] Verse not found in version " .. tostring(next_ver), vim.log.levels.WARN)
      return
    end

    local new_body = wrap(new_text, max_width - 2)
    local new_content = {}
    table.insert(new_content, " " .. ref_str)
    table.insert(new_content, "")
    for _, l in ipairs(new_body) do
      table.insert(new_content, " " .. l)
    end
    table.insert(new_content, "")
    table.insert(new_content, " " .. footer)

    vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_content)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

    vim.b[buf].bible_ref_version = next_ver
  end, { buffer = buf, nowait = true, silent = true })

  -- Auto-close when focus leaves the float
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer  = buf,
    once    = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })
end

return M
