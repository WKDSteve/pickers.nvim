---@diagnostic disable: need-check-nil
-- pickers.nvim -- `pickers.engines.fzf_version`: the version of fzf is asked for once, off the main path
-- (task pickers.nvim/fzf-lua-synchrones-fzf-version-beim-ersten-picker-505-ms). A stand-in of
-- `fzf-lua.utils` counts fzf-lua's own synchronous calls; the program asked is nvim itself.
--
-- Run:  nvim -l TESTS/fzf_version_spec.lua

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

local sync_calls = 0
local utils = {
  parse_verstr = function(s)
    return s:match("NVIM") and { 0, 99 } or nil
  end,
}
utils.fzf_version = function()
  sync_calls = sync_calls + 1
  return utils.parse_verstr("NVIM"), 0, "NVIM"
end
package.loaded["fzf-lua.utils"] = utils

local fv = require("pickers.engines.fzf_version")
check("installs on a fzf-lua that looks as expected", fv.install() == true)
check("installing twice is a no-op", fv.install() == true)

local bin = vim.v.progpath
local v1 = utils.fzf_version({ fzf_bin = bin })
check("the first call falls through to fzf-lua's own", sync_calls == 1 and v1[2] == 99)
local ok = vim.wait(10000, function()
  return fv._cached(bin) ~= nil
end, 20)
check("the lookup finishes asynchronously", ok)

local before = sync_calls
local v2, rc = utils.fzf_version({ fzf_bin = bin })
check("then the answer comes from the cache", sync_calls == before and rc == 0 and v2[2] == 99)
v2[2] = 0
check("a caller changing the answer does not touch the cache", utils.fzf_version({ fzf_bin = bin })[2] == 99)

package.loaded["fzf-lua.utils"] = { fzf_version = function() end }
check("a fzf-lua that looks different is left alone", (function()
  package.loaded["pickers.engines.fzf_version"] = nil
  return require("pickers.engines.fzf_version").install() == false
end)())

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
