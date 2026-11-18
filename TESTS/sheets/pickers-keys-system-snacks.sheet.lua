-- Feature pickers.keys (TESTS/sheets/features.lua) on the real snacks: on a row of a files picker <M-o> hands the file
-- to the system's default application and <M-x> shows it in the file manager; the picker stays open for both.
-- The system programs are stand-ins (`fakes`): no application or window opens. lib.nvim takes the Linux dispatch on
-- every system here (`xdg-open <file>`, a file manager that selects the file): on Windows the real launcher is
-- `explorer.exe`, a name the `.cmd` stand-in of testing.nvim does not catch, so a real window would open. The real
-- launchers per system stay a hand check (`manual`).
-- Needs snacks.nvim and fd (or fdfind: snacks' files source); the workflow checks snacks out and installs fd.
local SETUP = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
  require("snacks").setup({ picker = { enabled = true } })
  require("pickers").setup({ engine = "snacks" })
  _G.proj = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(_G.proj, "p")
  vim.fn.writefile({ "x" }, _G.proj .. "/notek5.txt")
  vim.cmd.cd(_G.proj)
  for _, name in ipairs({ "is_windows", "is_wsl", "is_macos" }) do
    package.loaded["lib.nvim.cross.platform." .. name] = function()
      return false
    end
  end
  ---What the stand-in `program` was called with: one argv per call.
  _G.calls = function(program)
    return vim.tbl_map(function(c)
      return c.argv
    end, require("testing.fake_programs").read(vim.env.TESTING_FAKES, program))
  end
  ---`path` resolved (on macOS the temp folder `/var/...` is `/private/var/...`, where the cwd lives).
  _G.real = function(path)
    return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
  end
  ---The last argument of the first call of `program`.
  _G.last_arg = function(program)
    local argv = _G.calls(program)[1] or {}
    return argv[#argv]
  end
  _G.picker_open = function()
    if #Snacks.picker.get() > 0 and vim.fn.mode() == "i" then return true end
    if #_G.notes > 0 then error(table.concat(_G.notes, " | "), 0) end
    return false
  end]]

return {
  id = "pickers.keys-system-snacks",
  feature = "pickers.keys",
  title = "<M-o> opens a picked file with the system, <M-x> shows it in the file manager, on snacks",
  task = "pickers.nvim/performance-pruefung-luecken-schliessen-katalog-feature-shee",
  engine = "rpc",
  sizes = { { rows = 24, cols = 120 } },
  fakes = { "xdg-open", "nautilus" },
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
      lua = SETUP,
      note = "snacks, pickers.nvim on it, a project of one file, the Linux dispatch of lib.nvim",
    },
    { input = ":Pickers cwd files<CR>", note = ":Pickers cwd files" },
    { wait = [[_G.on_screen("notek5.txt")]], timeout = 15000, note = "the file is listed" },
    { wait = "_G.picker_open()", timeout = 5000, note = "the picker takes input" },

    { input = "<M-o>", note = "<M-o>: open with the system" },
    {
      wait = [[#_G.calls("xdg-open") == 1]],
      timeout = 10000,
      note = "the default application is asked once",
    },
    {
      expect = [[_G.eq(_G.real(_G.calls("xdg-open")[1][1]), _G.real(_G.proj .. "/notek5.txt"))]],
      note = "with the file of the row",
    },

    { input = "<M-x>", note = "<M-x>: show in the file manager" },
    {
      wait = [[#_G.calls("nautilus") == 1]],
      timeout = 10000,
      note = "the file manager is asked once",
    },
    {
      expect = [[_G.eq(_G.real(_G.last_arg("nautilus")), _G.real(_G.proj .. "/notek5.txt"))]],
      note = "to select the file of the row",
    },
    { expect = [[#Snacks.picker.get() == 1]], note = "the picker is still open" },
    {
      lua = [[for _, p in ipairs(Snacks.picker.get()) do p:close() end; vim.cmd.stopinsert()]],
    },
  },
  manual = {
    "On each system with the real launchers: <M-o> opens the file in its application, <M-x> opens Explorer/Finder/the file manager with the file selected",
  },
}
