-- Feature pickers.actions (TESTS/sheets/features.lua) with the real rg and fd on the real snacks: in a project folder
-- the smart action is typed as a person does (:Pickers cwd smart), a word finds the file by its name (the listing of
-- the folder) and by its content (rg); a query only a regex can answer (`.*`) runs fd itself for that keystroke.
-- :FileGrep then finds the file by a word of its path and `grep=` a word of its content (rg).
-- What it measures for `testing perf`: the per-keystroke starts of rg and fd (pickers.smart.search, pickers.filegrep).
-- Needs snacks.nvim, rg and fd (or fdfind); the workflow checks snacks out and installs both tools.
local SETUP = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
  -- The smart picker opens snacks with `source = "smart"` and so inherits snacks' own smart source, frecency
  -- included: on Windows without sqlite3.dll in the (fresh) cache that downloads it from the network, and without
  -- the image integration its preview is the one of snacks' several sources, which raises on these rows. Both
  -- off here; task pickers.nvim/snacks-smart-erbt-frecency-und-vorschau-der-snacks-quelle-sm.
  require("snacks").setup({
    picker = {
      enabled = true,
      sources = { smart = { matcher = { frecency = false }, preview = "file" } },
    },
  })
  require("pickers").setup({ engine = "snacks" })
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
  ---The picker is open and takes input (else: what was said instead, as the failure).
  _G.picker_open = function()
    if #Snacks.picker.get() > 0 and vim.fn.mode() == "i" then return true end
    if #_G.notes > 0 then error(table.concat(_G.notes, " | "), 0) end
    return false
  end
  _G.close_pickers = function()
    for _, p in ipairs(Snacks.picker.get()) do p:close() end
    vim.cmd.stopinsert()
    return true
  end]]

return {
  id = "pickers.actions-smart-snacks",
  feature = "pickers.actions",
  title = "The smart action and :FileGrep find files by name and content with the real rg and fd on snacks",
  task = "pickers.nvim/performance-pruefung-luecken-schliessen-katalog-feature-shee",
  engine = "rpc",
  sizes = { { rows = 24, cols = 120 } },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps("snacks.nvim")]],
      reason = "snacks.nvim is not to be found",
    },
    { lua = [[vim.fn.executable("rg") == 1]], reason = "rg is not installed" },
    {
      lua = [[vim.fn.executable("fd") == 1 or vim.fn.executable("fdfind") == 1]],
      reason = "fd is not installed",
    },
  },
  steps = {
    { lua = SETUP, note = "snacks, pickers.nvim on it, a project of three files as the cwd" },

    -- smart: a word, then a regex
    { input = ":Pickers cwd smart<CR>", note = ":Pickers cwd smart" },
    { wait = "_G.picker_open()", timeout = 15000, note = "the snacks picker is open" },
    { input = "quokka2", note = "a word of a file's content" },
    {
      wait = [[_G.on_screen("plain.md") and not _G.on_screen("haystack.txt")]],
      timeout = 20000,
      note = "rg finds the file that holds it, and no other",
    },
    { lua = "_G.close_pickers()" },
    { wait = [[not _G.on_screen("plain.md")]], timeout = 5000, note = "closed" },
    { input = ":Pickers cwd smart<CR>", note = "smart again" },
    { wait = "_G.picker_open()", timeout = 15000, note = "open" },
    { input = "needlek2.*", note = "a query only a regex can answer" },
    {
      wait = [[_G.on_screen("needlek2_file.lua") and not _G.on_screen("haystack.txt")]],
      timeout = 20000,
      note = "fd finds the file by its name",
    },
    { lua = "_G.close_pickers()" },
    { wait = [[not _G.on_screen("needlek2_file.lua")]], timeout = 5000, note = "closed" },

    -- :FileGrep: a word of the content and a word of the path
    { input = ":FileGrep<CR>", note = ":FileGrep" },
    { wait = "_G.picker_open()", timeout = 15000, note = "open" },
    { input = "notes grep=quokka2", note = "a word of the path and grep= a word of the content" },
    {
      wait = [[_G.on_screen("plain.md") and not _G.on_screen("haystack.txt")]],
      timeout = 20000,
      note = "rg finds the file whose path holds the word and whose content the other, and no other file",
    },
    { lua = "_G.close_pickers()" },
  },
  manual = {
    "In the real editor on a large repository: typing in the smart picker stays fluent while rg runs per keystroke",
  },
}
