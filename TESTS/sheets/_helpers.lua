-- TESTS/sheets/_helpers.lua -- what the pickers.nvim test sheets need in their child editor. Not a sheet
-- (`testing.sheet` only reads *.sheet.lua); a sheet's `requires` and its first step run it with `dofile`, the
-- child's cwd is the project root. The directory is in the spec's @cache-inputs, so a change here re-runs the
-- sheets.
--
-- The sheets open `pickers.items` on the REAL picker libraries (telescope, fzf-lua, snacks), with a UI attached:
-- what the specs can only pin on stand-ins (fzf-lua draws no list without a UI) is typed and read here.

-- luacheck: globals vim

local M = {}

---The named picker libraries on the runtimepath; false when one is not to be found. For `requires`.
---TESTS/minimal_init.lua looked them up ($<NAME>_DIR, .deps/<name>, ../<name>, the lazy.nvim directory of the
---real editor) and left what it found in `vim.g.pickers_sheets_deps`.
---@param ... string
---@return boolean
function M.add_deps(...)
  local found = vim.g.pickers_sheets_deps or {}
  for _, name in ipairs({ ... }) do
    if type(found[name]) ~= "string" then return false end
  end
  for _, name in ipairs({ ... }) do
    vim.opt.rtp:append(found[name])
  end
  return true
end

vim.o.swapfile = false
vim.opt.shortmess:append("I")

-- Every notification is kept instead of shown: a long one would become a hit-enter prompt.
_G.notes = {}
vim.notify = function(msg)
  _G.notes[#_G.notes + 1] = tostring(msg)
end

---Whether a notification so far is exactly `text`.
---@param text string
---@return boolean
function _G.noted(text)
  return vim.tbl_contains(_G.notes, text)
end

---`got == want`, or an error that says what came instead (the failure line of the sheet shows it).
---@param got any
---@param want any
---@return boolean
function _G.eq(got, want)
  if not vim.deep_equal(got, want) then
    error(("got %s, wanted %s"):format(vim.inspect(got), vim.inspect(want)), 0)
  end
  return true
end

---The screen as text, one row per line: a picker is floats, a terminal (fzf) or both, and only the screen is
---the same question on all three.
---@return string
function _G.screen_text()
  vim.cmd("redraw")
  local rows = {}
  for row = 1, vim.o.lines do
    local cells = {}
    for col = 1, vim.o.columns do
      cells[#cells + 1] = vim.fn.screenstring(row, col)
    end
    rows[#rows + 1] = table.concat(cells)
  end
  return table.concat(rows, "\n")
end

---Whether the screen shows `text` (plain, within one row).
---@param text string
---@return boolean
function _G.on_screen(text)
  return _G.screen_text():find(text, 1, true) ~= nil
end

---Where `text` first appears on the screen, as the 0-based row and column `nvim_input_mouse` takes
---(grid 0: the whole screen). A cell may hold a multi-byte character (an icon), so the column counts
---cells, not bytes. With `win`, only the text area of that window is searched (a file name can
---also stand in the title of another window). nil when it is not there.
---@param text string
---@param win? integer
---@return integer|nil row, integer|nil col
function _G.screen_pos(text, win)
  vim.cmd("redraw")
  local top, left, bottom, right = 1, 1, vim.o.lines, vim.o.columns
  if win then
    local pos = vim.fn.win_screenpos(win) -- 1-based row, col of the text area
    top, left = pos[1], pos[2]
    bottom = top + vim.api.nvim_win_get_height(win) - 1
    right = left + vim.api.nvim_win_get_width(win) - 1
  end
  for row = top, bottom do
    local cells = {}
    for col = left, right do
      cells[#cells + 1] = vim.fn.screenstring(row, col)
    end
    local at = table.concat(cells):find(text, 1, true)
    if at then
      local bytes = 0
      for i, cell in ipairs(cells) do
        -- the right half of a double-width character is an empty cell: never the start of `text`
        if cell ~= "" and bytes + 1 >= at then return row - 1, left + i - 2 end
        bytes = bytes + #cell
      end
    end
  end
  return nil
end

---Click with the mouse on the first place the screen shows `text`: `button` "left" or "right",
---`count` 2 for a double click (two presses on one cell within 'mousetime'). Raises when the
---text is not on the screen, so the step that clicks names what was missing.
---@param button "left"|"right"
---@param text string
---@param count? integer
---@param win? integer  search only this window (see `screen_pos`)
function _G.click(button, text, count, win)
  local row, col = _G.screen_pos(text, win)
  if not row then error(("not on the screen: %q"):format(text), 0) end
  for _ = 1, count or 1 do
    vim.api.nvim_input_mouse(button, "press", "", 0, row, col)
    vim.api.nvim_input_mouse(button, "release", "", 0, row, col)
  end
end

---A project for the mouse sheet: `beta.txt` and `src/alpha.lua` as the cwd. Sets `_G.proj`.
function _G.mouse_project()
  _G.proj = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(_G.proj .. "/src", "p")
  vim.fn.writefile({ "local alpha = 1", "return alpha" }, _G.proj .. "/src/alpha.lua")
  vim.fn.writefile({ "beta line one", "beta line two", "beta line three" }, _G.proj .. "/beta.txt")
  vim.cmd.cd(_G.proj)
end

---The line under the cursor of the filetree window, or nil when no tree is shown.
---@return string|nil
function _G.tree_cursor_line()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "filetree" then
      local row = vim.api.nvim_win_get_cursor(win)[1]
      return vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
    end
  end
  return nil
end

---A project of three files as the cwd, for the smart/filegrep sheets: `needlek2_file.lua` (found by its name),
---`plain.md` holding `quokka2` (found by its content) and `haystack.txt` (found by neither). Sets `_G.proj`.
function _G.smart_project()
  _G.proj = vim.fs.normalize(vim.fn.tempname())
  local files = {
    ["src/needlek2_file.lua"] = { "local x = 1" },
    ["notes/plain.md"] = { "the quokka2 lives here" },
    ["other/haystack.txt"] = { "nothing" },
  }
  for rel, lines in pairs(files) do
    vim.fn.mkdir(vim.fs.dirname(_G.proj .. "/" .. rel), "p")
    vim.fn.writefile(lines, _G.proj .. "/" .. rel)
  end
  vim.cmd.cd(_G.proj)
end

---The rows of the list every sheet opens.
local ROWS = { { text = "alpha one" }, { text = "beta two" }, { text = "alpha three" } }

---@param sel table[]
---@return string
local function names(sel)
  return table.concat(
    vim.tbl_map(function(row)
      return row.text
    end, sel),
    ", "
  )
end

---Open `pickers.items` on the engine `name` ("telescope", "fzf", "snacks"): three rows, marks on, a preview
---worked out per row, the key <M-s> that says which rows it got and what was typed and opens the list again,
---and <CR> that says which rows it got. `_G.opened` counts how often the list was opened.
---@param name string
function _G.open_list(name)
  if name == "snacks" then require("snacks").setup({ picker = { enabled = true } }) end
  _G.opened = 0
  local engine = require("pickers.engines." .. name)
  local items = require("pickers.items")
  items.open({
    engine_mod = engine,
    items = function()
      _G.opened = _G.opened + 1
      return ROWS
    end,
    title = "Sheet> ",
    marks = true,
    preview = function(item)
      return { lines = { "preview of " .. item.text } }
    end,
    actions = {
      show = {
        key = "<M-s>",
        desc = "show",
        fn = function(sel, ctx)
          vim.notify("key: " .. names(sel) .. " | query: " .. ctx.query)
          ctx.reopen()
        end,
      },
    },
    on_select = function(_, sel)
      vim.notify("enter: " .. names(sel))
    end,
  })
end

return M
