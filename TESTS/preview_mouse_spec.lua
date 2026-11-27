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

-- macOS reaches the temp dir through a symlink (/var -> /private/var): compare real paths
local function real(path)
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end
local function current_file()
  return real(vim.api.nvim_buf_get_name(0))
end

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

local input_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_option_value("filetype", "snacks_picker_input", { buf = input_buf })
local input_win = vim.api.nvim_open_win(input_buf, false, {
  relative = "editor",
  row = 14,
  col = 1,
  width = 20,
  height = 1,
})

local closed = 0
local picker = {
  closed = false,
  preview = { win = { win = preview_win }, item = { file = file } },
  list = { win = { win = list_win } },
  input = { win = { win = input_win } },
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

local function maparg(buf, lhs, mode)
  return vim.api.nvim_buf_call(buf, function()
    return vim.fn.maparg(lhs, mode or "n", false, true)
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
-- the focus sits in the input field while the user points at the list: the right click must be
-- mapped there too, in insert mode as well (the field is typed into)
check("find_picker: input window", select(2, pmouse.find_picker(input_win)) == "input")
vim.api.nvim_set_current_win(input_win)
check(
  "enter input: right click map set in insert mode",
  maparg(input_buf, "<RightMouse>", "i").buffer == 1
)
check("enter input: and in normal mode", maparg(input_buf, "<RightMouse>").buffer == 1)
check("enter input: no double click map", next(maparg(input_buf, "<2-LeftMouse>")) == nil)
vim.api.nvim_set_current_win(main_win)
check(
  "leave input: insert-mode right click map removed",
  next(maparg(input_buf, "<RightMouse>", "i")) == nil
)

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
check("double click, answer no: no buffer opened", current_file() ~= real(file))

vim.fn.confirm = function()
  return 1
end
pmouse.preview_double_click(preview_win)
vim.wait(500, function()
  return current_file() == real(file)
end)
check("double click, answer yes: picker closed", closed == 1)
check("double click, answer yes: file opened", current_file() == real(file))
check("double click, answer yes: on the clicked line", vim.api.nvim_win_get_cursor(0)[1] == 3)
picker.closed = false
vim.cmd("enew")

-- ── a preview that is not the file's text: the row is not the file's line ───
vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, { "(mode text)", "other", "rows" })
vim.api.nvim_win_set_cursor(preview_win, { 2, 0 })
picker.preview.item = { file = file, pos = { 4, 0 } }
asked = nil
vim.fn.confirm = function(msg)
  asked = msg
  return 2
end
pmouse.preview_double_click(preview_win)
check(
  "foreign preview text: jumps to the item's own line, not the preview row",
  asked and asked:find("target.txt:4", 1, true),
  asked
)
vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, { "one", "two", "three", "four" })
picker.preview.item = { file = file }

-- ── the feature can be switched off, also after the engine loaded ───────────
vim.api.nvim_set_current_win(preview_win)
vim.api.nvim_set_current_win(main_win)
pmouse.install()
require("pickers.config").apply({ preview_mouse = false })
vim.api.nvim_set_current_win(preview_win)
check(
  "preview_mouse = false: no map on entering the preview",
  next(maparg(preview_buf, "<RightMouse>")) == nil
)
vim.api.nvim_set_current_win(main_win)
require("pickers.config").reset()

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

-- ── "Reveal in filetree": only with filetree.nvim, calls its reveal with the path ──
local function find_item(list, name)
  for _, it in ipairs(list or {}) do
    if it.name == name then return it end
  end
end
local function run(it)
  if type(it.cmd) == "function" then
    it.cmd()
  else
    vim.cmd(it.cmd)
  end
end

package.loaded["filetree"] = nil
package.preload["filetree"] = nil
n = names(pmouse.menu_items(picker, "list", list_win))
check("without filetree: no 'Reveal in filetree'", n["Reveal in filetree"] == nil)

package.loaded["filetree"] = {
  adapter = function()
    return nil -- installed, but setup() never ran
  end,
}
n = names(pmouse.menu_items(picker, "list", list_win))
check("filetree without adapter: no 'Reveal in filetree'", n["Reveal in filetree"] == nil)

local revealed = {}
local reveal_result = true
package.loaded["filetree"] = {
  adapter = function()
    return {
      open_reveal = function(path)
        revealed[#revealed + 1] = path
        if reveal_result == "error" then error("boom") end
        return reveal_result
      end,
    }
  end,
}
local closed_before = closed
local reveal_item = find_item(pmouse.menu_items(picker, "list", list_win), "Reveal in filetree")
check("with filetree: list menu offers 'Reveal in filetree'", reveal_item ~= nil)
vim.api.nvim_set_current_win(preview_win)
check(
  "with filetree: preview menu offers 'Reveal in filetree'",
  names(pmouse.menu_items(picker, "preview", preview_win))["Reveal in filetree"]
)
vim.api.nvim_set_current_win(main_win)
if reveal_item then
  run(reveal_item)
  vim.wait(500, function()
    return #revealed > 0
  end)
  picker.closed = false
end
check(
  "reveal: filetree gets the row's path",
  #revealed == 1 and real(revealed[1]) == real(file),
  vim.inspect(revealed)
)
check("reveal: the picker is closed first", closed == closed_before + 1)

local notes = {}
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(msg)
  notes[#notes + 1] = msg
end
reveal_result = "error"
reveal_item = find_item(pmouse.menu_items(picker, "list", list_win), "Reveal in filetree")
if reveal_item then
  run(reveal_item)
  vim.wait(500, function()
    return #notes > 0
  end)
  picker.closed = false
end
check(
  "reveal: a filetree error is reported, not raised",
  notes[1] and notes[1]:find("could not reveal in filetree", 1, true),
  vim.inspect(notes)
)
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function() end

saved = picker.current
picker.current = function()
  return { text = "no file" }
end
n = names(pmouse.menu_items(picker, "list", list_win))
check("row without a path: no 'Reveal in filetree'", n["Reveal in filetree"] == nil)
picker.current = function()
  return { file = dir .. "/missing.txt" }
end
n = names(pmouse.menu_items(picker, "list", list_win))
check("row with a missing path: no 'Reveal in filetree'", n["Reveal in filetree"] == nil)
picker.current = saved
package.loaded["filetree"] = nil

-- ── "Preview in mdview": only with mdview.nvim and only on a Markdown file ───
local md = dir .. "/notes.md"
vim.fn.writefile({ "# Notes" }, md)
local md_row = function()
  return { file = md, pos = { 1, 0 } }
end
saved = picker.current
picker.current = md_row
package.loaded["mdview"] = nil
package.preload["mdview"] = function()
  error("mdview.nvim is not installed")
end
n = names(pmouse.menu_items(picker, "list", list_win))
check("without mdview: no 'Preview in mdview'", n["Preview in mdview"] == nil)
package.preload["mdview"] = nil

local previewed = {}
package.loaded["mdview"] = {
  open = function()
    previewed[#previewed + 1] = vim.api.nvim_buf_get_name(0)
  end,
}
picker.current = saved
n = names(pmouse.menu_items(picker, "list", list_win))
check("with mdview, a .txt row: no 'Preview in mdview'", n["Preview in mdview"] == nil)
picker.current = md_row
closed_before = closed
local md_item = find_item(pmouse.menu_items(picker, "list", list_win), "Preview in mdview")
check("with mdview, a .md row: 'Preview in mdview' offered", md_item ~= nil)
if md_item then
  run(md_item)
  vim.wait(500, function()
    return #previewed > 0
  end)
  picker.closed = false
end
check(
  "mdview: opened with the Markdown file as the current buffer",
  #previewed == 1 and real(previewed[1]) == real(md),
  vim.inspect(previewed)
)
check("mdview: the picker is closed first", closed == closed_before + 1)
check("mdview: the file stays unlisted", vim.fn.buflisted(vim.fn.bufnr(md)) == 0)
picker.current = saved
package.loaded["mdview"] = nil

-- ── "Blame this line (gitsuite)": gitsuite's blame of the row's file and line ──
package.loaded["gitsuite.features.blame"] = nil
package.preload["gitsuite.features.blame"] = function()
  error("gitsuite.nvim is not installed")
end
n = names(pmouse.menu_items(picker, "list", list_win))
check("without gitsuite: no 'Blame this line (gitsuite)'", n["Blame this line (gitsuite)"] == nil)
package.preload["gitsuite.features.blame"] = nil

local blamed = {}
local blame_answer = {
  sha = "0123456789abcdef0123456789abcdef01234567",
  author = "Ada",
  author_time = 0,
  summary = "first cut",
}
package.loaded["gitsuite.features.blame"] = {
  for_location = function(bdir, bpath, lnum, cb)
    blamed[#blamed + 1] = { dir = bdir, path = bpath, lnum = lnum }
    if blame_answer == "error" then
      cb(nil, "not a git repository")
    else
      cb(blame_answer, nil)
    end
    return { stop = function() end }
  end,
}
notes = {}
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(msg)
  notes[#notes + 1] = msg
end
local blame_item =
  find_item(pmouse.menu_items(picker, "list", list_win), "Blame this line (gitsuite)")
check("with gitsuite: 'Blame this line (gitsuite)' offered", blame_item ~= nil)
if blame_item then
  run(blame_item)
  vim.wait(500, function()
    return #notes > 0
  end)
end
check(
  "blame: gitsuite gets the row's directory, file name and line",
  #blamed == 1
    and real(blamed[1].dir) == real(dir)
    and blamed[1].path == "target.txt"
    and blamed[1].lnum == 3,
  vim.inspect(blamed)
)
check(
  "blame: the answer is shown with short sha, author and summary",
  notes[1]
    and notes[1]:find("target.txt:3", 1, true)
    and notes[1]:find("01234567 ", 1, true)
    and notes[1]:find("Ada", 1, true)
    and notes[1]:find("first cut", 1, true),
  vim.inspect(notes)
)
notes = {}
blame_answer = "error"
if blame_item then
  run(blame_item)
  vim.wait(500, function()
    return #notes > 0
  end)
end
check(
  "blame: a git error is reported, not raised",
  notes[1] and notes[1]:find("not a git repository", 1, true),
  vim.inspect(notes)
)
check(
  "format_blame: an all-zero sha is uncommitted",
  pmouse.format_blame({ sha = string.rep("0", 40) }) == "uncommitted"
)
picker.current = function()
  return { file = file }
end
n = names(pmouse.menu_items(picker, "list", list_win))
check("row without a line: no blame entry", n["Blame this line (gitsuite)"] == nil)
picker.current = saved
package.loaded["gitsuite.features.blame"] = nil
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function() end

-- ── "Copy Markdown link": [name](target) of the row's file ──────────────────
local link_item = find_item(pmouse.menu_items(picker, "list", list_win), "Copy Markdown link")
check("'Copy Markdown link' offered for a row with a file", link_item ~= nil)
vim.fn.setreg('"', "")
if link_item then run(link_item) end
local link = vim.fn.getreg('"')
check(
  "copy Markdown link: one [name](target) link to the file",
  link:match("^%[[^%]]+%]%([^%)]*target%.txt%)$") ~= nil,
  link
)

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

-- ── the menu shows above the picker ─────────────────────────────────────────
-- the picker's floats get a zindex above the menu's popup level, as snacks' do
for _, w in ipairs({ preview_win, list_win, input_win }) do
  vim.api.nvim_win_set_config(w, { zindex = 55 })
end
local menu_buf = vim.api.nvim_create_buf(false, true)
local menu_win = vim.api.nvim_open_win(menu_buf, true, {
  relative = "editor",
  row = 2,
  col = 2,
  width = 10,
  height = 2,
  zindex = 50,
})
pmouse.raise_above(picker)
check(
  "raise_above: the menu that took the focus goes above the picker",
  vim.api.nvim_win_get_config(menu_win).zindex > 55,
  vim.api.nvim_win_get_config(menu_win).zindex
)
vim.api.nvim_win_close(menu_win, true)
-- a renderer that leaves the focus in the picker (nvzone/menu): the picker window stays as it was
vim.api.nvim_set_current_win(input_win)
pmouse.raise_above(picker)
check(
  "raise_above: a picker window with the focus is not raised",
  vim.api.nvim_win_get_config(input_win).zindex == 55,
  vim.api.nvim_win_get_config(input_win).zindex
)
vim.api.nvim_set_current_win(main_win)

_G.Snacks = nil
check("without snacks: find_picker is nil", pmouse.find_picker(preview_win) == nil)

vim.notify = real_notify
vim.fn.delete(dir, "rf")

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
