-- Feature pickers.items (TESTS/sheets/features.lua) on the real snacks picker: the list shows its three rows,
-- `al` narrows it to two, <Tab> marks both, <M-s> acts on the marked rows in the order of the list and the list
-- comes back with `al` still typed; <CR> on marked rows hands both over.
-- Needs snacks.nvim (.deps/, beside this repository, or the lazy.nvim directory of the real editor); the
-- workflow checks it out.
return {
  id = "pickers.items-snacks",
  feature = "pickers.items",
  title = "pickers.items on snacks: the list shows, two rows are marked, a key acts on them, the query stays",
  task = "images.nvim/own-tree-feature-sheets-images-media-pickers",
  engine = "rpc",
  sizes = { { rows = 24, cols = 100 } },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps("snacks.nvim")]],
      reason = "snacks.nvim is not to be found",
    },
  },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.open_list("snacks")]],
      note = "pickers.items with three rows, marks on, a key <M-s> and a preview, on the snacks picker",
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
      wait = [[not _G.on_screen("beta two") and _G.on_screen("2/3")]],
      timeout = 5000,
      note = "the list narrows to the two rows that match",
    },
    { input = "<Tab><Tab>", note = "mark both rows" },
    { wait = [[_G.on_screen("(2)")]], timeout = 5000, note = "snacks counts two marked rows" },
    { input = "<M-s>", note = "the key of the call" },
    {
      wait = [[_G.noted("key: alpha one, alpha three | query: al")]],
      timeout = 10000,
      note = "it got both marked rows in the order of the list, and what was typed",
    },
    {
      wait = [[_G.opened == 2 and _G.on_screen("alpha three") and _G.on_screen("2/3")]],
      timeout = 15000,
      note = "the list is back, narrowed as before",
    },
    {
      expect = [[_G.eq(vim.api.nvim_get_current_line(), "al") and not _G.on_screen("beta two")]],
      note = "with al still typed",
    },
    { expect = [[not _G.on_screen("(2)")]], note = "the marks are gone after the action" },

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
      wait = [[not _G.on_screen("alpha one")]],
      timeout = 10000,
      note = "and the list is closed",
    },
    { expect = [[_G.eq(_G.opened, 2)]], note = "nothing opened it again" },
  },
  manual = {
    "In the real editor with the real config of snacks: the list, the marks and the preview look as in its other pickers",
  },
}
