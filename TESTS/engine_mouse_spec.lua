-- pickers.nvim -- `pickers.engines.ensure_mouse`: the mouse of the pickers is set up on every path that takes an
-- engine, also when a caller names the engine itself (`pickers.builtins.run(name, opts, engine_name)` takes the
-- engine module without `engines.load()`), and a setup that failed is tried again. A stand-in of
-- `pickers.preview_mouse` counts the calls; no picker is opened.
--
-- Run:  nvim -l TESTS/engine_mouse_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(vim.fn.fnamemodify(this, ":p:h"), ":h")
vim.opt.runtimepath:append(root)
local lib = vim.fn.fnamemodify(root, ":h") .. "/lib.nvim"
if vim.env.LIB_NVIM_PATH and vim.fn.isdirectory(vim.env.LIB_NVIM_PATH) == 1 then
  lib = vim.env.LIB_NVIM_PATH
elseif vim.env.REPOS_DIR and vim.fn.isdirectory(vim.env.REPOS_DIR .. "/lib.nvim") == 1 then
  lib = vim.env.REPOS_DIR .. "/lib.nvim"
end
if vim.fn.isdirectory(lib) == 1 then vim.opt.runtimepath:append(lib) end

local passed, failed = 0, 0
local function check(name, cond, detail)
  if cond then
    passed = passed + 1
    print("  ok   " .. name)
  else
    failed = failed + 1
    print("  FAIL " .. name .. (detail and ("  → " .. tostring(detail)) or ""))
  end
end

local installs, fail_next = 0, true
package.loaded["pickers.preview_mouse"] = {
  install = function()
    installs = installs + 1
    if fail_next then
      fail_next = false
      error("the first setup fails")
    end
  end,
}
-- no warnings on the screen of the test
package.loaded["lib.nvim.notify"] = {
  create = function()
    return setmetatable({}, {
      __index = function()
        return function() end
      end,
    })
  end,
}

local engines = require("pickers.engines")
engines.ensure_mouse()
check(
  "a setup that failed is tried again",
  (function()
    engines.ensure_mouse()
    return installs == 2
  end)(),
  installs
)
engines.ensure_mouse()
check("once it worked, it is not set up a second time", installs == 2, installs)

-- a fresh session: the engine named by the caller, `engines.load()` never runs
package.loaded["pickers.engines"] = nil
installs, fail_next = 0, false
local builtins = require("pickers.builtins")
local loads = 0
local real_load = require("pickers.engines").load
require("pickers.engines").load = function(...)
  loads = loads + 1
  return real_load(...)
end
local name = builtins.names()[1]
pcall(builtins.run, name, {}, "no-such-engine")
check("builtins.run with an engine named does not go through engines.load()", loads == 0, loads)
check("... and still sets up the mouse", installs == 1, installs)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
