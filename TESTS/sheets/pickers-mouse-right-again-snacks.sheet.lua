-- Feature pickers.mouse (TESTS/sheets/features.lua): right click, <Esc>, right click again on the same row of the
-- real snacks picker opens the context menu again. Neovim counts the second click as <2-RightMouse> when it lands
-- on the same cell within 'mousetime'; with only <RightMouse> mapped, Neovim took it itself (with 'mousemodel'
-- "extend" it extended a selection, with the default "popup_setpos" it opened its own blocking PopUp menu).
-- 'mousetime' is set long here, so the second click is always a double click, however slow the machine.
-- Needs snacks.nvim (.deps/, beside this repository, or the lazy.nvim directory of the real editor).
return {
  id = "pickers.mouse-right-again-snacks",
  feature = "pickers.mouse",
  title = "The mouse in a snacks picker: a quick second right click (a double click) opens the menu again",
  task = "pickers.nvim/rechtsklick-nach-einem-mit-esc-geschlossenen-kit-menue-geht",
  engine = "rpc",
  sizes = { { rows = 30, cols = 120 } },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps("snacks.nvim")]],
      reason = "snacks.nvim is not to be found",
    },
  },
  steps = {
    {
      lua = [[
        dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
        vim.o.mouse = "a"
        -- what lib.nvim.contextmenu.setup() sets: a click no map takes extends a selection instead of opening
        -- Neovim's own PopUp menu, which would block the child editor
        vim.o.mousemodel = "extend"
        vim.o.mousetime = 10000
        _G.mouse_project()
        require("snacks").setup({ picker = { enabled = true } })
        require("pickers.preview_mouse").install()
        Snacks.picker.files({ layout = { preset = "default", preview = false } })
      ]],
      note = "a project with beta.txt, the snacks file picker open, 'mousetime' 10 s",
    },
    { wait = [[_G.on_screen("beta.txt")]], timeout = 15000, note = "the list shows beta.txt" },
    {
      lua = [[_G.click("right", "beta.txt", 1, Snacks.picker.get()[1].list.win.win)]],
      note = "right click on the row beta.txt",
    },
    { wait = [[_G.on_screen("Open here")]], timeout = 5000, note = "the context menu opens" },
    { input = "<Esc>", note = "close it with <Esc>" },
    { wait = [[not _G.on_screen("Open here")]], timeout = 5000, note = "the menu is gone" },
    {
      lua = [[_G.click("right", "beta.txt", 1, Snacks.picker.get()[1].list.win.win)]],
      note = "right click on the same row again (Neovim: <2-RightMouse>)",
    },
    { wait = [[_G.on_screen("Open here")]], timeout = 5000, note = "the context menu opens again" },
    {
      expect = [[vim.api.nvim_get_mode().mode == "n" and vim.bo.filetype ~= "snacks_picker_input"]],
      note = "the focus is in the menu, no selection was started in the input field",
    },
    { input = "<Esc>", note = "close it" },
    { wait = [[not _G.on_screen("Open here")]], timeout = 5000, note = "the menu is gone" },
  },
}
