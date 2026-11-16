-- :FindOnSystem with the real fd on the real snacks (the hand check of pickers-bindings-commands, where fd is a
-- stand-in and the engine a recorder): the search typed names a pattern and a folder, fd lists what matches below
-- it, and the snacks picker shows those files and no other.
-- Needs snacks.nvim and fd (or fdfind). Without either it is a reported skip; it names no feature, so it stays a
-- skip on CI, whose workflow installs no fd.
return {
  id = "pickers.system-fd-snacks",
  title = ":FindOnSystem runs the real fd and the snacks picker shows what it found",
  task = "pickers.nvim/testblatt-bindings-checkliste",
  engine = "rpc",
  sizes = { { rows = 24, cols = 120 } },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps("snacks.nvim")]],
      reason = "snacks.nvim is not to be found",
    },
    {
      lua = [[vim.fn.executable("fd") == 1 or vim.fn.executable("fdfind") == 1]],
      reason = "fd is not installed",
    },
  },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
        -- ui.kit (ui.nvim) is not on the runtimepath: its input is the one place a person types the search.
        package.loaded["ui.kit"] = { input = function(opts) _G.kit_input = opts end }
        require("snacks").setup({ picker = { enabled = true } })
        require("pickers").setup({ engine = "snacks" })
        _G.sys = vim.fs.normalize(vim.fn.tempname())
        for _, rel in ipairs({ "deep/er/needlek1-one.txt", "needlek1-two.md", "other/haystack.txt" }) do
          vim.fn.mkdir(vim.fs.dirname(_G.sys .. "/" .. rel), "p")
          vim.fn.writefile({ "x" }, _G.sys .. "/" .. rel)
        end]],
      note = "snacks, pickers.nvim on it, three files in a temp folder",
    },
    { keys = ":FindOnSystem<CR>", note = ":FindOnSystem" },
    { wait = "_G.kit_input ~= nil", note = "it asks for the search" },
    {
      lua = [[_G.kit_input.on_submit("needlek1 " .. _G.sys)]],
      note = "a pattern and the folder",
    },
    {
      wait = [[_G.on_screen("needlek1-one.txt") and _G.on_screen("needlek1-two.md")]],
      timeout = 20000,
      note = "the snacks picker lists both files fd found, the nested one too",
    },
    { expect = [[_G.on_screen("System> ")]], note = "under the prompt of the system scope" },
    {
      expect = [[not _G.on_screen("haystack.txt")]],
      note = "and not the file that does not match",
    },
    {
      lua = [[for _, p in ipairs(Snacks.picker.get()) do p:close() end; vim.cmd.stopinsert()]],
    },
  },
}
