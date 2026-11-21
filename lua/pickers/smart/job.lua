---@module 'pickers.smart.job'
---@brief Runs a query core (pickers.smart, pickers.filegrep) without making the editor wait.
---@description
--- The cores are written as straight-line code: "run rg, read its lines, run the next one". Inside a
--- job (`M.start`) every wait of theirs -- a process (`M.system`), a listing on its way
--- (`M.await`) -- suspends the job's coroutine and returns to the editor; the process' exit
--- resumes it on the main loop. Outside a job (a direct `query()` call, the specs) the same code
--- waits with `vim.wait` for the callback instead, so both paths share every line of the cores.
---
--- A job can be cancelled (the next keystroke): its processes are killed, a pending wait returns at
--- once, the coroutine ends with `M.CANCELLED` before it can cache or report anything, and its
--- `on_done` is never called.
---
--- No `vim.system():wait()` anywhere: a process is always started with an exit callback.

local async = require("lib.nvim.async")
local varargs = require("lib.lua.functions.varargs")
local pack, unpack = varargs.pack, varargs.unpack

local M = {}

---The error a cancelled job ends with (never reported).
M.CANCELLED = setmetatable({}, {
  __tostring = function()
    return "pickers: query superseded"
  end,
})

---@class Pickers.Smart.Job
---@field cancelled boolean
---@field procs table<vim.SystemObj, true>  processes still running
---@field pending fun(...)|nil              the wake-up of the wait the job is suspended in
---@field cancel fun(self: Pickers.Smart.Job)

---coroutine -> its job
---@type table<thread, Pickers.Smart.Job>
local jobs = setmetatable({}, { __mode = "k" })

---The job the running code belongs to, or nil (a direct, synchronous call).
---@return Pickers.Smart.Job|nil
function M.current()
  local co = coroutine.running()
  return co and jobs[co] or nil
end

---@param job Pickers.Smart.Job
local function check(job)
  if job.cancelled then error(M.CANCELLED, 0) end
end

---Wait until `start(done)` calls `done(...)` and return what it was called with. Inside a job the
---job is suspended (the editor goes on) and resumed on the main loop; outside one this waits up to
---`timeout` ms with `vim.wait` and returns nothing when the time ran out. `done` may be called
---more than once (or from a fast-event callback): only the first call counts.
---@param start fun(done: fun(...))
---@param timeout integer
---@return ...
function M.await(start, timeout)
  local job = M.current()
  if not job then
    local out
    start(function(...)
      out = out or pack(...)
    end)
    if not out then vim.wait(timeout, function()
      return out ~= nil
    end, 2) end
    if out then return unpack(out, 1, out.n) end
    return
  end
  check(job)
  local result = pack(async.await(function(resume)
    local fired = false
    local function once(...)
      if fired then return end
      fired = true
      job.pending = nil
      local args = pack(...)
      vim.schedule(function()
        resume(unpack(args, 1, args.n))
      end)
    end
    job.pending = once
    start(once)
  end))
  check(job)
  return unpack(result, 1, result.n)
end

---`vim.system(cmd, opts)` with a time limit, waited for as `M.await` does: like
---`vim.system(cmd, opts):wait(timeout)` but without blocking the editor inside a job. The process
---is started with the bare name in `cmd[1]` and no shell.
---@param cmd string[]
---@param opts table  vim.system options (cwd, text, env ...)
---@param timeout integer  ms; the process is killed after it
---@return boolean ok  false when the process could not be started
---@return vim.SystemCompleted|string|nil res  the result, the start error, or nil when the wait ran out
function M.system(cmd, opts, timeout)
  local job = M.current()
  local o = vim.tbl_extend("force", opts or {}, { timeout = timeout })
  local started, err, proc = true, nil, nil
  local res = M.await(function(done)
    local ok, obj = pcall(vim.system, cmd, o, function(r)
      done(r)
    end)
    if not ok then
      started, err = false, obj
      done(nil)
      return
    end
    proc = obj
    if job then job.procs[obj] = true end
  end, timeout + 1000)
  if job and proc then job.procs[proc] = nil end
  if not started then return false, err end
  return true, res
end

---Kill what the job runs and end it: no result, no cache entry, no report.
---@param job Pickers.Smart.Job
local function cancel(job)
  if job.cancelled then return end
  job.cancelled = true
  for proc in pairs(job.procs) do
    pcall(proc.kill, proc, "sigterm")
  end
  job.procs = {}
  if job.pending then job.pending() end
end

---Run `body` as a job. `on_done` gets what `body` returns, on the main loop, unless the job was
---cancelled. An error in `body` (not a cancel) reaches `on_done` as `({}, { message })`, so a
---picker waiting on the job always hears back.
---@param body fun(): ...
---@param on_done fun(...)
---@return Pickers.Smart.Job
function M.start(body, on_done)
  ---@type Pickers.Smart.Job
  local job = { cancelled = false, procs = {}, cancel = cancel }
  async.run(function()
    jobs[coroutine.running()] = job
    return body()
  end, function(...)
    if not job.cancelled then on_done(...) end
  end, {
    on_error = function(err)
      if err == M.CANCELLED or job.cancelled then return end
      vim.schedule(function()
        on_done({}, { "pickers: the search failed: " .. tostring(err) })
      end)
    end,
  })
  return job
end

return M
