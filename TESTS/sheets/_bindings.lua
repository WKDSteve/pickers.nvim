-- TESTS/sheets/_bindings.lua -- the setup of the binding sheets (pickers-bindings-*.sheet.lua). Not a sheet
-- (`testing.sheet` only reads *.sheet.lua); the first step of such a sheet runs it with `dofile` after
-- _helpers.lua, the child's cwd is the project root. The directory is in the spec's @cache-inputs.
--
-- Covers the pickers.nvim items of the bindings runtime checklist of the nvim config
-- (docs/ROADMAP/Final_Checks/BINDINGS-RUNTIME-CHECKLIST.md): every key and command is typed as a person types
-- it, and the sheet reads what reached the picker. The picker itself is a recorder standing in for the engine
-- (pick_files, live_grep, smart, pick_item, pick_dir) and for ui.kit (select, input), so no picker library is
-- needed and the interactive steps in between (a folder, a repo, an action, a directory) are answered by the
-- sheet. That the real engines draw what they are handed is the business of the pickers.items sheets.
--
-- The configuration mirrors the one of the nvim config (lua/plugins/personal/specs/navigate.lua): the same
-- opt-in keys and the same nine collections with their keys and prefixes, on fixture folders in a temp dir.

-- luacheck: globals vim

---@type { kind: string, opts: table }[]
_G.calls = {}

local function record(kind)
  return function(opts)
    _G.calls[#_G.calls + 1] = { kind = kind, opts = opts or {} }
  end
end

-- The engine: what pickers.engines.load hands every action.
local recorder = {
  available = function()
    return true
  end,
}
for _, fn in ipairs({ "pick_files", "live_grep", "smart", "pick_item", "pick_dir" }) do
  recorder[fn] = record(fn)
end
_G.recorder = recorder

-- ui.kit (ui.nvim) is not on the runtimepath of the child: its select/input are recorded the same way, which
-- is what the scope, action and dir-navigation pickers and the system search ask.
package.loaded["ui.kit"] = { select = record("select"), input = record("input") }

local tmp = vim.fs.normalize(vim.fn.tempname())
_G.fixture = tmp

local function file(path)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ "alpha" }, path)
end

-- Flat collections: one folder each.
for _, name in ipairs({
  "notes",
  "notes_lua",
  "notes_nvim",
  "checklists",
  "spickzettel",
  "wkdbooks_lua",
  "wkdbooks_nvim",
}) do
  file(tmp .. "/coll/" .. name .. "/note.md")
end
-- wkdbooks: prefix "wkdbook-" lists only the subdirs that start with it.
file(tmp .. "/coll/wkdbooks/wkdbook-alpha/a.md")
file(tmp .. "/coll/wkdbooks/other/o.md")
-- plugins_book: prefix "" lists every subdir but the excluded ones.
file(tmp .. "/coll/plugins_book/alpha.nvim/a.md")
file(tmp .. "/coll/plugins_book/ALL/x.md")
file(tmp .. "/coll/plugins_book/TOOLS/x.md")
-- repos_dir: only git repos count.
file(tmp .. "/repos/alpha/.git/HEAD")
file(tmp .. "/repos/alpha/a.lua")
file(tmp .. "/repos/plain/p.lua")

local coll = tmp .. "/coll/"
vim.g.mapleader = " "
require("pickers").setup({
  repos_dir = tmp .. "/repos",
  keymaps = {
    cwd_smart = "<leader>CW",
    config_smart = "<leader>CF",
    cwd_filegrep = "<leader>mp",
    cwd_find_all = "<leader>fa",
  },
  collections = {
    {
      name = "notes",
      dir = coll .. "notes",
      keys = { files = "<leader>mnf", grep = "<leader>mng", smart = "<leader>mns" },
    },
    {
      name = "notes_lua",
      dir = coll .. "notes_lua",
      keys = { files = "<leader>mlf", grep = "<leader>mlg" },
    },
    {
      name = "notes_nvim",
      dir = coll .. "notes_nvim",
      keys = { files = "<leader>mvf", grep = "<leader>mvg" },
    },
    {
      name = "checklists",
      dir = coll .. "checklists",
      keys = { files = "<leader>chf", grep = "<leader>chg" },
    },
    {
      name = "spickzettel",
      dir = coll .. "spickzettel",
      keys = { files = "<leader>spf", grep = "<leader>spg" },
    },
    {
      name = "wkdbooks",
      dir = coll .. "wkdbooks",
      prefix = "wkdbook-",
      keys = { files = "<leader>wkf", grep = "<leader>wkg", smart = "<leader>wks" },
    },
    {
      name = "wkdbooks_lua",
      dir = coll .. "wkdbooks_lua",
      keys = { files = "<leader>wlf", grep = "<leader>wlg" },
    },
    {
      name = "wkdbooks_nvim",
      dir = coll .. "wkdbooks_nvim",
      keys = { files = "<leader>wvf", grep = "<leader>wvg" },
    },
    {
      name = "plugins_book",
      dir = coll .. "plugins_book",
      prefix = "",
      exclude = { "ALL", "TEMPLATES", "TOOLS", "_Telemetry" },
      keys = { files = "<leader>pbf", grep = "<leader>pbg", smart = "<leader>pbs" },
    },
  },
})

-- After setup: every action asks the engines module, which now hands out the recorder.
require("pickers.engines").load = function()
  return recorder, "recorder"
end

local function fail(fmt, ...)
  error(fmt:format(...), 0)
end

---The last call, which must be of `kind`.
---@param kind string
---@return table opts
local function last(kind)
  local c = _G.calls[#_G.calls]
  if not c then fail("nothing reached the picker, wanted %s", kind) end
  _G.taken = c
  if c.kind ~= kind then
    fail(
      "the picker got %s (%s), wanted %s",
      c.kind,
      vim.inspect(c.opts.prompt or c.opts.title),
      kind
    )
  end
  return c.opts
end

---Whether the last call is `kind` and has what `want` names; the calls are cleared after it, so the next step
---reads only what its own key did.
---  root   = the first root ends with it (a path below the fixture, or a whole path)
---  roots  = the number of roots is at least this
---  prompt = the prompt starts with it
---  query  = the query is exactly this
---  core   = the smart picker's core is this ("filegrep" for the files picker with a grep= filter); false = none
---  find   = these find flags are set
---  items  = the items contain these (in any order); `not_items` must not be among them
---@param kind string
---@param want? table
---@return boolean
function _G.took(kind, want)
  local opts = last(kind)
  want = want or {}
  if want.root then
    local got = opts.roots and opts.roots[1] and vim.fs.normalize(opts.roots[1]) or "(none)"
    if got:sub(-#want.root) ~= want.root then
      fail("root %s, wanted one ending in %s", got, want.root)
    end
  end
  if want.roots and #(opts.roots or {}) < want.roots then
    fail("%d roots, wanted at least %d", #(opts.roots or {}), want.roots)
  end
  if want.prompt then
    local got = tostring(opts.prompt or opts.title)
    if got:sub(1, #want.prompt) ~= want.prompt then
      fail("prompt %q, wanted %q", got, want.prompt)
    end
  end
  if want.query ~= nil and opts.query ~= want.query then
    fail("query %s, wanted %s", vim.inspect(opts.query), vim.inspect(want.query))
  end
  if want.core ~= nil and (opts.core or false) ~= want.core then
    fail("core %s, wanted %s", vim.inspect(opts.core), vim.inspect(want.core))
  end
  for flag, value in pairs(want.find or {}) do
    if (opts.find or {})[flag] ~= value then
      fail(
        "find.%s is %s, wanted %s",
        flag,
        vim.inspect((opts.find or {})[flag]),
        vim.inspect(value)
      )
    end
  end
  for _, item in ipairs(want.items or {}) do
    if not vim.tbl_contains(opts.items or {}, item) then
      fail("items %s lack %q", vim.inspect(opts.items), item)
    end
  end
  for _, item in ipairs(want.not_items or {}) do
    if vim.tbl_contains(opts.items or {}, item) then
      fail("items %s have %q", vim.inspect(opts.items), item)
    end
  end
  _G.calls = {}
  return true
end

---Answer the interactive step `_G.took` just read: a sub-picker gets its choice, an input its text.
---@param value string
---@return boolean
function _G.answer(value)
  local c = _G.taken
  if not c then fail("nothing waits for an answer") end
  _G.taken = nil
  if c.kind == "input" then
    c.opts.on_submit(value)
  else
    c.opts.on_select(value)
  end
  return true
end

---The fixture path of a collection (or of a folder below the fixture).
---@param rel string
---@return string
function _G.fx(rel)
  return tmp .. "/" .. rel
end

---The child's cwd and config folder, as the cwd and config scopes resolve them.
---@return string
function _G.cwd()
  return vim.fs.normalize(vim.uv.cwd() or vim.fn.getcwd())
end
---@return string
function _G.cfgdir()
  return vim.fs.normalize(tostring(vim.fn.stdpath("config")))
end

return {}
