-- Feature pickers.mouse (TESTS/sheets/features.lua): the menu entry "Preview in mdview" on the real snacks picker
-- and the real mdview.nvim. A right click on a Markdown row offers it; clicking it closes the picker and runs
-- mdview's own `open()` in a buffer of exactly that file, loaded unlisted. Without a running mdview session (none
-- in a sheet) mdview says so itself; the browser is the one thing not checked here. A row that is not Markdown has
-- no such entry.
-- Needs snacks.nvim and mdview.nvim (.deps/, beside this repository, or the lazy.nvim directory of the real
-- editor); the workflow checks them out.
-- The menu is closed with <Esc> only at the very end: a right click after an <Esc>-closed kit menu is sometimes
-- lost (pickers.nvim/rechtsklick-nach-einem-mit-esc-geschlossenen-kit-menue-geht).
return {
  id = "pickers.mouse-mdview",
  feature = "pickers.mouse",
  title = "The mouse in a snacks picker: Preview in mdview runs the real mdview.nvim in the clicked Markdown file",
  task = "pickers.nvim/feature-sheet-picker-menue-mit-echtem-nvzone-menu-und",
  engine = "rpc",
  sizes = { { rows = 30, cols = 120 } },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps("snacks.nvim", "mdview.nvim")]],
      reason = "snacks.nvim or mdview.nvim is not to be found",
    },
  },
  steps = {
    {
      lua = [[
        dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
        vim.o.mouse = "a"
        -- what lib.nvim.contextmenu.setup() sets in a real config: a right click no map takes does not open
        -- Neovim's own PopUp menu, which would block the child editor
        vim.o.mousemodel = "extend"
        _G.mouse_project()
        vim.fn.writefile({ "# notes", "notes line two" }, _G.proj .. "/notes.md")
        -- mdview's own open() runs; only what it is called on is written down
        local mdview = require("mdview")
        local open = mdview.open
        _G.md_calls = {}
        mdview.open = function(...)
          local buf = vim.api.nvim_get_current_buf()
          _G.md_calls[#_G.md_calls + 1] = {
            name = vim.fs.normalize(vim.api.nvim_buf_get_name(buf)),
            listed = vim.bo[buf].buflisted,
          }
          return open(...)
        end
        require("snacks").setup({ picker = { enabled = true } })
        require("pickers.preview_mouse").install()
        Snacks.picker.files({ layout = { preset = "default" } })
      ]],
      note = "a project with notes.md and beta.txt, mdview.open wrapped, the snacks file picker open",
    },
    {
      wait = [[_G.on_screen("notes.md") and _G.on_screen("beta.txt")]],
      timeout = 15000,
      note = "the list shows the files",
    },

    -- Markdown: the entry runs mdview in that file
    { input = "notes", note = "narrow the list to notes.md" },
    {
      wait = [[_G.on_screen("notes line two")]],
      timeout = 5000,
      note = "the preview shows notes.md",
    },
    {
      lua = [[_G.click("right", "notes.md", 1, Snacks.picker.get()[1].list.win.win)]],
      note = "right click on the row notes.md",
    },
    {
      wait = [[_G.on_screen("Preview in mdview")]],
      timeout = 5000,
      note = "the context menu offers Preview in mdview",
    },
    { lua = [[_G.click("left", "Preview in mdview")]], note = "click Preview in mdview" },
    { wait = [[#_G.md_calls == 1]], timeout = 10000, note = "mdview.open is called once" },
    {
      expect = [[(function()
        local call = _G.md_calls[1]
        -- the real path on both sides: on macOS the temp directory /var/... is /private/var/...
        local function real(p)
          return vim.fs.normalize(vim.uv.fs_realpath(p) or p):lower()
        end
        local want = _G.proj .. "/notes.md"
        assert(real(call.name) == real(want), ("mdview ran in %s, not in %s"):format(call.name, want))
        assert(call.listed == false, "the file was not open, its buffer should stay unlisted")
        return true
      end)()]],
      note = "it runs in a buffer of notes.md, unlisted",
    },
    {
      wait = [[_G.note_with("no mdview session running") ~= nil]],
      timeout = 5000,
      note = "without a session mdview says so itself",
    },
    {
      expect = [[#Snacks.picker.get() == 0 and _G.note_with("could not preview in mdview") == nil]],
      note = "the picker is closed and nothing threw",
    },

    -- not Markdown: no entry
    {
      lua = [[Snacks.picker.files({ layout = { preset = "default" } })]],
      note = "the picker open again",
    },
    { wait = [[_G.on_screen("beta.txt")]], timeout = 15000 },
    { input = "beta", note = "narrow the list to beta.txt" },
    {
      wait = [[_G.on_screen("beta line two")]],
      timeout = 5000,
      note = "the preview shows beta.txt",
    },
    {
      lua = [[_G.click("right", "beta.txt", 1, Snacks.picker.get()[1].list.win.win)]],
      note = "right click on the row beta.txt",
    },
    { wait = [[_G.on_screen("Open here")]], timeout = 5000, note = "the context menu is open" },
    {
      expect = [[not _G.on_screen("Preview in mdview")]],
      note = "a .txt row has no Preview in mdview",
    },
    { input = "<Esc>", note = "close the menu" },
    { wait = [[not _G.on_screen("Open here")]], timeout = 5000, note = "the menu is gone" },
    { expect = [[#_G.md_calls == 1]], note = "mdview was not called again" },
  },
}
