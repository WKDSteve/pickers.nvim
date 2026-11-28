---@module 'pickers.preview_mouse'
---@brief Mouse interactions for the preview and the result list of a picker (snacks, telescope, fzf-lua).
---@description
--- * Double click in the preview: asks "jump there?" and, on yes, closes the picker and
---   opens the previewed file in a new buffer at the clicked line.
--- * Right click in the preview or the result list: a context menu
---   (`lib.nvim.contextmenu`, also re-exported by ui.nvim) -- open in
---   window/split/vsplit/tab, copy selection/line/file/path, go to a path via
---   gopath.nvim, reveal the file in filetree.nvim, copy/export the whole list, open with the
---   system app.
---
--- The maps are buffer-local and live only while the picker window is the current
--- one (`WinEnter` sets them, `WinLeave` removes them), so a previewed buffer is
--- never left with a stray map. snacks pickers are used as they are; telescope and
--- fzf-lua go through a handle of the same shape (`pickers.preview_mouse_engines`, which
--- also names their limits). Switch off with `cfg.preview_mouse = false`.

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
---@return "preview"|"list"|"input"|nil part
local function find_snacks(win)
  local sp = snacks_picker_mod()
  if not sp then return nil end
  local ok, pickers = pcall(sp.get)
  if not ok or type(pickers) ~= "table" then return nil end
  for _, p in ipairs(pickers) do
    if not p.closed then
      if p.preview and p.preview.win and p.preview.win.win == win then return p, "preview" end
      if p.list and p.list.win and p.list.win.win == win then return p, "list" end
      if p.input and p.input.win and p.input.win.win == win then return p, "input" end
    end
  end
end

---The picker owning window `win` -- a snacks picker, or a handle of the same shape for
---telescope and fzf-lua (`pickers.preview_mouse_engines`) -- and which part of it that is.
---@param win integer
---@return table|nil picker
---@return "preview"|"list"|"input"|nil part
function M.find_picker(win)
  local p, part = find_snacks(win)
  if p then return p, part end
  for _, engine in ipairs(require("pickers.preview_mouse_engines").list) do
    local ok, h, hpart = pcall(engine.find, win)
    if ok and h then return h, hpart end
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

---Whether the feature is on (`cfg.preview_mouse`, default true); asked at use time, so a
---`setup()` after the engine loaded still counts.
---@return boolean
local function enabled()
  local ok, cfg = pcall(function()
    return require("pickers.config").get()
  end)
  return not ok or type(cfg) ~= "table" or cfg.preview_mouse ~= false
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
  if not ok then return file, nil end
  local row = cur[1]
  -- The row is the file's line only when the preview shows the file itself; a preview of
  -- another mode (`pickers.preview_modes` text) has other rows. Compare the line, and fall
  -- back to the item's own position when it differs. Big files are trusted unchecked.
  local stat = vim.uv.fs_stat(file)
  if stat and stat.size <= 2 * 1024 * 1024 then
    local shown = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), row - 1, row, false)[1]
    local read = vim.fn.readfile(file, "", row)
    if shown == nil or read[row] ~= shown then
      local pos = item and type(item.pos) == "table" and item.pos[1] or nil
      return file, pos
    end
  end
  return file, row
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

---filetree.nvim's reveal function (shows a path in its tree), or nil when filetree is not
---installed or not set up. A soft dependency: pickers never requires it.
---@return (fun(path: string): boolean?)|nil
function M.filetree_reveal()
  local ok, ft = pcall(require, "filetree")
  if not ok or type(ft) ~= "table" or type(ft.adapter) ~= "function" then return nil end
  local oka, adapter = pcall(ft.adapter)
  if not oka or type(adapter) ~= "table" or type(adapter.open_reveal) ~= "function" then
    return nil
  end
  return function(path)
    return adapter.open_reveal(path)
  end
end

---Whether `path` names a Markdown file (by its extension).
---@param path string|nil
---@return boolean
function M.is_markdown(path)
  if not path then return false end
  local ext = (path:match("%.([%w]+)$") or ""):lower()
  return ext == "md" or ext == "markdown" or ext == "mdx"
end

---A function that shows a Markdown file in mdview.nvim's browser preview, or nil when mdview is
---not installed. A soft dependency, the same way filetree's `mdview_open` uses it: mdview previews
---the current buffer, so the file is loaded (unlisted if it was not open) and mdview runs in it.
---@return (fun(path: string))|nil
function M.mdview_open()
  local ok, mdview = pcall(require, "mdview")
  if not ok or type(mdview) ~= "table" or type(mdview.open) ~= "function" then return nil end
  return function(path)
    local existed = vim.fn.bufexists(path) == 1
    local buf = vim.fn.bufadd(path)
    vim.fn.bufload(buf)
    if not existed then vim.api.nvim_set_option_value("buflisted", false, { buf = buf }) end
    vim.api.nvim_buf_call(buf, function()
      mdview.open()
    end)
  end
end

---gitsuite.nvim's blame of one line of a file without a buffer
---(`gitsuite.features.blame.for_location`), or nil when gitsuite is not installed.
---@return (fun(dir: string|nil, path: string, lnum: integer, cb: fun(entry: table|nil, err: string|nil)))|nil
function M.gitsuite_blame()
  local ok, blame = pcall(require, "gitsuite.features.blame")
  if not ok or type(blame) ~= "table" or type(blame.for_location) ~= "function" then return nil end
  return blame.for_location
end

---One line for a blame entry: short sha, date, author, summary; "uncommitted" for an all-zero sha.
---@param entry table  # Lib.Git.BlameEntry
---@return string
function M.format_blame(entry)
  if type(entry.sha) ~= "string" or entry.sha:match("^0+$") then return "uncommitted" end
  local date = entry.author_time and os.date("%Y-%m-%d", entry.author_time) or "?"
  return ("%s %s %s %s"):format(entry.sha:sub(1, 8), date, entry.author or "?", entry.summary or "")
end

---The buffer a copied Markdown link is meant for: the window behind the picker, else the current one.
---@param picker table
---@return integer
local function link_buffer(picker)
  local win = picker.main
  if type(win) == "number" and vim.api.nvim_win_is_valid(win) then
    return vim.api.nvim_win_get_buf(win)
  end
  return vim.api.nvim_get_current_buf()
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

  local reveal = file ~= nil and vim.uv.fs_stat(file) ~= nil and M.filetree_reveal() or nil
  local mdview = readable and M.is_markdown(file) and M.mdview_open() or nil
  local blame = readable and line ~= nil and M.gitsuite_blame() or nil

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
    end),
    cm.entry(reveal ~= nil, "Reveal in filetree", function()
      after_close(picker, function()
        local okr, res = pcall(reveal, file)
        if not okr or res == false then
          vim.notify(
            ("could not reveal in filetree: %s%s"):format(
              file,
              okr and "" or (" (" .. tostring(res) .. ")")
            ),
            vim.log.levels.WARN,
            { title = "pickers" }
          )
        end
      end)
    end),
    cm.entry(mdview ~= nil, "Preview in mdview", function()
      after_close(picker, function()
        local okm, err = pcall(mdview, file)
        if not okm then
          vim.notify(
            ("could not preview in mdview: %s (%s)"):format(file, tostring(err)),
            vim.log.levels.WARN,
            { title = "pickers" }
          )
        end
      end)
    end)
  )
  cm.group(
    out,
    cm.heading("Git"),
    cm.entry(blame ~= nil, "Blame this line (gitsuite)", function()
      local dir, name, lnum = vim.fs.dirname(file), vim.fs.basename(file), line
      blame(dir, name, lnum, function(entry, err)
        vim.schedule(function()
          if err then
            vim.notify("blame: " .. err, vim.log.levels.WARN, { title = "pickers" })
          elseif not entry then
            vim.notify("blame: no data for this line", vim.log.levels.INFO, { title = "pickers" })
          else
            vim.notify(
              ("%s:%d  %s"):format(name, lnum, M.format_blame(entry)),
              vim.log.levels.INFO,
              { title = "pickers" }
            )
          end
        end)
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
    cm.entry(file ~= nil, "Copy Markdown link", function()
      local links =
        require("pickers.entry_actions.link_insert").build({ file }, link_buffer(picker))
      copy(table.concat(links, "\n"))
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
  -- an engine whose list is not readable (fzf-lua: fzf in a terminal) has no `items`
  local has_items = type(picker.items) == "function"
  cm.group(
    out,
    cm.heading("List"),
    cm.entry(has_items, "Copy all entries", function()
      copy(table.concat(list_lines(picker), "\n"))
    end),
    cm.entry(has_items, "Send all entries to quickfix", function()
      list_to_quickfix(picker)
    end),
    cm.entry(has_items, "Open all entries in a new buffer", function()
      list_to_buffer(picker)
    end)
  )
  return out
end

---Right click handler. The click is mapped in every picker window, the input field too: the
---focus sits there while the user points at the list or the preview, and a mapping is looked up
---in the buffer that has the focus, not in the one under the pointer. So the window that gets
---the menu is the one under the mouse.
local function right_click()
  local win = vim.fn.getmousepos().winid
  local picker, part = M.find_picker(win)
  if not picker or (part ~= "list" and part ~= "preview") then return end
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
  if part == "preview" and not visual_text() then
    -- a right click does not move the cursor by itself: put it on the clicked line, so
    -- "copy this line" and the open-at-line entries mean what was clicked
    local pos = vim.fn.getmousepos()
    if pos.winid == win and pos.line > 0 then
      pcall(vim.api.nvim_win_set_cursor, win, { pos.line, math.max(pos.column - 1, 0) })
    end
  end
  local items = M.menu_items(picker, part, win)
  if not items or #items == 0 then return end
  -- an engine that closes its picker when the focus leaves it (telescope) holds it open
  if type(picker.before_menu) == "function" then pcall(picker.before_menu, picker) end
  local surf = require("lib.nvim.contextmenu").open(items, { mouse = true })
  -- and gets the focus back once the menu is gone (an entry that closed the picker runs first)
  if surf and type(surf.on_close) == "function" and type(picker.after_menu) == "function" then
    surf:on_close(function()
      vim.schedule(function()
        pcall(picker.after_menu, picker)
      end)
    end)
  end
  -- the menu opens above the picker's floats on its own (lib.nvim.ui.kit.menu, lib.nvim@63ebb1d)
end

---@param buf integer
local function unmap(buf)
  for _, m in ipairs(mapped[buf] or {}) do
    for _, mode in ipairs(m.modes) do
      pcall(vim.keymap.del, mode, m.lhs, { buffer = buf })
      -- a buffer-local map of the user's that ours stood in front of comes back
      local saved = m.saved and m.saved[mode]
      if saved and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_call(buf, function()
          pcall(vim.fn.mapset, mode, false, saved)
        end)
      end
    end
  end
  mapped[buf] = nil
end

---The buffer-local maps of `lhs` in `buf` that are not ours, per mode: the preview of fzf-lua can
---show a real, loaded buffer, whose own maps must survive the time the preview is current.
---@param buf integer
---@param lhs string
---@param modes string[]
---@return table<string, table>|nil
local function own_maps(buf, lhs, modes)
  local saved
  vim.api.nvim_buf_call(buf, function()
    for _, mode in ipairs(modes) do
      local m = vim.fn.maparg(lhs, mode, false, true)
      if m.buffer == 1 and not tostring(m.desc or ""):find("^pickers: ") then
        saved = saved or {}
        saved[mode] = m
      end
    end
  end)
  return saved
end

---The part of a picker `win` is for binding: snacks asked directly, the other engines by a cheap
---test (a telescope prompt can be entered before telescope has filed the picker).
---@param win integer
---@return "preview"|"list"|"input"|nil
local function bind_part(win)
  local _, part = find_snacks(win)
  if part then return part end
  for _, engine in ipairs(require("pickers.preview_mouse_engines").list) do
    local ok, p = pcall(engine.classify, win)
    if ok and p then return p end
  end
end

---@param win integer
local function bind(win)
  local part = bind_part(win)
  if not part then return end
  local buf = vim.api.nvim_win_get_buf(win)
  unmap(buf)
  local maps = {}
  if part == "preview" then
    local saved = own_maps(buf, "<2-LeftMouse>", { "n" })
    vim.keymap.set("n", "<2-LeftMouse>", function()
      M.preview_double_click(win)
    end, {
      buffer = buf,
      silent = true,
      desc = "pickers: jump to the previewed line",
    })
    maps[#maps + 1] = { lhs = "<2-LeftMouse>", modes = { "n" }, saved = saved }
  end
  -- the input field is in insert mode while the user types
  local modes = part == "input" and { "n", "i" } or { "n", "v" }
  local saved = own_maps(buf, "<RightMouse>", modes)
  vim.keymap.set(modes, "<RightMouse>", right_click, {
    buffer = buf,
    silent = true,
    desc = "pickers: context menu",
  })
  maps[#maps + 1] = { lhs = "<RightMouse>", modes = modes, saved = saved }
  mapped[buf] = maps
end

---Register the autocmds (idempotent).
function M.install()
  -- No `Snacks` check here: the engine module can load before snacks has set its global,
  -- and a check now would leave the feature off for the whole session. `find_picker` and
  -- `enabled` are asked when a window is entered.
  local group = vim.api.nvim_create_augroup(augroup, { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    desc = "pickers: bind mouse maps in a picker's input, list and preview (snacks, telescope, fzf-lua)",
    callback = function()
      local ft = vim.bo.filetype
      if
        enabled()
        and (
          vim.w.snacks_picker_preview
          or ft == "snacks_picker_list"
          or ft == "snacks_picker_input"
          or ft == "TelescopePrompt"
          or vim.w.fzf_lua_preview
        )
      then
        bind(vim.api.nvim_get_current_win())
      end
    end,
  })
  -- telescope enters its prompt window first and sets the filetype after: WinEnter saw none
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "TelescopePrompt",
    desc = "pickers: bind the mouse maps in a telescope prompt",
    callback = function(args)
      local win = vim.api.nvim_get_current_win()
      if enabled() and vim.api.nvim_win_get_buf(win) == args.buf then bind(win) end
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
