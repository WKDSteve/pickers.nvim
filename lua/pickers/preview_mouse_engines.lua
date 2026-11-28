---@module 'pickers.preview_mouse_engines'
---@brief The telescope and fzf-lua side of `pickers.preview_mouse`.
---@description
--- `pickers.preview_mouse` speaks to a picker in the shape of a snacks picker: `close()`,
--- `current()`, `items()` (optional), `preview.item`, `preview.win.win`, `list.win.win` with
--- `list.row2idx`/`list.view`, `input.win.win`, `main`. snacks pickers are that shape already;
--- for telescope and fzf-lua each adapter here builds a handle of it at click time.
---
--- Each adapter has `classify(win)`, a cheap test for the `WinEnter` autocmd (which part of a
--- picker `win` is, without asking the engine), and `find(win)`, the handle and the part.
---
--- * telescope: the focus stays in the prompt, which telescope gives its own `<LeftMouse>` and
---   `<2-LeftMouse>` (a click in the results selects, one in the preview opens). The right click
---   is bound in the prompt and works on the window under the pointer; there is no own double
---   click, telescope's single click in the preview already opens the entry.
--- * fzf-lua: the result list is fzf itself in a terminal, no rows to bind. Only the preview of
---   the builtin previewer is a window: after a click into it, the double click and the right
---   click work there. A shell previewer (a terminal too) is not covered.

local M = {}

---@param path string|nil
---@param cwd string|nil
---@return string|nil
local function absolute(path, cwd)
  if type(path) ~= "string" or path == "" then return nil end
  if not vim.startswith(path, "/") and not path:match("^%a:[/\\]") and not path:match("^~") then
    path = (cwd or vim.uv.cwd()) .. "/" .. path
  end
  return vim.fs.normalize(vim.fn.fnamemodify(vim.fs.normalize(path), ":p"))
end

-- ── telescope ────────────────────────────────────────────────────────────────

M.telescope = {}

---A telescope entry as a picker item `{ file, pos, text }`.
---@param entry table|nil
---@return table|nil
function M.telescope.item(entry)
  if type(entry) ~= "table" then return nil end
  local file = absolute(entry.path or entry.filename, entry.cwd)
  local text = entry.ordinal
  if type(text) ~= "string" then text = tostring(entry.value or "") end
  local item = { text = text, file = file }
  if type(entry.lnum) == "number" then
    item.pos = { entry.lnum, math.max((entry.col or 1) - 1, 0) }
  end
  return item
end

---The open telescope pickers, from its global state. Never a require: with telescope not yet
---loaded no telescope picker can be open, and a require would load it (lazy.nvim) on a right
---click in any other picker.
---@return table[]  # { prompt_bufnr, picker }
local function telescope_pickers()
  local out = {}
  local state = package.loaded["telescope.state"]
  if type(state) ~= "table" or type(state.get_existing_prompt_bufnrs) ~= "function" then
    return out
  end
  local okb, bufs = pcall(state.get_existing_prompt_bufnrs)
  if not okb or type(bufs) ~= "table" then return out end
  for _, buf in ipairs(bufs) do
    local status = state.get_status(buf)
    if type(status) == "table" and type(status.picker) == "table" then
      out[#out + 1] = { prompt_bufnr = buf, picker = status.picker }
    end
  end
  return out
end

---The part of a telescope picker `win` is, by its filetype alone: only the prompt is bound.
---@param win integer
---@return "input"|nil
function M.telescope.classify(win)
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].filetype == "TelescopePrompt" then return "input" end
end

---@param prompt_bufnr integer
---@param tp table  # the telescope picker
---@return table handle
function M.telescope.handle(prompt_bufnr, tp)
  local h = {
    engine = "telescope",
    closed = false,
    main = tp.original_win_id,
    input = { win = { win = tp.prompt_win } },
    preview = { win = { win = tp.preview_win } },
    list = {
      win = { win = tp.results_win },
      -- telescope's rows are 0-based buffer rows; the click gives the 1-based line
      row2idx = function(_, line)
        return line
      end,
      view = function(_, line)
        tp:set_selection(line - 1)
      end,
    },
  }
  function h:current()
    local ok, entry = pcall(tp.get_selection, tp)
    return ok and M.telescope.item(entry) or nil
  end
  function h:items()
    local out = {}
    if not (tp.manager and type(tp.manager.iter) == "function") then return out end
    for entry in tp.manager:iter() do
      out[#out + 1] = M.telescope.item(entry)
    end
    return out
  end
  function h:close()
    self.closed = true
    require("telescope.actions").close(prompt_bufnr)
  end
  -- the menu takes the focus, and telescope closes its picker when the prompt is left
  function h:before_menu()
    M.telescope.hold_open(prompt_bufnr)
  end
  -- the menu gives the focus back to some window: if the picker is still open, to its prompt
  -- (that is what puts telescope's close-on-leave back, see hold_open)
  function h:after_menu()
    local w = tp.prompt_win
    if w and vim.api.nvim_win_is_valid(w) and vim.api.nvim_get_current_win() ~= w then
      pcall(vim.api.nvim_set_current_win, w)
    end
  end
  -- the preview shows the selected entry
  h.preview.item = h:current()
  return h
end

---Keep a telescope picker open while a menu has the focus. telescope closes the picker on the
---prompt's `BufLeave` (group `PickerInsert`, `once`, `nested`); that autocmd is taken off and put
---back with telescope's own callback when the focus is back in the prompt (`BufEnter`), and the
---prompt goes back to insert mode if it was typed in.
---@param prompt_bufnr integer
function M.telescope.hold_open(prompt_bufnr)
  local ok, aus = pcall(vim.api.nvim_get_autocmds, {
    group = "PickerInsert",
    buffer = prompt_bufnr,
    event = "BufLeave",
  })
  if not ok or type(aus) ~= "table" or #aus == 0 then return end
  local was_insert = vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
  for _, au in ipairs(aus) do
    pcall(vim.api.nvim_del_autocmd, au.id)
  end
  vim.api.nvim_create_autocmd("BufEnter", {
    buffer = prompt_bufnr,
    once = true,
    desc = "pickers: put telescope's close-on-leave back after the mouse menu",
    callback = function()
      for _, au in ipairs(aus) do
        pcall(vim.api.nvim_create_autocmd, "BufLeave", {
          group = "PickerInsert",
          buffer = prompt_bufnr,
          nested = true,
          once = true,
          desc = au.desc,
          callback = au.callback,
          command = au.callback == nil and au.command or nil,
        })
      end
      if was_insert then vim.cmd("startinsert!") end
    end,
  })
end

---The telescope picker owning `win`, as a handle, and which part `win` is.
---@param win integer
---@return table|nil handle
---@return "preview"|"list"|"input"|nil part
function M.telescope.find(win)
  for _, it in ipairs(telescope_pickers()) do
    local tp = it.picker
    local part = (tp.preview_win == win and "preview")
      or (tp.results_win == win and "list")
      or (tp.prompt_win == win and "input")
      or nil
    if part then return M.telescope.handle(it.prompt_bufnr, tp), part end
  end
end

-- ── fzf-lua ──────────────────────────────────────────────────────────────────

M.fzf_lua = {}

---The window object of the running fzf-lua picker, without loading fzf-lua.
---@return table|nil
local function fzf_winobj()
  local fzf = package.loaded["fzf-lua"]
  if type(fzf) ~= "table" then return nil end
  local ok, obj = pcall(function()
    return fzf.win.__SELF()
  end)
  if ok and type(obj) == "table" and not obj.closing then return obj end
end

---@param win integer
---@return "preview"|nil
function M.fzf_lua.classify(win)
  local ok, is = pcall(vim.api.nvim_win_get_var, win, "fzf_lua_preview")
  if ok and is then return "preview" end
end

---The previewed entry of the builtin previewer as a picker item.
---@param previewer table|nil
---@return table|nil
function M.fzf_lua.item(previewer)
  if type(previewer) ~= "table" or type(previewer.last_entry) ~= "string" then return nil end
  if type(previewer.entry_to_file) ~= "function" then return { text = previewer.last_entry } end
  local ok, e = pcall(previewer.entry_to_file, previewer, previewer.last_entry)
  if not ok or type(e) ~= "table" then return { text = previewer.last_entry } end
  local cwd = type(previewer.opts) == "table" and previewer.opts.cwd or nil
  local item = { text = previewer.last_entry, file = absolute(e.path, cwd) }
  local line = tonumber(e.line)
  if line and line > 0 then item.pos = { line, math.max((tonumber(e.col) or 1) - 1, 0) } end
  return item
end

---@param obj table  # fzf-lua's window object
---@return table handle
function M.fzf_lua.handle(obj)
  local item = M.fzf_lua.item(obj._previewer)
  local h = {
    engine = "fzf-lua",
    closed = false,
    main = obj.src_winid,
    input = { win = { win = obj.fzf_winid } },
    preview = { win = { win = obj.preview_winid }, item = item },
    -- the list is fzf in a terminal: no rows, no items
    list = nil,
  }
  function h:current()
    return item
  end
  function h:close()
    self.closed = true
    obj:close()
  end
  return h
end

---@param win integer
---@return table|nil handle
---@return "preview"|"input"|nil part
function M.fzf_lua.find(win)
  local obj = fzf_winobj()
  if not obj then return nil end
  if obj.preview_winid == win then return M.fzf_lua.handle(obj), "preview" end
  if obj.fzf_winid == win then return M.fzf_lua.handle(obj), "input" end
end

---The adapters in the order they are asked.
M.list = { M.telescope, M.fzf_lua }

return M
