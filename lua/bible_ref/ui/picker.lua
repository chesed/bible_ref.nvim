--- lua/bible_ref/ui/picker.lua
--- Fuzzy verse picker with fzf-lua primary, vim.ui.select fallback.
---
--- On <CR>: inserts SBL-formatted reference at saved cursor position.
--- On <C-l> / <C-o>: opens highlighted verse on logos.com.

local M = {}

local db    = require("bible_ref.db")
local sbl   = require("bible_ref.sbl")
local logos = require("bible_ref.logos")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Insert text at a saved {win, row, col} position.
---@param target_win  number  window id
---@param target_buf  number  buffer id
---@param row         number  1-indexed row
---@param col         number  0-indexed byte col
---@param text        string
local function insert_at(target_win, target_buf, row, col, text)
  if not vim.api.nvim_win_is_valid(target_win) then
    vim.notify("[bible_ref] Target window no longer valid", vim.log.levels.WARN)
    return
  end
  vim.api.nvim_set_current_win(target_win)
  local line = vim.api.nvim_buf_get_lines(target_buf, row - 1, row, false)[1] or ""
  local new_line = line:sub(1, col) .. text .. line:sub(col + 1)
  vim.api.nvim_buf_set_lines(target_buf, row - 1, row, false, { new_line })
  -- Move cursor to end of inserted text
  vim.api.nvim_win_set_cursor(target_win, { row, col + #text })
end

--- Build the action callback: format entry and insert it.
---@param entry      table   {ref = {book,chapter,verse_start}, label = string}
---@param target_win number
---@param target_buf number
---@param row        number  1-indexed
---@param col        number  0-indexed byte col
local function accept_entry(entry, target_win, target_buf, row, col)
  local ref_str = sbl.format(entry.ref)
  insert_at(target_win, target_buf, row, col, ref_str)
end

-- ---------------------------------------------------------------------------
-- fzf-lua picker
-- ---------------------------------------------------------------------------
local function open_fzf(entries, target_win, target_buf, row, col)
  local fzf = require("fzf-lua")

  -- Build display items: label string → entry mapping
  local labels = {}
  local by_label = {}
  for _, e in ipairs(entries) do
    table.insert(labels, e.label)
    by_label[e.label] = e
  end

  fzf.fzf_exec(labels, {
    prompt  = "Bible  ",
    previewer = false,
    actions = {
      -- <CR>: insert SBL reference
      ["default"] = function(selected)
        if selected and selected[1] then
          local entry = by_label[selected[1]]
          if entry then
            accept_entry(entry, target_win, target_buf, row, col)
          end
        end
      end,
      -- <C-l>: open in Logos
      ["ctrl-l"] = function(selected)
        if selected and selected[1] then
          local entry = by_label[selected[1]]
          if entry then
            logos.open(sbl.format(entry.ref))
          end
        end
      end,
      -- <C-o>: also open in Logos (alternate binding)
      ["ctrl-o"] = function(selected)
        if selected and selected[1] then
          local entry = by_label[selected[1]]
          if entry then
            logos.open(sbl.format(entry.ref))
          end
        end
      end,
    },
  })
end

-- ---------------------------------------------------------------------------
-- vim.ui.select fallback
-- ---------------------------------------------------------------------------
local function open_select(entries, target_win, target_buf, row, col)
  local labels = {}
  local by_label = {}
  for _, e in ipairs(entries) do
    table.insert(labels, e.label)
    by_label[e.label] = e
  end

  vim.ui.select(labels, {
    prompt = "Bible verse: ",
    format_item = function(item) return item end,
  }, function(choice)
    if choice then
      local entry = by_label[choice]
      if entry then
        accept_entry(entry, target_win, target_buf, row, col)
      end
    end
  end)
end

-- ---------------------------------------------------------------------------
-- Public: open picker
-- ---------------------------------------------------------------------------

--- Open the Bible verse picker.
--- Saves current window/buffer/cursor before opening so text can be inserted
--- at the right place after the picker closes.
function M.open()
  -- Capture target context BEFORE opening picker
  local target_win = vim.api.nvim_get_current_win()
  local target_buf = vim.api.nvim_get_current_buf()
  local cursor     = vim.api.nvim_win_get_cursor(target_win)
  local row        = cursor[1]      -- 1-indexed
  local col        = cursor[2]      -- 0-indexed byte col

  -- Load dataset entries (lazy; first call may take a moment)
  local entries = db.all_entries()
  if #entries == 0 then
    vim.notify("[bible_ref] No verses loaded. Check your json_path setting.", vim.log.levels.WARN)
    return
  end

  -- Choose picker backend
  local has_fzf = pcall(require, "fzf-lua")
  if has_fzf then
    open_fzf(entries, target_win, target_buf, row, col)
  else
    open_select(entries, target_win, target_buf, row, col)
  end
end

return M
