-- Feature pickers.mouse (TESTS/sheets/features.lua) on the real fzf-lua with its builtin previewer, clicked with
-- the mouse (nvim_input_mouse). The list is fzf in a terminal, so only the preview is bound: a click into it, then a
-- right click on a line opens the context menu without the list entries; a double click asks and jumps, and fzf is
-- gone afterwards (no window, no running job). pickers.preview_mouse_engines names the limits.
-- Needs fzf-lua (.deps/, beside this repository, or the lazy.nvim directory of the real editor) and the programs fzf
-- and fd; the workflow provides them.
return {
  id = "pickers.mouse-fzf-lua",
  feature = "pickers.mouse",
  title = "The mouse in the fzf-lua preview: right click opens the context menu, a double click jumps",
  task = "pickers.nvim/feature-sheet-maus-menue-auf-echtem-telescope-und-fzf-lua",
  engine = "rpc",
  sizes = { { rows = 30, cols = 120 } },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps("fzf-lua")]],
      reason = "fzf-lua is not to be found",
    },
    { lua = [[vim.fn.executable("fzf") == 1]], reason = "the program fzf is not installed" },
  },
  steps = {
    {
      lua = [[
        dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
        vim.o.mouse = "a"
        _G.mouse_project()
        require("pickers.preview_mouse").install()
        -- fzf-lua's window object while a picker is open
        _G.fw = function()
          local ok, obj = pcall(function()
            return require("fzf-lua").win.__SELF()
          end)
          if ok and type(obj) == "table" and not obj.closing and obj.fzf_winid
            and vim.api.nvim_win_is_valid(obj.fzf_winid) then
            return obj
          end
        end
        -- fzf still running in a terminal of this editor
        _G.fzf_jobs = function()
          local n = 0
          for _, b in ipairs(vim.api.nvim_list_bufs()) do
            local job = vim.api.nvim_buf_is_valid(b) and vim.b[b].terminal_job_id
            if job and vim.fn.jobwait({ job }, 0)[1] == -1 then n = n + 1 end
          end
          return n
        end
        -- the second line of the file in the preview
        _G.line2 = function()
          local item = require("pickers.preview_mouse_engines").fzf_lua.item(_G.fw()._previewer)
          return item and item.file and vim.fn.readfile(item.file)[2] or nil
        end
      ]],
      note = "a project with beta.txt and src/alpha.lua, the mouse maps installed",
    },
    {
      lua = [[vim.schedule(function() require("fzf-lua").files({ cwd = _G.proj }) end)]],
      note = "the fzf-lua file picker opens",
    },
    {
      wait = [[_G.on_screen("beta.txt") and _G.on_screen("alpha.lua") and _G.fw() ~= nil]],
      timeout = 15000,
      note = "the list shows both files",
    },
    {
      wait = [[_G.line2() ~= nil and _G.screen_pos(_G.line2(), _G.fw().preview_winid) ~= nil]],
      timeout = 10000,
      note = "the preview shows the lines of the selected file",
    },

    -- right click in the preview
    {
      lua = [[_G.want = _G.line2(); _G.pwin = _G.fw().preview_winid; _G.click("left", _G.want, 1, _G.pwin)]],
      note = "click into the preview",
    },
    {
      wait = [[vim.api.nvim_get_current_win() == _G.pwin]],
      timeout = 5000,
      note = "the preview has the focus",
    },
    { lua = [[_G.click("right", _G.want, 1, _G.pwin)]], note = "right click on that line" },
    {
      wait = [[_G.on_screen("Copy this line") and _G.on_screen("Open here")]],
      timeout = 5000,
      note = "the context menu opens",
    },
    {
      expect = [[not _G.on_screen("Copy all entries")]],
      note = "without the list entries (fzf's list is a terminal)",
    },
    { lua = [[_G.click("left", "Copy this line")]], note = "click Copy this line" },
    {
      wait = [[vim.fn.getreg('"') == _G.want]],
      timeout = 5000,
      note = "the clicked line is copied",
    },
    { expect = [[_G.fw() ~= nil]], note = "and fzf-lua is still open" },

    -- double click in the preview
    {
      lua = [[
        if vim.api.nvim_get_current_win() ~= _G.pwin then _G.click("left", _G.want, 1, _G.pwin) end
      ]],
      note = "the preview has the focus again",
    },
    { wait = [[vim.api.nvim_get_current_win() == _G.pwin]], timeout = 5000 },
    { lua = [[_G.click("left", _G.want, 2, _G.pwin)]], note = "double click on the second line" },
    {
      -- the kit dialog of lib.nvim.ui.dialog (UI-63), "No" first and the default
      wait = [[_G.on_screen("Jump to ") and _G.on_screen("Yes") and _G.on_screen("No")]],
      timeout = 5000,
      note = "it asks whether to jump there, in the kit dialog",
    },
    { input = "y", note = "answer yes with its hotkey" },
    {
      wait = [[_G.fw() == nil and vim.api.nvim_win_get_cursor(0)[1] == 2
        and vim.fn.readfile(vim.api.nvim_buf_get_name(0))[2] == _G.want]],
      timeout = 10000,
      note = "fzf-lua is closed and the file is open on the clicked line",
    },
    { wait = [[_G.fzf_jobs() == 0]], timeout = 5000, note = "and no fzf is left running" },
  },
}
