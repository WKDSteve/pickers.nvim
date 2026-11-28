-- Feature pickers.mouse (TESTS/sheets/features.lua): the menu entry "Blame this line (gitsuite)" on the real snacks
-- picker and the real gitsuite.nvim, in a real git repository. A right click on a preview line blames that line:
-- the notification names file:line, the short sha, the author and the subject of the commit; for a file that is
-- not checked in it names git's error instead, and nothing throws. The picker stays open.
-- Needs snacks.nvim and gitsuite.nvim (.deps/, beside this repository, or the lazy.nvim directory of the real
-- editor) and git on PATH; the workflow checks them out.
return {
  id = "pickers.mouse-blame-gitsuite",
  feature = "pickers.mouse",
  title = "The mouse in a snacks picker: Blame this line asks the real gitsuite.nvim for the clicked preview line",
  task = "pickers.nvim/feature-sheet-blame-this-line-auf-echtem-gitsuite-in-einem",
  engine = "rpc",
  sizes = { { rows = 30, cols = 120 } },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps("snacks.nvim", "gitsuite.nvim")]],
      reason = "snacks.nvim or gitsuite.nvim is not to be found",
    },
    { lua = [[vim.fn.executable("git") == 1]], reason = "git is not on PATH" },
  },
  steps = {
    {
      lua = [[
        dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
        vim.o.mouse = "a"
        _G.blame_project()
        require("snacks").setup({ picker = { enabled = true } })
        require("pickers.preview_mouse").install()
        Snacks.picker.files({ layout = { preset = "default" } })
      ]],
      note = "a git repository with one commit by Sheet Author, gamma.txt not checked in, the snacks file picker open",
    },
    {
      wait = [[_G.on_screen("beta.txt") and _G.on_screen("gamma.txt")]],
      timeout = 15000,
      note = "the list shows the files",
    },

    -- a checked-in line
    { input = "beta", note = "narrow the list to beta.txt" },
    {
      wait = [[_G.on_screen("beta line two")]],
      timeout = 5000,
      note = "the preview shows the lines of beta.txt",
    },
    {
      lua = [[_G.click("right", "beta line two", 1, Snacks.picker.get()[1].preview.win.win)]],
      note = "right click on the second line of the preview",
    },
    {
      wait = [[_G.on_screen("Blame this line (gitsuite)")]],
      timeout = 5000,
      note = "the context menu has the blame entry",
    },
    { lua = [[_G.click("left", "Blame this line (gitsuite)")]], note = "click Blame this line" },
    {
      wait = [[_G.note_with("beta.txt:2") ~= nil]],
      timeout = 10000,
      note = "a notification for beta.txt line 2 arrives",
    },
    {
      expect = [[(function()
        local n = _G.note_with("beta.txt:2")
        assert(n:find(_G.sha:sub(1, 8), 1, true), "no short sha in: " .. n)
        assert(n:find("Sheet Author", 1, true), "no author in: " .. n)
        assert(n:find("add the files", 1, true), "no subject in: " .. n)
        return true
      end)()]],
      note = "it names the short sha, the author and the subject of the commit",
    },
    { expect = [[#Snacks.picker.get() == 1]], note = "the picker is still open" },

    -- a file that is not checked in
    {
      lua = [[
        for _, p in ipairs(Snacks.picker.get()) do p:close() end
        Snacks.picker.files({ layout = { preset = "default" } })
      ]],
      note = "the picker open again",
    },
    { wait = [[_G.on_screen("gamma.txt")]], timeout = 15000 },
    { input = "gamma", note = "narrow the list to gamma.txt" },
    {
      wait = [[_G.on_screen("gamma line two")]],
      timeout = 5000,
      note = "the preview shows the lines of gamma.txt",
    },
    {
      lua = [[_G.click("right", "gamma line two", 1, Snacks.picker.get()[1].preview.win.win)]],
      note = "right click on a line of the preview",
    },
    { wait = [[_G.on_screen("Blame this line (gitsuite)")]], timeout = 5000 },
    { lua = [[_G.click("left", "Blame this line (gitsuite)")]], note = "click Blame this line" },
    {
      wait = [[_G.note_with("blame: ") ~= nil]],
      timeout = 10000,
      note = "a blame notification arrives",
    },
    {
      expect = [[(function()
        local n = _G.note_with("blame: ")
        assert(not n:find("Sheet Author", 1, true), "a blame line for a file not checked in: " .. n)
        assert(_G.note_with("gamma.txt:") == nil, "a blame line for a file not checked in: " .. n)
        -- git's own reason (lib.nvim@f011fc7), e.g. "fatal: no such path 'gamma.txt' in HEAD"
        assert(n:find("gamma.txt", 1, true), "the error does not name the file: " .. n)
        return true
      end)()]],
      note = "it is git's error about gamma.txt, not a blame line",
    },
    { expect = [[#Snacks.picker.get() == 1]], note = "nothing threw, the picker is still open" },
  },
}
