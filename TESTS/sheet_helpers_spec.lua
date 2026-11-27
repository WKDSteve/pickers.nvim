-- pickers.nvim -- the screen helpers of the test sheets (TESTS/sheets/_helpers.lua): `_G.screen_pos`
-- gives the 0-based cell `nvim_input_mouse` takes, also behind a double-width character, whose
-- right half `screenstring()` reports as an empty cell.
--
-- Run:  nvim -l TESTS/sheet_helpers_spec.lua

local this = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(vim.fn.fnamemodify(this, ":p:h"), ":h")
dofile(root .. "/TESTS/sheets/_helpers.lua")

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

vim.api.nvim_set_option_value("lines", 10, {})
vim.api.nvim_set_option_value("columns", 40, {})

local function pos_of(line, text)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  local row, col = _G.screen_pos(text)
  return row, col
end

do
  local row, col = pos_of("abc xyz", "xyz")
  check("plain text: row 0, the cell of x", row == 0 and col == 4, ("%s,%s"):format(row, col))
end

do
  -- cells: a | 中 | (right half of 中) | x
  local row, col = pos_of("a\u{4e2d}xyz", "xyz")
  check(
    "behind a double-width character: the cell of x, not the right half before it",
    row == 0 and col == 3,
    ("%s,%s"):format(row, col)
  )
end

do
  local row, col = pos_of("a\u{4e2d}xyz", "\u{4e2d}x")
  check(
    "text that starts with a double-width character: its left cell",
    row == 0 and col == 1,
    ("%s,%s"):format(row, col)
  )
end

check("text not on the screen: nil", pos_of("abc", "zzz") == nil)

print(("\n%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
