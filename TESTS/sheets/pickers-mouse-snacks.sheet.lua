-- Feature pickers.mouse (TESTS/sheets/features.lua) on the real snacks picker and the real filetree.nvim, clicked
-- with the mouse (nvim_input_mouse): a right click on a result row opens the context menu while the focus is still
-- in the input field, "Reveal in filetree" closes the picker and shows the file in the tree; a double click in the
-- preview asks and jumps to the clicked line; without filetree.nvim the menu has no reveal entry.
-- Needs snacks.nvim, ui.nvim and filetree.nvim (.deps/, beside this repository, or the lazy.nvim directory of the
-- real editor); the workflow checks them out.
return {
  id = "pickers.mouse-snacks",
  feature = "pickers.mouse",
  title = "The mouse in a snacks picker: right click menu with Reveal in filetree, double click in the preview jumps",
  task = "pickers.nvim/feature-sheet-rechtsklick-menue-der-snacks-vorschau-samt",
  engine = "rpc",
  -- the double click asks with confirm(); answered by the sheet, not "cancelled" at once
  prompts = "real",
  sizes = { { rows = 30, cols = 120 } },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps("snacks.nvim", "ui.nvim", "filetree.nvim")]],
      reason = "snacks.nvim, ui.nvim or filetree.nvim is not to be found",
    },
  },
  steps = {
    {
      lua = [[
        dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
        vim.o.mouse = "a"
        _G.mouse_project()
        require("snacks").setup({ picker = { enabled = true } })
        -- `auto` would pick netrw, which -u NONE does not load; native is filetree's own tree
        require("filetree").setup({ adapter = "native" })
        require("pickers.preview_mouse").install()
        Snacks.picker.files({ layout = { preset = "default" } })
      ]],
      note = "a project with beta.txt and src/alpha.lua, filetree.nvim set up, the snacks file picker open",
    },
    {
      wait = [[_G.on_screen("beta.txt") and _G.on_screen("alpha.lua")]],
      timeout = 15000,
      note = "the list shows both files",
    },
    {
      expect = [[_G.eq(vim.bo.filetype, "snacks_picker_input")]],
      note = "the focus is in the input field",
    },

    -- right click on a row, the focus still in the input field
    {
      lua = [[_G.click("right", "beta.txt", 1, Snacks.picker.get()[1].list.win.win)]],
      note = "right click on the row beta.txt in the list",
    },
    {
      wait = [[_G.on_screen("Reveal in filetree") and _G.on_screen("Copy path")]],
      timeout = 5000,
      note = "the context menu opens, with Reveal in filetree",
    },
    { lua = [[_G.click("left", "Reveal in filetree")]], note = "click Reveal in filetree" },
    {
      wait = [[#Snacks.picker.get() == 0 and (_G.tree_cursor_line() or ""):find("beta.txt", 1, true) ~= nil]],
      timeout = 10000,
      note = "the picker is closed and the tree shows the file, its cursor on beta.txt",
    },

    -- double click in the preview
    {
      lua = [[Snacks.picker.files({ layout = { preset = "default" } })]],
      note = "open the picker again",
    },
    { wait = [[_G.on_screen("alpha.lua")]], timeout = 15000 },
    { input = "beta", note = "narrow the list to beta.txt" },
    {
      wait = [[_G.on_screen("beta line two")]],
      timeout = 5000,
      note = "the preview shows the lines of beta.txt",
    },
    {
      lua = [[_G.click("left", "beta line two", 2, Snacks.picker.get()[1].preview.win.win)]],
      note = "double click on the second line of the preview",
    },
    { prompt = "confirm", timeout = 5000, note = "it asks whether to jump there" },
    { input = "Y", note = "answer yes" },
    {
      wait = [[vim.api.nvim_buf_get_name(0):find("beta.txt", 1, true) ~= nil and vim.api.nvim_win_get_cursor(0)[1] == 2]],
      timeout = 10000,
      note = "the file is open in a buffer of its own, the cursor on the clicked line",
    },
    { expect = [[#Snacks.picker.get() == 0]], note = "and the picker is closed" },

    -- without filetree.nvim the menu has no reveal entry
    {
      lua = [[
        package.loaded["filetree"] = nil
        package.preload["filetree"] = function() error("filetree.nvim is not installed") end
        Snacks.picker.files({ layout = { preset = "default" } })
      ]],
      note = "filetree.nvim gone, the picker open again",
    },
    { wait = [[_G.on_screen("alpha.lua")]], timeout = 15000 },
    {
      lua = [[_G.click("right", "alpha.lua", 1, Snacks.picker.get()[1].list.win.win)]],
      note = "right click on a row",
    },
    { wait = [[_G.on_screen("Copy path")]], timeout = 5000, note = "the menu opens" },
    { expect = [[not _G.on_screen("Reveal in filetree")]], note = "without the reveal entry" },
  },
  manual = {
    "In the real editor with nvzone/menu installed: the same menu opens as a nvzone menu and Reveal in filetree works",
  },
}
