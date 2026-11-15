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
