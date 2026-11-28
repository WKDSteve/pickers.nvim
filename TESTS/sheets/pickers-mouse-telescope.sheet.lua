-- Feature pickers.mouse (TESTS/sheets/features.lua) on the real telescope, clicked with the mouse
-- (nvim_input_mouse): a right click on a result row, with the focus still in the prompt, opens the context menu with
-- the list entries; "Open here" closes the picker and opens the file. A right click on a line of the preview opens
-- the menu for that line; "Copy this line" copies it. telescope has no own double click of ours: its own single
-- click in the preview already opens the entry (pickers.preview_mouse_engines).
-- Needs telescope.nvim and plenary.nvim (.deps/, beside this repository, or the lazy.nvim directory of the real
-- editor); the workflow checks both out.
return {
  id = "pickers.mouse-telescope",
  feature = "pickers.mouse",
  title = "The mouse in a telescope picker: right click on a row or a preview line opens the context menu",
  task = "pickers.nvim/feature-sheet-maus-menue-auf-echtem-telescope-und-fzf-lua",
  engine = "rpc",
  sizes = { { rows = 30, cols = 120 } },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps("plenary.nvim", "telescope.nvim")]],
      reason = "telescope.nvim or plenary.nvim is not to be found",
    },
  },
  steps = {
    {
      lua = [[
        dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
        vim.o.mouse = "a"
        _G.mouse_project()
      ]],
      note = "a project with beta.txt and src/alpha.lua",
    },
    {
      -- the child of a sheet is slow under load: telescope's 250 ms for a preview can run out
      lua = [[require("telescope").setup({ defaults = { preview = { timeout = 5000 } } })]],
      note = "telescope set up",
    },
    {
      lua = [[assert(select(2, require("pickers.engines").load("telescope")) == "telescope")]],
      note = "the telescope engine loaded, which installs the mouse maps",
    },
    {
      lua = [[
        -- the one open telescope picker, found the way preview_mouse finds it
        _G.tp = function()
          local state = require("telescope.state")
          local buf = state.get_existing_prompt_bufnrs()[1]
          return buf and state.get_status(buf).picker or nil
        end
        -- the second line of the file the picker has selected (fd decides which file comes first)
        _G.line2 = function()
          local sel = _G.tp():get_selection()
          local path = sel.path or (_G.proj .. "/" .. sel.filename)
          return vim.fn.readfile(path)[2]
        end
      ]],
      note = "a project with beta.txt and src/alpha.lua, telescope set up",
    },
    {
      lua = [[vim.schedule(function() require("telescope.builtin").find_files({ cwd = _G.proj }) end)]],
      note = "the telescope file picker opens",
    },
    {
      wait = [[_G.on_screen("beta.txt") and _G.on_screen("alpha.lua") and _G.tp() ~= nil]],
      timeout = 15000,
      note = "the list shows both files",
    },
    {
      expect = [[_G.eq(vim.bo.filetype, "TelescopePrompt")]],
      note = "the focus is in the prompt",
    },

    -- right click on a line of the preview
    {
      wait = [[_G.screen_pos(_G.line2(), _G.tp().preview_win) ~= nil]],
      timeout = 10000,
      note = "the preview shows the lines of the selected file",
    },
    {
      lua = [[_G.copied_want = _G.line2(); _G.click("right", _G.copied_want, 1, _G.tp().preview_win)]],
      note = "right click on the second line of the preview",
    },
    {
      wait = [[_G.on_screen("Copy this line")]],
      timeout = 5000,
      note = "the context menu opens for the preview line",
    },
    { lua = [[_G.click("left", "Copy this line")]], note = "click Copy this line" },
    {
      wait = [[vim.fn.getreg('"') == _G.copied_want]],
      timeout = 5000,
      note = "the clicked line is copied",
    },
    { expect = [[_G.tp() ~= nil]], note = "and the picker is still open" },
    {
      expect = [[_G.eq(vim.bo.filetype, "TelescopePrompt") and vim.api.nvim_get_mode().mode == "i"]],
      note = "the focus is back in the prompt, in insert mode",
    },

    -- right click on a row, the focus still in the prompt
    {
      lua = [[_G.click("right", "beta.txt", 1, _G.tp().results_win)]],
      note = "right click on the row beta.txt in the results",
    },
    {
      wait = [[_G.on_screen("Open here") and _G.on_screen("Copy all entries")]],
      timeout = 5000,
      note = "the context menu opens, with the list entries",
    },
    { lua = [[_G.click("left", "Open here")]], note = "click Open here" },
    {
      wait = [[_G.tp() == nil and vim.api.nvim_buf_get_name(0):find("beta.txt", 1, true) ~= nil]],
      timeout = 10000,
      note = "the picker is closed and beta.txt is open",
    },
    {
      wait = [[vim.api.nvim_get_mode().mode == "n"]],
      timeout = 2000,
      note = "in normal mode: the prompt's insert mode does not follow into the file",
    },
  },
}
