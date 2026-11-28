---@diagnostic disable: need-check-nil
-- pickers.nvim -- `pickers.preview_mouse` on telescope and fzf-lua (`pickers.preview_mouse_engines`):
-- the right-click menu and the double click work on a handle in the shape of a snacks picker.
-- The engines are stand-ins of what preview_mouse reads from them: telescope's global state
-- (`telescope.state`) and picker fields, fzf-lua's window object (`fzf-lua`.win.__SELF()) and the
-- `last_entry` of its builtin previewer.
--
-- Run:  nvim -l TESTS/preview_mouse_engines_spec.lua

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

---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function() end

local dir = vim.fn.tempname()
vim.fn.mkdir(dir .. "/src", "p")
local file = dir .. "/src/alpha.lua"
vim.fn.writefile({ "one", "two", "three", "four" }, file)

-- macOS reaches the temp dir through a symlink (/var -> /private/var): compare real paths
local function real(path)
  return path and vim.fs.normalize(vim.uv.fs_realpath(path) or path) or nil
end

local function float(row, lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or { "x" })
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = row,
    col = 1,
    width = 30,
    height = 4,
  })
  return win, buf
end

local function names(items)
  local out = {}
  for _, it in ipairs(items or {}) do
    if it.name then out[it.name] = true end
  end
  return out
end
local function find_item(list, name)
  for _, it in ipairs(list or {}) do
    if it.name == name then return it end
  end
end
local function maparg(buf, lhs, mode)
  return vim.api.nvim_buf_call(buf, function()
    return vim.fn.maparg(lhs, mode or "n", false, true)
  end)
end

local main_win = vim.api.nvim_get_current_win()
local pmouse = require("pickers.preview_mouse")
local engines = require("pickers.preview_mouse_engines")

-- ── telescope ───────────────────────────────────────────────────────────────
local prompt_win, prompt_buf = float(1)
vim.api.nvim_set_option_value("filetype", "TelescopePrompt", { buf = prompt_buf })
local results_win = float(6, { "alpha.lua:2", "beta.lua" })
local preview_win = float(11, { "one", "two", "three", "four" })

local selected = 0
local closed_with
local entries = {
  -- relative to the picker's cwd, with a position (a grep hit)
  { filename = "src/alpha.lua", cwd = dir, lnum = 2, col = 3, ordinal = "alpha.lua:2" },
  { value = "no file", ordinal = "no file" },
}
local tp = {
  prompt_win = prompt_win,
  results_win = results_win,
  preview_win = preview_win,
  original_win_id = main_win,
  get_selection = function()
    return entries[selected + 1]
  end,
  set_selection = function(_, row)
    selected = row
  end,
  manager = {
    iter = function()
      local i = 0
      return function()
        i = i + 1
        return entries[i]
      end
    end,
  },
}
package.loaded["telescope.state"] = {
  get_existing_prompt_bufnrs = function()
    return { prompt_buf }
  end,
  get_status = function(buf)
    return buf == prompt_buf and { picker = tp } or {}
  end,
}
package.loaded["telescope.actions"] = {
  close = function(buf)
    closed_with = buf
  end,
}

local h, part = pmouse.find_picker(results_win)
check("telescope: results window -> list", h ~= nil and part == "list" and h.engine == "telescope")
check(
  "telescope: preview window -> preview",
  select(2, pmouse.find_picker(preview_win)) == "preview"
)
check("telescope: prompt window -> input", select(2, pmouse.find_picker(prompt_win)) == "input")
check("telescope: a foreign window is no picker", pmouse.find_picker(main_win) == nil)

local cur = h:current()
check(
  "telescope: a relative entry path becomes absolute against the entry's cwd",
  cur and real(cur.file) == real(file),
  cur and cur.file
)
check(
  "telescope: lnum/col become the item's pos (1-based line, 0-based col)",
  cur and cur.pos and cur.pos[1] == 2 and cur.pos[2] == 2,
  cur and vim.inspect(cur.pos)
)
check(
  "telescope: the preview item is the selection",
  h.preview.item and h.preview.item.file == cur.file
)

h.list:view(h.list:row2idx(2))
check(
  "telescope: selecting a clicked row sets telescope's 0-based selection",
  selected == 1,
  selected
)
selected = 0

local all = h:items()
check("telescope: items() lists the manager's entries", #all == 2 and all[2].text == "no file")

local n = names(pmouse.menu_items(h, "list", results_win))
check("telescope list menu: open entries", n["Open here"] and n["Open in split"])
check(
  "telescope list menu: list entries",
  n["Copy all entries"] and n["Send all entries to quickfix"]
)
check("telescope list menu: copy path:line (the entry has a line)", n["Copy path:line"])

local opened = false
local open_item = find_item(pmouse.menu_items(h, "list", results_win), "Open here")
if open_item then
  open_item.cmd()
  vim.wait(500, function()
    opened = real(vim.api.nvim_buf_get_name(0)) == real(file)
    return opened
  end)
end
check(
  "telescope: 'Open here' closes the picker through telescope's actions",
  closed_with == prompt_buf
)
check(
  "telescope: and opens the file on the entry's line",
  opened and vim.api.nvim_win_get_cursor(0)[1] == 2,
  vim.api.nvim_buf_get_name(0)
)
vim.cmd("enew")
main_win = vim.api.nvim_get_current_win()

-- binding: loading the telescope engine installs the mouse, with no call by hand and without the
-- snacks engine's module (it used to be the only place that installed it)
local real_telescope_engine = package.loaded["pickers.engines.telescope"]
package.loaded["pickers.engines.telescope"] = {
  available = function()
    return true
  end,
}
require("pickers.config").reset()
require("pickers.config").apply({ engine = "telescope" })
local _, engine_name = require("pickers.engines").load()
package.loaded["pickers.engines.telescope"] = real_telescope_engine
check("telescope: engines.load() picks the telescope engine", engine_name == "telescope")
check(
  "... without loading the snacks engine's module",
  package.loaded["pickers.engines.snacks"] == nil
)
-- an augroup that was never created is an error to ask for, not an empty list
local has_group, mouse_aus =
  pcall(vim.api.nvim_get_autocmds, { group = "pickers_preview_mouse", event = "WinEnter" })
check("... and the mouse is installed", has_group and #mouse_aus == 1)
-- the right click on the prompt (insert mode too), no own double click
vim.api.nvim_set_current_win(prompt_win)
check(
  "telescope: entering the prompt maps <RightMouse>",
  maparg(prompt_buf, "<RightMouse>").buffer == 1
)
check(
  "telescope: in insert mode too (the prompt is typed in)",
  maparg(prompt_buf, "<RightMouse>", "i").buffer == 1
)
check(
  "telescope: no own double click (telescope's click opens the preview's entry)",
  next(maparg(prompt_buf, "<2-LeftMouse>")) == nil
)
vim.api.nvim_set_current_win(main_win)
check(
  "telescope: leaving the prompt removes the map",
  next(maparg(prompt_buf, "<RightMouse>")) == nil
)

-- the prompt is bound even before telescope filed the picker (classify, not find)
package.loaded["telescope.state"].get_existing_prompt_bufnrs = function()
  return {}
end
vim.api.nvim_set_current_win(prompt_win)
check(
  "telescope: a prompt not yet in telescope's state is bound anyway",
  maparg(prompt_buf, "<RightMouse>").buffer == 1
)
vim.api.nvim_set_current_win(main_win)

-- telescope enters the prompt window first and sets its filetype after: bound on FileType
local late_win, late_buf = float(20)
vim.api.nvim_set_current_win(late_win)
check(
  "telescope: a prompt without its filetype yet is not bound",
  next(maparg(late_buf, "<RightMouse>")) == nil
)
vim.api.nvim_set_option_value("filetype", "TelescopePrompt", { buf = late_buf })
check(
  "telescope: setting the prompt filetype in the current window binds it",
  maparg(late_buf, "<RightMouse>", "i").buffer == 1
)
vim.api.nvim_set_current_win(main_win)
pcall(vim.api.nvim_win_close, late_win, true)

-- the menu takes the focus: telescope's close-on-leave is held off and comes back in the prompt
package.loaded["telescope.state"].get_existing_prompt_bufnrs = function()
  return { prompt_buf }
end
local left = 0
vim.api.nvim_create_augroup("PickerInsert", {})
vim.api.nvim_create_autocmd("BufLeave", {
  group = "PickerInsert",
  buffer = prompt_buf,
  nested = true,
  once = true,
  callback = function()
    left = left + 1
  end,
})
local function leave_autocmds()
  return #vim.api.nvim_get_autocmds({
    group = "PickerInsert",
    buffer = prompt_buf,
    event = "BufLeave",
  })
end
vim.api.nvim_set_current_win(prompt_win)
local th = pmouse.find_picker(prompt_win)
th:before_menu()
check("telescope: before_menu takes telescope's BufLeave off the prompt", leave_autocmds() == 0)
vim.api.nvim_set_current_win(main_win) -- the menu has the focus
check("telescope: leaving the prompt for the menu does not close the picker", left == 0)
th:after_menu()
check(
  "telescope: after_menu puts the focus back in the prompt",
  vim.api.nvim_get_current_win() == prompt_win
)
check("telescope: and telescope's BufLeave is back", leave_autocmds() == 1)
vim.api.nvim_set_current_win(main_win)
check("telescope: leaving the prompt afterwards closes it as before", left == 1)
vim.api.nvim_set_current_win(main_win)
package.loaded["telescope.state"] = nil
package.loaded["telescope.actions"] = nil

-- telescope installed but not loaded (lazy.nvim): asking for a picker must not load it
local telescope_loaded = false
package.preload["telescope.state"] = function()
  telescope_loaded = true
  return {
    get_existing_prompt_bufnrs = function()
      return {}
    end,
    get_status = function()
      return {}
    end,
  }
end
pmouse.find_picker(results_win)
check("telescope not loaded: finding a picker does not load it", not telescope_loaded)
package.preload["telescope.state"] = nil
package.loaded["telescope.state"] = nil

for _, w in ipairs({ prompt_win, results_win, preview_win }) do
  pcall(vim.api.nvim_win_close, w, true)
end

-- ── fzf-lua ─────────────────────────────────────────────────────────────────
local fzf_win = float(1)
local fpreview_win, fpreview_buf = float(6, { "one", "two", "three", "four" })
vim.api.nvim_win_set_var(fpreview_win, "fzf_lua_preview", true)

local fzf_closed = 0
local obj = {
  fzf_winid = fzf_win,
  preview_winid = fpreview_win,
  src_winid = main_win,
  _previewer = {
    last_entry = "src/alpha.lua:3:2:three",
    opts = { cwd = dir },
    entry_to_file = function(_, s)
      local p, l, c = s:match("^([^:]+):(%d+):(%d+):")
      return { path = p, line = tonumber(l), col = tonumber(c) }
    end,
  },
}
function obj:close()
  fzf_closed = fzf_closed + 1
  self.closing = true
end
package.loaded["fzf-lua"] = {
  win = {
    __SELF = function()
      return obj
    end,
  },
}

local fh, fpart = pmouse.find_picker(fpreview_win)
check(
  "fzf-lua: preview window -> preview",
  fh ~= nil and fpart == "preview" and fh.engine == "fzf-lua"
)
check("fzf-lua: the fzf terminal -> input", select(2, pmouse.find_picker(fzf_win)) == "input")
local fitem = fh and fh.preview.item
check(
  "fzf-lua: the previewed entry is parsed and made absolute against the picker's cwd",
  fitem and real(fitem.file) == real(file) and fitem.pos[1] == 3 and fitem.pos[2] == 1,
  fitem and vim.inspect(fitem)
)

vim.api.nvim_set_current_win(fpreview_win)
vim.api.nvim_win_set_cursor(fpreview_win, { 3, 0 })
n = names(pmouse.menu_items(fh, "preview", fpreview_win))
check("fzf-lua preview menu: open entries", n["Open here"] and n["Copy this line"])
check(
  "fzf-lua preview menu: no list entries (fzf's list is a terminal)",
  n["Copy all entries"] == nil and n["Send all entries to quickfix"] == nil
)
vim.api.nvim_set_current_win(main_win)

-- binding: entering the preview maps the double click and the right click
vim.api.nvim_set_current_win(fpreview_win)
check(
  "fzf-lua: entering the preview maps <2-LeftMouse>",
  maparg(fpreview_buf, "<2-LeftMouse>").buffer == 1
)
check("fzf-lua: and <RightMouse>", maparg(fpreview_buf, "<RightMouse>").buffer == 1)

-- double click: asks, closes fzf-lua, opens the file on the clicked line
local dialog = require("lib.nvim.ui.dialog")
local real_yesno = dialog.yesno
---@diagnostic disable-next-line: duplicate-set-field
dialog.yesno = function(_, _, cb)
  cb(true)
end
vim.api.nvim_win_set_cursor(fpreview_win, { 3, 0 })
pmouse.preview_double_click(fpreview_win)
local jumped = vim.wait(500, function()
  return real(vim.api.nvim_buf_get_name(0)) == real(file)
end)
dialog.yesno = real_yesno
check("fzf-lua: double click closes the picker", fzf_closed == 1, fzf_closed)
check(
  "fzf-lua: and opens the file on the clicked line",
  jumped and vim.api.nvim_win_get_cursor(0)[1] == 3,
  vim.api.nvim_buf_get_name(0)
)
check("fzf-lua: a closing picker is no picker", pmouse.find_picker(fpreview_win) == nil)

package.loaded["fzf-lua"] = nil
check("without fzf-lua: no picker", pmouse.find_picker(fpreview_win) == nil)
check(
  "engines are listed in order",
  engines.list[1] == engines.telescope and engines.list[2] == engines.fzf_lua
)

vim.fn.delete(dir, "rf")
print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
