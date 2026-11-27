---@module 'pickers.preview_mouse'
---@brief Mouse interactions for the preview and the result list of a snacks picker.
---@description
--- * Double click in the preview: asks "jump there?" and, on yes, closes the picker and
---   opens the previewed file in a new buffer at the clicked line.
--- * Right click in the preview or the result list: a context menu
---   (`lib.nvim.contextmenu`, also re-exported by ui.nvim) -- open in
---   window/split/vsplit/tab, copy selection/line/file/path, go to a path via
---   gopath.nvim, copy/export the whole list, open with the system app.
---
--- The maps are buffer-local and live only while the picker window is the current
--- one (`WinEnter` sets them, `WinLeave` removes them), so a previewed buffer is
--- never left with a stray map. Only the snacks engine has real preview/list
--- windows to bind to; telescope and fzf-lua are not covered. Switch off with
--- `cfg.preview_mouse = false`.

local M = {}

local augroup = "pickers_preview_mouse"
---@type table<integer, string[]>  buffer -> the lhs we mapped there
local mapped = {}

---@return table|nil
local function snacks_picker_mod()
  local S = rawget(_G, "Snacks")
  if type(S) == "table" and S.picker and type(S.picker.get) == "function" then return S.picker end
end

---The snacks picker owning window `win`, and which part of it that is.
---@param win integer
---@return table|nil picker
---@return "preview"|"list"|nil part
function M.find_picker(win)
  local sp = snacks_picker_mod()
  if not sp then return nil end
  local ok, pickers = pcall(sp.get)
  if not ok or type(pickers) ~= "table" then return nil end
  for _, p in ipairs(pickers) do
    if not p.closed then
      if p.preview and p.preview.win and p.preview.win.win == win then return p, "preview" end
      if p.list and p.list.win and p.list.win.win == win then return p, "list" end
    end
  end
end

---Absolute path of a picker item, or nil when it has none.
---@param item table|nil
---@return string|nil
function M.item_path(item)
  if type(item) ~= "table" then return nil end
  local sp = snacks_picker_mod()
  local path
  if sp and sp.util and sp.util.path then
    local ok, res = pcall(sp.util.path, item)
    if ok then path = res end
  end
  path = path or item.file
  if type(path) ~= "string" or path == "" then return nil end
  return vim.fs.normalize(path)
end

---Text of the visual selection when called in visual mode, else nil.
---@return string|nil
local function visual_text()
  local mode = vim.fn.mode()
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then return nil end
  local ok, lines = pcall(vim.fn.getregion, vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
  if not ok or type(lines) ~= "table" then return nil end
  local text = table.concat(lines, "\n")
  return text ~= "" and text or nil
end

---@param text string
local function copy(text)
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  vim.notify(("copied %d chars"):format(#text), vim.log.levels.INFO, { title = "pickers" })
end

---Close the picker, then run `fn` once the editor is back on the window behind it.
---@param picker table
---@param fn fun()
local function after_close(picker, fn)
  pcall(function()
    picker:close()
  end)
  vim.schedule(fn)
end

---Open `file` with `cmd` (edit/split/vsplit/tabedit), cursor on `line` when given.
---@param file string
---@param line integer|nil
---@param cmd string|nil
function M.open_file(file, line, cmd)
  vim.cmd((cmd or "edit") .. " " .. vim.fn.fnameescape(file))
  if line and line > 0 then
    local last = vim.api.nvim_buf_line_count(0)
    pcall(vim.api.nvim_win_set_cursor, 0, { math.min(line, last), 0 })
    vim.cmd("normal! zz")
  end
end

---What the preview currently shows: the file and the line under the cursor.
---@param picker table
---@param win integer
---@return string|nil file, integer|nil line
local function preview_target(picker, win)
  local item = picker.preview and picker.preview.item or nil
  local file = M.item_path(item)
  if not file then return nil end
  local ok, cur = pcall(vim.api.nvim_win_get_cursor, win)
  return file, ok and cur[1] or nil
end

---Double click in the preview: confirm, then jump.
---@param win integer
function M.preview_double_click(win)
  local picker = M.find_picker(win)
  if not picker then return end
  local file, line = preview_target(picker, win)
  if not file or vim.fn.filereadable(file) ~= 1 then return end
  local label = ("%s:%d"):format(vim.fn.fnamemodify(file, ":~:."), line or 1)
  if vim.fn.confirm(("Jump to %s?"):format(label), "&Yes\n&No", 2) ~= 1 then return end
  after_close(picker, function()
    M.open_file(file, line, "edit")
  end)
end

---@param picker table
---@return string[]
local function list_lines(picker)
  local out = {}
  local ok, items = pcall(function()
    return picker:items()
  end)
  if not ok or type(items) ~= "table" then return out end
  for _, it in ipairs(items) do
    local path = M.item_path(it)
    out[#out + 1] = path and vim.fn.fnamemodify(path, ":~:.") or tostring(it.text or "")
  end
  return out
end

---@param picker table
local function list_to_quickfix(picker)
  local ok, items = pcall(function()
    return picker:items()
  end)
  if not ok or type(items) ~= "table" then return end
  local qf = {}
  for _, it in ipairs(items) do
    local path = M.item_path(it)
    local pos = type(it.pos) == "table" and it.pos or {}
    qf[#qf + 1] =
      { filename = path, lnum = pos[1] or 1, col = (pos[2] or 0) + 1, text = it.text or "" }
  end
  after_close(picker, function()
    vim.fn.setqflist({}, " ", { title = "pickers", items = qf })
    vim.cmd("copen")
  end)
end

---@param picker table
local function list_to_buffer(picker)
  local lines = list_lines(picker)
  after_close(picker, function()
    vim.cmd("enew")
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = 0 })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = 0 })
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  end)
end

---The menu items for a click on `part` of `picker`. nil when contextmenu is unavailable.
---@param picker table
---@param part "preview"|"list"
---@param win integer
---@return table[]|nil
function M.menu_items(picker, part, win)
  local ok, cm = pcall(require, "lib.nvim.contextmenu")
  if not ok then return nil end

  local sel = part == "preview" and visual_text() or nil
  local file, line
  if part == "preview" then
    file, line = preview_target(picker, win)
  else
    local cur = picker:current()
    file = M.item_path(cur)
    line = cur and type(cur.pos) == "table" and cur.pos[1] or nil
  end
  local readable = file ~= nil and vim.fn.filereadable(file) == 1

  local function open_in(cmd)
    return function()
      after_close(picker, function()
        M.open_file(file, line, cmd)
      end)
    end
  end

  local gopath_target
  if sel and not sel:find("\n", 1, true) then
    local okg, gp = pcall(require, "gopath")
    if okg and type(gp.resolve_line) == "function" then
      local okr, res = pcall(gp.resolve_line, sel, { dir = file and vim.fs.dirname(file) or nil })
      if okr and type(res) == "table" and res.path then gopath_target = res end
    end
  end

  local out = {}
  cm.group(
    out,
    cm.heading("Open"),
    cm.entry(readable, "Open here", open_in("edit")),
    cm.entry(readable, "Open in split", open_in("split")),
    cm.entry(readable, "Open in vsplit", open_in("vsplit")),
    cm.entry(readable, "Open in new tab", open_in("tabedit")),
    cm.entry(readable and vim.ui.open ~= nil, "Open with system app", function()
      vim.ui.open(file)
    end),
    cm.entry(gopath_target ~= nil, "Go to selected path (gopath)", function()
      local r = gopath_target
      after_close(picker, function()
        M.open_file(r.path, r.line or r.lnum, "edit")
      end)
    end)
  )
  cm.group(
    out,
    cm.heading("Copy"),
    cm.entry(sel ~= nil, "Copy selection", function()
      copy(sel)
    end),
    cm.entry(file ~= nil, "Copy path", function()
      copy(file)
    end),
    cm.entry(file ~= nil and line ~= nil, "Copy path:line", function()
      copy(("%s:%d"):format(file, line))
    end),
    cm.entry(part == "preview", "Copy this line", function()
      local row = vim.api.nvim_win_get_cursor(win)[1]
      local l = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), row - 1, row, false)[1]
      copy(l or "")
    end),
    cm.entry(readable, "Copy whole file content", function()
      copy(table.concat(vim.fn.readfile(file), "\n"))
    end)
  )
  cm.group(
    out,
    cm.heading("List"),
    cm.entry(true, "Copy all entries", function()
      copy(table.concat(list_lines(picker), "\n"))
    end),
    cm.entry(true, "Send all entries to quickfix", function()
      list_to_quickfix(picker)
    end),
    cm.entry(true, "Open all entries in a new buffer", function()
      list_to_buffer(picker)
    end)
  )
  return out
end

---Right click handler for a picker window.
---@param win integer
local function right_click(win)
  local picker, part = M.find_picker(win)
  if not picker or not part then return end
  if part == "list" then
    -- the click does not move the list cursor: select the row under the mouse
    local pos = vim.fn.getmousepos()
    if pos.winid == win and picker.list and picker.list.row2idx then
      local okr, idx = pcall(picker.list.row2idx, picker.list, pos.line)
      if okr and idx then pcall(function()
        picker.list:view(idx)
      end) end
    end
  end
  local items = M.menu_items(picker, part, win)
  if items and #items > 0 then require("lib.nvim.contextmenu").open(items, { mouse = true }) end
end

---@param buf integer
local function unmap(buf)
  for _, lhs in ipairs(mapped[buf] or {}) do
    pcall(vim.keymap.del, { "n", "v" }, lhs, { buffer = buf })
  end
  mapped[buf] = nil
end

---@param win integer
local function bind(win)
  local picker, part = M.find_picker(win)
  if not picker then return end
  local buf = vim.api.nvim_win_get_buf(win)
  unmap(buf)
  if part == "preview" then
    vim.keymap.set("n", "<2-LeftMouse>", function()
      M.preview_double_click(win)
    end, {
      buffer = buf,
      silent = true,
      desc = "pickers: jump to the previewed line",
    })
  end
  vim.keymap.set({ "n", "v" }, "<RightMouse>", function()
    right_click(win)
  end, {
    buffer = buf,
    silent = true,
    desc = "pickers: context menu",
  })
  mapped[buf] = { "<2-LeftMouse>", "<RightMouse>" }
end

---Register the autocmds (idempotent).
function M.install()
  if not snacks_picker_mod() then return end
  local group = vim.api.nvim_create_augroup(augroup, { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    desc = "pickers: bind mouse maps in a snacks picker preview/list",
    callback = function()
      if vim.w.snacks_picker_preview or vim.bo.filetype == "snacks_picker_list" then
        bind(vim.api.nvim_get_current_win())
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinLeave", {
    group = group,
    callback = function()
      local buf = vim.api.nvim_get_current_buf()
      if mapped[buf] then unmap(buf) end
    end,
  })
end

return M
