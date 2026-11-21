---@module 'pickers.smart.live'
---@brief One live picker's searches: debounced, the newest wins, the editor never waits.
---@description
--- Each engine adapter of the smart/filegrep picker owns one runner and calls `run(query, cb)` from
--- its per-keystroke finder. The search starts `smart.debounce` ms after the last keystroke, as a
--- job (`pickers.smart.job`) of the chosen core. A new `run` (or `cancel`, the picker closing)
--- cancels the search before it -- its processes are killed -- and calls that search's `cb(nil)`,
--- so an engine that holds something open for it (fzf-lua's pipe, a suspended snacks task) can let
--- go. Only the newest search's `cb(items, problems)` is ever called with a result: a slow old run
--- cannot overwrite the result of a newer one.

local M = {}

---@class Pickers.Smart.Live
---@field core { query_async: fun(query: string, opts: table, on_done: fun(items: Pickers.Smart.Item[], problems: string[])): Pickers.Smart.Job }
---@field opts table          what `query_async` gets besides the query (roots, find, additional_args)
---@field debounce integer    ms
---@field token integer       bumped by every run/cancel: a callback of an older token is dropped
---@field delay Lib.Debounce.Handle|nil  the debounce (nil: start at once)
---@field job Pickers.Smart.Job|nil
---@field cb fun(items: Pickers.Smart.Item[]|nil, problems: string[]|nil)|nil  the open search's callback
local Live = {}
Live.__index = Live

---The debounce of `smart.debounce` (ms, >= 0).
---@return integer
local function configured_debounce()
  local ms = require("pickers.smart").config().debounce
  if type(ms) ~= "number" or ms < 0 then return 0 end
  return math.floor(ms)
end

---@param core_name "smart"|"filegrep"|nil
---@param opts table  roots, find, additional_args
---@param debounce integer|nil  ms; default `smart.debounce`
---@return Pickers.Smart.Live
function M.new(core_name, opts, debounce)
  local self = setmetatable({
    core = require("pickers.smart").core(core_name),
    opts = opts,
    debounce = debounce or configured_debounce(),
    token = 0,
  }, Live)
  if self.debounce > 0 then
    self.delay = require("lib.nvim.debounce").new(function(start)
      start()
    end, self.debounce)
  end
  return self
end

---Stop the open search (pending timer or running job) and tell its caller with `cb(nil)`. With
---`token` (what `run` returned) only that search is stopped: a late "stop" from an engine for an
---older search (snacks reports the abort of a task one step later) leaves a newer one running.
---@param token integer|nil
function Live:cancel(token)
  if token and token ~= self.token then return end
  self.token = self.token + 1
  local running, cb = self.job, self.cb
  self.job, self.cb = nil, nil
  if self.delay then self.delay.cancel() end
  if running then running:cancel() end
  if cb then cb(nil) end
end

---Search `query`; `cb(items, problems)` on the main loop with the result, or `cb(nil)` when a newer
---search (or `cancel`) came first.
---@param query string
---@param cb fun(items: Pickers.Smart.Item[]|nil, problems: string[]|nil)
---@return integer token  for `cancel(token)`
function Live:run(query, cb)
  self:cancel()
  local token = self.token
  self.cb = cb
  local function start()
    if token ~= self.token then return end
    self.job = self.core.query_async(query, self.opts, function(items, problems)
      if token ~= self.token then return end
      self.job, self.cb = nil, nil
      cb(items or {}, problems or {})
    end)
  end
  if self.delay then
    self.delay.call(start)
  else
    start()
  end
  return token
end

return M
