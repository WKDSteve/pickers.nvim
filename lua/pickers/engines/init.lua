---@module 'pickers.engines'
---@brief Engine loader: detects availability and returns the right adapter.
---@description
--- Priority order for "auto": telescope → fzf → snacks.
--- The resolved engine module exposes:
---   pick_files(opts)   pick_item(opts)
---   live_grep(opts)    pick_dir(opts)
---   smart(opts)

local notify = require("lib.nvim.notify").create("[pickers.engines]")

local M = {}

---Has the mouse of the pickers been set up yet (`ensure_mouse`)?
local mouse_installed = false

---Set up the mouse in the preview and the result list of every engine (double click jumps, right click opens a
---context menu), once per session. Called by `load()` and by every path that takes an engine module without it
---(`pickers.builtins.run` with an engine named): only the module of the chosen engine is loaded, so no engine's own
---module can do it. `cfg.preview_mouse = false` switches it off (asked when a picker window is entered, not here). A
---failed setup is tried again next time.
function M.ensure_mouse()
  if mouse_installed then return end
  mouse_installed = pcall(function()
    require("pickers.preview_mouse").install()
  end)
end

---Try to load and verify an engine module.
---@internal
---@param name string  "telescope"|"fzf"|"snacks"
---@return table|nil
local function try_load(name)
  local ok, mod = pcall(require, "pickers.engines." .. name)
  if not ok or not mod then return nil end
  if type(mod.available) ~= "function" or not mod.available() then return nil end
  return mod
end

---Load the best available engine, respecting the config default.
---@param requested Pickers.Engine|nil  Override; nil → use config default.
---@return table|nil  Engine module, or nil when nothing is available.
---@return string|nil name  "telescope"|"fzf"|"snacks", the module's own name — for
---callers (e.g. pickers.builtins) that need to pick an engine-specific
---implementation rather than just the pick_files/live_grep/... interface.
function M.load(requested)
  M.ensure_mouse()
  local cfg = require("pickers.config").get()
  local want = (type(requested) == "string" and requested) or cfg.engine

  if want ~= "auto" then
    local mod = try_load(want)
    if mod then return mod, want end
    notify.warn("Engine '" .. want .. "' not available — falling back to auto-detect")
  end

  for _, name in ipairs({ "telescope", "fzf", "snacks" }) do
    local mod = try_load(name)
    if mod then return mod, name end
  end

  notify.error("No picker engine found. Install telescope.nvim, fzf-lua, or snacks.nvim.")
  return nil, nil
end

return M
