--- lua/bible_ref/ui/float.lua
--- LSP-style floating window for displaying Bible verse previews.

local M = {}

local logos = require("bible_ref.logos")

--- Wrap `text` to lines of at most `width` characters.
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

--- Open an LSP-style floating window showing the verse preview.
---
---@param ref_str  string   SBL-formatted reference (e.g. "Jas 3:1")
---@param verse_text string  Resolved verse/passage text
function M.show(ref_str, verse_text)
  -- Determine window size
  local max_width  = math.min(70, vim.o.columns - 4)
  local separator  = string.rep("\u{2500}", max_width) -- horizontal box-drawing line

  -- Build content lines
  local body_lines = wrap(verse_text, max_width - 2)
  local footer     = "[l] Open in Logos.com  \u{00B7}  [q/Esc] Close"

  local content = {}
  table.insert(content, " " .. ref_str)                    -- header (indent 1)
  table.insert(content, separator)
  for _, l in ipairs(body_lines) do
    table.insert(content, " " .. l)
  end
  table.insert(content, separator)
  table.insert(content, " " .. footer)

  local height = #content
  local width  = max_width

  -- Create a scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
  vim.api.nvim_set_option_value("bufhidden", "wipe",     { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false,     { buf = buf })
  vim.api.nvim_set_option_value("filetype", "bible_ref", { buf = buf })

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
  vim.keymap.set("n", "q",   close, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true, silent = true })

  -- Keymap: open in Logos
  vim.keymap.set("n", "l", function()
    close()
    logos.open(ref_str)
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
