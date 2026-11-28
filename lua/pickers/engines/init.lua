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

---Has `load()` set up the mouse of the pickers yet?
local mouse_installed = false

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
  -- Mouse in the preview and the result list of every engine (double click jumps, right
  -- click opens a context menu). Here and not in one engine's module: only the module of
  -- the chosen engine is loaded. Once per session; `cfg.preview_mouse = false` switches
  -- it off (asked when a picker window is entered, not here).
  if not mouse_installed then
    mouse_installed = true
    pcall(function()
      require("pickers.preview_mouse").install()
    end)
  end
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
