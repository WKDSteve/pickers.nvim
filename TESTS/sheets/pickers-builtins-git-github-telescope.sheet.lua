-- Feature pickers.builtins (TESTS/sheets/features.lua) where pickers.nvim runs the program itself, on the real
-- telescope: :Pickers builtin git_status_filtered asks the real git of a project with one changed and one new file
-- and lists both under the filter rows; :Pickers builtin gh_issue runs `gh issue list --json` and lists the issues.
-- gh is a stand-in on the PATH that prints two issues (a real gh needs an account and the network); git is real.
-- (On snacks the gh_* builtins are snacks' own sources: pickers.sources.github is the telescope/fzf-lua half.)
-- Needs telescope.nvim, plenary.nvim and git; the workflow checks both plugins out.
local SETUP = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua")
  require("telescope").setup({})
  require("pickers").setup({ engine = "telescope" })
  _G.proj = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(_G.proj, "p")
  local function git(...)
    local out = vim.fn.system(vim.list_extend({ "git", "-C", _G.proj }, { ... }))
    assert(vim.v.shell_error == 0, out)
  end
  vim.fn.writefile({ "one" }, _G.proj .. "/changedk3.txt")
  git("init", "-q")
  git("add", "changedk3.txt")
  git("-c", "user.name=sheet", "-c", "user.email=sheet@example.test", "-c", "commit.gpgsign=false",
    "commit", "-q", "-m", "first")
  vim.fn.writefile({ "two" }, _G.proj .. "/changedk3.txt")
  vim.fn.writefile({ "new" }, _G.proj .. "/untrackedk3.txt")
  vim.cmd.cd(_G.proj)
  _G.close_telescope = function()
    vim.cmd.stopinsert()
    require("telescope.actions").close(vim.api.nvim_get_current_buf())
    return true
  end]]

local GH = [[local issues = {
    { number = 7, title = "Fix the quokka3 layout", state = "OPEN", url = "https://example.test/i/7",
      author = { login = "someone" }, updatedAt = "2026-11-18T10:00:00Z" },
    { number = 5, title = "Second quokka3 issue", state = "OPEN", url = "https://example.test/i/5",
      author = { login = "other" }, updatedAt = "2026-11-17T10:00:00Z" },
  }
  _G.fake = require("testing.fake_programs").new({ gh = { stdout = vim.json.encode(issues) } })
  vim.env.PATH = _G.fake:path()
  -- picking an issue would open the browser: recorded instead
  vim.ui.open = function(url) _G.opened_url = url end]]

return {
  id = "pickers.builtins-git-github-telescope",
  feature = "pickers.builtins",
  title = "git_status_filtered asks the real git, gh_issue runs gh, both list on telescope",
  task = "pickers.nvim/performance-pruefung-luecken-schliessen-katalog-feature-shee",
  engine = "rpc",
  sizes = { { rows = 24, cols = 110 } },
  requires = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua").add_deps("plenary.nvim", "telescope.nvim")]],
      reason = "telescope.nvim or plenary.nvim is not to be found",
    },
    { lua = [[vim.fn.executable("git") == 1]], reason = "git is not installed" },
  },
  steps = {
    {
      lua = SETUP,
      note = "telescope, pickers.nvim on it, a git project with a changed and a new file as the cwd",
    },

    -- git_status_filtered
    {
      input = ":Pickers builtin git_status_filtered<CR>",
      note = ":Pickers builtin git_status_filtered",
    },
    {
      wait = [[_G.on_screen("changedk3.txt") and _G.on_screen("untrackedk3.txt")]],
      timeout = 15000,
      note = "git status lists the changed and the new file",
    },
    { expect = [[_G.on_screen("Git status")]], note = "under the title of the git status list" },
    { lua = "_G.close_telescope()" },
    { wait = [[not _G.on_screen("changedk3.txt")]], timeout = 5000, note = "closed" },

    -- gh_issue
    { lua = GH, note = "gh: a stand-in that prints two issues" },
    { input = ":Pickers builtin gh_issue<CR>", note = ":Pickers builtin gh_issue" },
    {
      wait = [[_G.on_screen("Fix the quokka3 layout") and _G.on_screen("Second quokka3 issue")]],
      timeout = 15000,
      note = "both issues are listed, newest first",
    },
    {
      expect = [[_G.on_screen("GitHub Issues (open)")]],
      note = "under the title of the open issues",
    },
    {
      expect = [[(function()
        local calls = _G.fake:calls("gh")
        return #calls == 1 and calls[1].argv[1] == "issue" and calls[1].argv[2] == "list"
      end)()]],
      note = "gh ran once, as `gh issue list`",
    },
    { input = "<CR>", note = "pick the first issue" },
    {
      wait = [[_G.opened_url == "https://example.test/i/7"]],
      timeout = 5000,
      note = "its page is handed to the browser",
    },
  },
  manual = {
    "In the real editor in a GitHub repository with a signed-in gh: :Pickers builtin gh_issue lists its open issues",
  },
}
