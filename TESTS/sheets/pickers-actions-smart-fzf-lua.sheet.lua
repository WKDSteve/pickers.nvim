-- Feature pickers.actions (TESTS/sheets/features.lua) with the real rg and fd on the real fzf-lua: the smart
-- action finds a file by its name (the listing) and by its content (rg), a regex query runs fd, and :FileGrep
-- narrows a path word by `grep=`. fzf-lua's reload calls the Lua contents in this editor; it returns a writer at
-- once, the search runs beside the editor (pickers.smart.job) and writes its rows when rg/fd are done.
-- Needs fzf-lua and the program fzf (the workflow provides both), rg and fd (or fdfind).
local SETUP = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
  require("fzf-lua").setup({})
  require("pickers").setup({ engine = "fzf" })
  _G.smart_project()
  ---The picker is open and takes input (else: what was said instead, as the failure).
  _G.picker_open = function()
    if vim.bo.filetype == "fzf" and vim.fn.mode() == "t" then return true end
    if #_G.notes > 0 then error(table.concat(_G.notes, " | "), 0) end
    return false
  end
  ---fzf has ended and its window is gone (an empty list alone is not enough: the window closes after it).
  _G.picker_closed = function()
    if vim.bo.filetype ~= "fzf" and vim.fn.mode() ~= "t" then return true end
    _G.close_state = ("filetype %s, mode %s"):format(vim.bo.filetype, vim.fn.mode())
    return false
  end]]

return {
  id = "pickers.actions-smart-fzf-lua",
  feature = "pickers.actions",
  title = "The smart action and :FileGrep find files by name and content with the real rg and fd on fzf-lua",
  task = "pickers.nvim/smart-filegrep-rg-und-fd-fuer-regex-laufen-je-taste-synchron",
  engine = "rpc",
  sizes = { { rows = 24, cols = 120 } },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps("fzf-lua")]],
      reason = "fzf-lua is not to be found",
    },
    { lua = [[vim.fn.executable("fzf") == 1]], reason = "the program fzf is not installed" },
    { lua = [[vim.fn.executable("rg") == 1]], reason = "rg is not installed" },
    {
      lua = [[vim.fn.executable("fd") == 1 or vim.fn.executable("fdfind") == 1]],
      reason = "fd is not installed",
    },
  },
  steps = {
    { lua = SETUP, note = "fzf-lua, pickers.nvim on it, a project of three files as the cwd" },

    { input = ":Pickers cwd smart<CR>", note = ":Pickers cwd smart" },
    { wait = "_G.picker_open()", timeout = 15000, note = "fzf runs in its terminal" },
    { input = "quokka2", note = "a word of a file's content" },
    {
      wait = [[_G.on_screen("plain.md") and not _G.on_screen("haystack.txt")]],
      timeout = 20000,
      note = "rg finds the file that holds it, and no other",
    },
    { input = "<Esc><Esc>", note = "<Esc> leaves the terminal, the second one closes the picker" },
    { wait = "_G.picker_closed()", timeout = 10000, note = "closed" },
    { input = ":Pickers cwd smart<CR>", note = "smart again" },
    { wait = "_G.picker_open()", timeout = 15000, note = "open" },
    { input = "needlek2.*", note = "a query only a regex can answer" },
    {
      wait = [[_G.on_screen("needlek2_file.lua") and not _G.on_screen("haystack.txt")]],
      timeout = 20000,
      note = "fd finds the file by its name",
    },
    { input = "<Esc><Esc>", note = "<Esc> leaves the terminal, the second one closes the picker" },
    { wait = "_G.picker_closed()", timeout = 10000, note = "closed" },

    { input = ":FileGrep<CR>", note = ":FileGrep" },
    { wait = "_G.picker_open()", timeout = 15000, note = "open" },
    { input = "notes grep=quokka2", note = "a word of the path and grep= a word of the content" },
    {
      wait = [[_G.on_screen("plain.md") and not _G.on_screen("haystack.txt")]],
      timeout = 20000,
      note = "rg finds the file whose path holds the word and whose content the other, and no other file",
    },
    { input = "<Esc><Esc>", note = "<Esc> leaves the terminal, the second one closes the picker" },
  },
  manual = {
    "In the real editor on a large repository: typing in the smart picker stays fluent while rg runs",
  },
}
