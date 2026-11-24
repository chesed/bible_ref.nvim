--- lua/bible_ref/init.lua
--- Public API, setup(), and Neovim user command registration.

local M = {}

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------
local DEFAULTS = {
  --- Absolute path to a single JSON Bible dataset (v1 backward-compat).
  --- When set, the version registry collapses to just this one dataset.
  json_path = nil,

  --- Directory to scan for datasets (default <plugin_root>/data).
  data_dir = nil,

  --- Explicit version list, overriding directory discovery:
  ---   versions = {
  ---     { tag = "ESV",  path = "/abs/path/esv.json",  label = "ESV" },
  ---     { tag = "KJV",  path = "/abs/path/kjv.json",  label = "KJV" },
  ---   }
  versions = nil,

  --- Starting active version: tag/name (string) or 1-based index (number).
  --- When unset, the built-in default applies: tag WEB if present, else
  --- the first dataset in the registry.
  default_version = nil,

  --- Picker options:
  ---   backend        "auto" | "fzf-lua" | "select"
  ---   append_version append the version tag to inserted refs when the active
  ---                  version is not the default dataset (e.g. "Jas 3:1 KJV")
  picker = {
    backend        = "auto",
    append_version = false,
  },

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
  -- init.lua → bible_ref/ → lua/ → plugin_root/
  local src = debug.getinfo(1, "S").source:sub(2) -- strip leading "@"
  return vim.fn.fnamemodify(src, ":h:h:h")
end

--- Register the user commands.
local function register_commands()
  -- :BibleHover — inspect reference under cursor (active dataset version)
  vim.api.nvim_create_user_command("BibleHover", function()
    local parse = require("bible_ref.parse")
    local float = require("bible_ref.ui.float")

    local ref = parse.ref_at_cursor()
    if not ref then
      vim.notify("[bible_ref] No Bible reference found under cursor", vim.log.levels.INFO)
      return
    end

    -- Structured ref; the float window handles version cycling internally.
    float.show(ref)
  end, { desc = "bible_ref: Show verse preview for reference under cursor" })

  -- :BiblePick — fuzzy picker
  vim.api.nvim_create_user_command("BiblePick", function()
    require("bible_ref.ui.picker").open()
  end, { desc = "bible_ref: Fuzzy-search Bible verses and insert SBL reference" })

  -- :BibleVersion [tag] — show active dataset, or set it
  vim.api.nvim_create_user_command("BibleVersion", function(args)
    local cfg = require("bible_ref.config")
    local versions = cfg.get_versions()

    if not args or not args.args or #vim.trim(args.args) == 0 then
      local cur = cfg.get_current_version()
      local idx = cfg.get_current_version_index()
      local lines = {
        string.format("bible_ref: active dataset → %s (%s)",
          cur and cur.tag or "?", cur and cur.label or "?"),
      }
      for i, v in ipairs(versions) do
        lines[#lines + 1] = string.format("  %s%d. %s — %s",
          (i == idx and "*" or " "), i, v.tag, v.label)
      end
      vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
    else
      local tag = vim.trim(args.args)
      if cfg.set_version(tag) then
        vim.notify("[bible_ref] Active dataset: "
          .. tostring(cfg.get_current_version().tag), vim.log.levels.INFO)
      else
        local known = {}
        for _, v in ipairs(versions) do known[#known + 1] = v.tag end
        vim.notify("[bible_ref] Unknown dataset " .. tag
          .. ". Available: " .. table.concat(known, ", "), vim.log.levels.WARN)
      end
    end
  end, { desc = "bible_ref: Show or set the active Bible dataset", nargs = "?" })

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
--- Example (auto-discovery of <plugin_root>/data):
---   require("bible_ref").setup({
---     keymaps = { hover = "<leader>bh", pick = "<leader>bp" },
---   })
---
--- Example (explicit datasets):
---   require("bible_ref").setup({
---     versions = {
---       { tag = "ESV",  path = "/data/esv.json" },
---       { tag = "KJV",  path = "/data/kjv.json" },
---     },
---     default_version = "KJV",
---     picker = { backend = "fzf-lua", append_version = true },
---   })
---
---@param opts table|nil
function M.setup(opts)
  config = vim.tbl_deep_extend("force", DEFAULTS, opts or {})

  -- Build the config-module options.
  local cfg_opts = {}
  if config.data_dir then
    cfg_opts.data_dir = config.data_dir
  end
  if config.default_version then
    cfg_opts.default_version = config.default_version
  end

  -- v1 backward-compat: a single json_path collapses the registry.
  if config.json_path then
    -- Derive the tag from the filename (bible_kjv.json → KJV, esv.json →
    -- ESV). A bare bible.json carries no tag information → DEFAULT.
    local name = vim.fn.fnamemodify(config.json_path, ":t")
    local tag  = name:match("^bible_([%w_%-]+)%.json$")
    if not tag then
      local bare = name:match("^([%w_%-]+)%.json$")
      if bare and bare:lower() ~= "bible" then tag = bare end
    end
    tag = (tag or "DEFAULT"):upper()
    cfg_opts.versions = {
      { tag = tag, file = name, path = config.json_path,
        label = tag == "DEFAULT" and "Default" or tag, aliases = { "DEFAULT" } },
    }
  elseif config.versions and #config.versions > 0 then
    cfg_opts.versions = config.versions
  end

  local versions = require("bible_ref.config").setup(cfg_opts)

  -- Register dataset paths with the db layer (only entries that have paths).
  local paths = {}
  for _, v in ipairs(versions) do
    if v.path then paths[v.tag] = v.path end
  end
  require("bible_ref.db").set_paths(paths)

  register_commands()
  register_keymaps()
end

--- Set the active dataset by tag/name. Returns true on success.
---@param tag string  e.g. "ESV", "KJV", "SBLGNT"
---@return boolean
function M.set_version(tag)
  return require("bible_ref.config").set_version(tag)
end

--- Retrieve a version entry by tag/name (string) or 1-based index (number).
---@param tag_or_idx string|number
---@return table|nil
function M.get_version(tag_or_idx)
  return require("bible_ref.config").get_version(tag_or_idx)
end

--- All registered versions, in order.
---@return table[]
function M.get_versions()
  return require("bible_ref.config").get_versions()
end

--- The currently active version entry.
---@return table|nil
function M.get_current_version()
  return require("bible_ref.config").get_current_version()
end

--- Merged user options (set after setup(); nil before).
---@return table|nil
function M.opts()
  return config
end

--- Direct access to sub-modules for advanced use.
M.parse  = function() return require("bible_ref.parse") end
M.sbl    = function() return require("bible_ref.sbl") end
M.db     = function() return require("bible_ref.db") end
M.logos  = function() return require("bible_ref.logos") end

return M
