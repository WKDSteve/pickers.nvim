-- Feature pickers.scopes (TESTS/sheets/features.lua) where resolving the scope starts a program, on the real snacks:
-- :FindInFolder lists the folders below the cwd with the real `fd --type d` (snacks has no folder source of its
-- own), the one picked becomes the root of a files picker that shows what is in it; :Pickers drives grep probes
-- the drives of the machine (PowerShell on Windows, df elsewhere) and opens the grep under the drives' prompt.
-- Nothing is searched on the drives: grep waits for a query, and the sheet closes it before typing one.
-- Needs snacks.nvim and fd (or fdfind); the workflow checks snacks out and installs fd.
local SETUP = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
  require("snacks").setup({ picker = { enabled = true } })
  require("pickers").setup({ engine = "snacks" })
  _G.proj = vim.fs.normalize(vim.fn.tempname())
  for _, rel in ipairs({ "qqzzk4/insidek4.txt", "otherk4/outsidek4.txt" }) do
    vim.fn.mkdir(vim.fs.dirname(_G.proj .. "/" .. rel), "p")
    vim.fn.writefile({ "x" }, _G.proj .. "/" .. rel)
  end
  vim.cmd.cd(_G.proj)
  ---A snacks picker is open and takes input (else: what was said instead, as the failure).
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
  id = "pickers.scopes-folder-drives-snacks",
  feature = "pickers.scopes",
  title = ":FindInFolder lists folders with the real fd, :Pickers drives grep probes the drives, on snacks",
  task = "pickers.nvim/performance-pruefung-luecken-schliessen-katalog-feature-shee",
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
    { lua = SETUP, note = "snacks, pickers.nvim on it, a project with two folders as the cwd" },

    -- folder
    { input = ":FindInFolder<CR>", note = ":FindInFolder" },
    {
      wait = [[_G.on_screen("Folder> ") and _G.on_screen("2/2")]],
      timeout = 15000,
      note = "fd lists both folders under the folder prompt (the rows are long temp paths)",
    },
    { expect = [[not _G.on_screen("table: 0x")]], note = "as paths, not as tables" },
    { wait = "_G.picker_open()", timeout = 5000, note = "it takes input" },
    { input = "qqzzk4", note = "type the folder's name" },
    { wait = [[_G.on_screen("1/2")]], timeout = 5000, note = "only that folder is left" },
    { input = "<CR>", note = "pick it" },
    {
      wait = [[_G.on_screen("insidek4.txt") and _G.on_screen("zzk4> ")]],
      timeout = 15000,
      note = "a files picker on the folder shows the file in it, under the folder's name",
    },
    {
      expect = [[not _G.on_screen("outsidek4.txt")]],
      note = "and not the file of the other folder",
    },
    { lua = "_G.close_pickers()" },
    { wait = [[not _G.on_screen("insidek4.txt")]], timeout = 5000, note = "closed" },

    -- drives
    { input = ":Pickers drives grep<CR>", note = ":Pickers drives grep" },
    {
      wait = [[_G.on_screen("All Drives> ")]],
      timeout = 20000,
      note = "the drives are probed and the grep opens under their prompt",
    },
    {
      lua = "_G.close_pickers()",
      note = "closed before anything is typed: no search on the drives",
    },
  },
}
