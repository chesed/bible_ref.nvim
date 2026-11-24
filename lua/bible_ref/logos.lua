--- lua/bible_ref/logos.lua
--- Logos.com URL builder and browser launcher.

local M = {}

local BASE_URL = "https://app.logos.com/search?q="

--- Build a Logos search URL for a given SBL reference string.
---@param ref_str string  e.g. "Jas 3:1" or "1 Cor 4:2–5"
---@return string
function M.url(ref_str)
	-- URL-encode the reference string.
	-- vim.uri_encode is not available; do minimal manual encoding.
	local encoded = ref_str
		:gsub(" ", "%%20")
		:gsub(":", "%%3A")
		:gsub("\u{2013}", "%%E2%%80%%93") -- en-dash
		:gsub("\u{2014}", "%%E2%%80%%94") -- em-dash
	return BASE_URL .. encoded
end

--- Open a Logos URL in the user's default browser.
--- Uses vim.ui.open (Neovim 0.10+) with xdg-open fallback.
---@param ref_str string
function M.open(ref_str)
	local target = M.url(ref_str)
	if vim.ui.open then
		vim.ui.open(target)
	else
		-- Fallback for older Neovim or missing vim.ui.open
		local ok, err = pcall(function()
			vim.fn.jobstart({ "xdg-open", target }, { detach = true })
		end)
		if not ok then
			vim.notify("[bible_ref] Could not open browser: " .. tostring(err), vim.log.levels.ERROR)
		end
	end
end

return M
