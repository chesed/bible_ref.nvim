--- lua/bible_ref/init.lua
--- Public API, setup(), and Neovim user command registration.

local M = {}

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------
local DEFAULTS = {
  --- Absolute path to the JSON Bible dataset.
  --- Defaults to <plugin_root>/data/bible.json (auto-detected).
  json_path = nil,

  --- Preferred picker backend: "fzf-lua" | "telescope" | "select" | "auto"
  picker = "auto",

  --- Keymaps to register globally (set to false to disable auto-keymaps)
  keymaps = {
    hover      = "<leader>bh",   -- BibleHover
    pick       = "<leader>bp",   -- BiblePick
    open_logos = "<leader>bl",   -- BibleOpenLogos
  },

  --- Which filetypes to restrict keymaps to (empty = all filetypes)
  filetypes = {},
}

local config = {}  -- merged options stored after setup()

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

--- Resolve plugin root directory (the parent of the lua/ folder).
---@return string
local function plugin_root()
  -- __FILE__ → .../lua/bible_ref/init.lua
  local src = debug.getinfo(1, "S").source:sub(2) -- strip leading "@"
  -- Navigate up: init.lua → bible_ref/ → lua/ → plugin_root/
  return vim.fn.fnamemodify(src, ":h:h:h")
end

--- Register the three user commands.
local function register_commands()
  -- :BibleHover — inspect reference under cursor
  vim.api.nvim_create_user_command("BibleHover", function()
    local parse = require("bible_ref.parse")
    local db    = require("bible_ref.db")
    local sbl   = require("bible_ref.sbl")
    local float = require("bible_ref.ui.float")

    local ref = parse.ref_at_cursor()
    if not ref then
      vim.notify("[bible_ref] No Bible reference found under cursor", vim.log.levels.INFO)
      return
    end

    local verse_text
    if ref.verse_end then
      verse_text = db.lookup_range(ref.book, ref.chapter, ref.verse_start, ref.verse_end)
    else
      verse_text = db.lookup(ref.book, ref.chapter, ref.verse_start)
    end

    local ref_str = sbl.format(ref)
    float.show(ref_str, verse_text)
  end, { desc = "bible_ref: Show verse preview for reference under cursor" })

  -- :BiblePick — fuzzy picker
  vim.api.nvim_create_user_command("BiblePick", function()
    require("bible_ref.ui.picker").open()
  end, { desc = "bible_ref: Fuzzy-search Bible verses and insert SBL reference" })

  -- :BibleOpenLogos — open cursor reference in logos.com
  vim.api.nvim_create_user_command("BibleOpenLogos", function()
    local parse  = require("bible_ref.parse")
    local sbl    = require("bible_ref.sbl")
    local logos  = require("bible_ref.logos")

    local ref = parse.ref_at_cursor()
    if not ref then
      vim.notify("[bible_ref] No Bible reference found under cursor", vim.log.levels.INFO)
      return
    end
    logos.open(sbl.format(ref))
  end, { desc = "bible_ref: Open reference under cursor in logos.com" })
end

--- Register global keymaps (if configured).
local function register_keymaps()
  local km = config.keymaps
  if not km then return end

  local function map(key, cmd, desc)
    if key then
      vim.keymap.set("n", key, "<cmd>" .. cmd .. "<CR>",
        { noremap = true, silent = true, desc = desc })
    end
  end

  if km.hover then
    map(km.hover, "BibleHover", "Bible: hover preview")
  end
  if km.pick then
    map(km.pick, "BiblePick", "Bible: fuzzy verse picker")
  end
  if km.open_logos then
    map(km.open_logos, "BibleOpenLogos", "Bible: open in Logos.com")
  end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Setup bible_ref.nvim.
---
--- Example:
---   require("bible_ref").setup({
---     json_path = vim.fn.stdpath("data") .. "/bible_ref/esv.json",
---     keymaps   = { hover = "<leader>bh", pick = "<leader>bp" },
---   })
---
---@param opts table|nil
function M.setup(opts)
  config = vim.tbl_deep_extend("force", DEFAULTS, opts or {})

  -- Resolve json_path: default to <plugin_root>/data/bible.json
  if not config.json_path then
    config.json_path = plugin_root() .. "/data/bible.json"
  end

  -- Tell db.lua where the dataset lives
  require("bible_ref.db").set_path(config.json_path)

  register_commands()
  register_keymaps()
end

--- Direct access to sub-modules for advanced use.
M.parse  = function() return require("bible_ref.parse") end
M.sbl    = function() return require("bible_ref.sbl") end
M.db     = function() return require("bible_ref.db") end
M.logos  = function() return require("bible_ref.logos") end

return M
