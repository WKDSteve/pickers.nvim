-- Feature pickers.builtins (TESTS/sheets/features.lua) on the real snacks: the bindings of pickers.nvim that hand
-- over to the engine's own pickers (BINDINGS-RUNTIME-CHECKLIST.md: <leader>., :Pickers builtin, :PickersResume),
-- which a recorder cannot stand in for. :Pickers builtin keymaps opens snacks' keymaps picker, a name that is no
-- builtin offers the closest ones (without a name the command only says it needs one); a files picker with
-- `README` typed is closed and :PickersResume brings it back with the query; <leader>. opens snacks' tree explorer
-- on the cwd.
-- Needs snacks.nvim (.deps/, beside this repository, or the lazy.nvim directory of the real editor); the workflow
-- checks it out.
return {
  id = "pickers.bindings-snacks",
  feature = "pickers.builtins",
  title = "<leader>., :Pickers builtin and :PickersResume open the engine's own pickers on snacks",
  task = "pickers.nvim/testblatt-bindings-checkliste",
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
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
        require("snacks").setup({ picker = { enabled = true }, explorer = { enabled = true } })
        vim.g.mapleader = " "
        require("pickers").setup({ engine = "snacks" })
        _G.close_pickers = function()
          for _, p in ipairs(Snacks.picker.get()) do p:close() end
          return true
        end]],
      note = "snacks with its picker and explorer, pickers.nvim on it",
    },

    -- :Pickers builtin
    { keys = ":Pickers builtin keymaps<CR>", note = ":Pickers builtin keymaps" },
    { input = "navigate", note = "type navigate" },
    {
      wait = [[_G.on_screen("Dir: navigate")]],
      timeout = 15000,
      note = "snacks' own keymaps picker lists the keys of pickers.nvim",
    },
    { lua = "_G.close_pickers(); vim.cmd.stopinsert()" },
    { wait = [[not _G.on_screen("Dir: navigate")]], timeout = 5000, note = "closed" },
    { keys = ":Pickers builtin keymap<CR>", note = "a name that is not a builtin" },
    {
      wait = [[_G.on_screen("Unknown builtin 'keymap'") and _G.on_screen("keymaps")]],
      timeout = 15000,
      note = "it offers the builtins that come closest",
    },
    { lua = "_G.close_pickers(); vim.cmd.stopinsert()" },
    { wait = [[not _G.on_screen("Unknown builtin")]], timeout = 5000, note = "closed" },

    -- :PickersResume
    { keys = ":Pickers cwd files<CR>", note = "files in the cwd" },
    { wait = [[_G.on_screen("CWD> ")]], timeout = 15000 },
    { input = "README", note = "type README" },
    { wait = [[_G.on_screen("README.md")]], timeout = 10000, note = "the readme is found" },
    { lua = "_G.close_pickers(); vim.cmd.stopinsert()" },
    { wait = [[not _G.on_screen("README.md")]], timeout = 5000, note = "closed" },
    { keys = ":PickersResume<CR>", note = ":PickersResume" },
    {
      wait = [[_G.on_screen("README.md") and _G.on_screen("README")]],
      timeout = 15000,
      note = "the files picker is back with README still typed",
    },
    { lua = "_G.close_pickers(); vim.cmd.stopinsert()" },
    { wait = [[not _G.on_screen("README.md")]], timeout = 5000, note = "closed" },

    -- <leader>.
    { keys = " .", note = "<leader>.: the explorer" },
    {
      wait = [[_G.on_screen("TESTS") and _G.on_screen("lua") and _G.on_screen("README.md")]],
      timeout = 15000,
      note = "snacks' explorer shows the cwd",
    },
    {
      expect = [[#vim.tbl_filter(function(p) return p.opts.source == "explorer" end, Snacks.picker.get()) == 1]],
      note = "as its explorer source",
    },
    { lua = "_G.close_pickers(); vim.cmd.stopinsert()" },
  },
  judge = { "the explorer reads as a file tree of the cwd" },
}
