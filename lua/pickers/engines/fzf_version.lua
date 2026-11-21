---@module 'pickers.engines.fzf_version'
---@brief Take `fzf --version` off the first fzf-lua picker.
---@description
--- fzf-lua asks for the fzf version in `config.normalize_opts`, synchronously
--- (`utils.fzf_version` -> `vim.system({ "fzf", "--version" }):wait()`), for
--- every picker it opens, and has no option to hand the answer in. On a slow
--- machine (a shim, a virus scanner) that is the 505 ms the first picker froze
--- the editor for. The version of a program does not change while the editor
--- runs, so this module
---
---   1. looks it up once, asynchronously, as soon as fzf-lua has loaded, and
---   2. wraps `fzf-lua.utils.fzf_version` so it answers from that result
---      (per `fzf_bin`) and only falls through to fzf-lua's own call while the
---      lookup is still running or has failed.
---
--- The wrapper is installed once; `install()` again is a no-op.

local M = {}

---@type table<string, { parsed: table, rc: integer, out: string }>
local cache = {}
---@type table<string, boolean>
local running = {}
local installed = false

---@param bin string
---@param parse fun(out: string): table|nil
local function lookup(bin, parse)
  if cache[bin] or running[bin] then return end
  if vim.fn.executable(bin) ~= 1 then return end
  running[bin] = true
  -- Same environment fzf-lua uses: FZF_DEFAULT_OPTS may not fit `--version`.
  local ok = pcall(vim.system, { bin, "--version" }, {
    text = true,
    env = { FZF_DEFAULT_OPTS = "" },
  }, function(res)
    vim.schedule(function()
      running[bin] = nil
      local out = (res.stderr or "") .. (res.stdout or "")
      local parsed = res.code == 0 and parse(out) or nil
      if parsed then cache[bin] = { parsed = parsed, rc = res.code, out = out } end
    end)
  end)
  if not ok then running[bin] = nil end
end

---Wrap `fzf-lua.utils.fzf_version` and start the asynchronous lookup.
---@return boolean installed  # false when fzf-lua is not loaded or looks different
function M.install()
  if installed then return true end
  local ok, utils = pcall(require, "fzf-lua.utils")
  if not ok or type(utils.fzf_version) ~= "function" or type(utils.parse_verstr) ~= "function" then
    return false
  end
  installed = true
  local original = utils.fzf_version
  utils.fzf_version = function(opts)
    local bin = opts and opts.fzf_bin or "fzf"
    local hit = cache[bin]
    -- A fresh table: fzf-lua keeps it in its options.
    if hit then return vim.deepcopy(hit.parsed), hit.rc, hit.out end
    lookup(bin, utils.parse_verstr)
    return original(opts)
  end
  lookup("fzf", utils.parse_verstr)
  return true
end

---@internal  for the spec
function M._reset()
  cache, running = {}, {}
end

---@internal  for the spec
---@param bin string
---@return table|nil
function M._cached(bin)
  return cache[bin or "fzf"]
end

return M
