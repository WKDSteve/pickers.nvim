---@module 'pickers.items'
---@brief A list of the caller's own rows on the active engine: a preview worked
---out per row, keys of the call, several marked rows, a title that is computed.
---@description
--- `pick_item` picks one entry and is done. A list that is worked in (a task
--- dashboard, a list of repositories with batch commands) needs more: keys that
--- act on the marked rows, a preview that is generated, and the list again
--- after an action, with the rows as they are now. This module is that, once
--- for telescope, fzf-lua and snacks:
---
--- ```lua
--- require("pickers.items").open({
---   items = function() return rows() end,       -- or a list; strings or Pickers.Item
---   title = function(rows) return ("Tasks (%d)"):format(#rows) end,
---   preview = function(item) return { lines = describe(item), ft = "markdown" } end,
---   marks = true,
---   actions = {
---     status = {
---       key = "<M-s>",
---       desc = "advance the status",
---       fn = function(sel, ctx)
---         advance(sel)        -- the marked rows, else the one under the cursor
---         ctx.reopen()        -- the list again: fresh rows, the query kept
---       end,
---     },
---   },
---   on_select = function(item, sel) open(sel) end,
--- })
--- ```
---
--- What this layer owns: reading the rows and the title (again on every
--- reopen), checking the keys, which rows an action gets, and the restart.
--- What an engine adapter owns (`pick_item` of `pickers.engines.*`, fields
--- `query`, `multi`, `keys`, `preview`): mapping a key, marking rows, drawing
--- the preview, and reading the marked rows and the query before it closes.
---
--- A key closes the list and then runs. No engine redraws a list in place
--- here: `ctx.reopen()` opens it again with what was typed, which is the one
--- way that is the same on all three (fzf is a process of its own). The marks
--- are gone after a reopen; the action has just used them.
---
--- Keys are chords (`<M-s>`, `<C-x>`, `<F5>`): the prompt has the focus on
--- every engine, a plain letter is typed into it, and fzf-lua binds nothing
--- else. A key of the call wins over an entry action on the same key
--- (`keys.*` of the config) inside this list.

local notify = require("lib.nvim.notify").create("[pickers]")

local M = {}

---@class Pickers.ItemsAction
---@field key string   A chord in Vim notation (`<M-s>`, `<C-x>`, `<F5>`).
---@field desc string?
---@field fn fun(sel: (string|Pickers.Item)[], ctx: Pickers.ItemsCtx)  `sel`: the marked rows in the order of the list, else the row under the cursor (with `marks` off always at most one); empty when the list shows nothing.

---@class Pickers.ItemsCtx
---@field query string  What was typed in the prompt when the key was pressed.
---@field reopen fun(changes?: Pickers.ItemsOpts)  Open the list again: rows and title are read anew, the query is kept. `changes` replaces fields of the call (`query = ""` clears the prompt).

---@class Pickers.ItemsOpts
---@field items (string|Pickers.Item)[]|fun(): (string|Pickers.Item)[]  The rows; a function is called on every (re)open.
---@field title (string|fun(rows: (string|Pickers.Item)[]): string)?  The prompt title; a function gets the rows just read (counts, filter chips).
---@field preview (fun(item: string|Pickers.Item): Pickers.PreviewSpec|nil)?  A file (`{ file, line? }`) or text (`{ lines, ft?, line? }`) per row.
---@field actions table<string, Pickers.ItemsAction>?  Keys of the call, by a name of the caller's choice.
---@field marks boolean?  Several rows can be marked (`<Tab>`, the engine's own); actions and `on_select` get all of them.
---@field on_select (fun(item: string|Pickers.Item, sel: (string|Pickers.Item)[]))?  `<CR>`: the first of `sel`, and `sel` as an action gets it.
---@field query string?  What is typed in the prompt when the list opens.
---@field engine_mod table?  The engine (default: the resolved one).

-- what every engine uses itself in a list
local RESERVED = {
  enter = "<CR>",
  tab = "<Tab>",
  ["shift-tab"] = "<S-Tab>",
  esc = "<Esc>",
  ["ctrl-c"] = "<C-c>",
}

---One spelling per key, so that `<M-s>` and `<A-S>` are seen as the same key.
---@param key string
---@return string
local function canonical(key)
  return require("pickers.preview_modes").fzf_key(key)
end

---The action names in a fixed order (keys are mapped and listed in it).
---@param actions table<string, Pickers.ItemsAction>|nil
---@return string[]
local function names(actions)
  local out = {}
  for name in pairs(actions or {}) do
    out[#out + 1] = name
  end
  table.sort(out)
  return out
end

---What is wrong with a call, as sentences; empty when it can be opened. Pure:
---the rows are not read.
---@param opts Pickers.ItemsOpts
---@return string[] issues
function M.check(opts)
  local issues = {}
  if type(opts) ~= "table" then return { "the options are not a table" } end
  if type(opts.items) ~= "table" and type(opts.items) ~= "function" then
    issues[#issues + 1] = "items: a list or a function that returns one"
  end
  if opts.preview ~= nil and type(opts.preview) ~= "function" then
    issues[#issues + 1] = "preview: a function"
  end
  if opts.actions ~= nil and type(opts.actions) ~= "table" then
    issues[#issues + 1] = "actions: a table of name -> { key, fn }"
    return issues
  end
  local taken = {}
  for _, name in ipairs(names(opts.actions)) do
    local action = opts.actions[name]
    if type(action) ~= "table" or type(action.fn) ~= "function" then
      issues[#issues + 1] = ("actions.%s: needs a function `fn`"):format(name)
    elseif type(action.key) ~= "string" or not action.key:match("^<[^<>]+>$") then
      issues[#issues + 1] = ("actions.%s: the key must be a chord like <M-s> or <F5>, got %s"):format(
        name,
        vim.inspect(action.key)
      )
    else
      local key = canonical(action.key)
      if RESERVED[key] then
        issues[#issues + 1] = ("actions.%s: %s is the list's own key"):format(name, RESERVED[key])
      elseif taken[key] then
        issues[#issues + 1] = ("actions.%s: %s is already the key of actions.%s"):format(
          name,
          action.key,
          taken[key]
        )
      else
        taken[key] = name
      end
    end
  end
  return issues
end

---The keys of a call, one line each (`<M-s>  advance the status`), in the order
---of the action names: for a help float or a header.
---@param actions table<string, Pickers.ItemsAction>|nil
---@return string[]
function M.describe(actions)
  local rows = {}
  for _, name in ipairs(names(actions)) do
    rows[#rows + 1] = { actions[name].key, actions[name].desc or name }
  end
  return M.columns(rows)
end

---Rows of cells as lines with aligned columns (a row of a dashboard: prio,
---status, effort, area, title). A column is as wide as its widest cell on the
---screen; the last one is not padded. Pure.
---@param rows any[][]  Cells are shown with `tostring`; a missing cell is empty.
---@param opts? { sep?: string, right?: table<integer, boolean> }  `sep`: between two columns (default two spaces); `right[i]`: column `i` is right-aligned.
---@return string[]
function M.columns(rows, opts)
  opts = opts or {}
  local sep, right = opts.sep or "  ", opts.right or {}
  local width, count = {}, 0
  for _, row in ipairs(rows) do
    count = math.max(count, #row)
    for i = 1, #row do
      width[i] = math.max(width[i] or 0, vim.fn.strdisplaywidth(tostring(row[i] or "")))
    end
  end
  local out = {}
  for r, row in ipairs(rows) do
    local cells = {}
    for i = 1, count do
      local cell = row[i] ~= nil and tostring(row[i]) or ""
      local pad = string.rep(" ", (width[i] or 0) - vim.fn.strdisplaywidth(cell))
      if right[i] then
        cells[i] = pad .. cell
      elseif i < count then
        cells[i] = cell .. pad
      else
        cells[i] = cell
      end
    end
    out[r] = (table.concat(cells, sep):gsub("%s+$", ""))
  end
  return out
end

---The rows an action or `<CR>` acts on: what the engine reported, cut to one
---row when the call does not mark.
---@param opts Pickers.ItemsOpts
---@param env Pickers.ItemEnv|nil
---@return (string|Pickers.Item)[]
local function selection(opts, env)
  local items = env and env.items or {}
  if not opts.marks and #items > 1 then return { items[1] } end
  return items
end

---Open the list. Returns false (and says why) when the call is not valid, no
---engine is there, or the rows cannot be read.
---@param opts Pickers.ItemsOpts
---@return boolean opened
function M.open(opts)
  local issues = M.check(opts)
  if #issues > 0 then
    notify.error("items: " .. table.concat(issues, "; "))
    return false
  end
  local engine_mod = opts.engine_mod or require("pickers.engines").load()
  if not engine_mod then return false end

  local rows = opts.items
  if type(rows) == "function" then
    local ok, got = pcall(rows)
    if not ok or type(got) ~= "table" then
      notify.error("items: the rows could not be read: " .. tostring(got))
      return false
    end
    rows = got
  end
  ---@cast rows (string|Pickers.Item)[]

  local title = opts.title
  if type(title) == "function" then
    local ok, got = pcall(title, rows)
    title = ok and tostring(got) or "Items"
  end

  ---@param env Pickers.ItemEnv
  ---@return Pickers.ItemsCtx
  local function ctx_of(env)
    local query = env.query or ""
    return {
      query = query,
      reopen = function(changes)
        local again = vim.tbl_extend("force", {}, opts, { query = query }, changes or {})
        again.engine_mod = again.engine_mod or engine_mod
        M.open(again)
      end,
    }
  end

  ---@type Pickers.ItemKey[]
  local keys = {}
  for _, name in ipairs(names(opts.actions)) do
    local action = opts.actions[name]
    keys[#keys + 1] = {
      key = action.key,
      desc = action.desc or name,
      run = function(env)
        local ok, err = pcall(action.fn, selection(opts, env), ctx_of(env))
        if not ok then notify.error(("items: action %s failed: %s"):format(name, tostring(err))) end
      end,
    }
  end

  engine_mod.pick_item({
    items = rows,
    prompt = title or "Items",
    query = opts.query,
    preview = opts.preview,
    multi = opts.marks == true,
    keys = keys,
    on_select = function(item, env)
      if not opts.on_select then return end
      local sel = selection(opts, env)
      -- an engine without the extras reports the one row only
      if #sel == 0 then sel = { item } end
      opts.on_select(sel[1], sel)
    end,
  })
  return true
end

return M
