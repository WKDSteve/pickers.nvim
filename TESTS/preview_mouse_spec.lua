-- Test code: a nil here (a require, a captured option) must crash and name it.
---@diagnostic disable: need-check-nil
-- pickers.nvim -- `pickers.preview_mouse`: double click in the preview jumps (after a
-- confirmation), right click opens the context menu, the maps live only while the
-- picker window is current. Runs against a fake `Snacks.picker` (no snacks needed).
--
-- Run:
--   nvim -l TESTS/preview_mouse_spec.lua

-- ── Self-bootstrapping runtimepath ──────────────────────────────────────────
local this = debug.getinfo(1, "S").source:sub(2)
local tests_dir = vim.fn.fnamemodify(this, ":p:h")
local root = vim.fn.fnamemodify(tests_dir, ":h")
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

local real_notify = vim.notify
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function() end

-- ── fixtures ────────────────────────────────────────────────────────────────
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local file = dir .. "/target.txt"
vim.fn.writefile({ "one", "two", "three", "four" }, file)

local main_win = vim.api.nvim_get_current_win()
local preview_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, { "one", "two", "three", "four" })
local preview_win = vim.api.nvim_open_win(preview_buf, false, {
  relative = "editor",
  row = 1,
  col = 1,
  width = 20,
  height = 4,
})
vim.api.nvim_win_set_var(preview_win, "snacks_picker_preview", true)

local list_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_option_value("filetype", "snacks_picker_list", { buf = list_buf })
local list_win = vim.api.nvim_open_win(list_buf, false, {
  relative = "editor",
  row = 8,
  col = 1,
  width = 20,
  height = 4,
})

local closed = 0
local picker = {
  closed = false,
  preview = { win = { win = preview_win }, item = { file = file } },
  list = { win = { win = list_win } },
  close = function(self)
    closed = closed + 1
    self.closed = true
  end,
  current = function()
    return { file = file, pos = { 3, 0 } }
  end,
  items = function()
    return { { file = file, text = "a" }, { text = "no file" } }
  end,
}
_G.Snacks = { picker = {
  get = function()
    return { picker }
  end,
} }

local pmouse = require("pickers.preview_mouse")

local function maparg(buf, lhs)
  return vim.api.nvim_buf_call(buf, function()
    return vim.fn.maparg(lhs, "n", false, true)
  end)
end

-- ── find_picker ─────────────────────────────────────────────────────────────
local p, part = pmouse.find_picker(preview_win)
check("find_picker: preview window", p == picker and part == "preview")
p, part = pmouse.find_picker(list_win)
check("find_picker: list window", p == picker and part == "list")
check("find_picker: foreign window", pmouse.find_picker(main_win) == nil)

-- ── maps live only while the picker window is current ───────────────────────
pmouse.install()
vim.api.nvim_set_current_win(preview_win)
check("enter preview: double click map set", maparg(preview_buf, "<2-LeftMouse>").buffer == 1)
check("enter preview: right click map set", maparg(preview_buf, "<RightMouse>").buffer == 1)
vim.api.nvim_set_current_win(main_win)
check("leave preview: double click map removed", next(maparg(preview_buf, "<2-LeftMouse>")) == nil)
check("leave preview: right click map removed", next(maparg(preview_buf, "<RightMouse>")) == nil)
vim.api.nvim_set_current_win(list_win)
check("enter list: right click map set", maparg(list_buf, "<RightMouse>").buffer == 1)
check("enter list: no double click map", next(maparg(list_buf, "<2-LeftMouse>")) == nil)
vim.api.nvim_set_current_win(main_win)

-- ── double click: confirm, then jump ────────────────────────────────────────
vim.api.nvim_win_set_cursor(preview_win, { 3, 0 })
local asked
vim.fn.confirm = function(msg)
  asked = msg
  return 2
end
pmouse.preview_double_click(preview_win)
vim.wait(100)
check(
  "double click, answer no: asks with file and line",
  asked and asked:find("target.txt:3", 1, true)
)
check("double click, answer no: picker stays open", closed == 0)
check("double click, answer no: no buffer opened", vim.fn.expand("%:p") ~= vim.fs.normalize(file))

vim.fn.confirm = function()
  return 1
end
pmouse.preview_double_click(preview_win)
vim.wait(500, function()
  return vim.fs.normalize(vim.api.nvim_buf_get_name(0)) == vim.fs.normalize(file)
end)
check("double click, answer yes: picker closed", closed == 1)
check(
  "double click, answer yes: file opened",
  vim.fs.normalize(vim.api.nvim_buf_get_name(0)) == vim.fs.normalize(file)
)
check("double click, answer yes: on the clicked line", vim.api.nvim_win_get_cursor(0)[1] == 3)
picker.closed = false
vim.cmd("enew")

-- ── menu items ──────────────────────────────────────────────────────────────
local function names(items)
  local out = {}
  for _, it in ipairs(items or {}) do
    if it.name then out[it.name] = true end
  end
  return out
end

vim.api.nvim_set_current_win(preview_win)
local n = names(pmouse.menu_items(picker, "preview", preview_win))
check("preview menu: open in split", n["Open in split"])
check("preview menu: copy whole file content", n["Copy whole file content"])
check("preview menu: copy this line", n["Copy this line"])
check("preview menu: list entries offered too", n["Copy all entries"])
check("preview menu: no selection, no 'Copy selection'", n["Copy selection"] == nil)
vim.api.nvim_set_current_win(main_win)

n = names(pmouse.menu_items(picker, "list", list_win))
check("list menu: open in vsplit", n["Open in vsplit"])
check("list menu: send to quickfix", n["Send all entries to quickfix"])
check("list menu: no 'Copy this line' (preview only)", n["Copy this line"] == nil)

local saved = picker.preview.item
picker.preview.item = { text = "no file" }
n = names(pmouse.menu_items(picker, "preview", preview_win))
check("item without a file: no open entries", n["Open here"] == nil and n["Copy path"] == nil)
picker.preview.item = saved

-- ── list actions ────────────────────────────────────────────────────────────
local items = pmouse.menu_items(picker, "list", list_win)
for _, it in ipairs(items) do
  if it.name == "Copy all entries" then
    local cmd = it.cmd
    if type(cmd) == "function" then
      cmd()
    else
      vim.cmd(cmd)
    end
  end
end
local copied = vim.fn.getreg('"')
check(
  "copy all entries: one line per item, path or text",
  copied:find("target.txt", 1, true) and copied:find("no file", 1, true),
  copied
)

_G.Snacks = nil
check("without snacks: find_picker is nil", pmouse.find_picker(preview_win) == nil)

vim.notify = real_notify
vim.fn.delete(dir, "rf")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
