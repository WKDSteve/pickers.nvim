-- Feature pickers.items (TESTS/sheets/features.lua) on the real fzf-lua: the hand test
-- pickers.nvim/items-fzf-lua-marks-hand-test as a sheet. Without a UI fzf-lua draws no list (0/0), so the specs
-- pin what it does with marked rows on a stand-in only; the child of a sheet has a UI attached, and fzf runs in
-- its terminal for real. The list shows its three rows, `al` narrows it to two, <Tab> marks both, <M-s> acts on
-- the marked rows in the order of the list and the list comes back with `al` still typed; <CR> on marked rows
-- hands both over.
-- Needs fzf-lua (.deps/, beside this repository, or the lazy.nvim directory of the real editor) and the program
-- fzf; the workflow provides both.
return {
  id = "pickers.items-fzf-lua",
  feature = "pickers.items",
  title = "pickers.items on fzf-lua: the list shows, two rows are marked, a key acts on them, the query stays",
  task = "pickers.nvim/items-fzf-lua-marks-hand-test",
  engine = "rpc",
  sizes = { { rows = 24, cols = 100 } },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps("fzf-lua")]],
      reason = "fzf-lua is not to be found",
    },
    { lua = [[vim.fn.executable("fzf") == 1]], reason = "the program fzf is not installed" },
  },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.open_list("fzf")]],
      note = "pickers.items with three rows, marks on, a key <M-s> and a preview, on fzf-lua",
    },
    {
      wait = [[_G.on_screen("alpha one") and _G.on_screen("beta two") and _G.on_screen("alpha three")]],
      timeout = 15000,
      note = "the list shows its three rows",
    },
    { expect = [[_G.on_screen("Sheet> ")]], note = "under the title of the call" },
    {
      wait = [[_G.on_screen("preview of alpha one")]],
      timeout = 5000,
      note = "with the preview worked out for the first row",
    },
    { input = "al", note = "type al" },
    {
      wait = [[not _G.on_screen("beta two") and _G.on_screen("Sheet> al")]],
      timeout = 5000,
      note = "the list narrows to the two rows that match",
    },
    { input = "<Tab><Tab>", note = "mark both rows" },
    { wait = [[_G.on_screen("(2)")]], timeout = 5000, note = "fzf counts two marked rows" },
    { input = "<M-s>", note = "the key of the call" },
    {
      wait = [[_G.noted("key: alpha one, alpha three | query: al")]],
      timeout = 10000,
      note = "it got both marked rows in the order of the list, and what was typed",
    },
    {
      wait = [[_G.opened == 2 and _G.on_screen("Sheet> al") and _G.on_screen("alpha three")]],
      timeout = 15000,
      note = "the list is back, with al still typed",
    },
    { expect = [[not _G.on_screen("beta two")]], note = "and still narrowed" },
    {
      wait = [[_G.on_screen("(0)")]],
      timeout = 5000,
      note = "the marks are gone after the action",
    },

    -- <CR> on marked rows
    { input = "<Tab><Tab>", note = "mark both rows again" },
    { wait = [[_G.on_screen("(2)")]], timeout = 5000 },
    { input = "<CR>", note = "accept" },
    {
      wait = [[_G.noted("enter: alpha one, alpha three")]],
      timeout = 10000,
      note = "<CR> hands both marked rows over",
    },
    {
      wait = [[not _G.on_screen("alpha one") and vim.api.nvim_get_mode().mode == "n"]],
      timeout = 10000,
      note = "and the list is closed",
    },
    { expect = [[_G.eq(_G.opened, 2)]], note = "nothing opened it again" },
  },
  judge = {
    "After the key the list comes back looking as before (same border, same preview pane)",
  },
  manual = {
    "In the real editor with the real config of fzf-lua (its own keys, a profile): <Tab> marks, <M-s> acts on the marked rows, the query stays",
  },
}
