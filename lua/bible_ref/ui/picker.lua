--- lua/bible_ref/ui/picker.lua
--- Fuzzy verse picker with fzf-lua primary, vim.ui.select fallback.
---
--- On <CR>:       inserts SBL-formatted reference at the saved cursor position
---                (appends the version tag when opts.picker.append_version = true
---                 and the active version is not the default dataset)
--- On <C-l>/<C-o>: opens the highlighted verse on logos.com
--- On <C-v>:      (fzf-lua) cycles to the next dataset version and reopens the
---                picker with that version's entries

local M = {}

local db = require("bible_ref.db")
local sbl = require("bible_ref.sbl")
local logos = require("bible_ref.logos")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

--- Insert text at a saved {win, row, col} position.
local function insert_at(target, text)
	local target_win, target_buf = target.win, target.buf
	if not vim.api.nvim_win_is_valid(target_win) then
		vim.notify("[bible_ref] Target window no longer valid", vim.log.levels.WARN)
		return
	end
	local row, col = target.row, target.col
	vim.api.nvim_set_current_win(target_win)
	local line = vim.api.nvim_buf_get_lines(target_buf, row - 1, row, false)[1] or ""
	local new_line = line:sub(1, col) .. text .. line:sub(col + 1)
	vim.api.nvim_buf_set_lines(target_buf, row - 1, row, false, { new_line })
	vim.api.nvim_win_set_cursor(target_win, { row, col + #text })
end

--- True when the user opted into appending the version tag on insert.
--- The merged user options, or nil before setup().
local function user_opts()
	local ok, api = pcall(require, "bible_ref")
	if ok and type(api.opts) == "function" then
		local ok2, o = pcall(api.opts)
		if ok2 and type(o) == "table" then
			return o
		end
	end
	return nil
end

--- True when the user opted into appending the version tag on insert.
local function append_version_enabled()
	local o = user_opts()
	if o and type(o.picker) == "table" then
		return o.picker.append_version == true
	end
	return false
end

--- Build the text to insert for an entry (SBL ref, optional version tag).
local function insert_text_for(entry)
	local ref_str = sbl.format(entry.ref)
	local cfg = require("bible_ref.config")
	local versions = cfg.get_versions()
	local v = cfg.get_current_version()
	local default = versions[cfg.get_default_version_index()]
	if v and default and v.tag ~= default.tag and append_version_enabled() then
		ref_str = ref_str .. " " .. v.tag
	end
	return ref_str
end

--- Accept the entry: insert at the saved target position.
local function accept_entry(entry, target)
	insert_at(target, insert_text_for(entry))
end

--- Resolve the picker backend from user config ("auto" | "fzf-lua" | "select").
local function choose_backend()
	local be = "auto"
	local o = user_opts()
	if o and type(o.picker) == "table" and type(o.picker.backend) == "string" then
		be = o.picker.backend
	end
	local has_fzf = pcall(require, "fzf-lua")
	if be == "auto" then
		return has_fzf and "fzf-lua" or "select"
	end
	if be == "fzf-lua" then
		if has_fzf then
			return "fzf-lua"
		end
		vim.notify("[bible_ref] fzf-lua not available; falling back to vim.ui.select", vim.log.levels.WARN)
		return "select"
	end
	return "select"
end

-- ---------------------------------------------------------------------------
-- fzf-lua picker
-- ---------------------------------------------------------------------------

local function open_fzf(target, version)
	local cfg = require("bible_ref.config")
	local fzf = require("fzf-lua")

	local entries = db.all_entries(version.tag)
	if #entries == 0 then
		vim.notify(
			"[bible_ref] No verses in dataset '" .. version.tag .. "'. Check your data directory.",
			vim.log.levels.WARN
		)
		return
	end

	local labels = {}
	local by_label = {}
	for _, e in ipairs(entries) do
		labels[#labels + 1] = e.label
		by_label[e.label] = e
	end

	fzf.fzf_exec(labels, {
		prompt = string.format("Bible [%s] > ", version.tag),
		previewer = false,
		actions = {
			-- <CR>: insert SBL reference
			["default"] = function(selected)
				if selected and selected[1] and by_label[selected[1]] then
					accept_entry(by_label[selected[1]], target)
				end
			end,
			-- <C-l> / <C-o>: open in Logos
			["ctrl-l"] = function(selected)
				if selected and selected[1] and by_label[selected[1]] then
					logos.open(sbl.format(by_label[selected[1]].ref))
				end
			end,
			["ctrl-o"] = function(selected)
				if selected and selected[1] and by_label[selected[1]] then
					logos.open(sbl.format(by_label[selected[1]].ref))
				end
			end,
			-- <C-v>: cycle version and reopen the picker on the new dataset
			["tab"] = function()
				local versions = cfg.get_versions()
				if #versions < 2 then
					vim.notify("[bible_ref] Only one dataset is available", vim.log.levels.INFO)
					return
				end
				local nidx = cfg.next_version_index(cfg.get_current_version_index())
				cfg.set_current_version_index(nidx)
				local nv = cfg.get_version(nidx)
				vim.notify(string.format("[bible_ref] Bible dataset: %s", nv.tag), vim.log.levels.INFO)
				open_fzf(target, nv)
			end,
		},
	})
end

-- ---------------------------------------------------------------------------
-- vim.ui.select fallback
-- ---------------------------------------------------------------------------

local function open_select(target, version)
	local entries = db.all_entries(version.tag)
	if #entries == 0 then
		vim.notify(
			"[bible_ref] No verses in dataset '" .. version.tag .. "'. Check your data directory.",
			vim.log.levels.WARN
		)
		return
	end

	local labels = {}
	local by_label = {}
	for _, e in ipairs(entries) do
		labels[#labels + 1] = e.label
		by_label[e.label] = e
	end

	vim.ui.select(labels, {
		prompt = string.format("Bible [%s] verse: ", version.tag),
		format_item = function(item)
			return item
		end,
	}, function(choice)
		if choice and by_label[choice] then
			accept_entry(by_label[choice], target)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Open the Bible verse picker on the currently active dataset version.
function M.open()
	local cfg = require("bible_ref.config")
	local versions = cfg.get_versions()
	if #versions == 0 then
		vim.notify("[bible_ref] No Bible datasets found. Check your data directory.", vim.log.levels.WARN)
		return
	end
	local version = cfg.get_current_version()

	-- Capture target context BEFORE opening the picker so text can be inserted
	-- at the right place after it closes.
	local target = {
		win = vim.api.nvim_get_current_win(),
		buf = vim.api.nvim_get_current_buf(),
	}
	local cursor = vim.api.nvim_win_get_cursor(target.win)
	target.row = cursor[1] -- 1-indexed
	target.col = cursor[2] -- 0-indexed byte col

	if choose_backend() == "fzf-lua" then
		open_fzf(target, version)
	else
		open_select(target, version)
	end
end

return M
