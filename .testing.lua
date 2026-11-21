-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "pickers",
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process.
  dialect = "auto",
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "lib.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file
  -- (nothing leaks from one file into the next).
  isolated = "none",
  -- "c" = child started from a -c command (v:vim_did_enter is 0, <cword> works),
  -- "l" = `nvim -l`.
  host = "l",
  -- Guards (safety nets). Every spec file is a self-running script (its own `nvim -l`
  -- process), where testing.nvim installs no guard at all, so the fleet measurement had no
  -- findings and no allowlist entry is justified. The values below are the documented defaults,
  -- written down so they apply as soon as the spec runs under a dialect that is guarded:
  -- error where a clean suite is expected, warn where a first guarded run may still show noise.
  guards = {
    fs = "warn",
    state = "warn",
    scheduled_error = "error",
    prompt = "error",
    deprecation = "warn",
    process_net = "off",
  },
  -- No allowlist for the script files: nothing legitimate was observed (they are not measured).
  -- nvim: TESTS/sheets_spec.lua (busted style, guarded) starts a child editor per test sheet (TESTS/sheets/).
  guard_allow = { fs = {}, spawn = { "nvim" }, network = {} },
  -- Environment variables the specs read; a child editor inherits an allowlist only (never secrets).
  -- PLENARY_NVIM_DIR .. SNACKS_NVIM_DIR: where the child editor of a test sheet finds the real picker libraries
  -- (TESTS/minimal_init.lua names them; else .deps/, ../, the lazy.nvim directory of the real editor).
  env_allow = {
    "LIB_NVIM_PATH",
    "LIB_FS_HELPER_TEST",
    "REPOS_DIR",
    "PICKERS_REQUIRE_TOOLS",
    "FILETREE_NVIM_DIR",
    "PLENARY_NVIM_DIR",
    "TELESCOPE_NVIM_DIR",
    "FZF_LUA_DIR",
    "SNACKS_NVIM_DIR",
  },
  -- A test sheet is one case that starts a child editor and a real picker (fzf is a process of its own); under load
  -- that takes longer than the default 10 s.
  timeouts = { case_ms = 60000, file_ms = 300000 },
  ci = {
    -- The GitHub workflow, generated: `testing init --workflow=public --force` writes .github/workflows/ci.yml from
    -- this (testing.nvim docs/WORKFLOW-CI.md); the step workflow-in-sync keeps the two together.
    workflow = {
      name = "pickers.nvim",
      layout = "hosted",
      -- the steps that depend on the platform: the windows and macOS legs run only these
      platform = { "suite", "conformance" },
      -- `testing ci land`: a check branch ci/** runs the hosted legs, main moves to a commit only once it is green there
      land = true,
      -- The test sheets of pickers.items (TESTS/sheets/) open the REAL picker libraries in a child editor; below
      -- .deps/ TESTS/minimal_init.lua finds them and puts none on the runtimepath of the specs. Pinned at the commits
      -- the sheets were written against; without one a feature sheet is a skip, which is red under CI.
      checkouts = {
        {
          repo = "nvim-lua/plenary.nvim",
          ref = "74b06c6c75e4eeb3108ec01852001636d85a932b",
          why = "telescope.nvim needs it for the sheet pickers-items-telescope",
        },
        {
          repo = "nvim-telescope/telescope.nvim",
          ref = "1e1bab730218eaf97fce743be3f56e51075928ac",
          why = "the real telescope picker of the sheet pickers-items-telescope",
        },
        {
          repo = "ibhagwan/fzf-lua",
          ref = "22f0bbd3140a8a3b34fec75e5a640513ca6d4ce3",
          why = "the real fzf-lua picker of the sheet pickers-items-fzf-lua",
        },
        {
          repo = "folke/snacks.nvim",
          ref = "882c996cf28183f4d63640de0b4c02ec886d01f2",
          why = "the real snacks picker of the sheet pickers-items-snacks",
        },
      },
      packages = {
        {
          name = "fzf",
          why = "fzf-lua runs fzf in a terminal of the child editor (sheet pickers-items-fzf-lua)",
        },
        {
          name = "fd",
          apt = "fd-find",
          why = "the filegrep specs and the sheets of pickers.actions, scopes and keys run the real fd (fdfind on Ubuntu)",
        },
        { name = "ripgrep", why = "the filegrep specs and the feature sheets run the real rg" },
      },
      env = {
        -- every leg installs fd and rg (packages above), so a missing one is a failure, not a skip
        PICKERS_REQUIRE_TOOLS = "1",
        -- TMPDIR=/tmp on macOS (the RPC socket of fzf-lua in a sheet's child) is the generator's default since
        -- testing.nvim@402296e, no longer an env of this repository.
      },
      publish = { why = "data.nvim and replacer.nvim check out pickers.nvim at ci-verified" },
    },
    steps = {
      ["workflow-in-sync"] = { preset = "workflow-in-sync" },
    },
  },
  -- Findings the minimal conformance editor cannot avoid (docs/CONFORMANCE.md of testing.nvim); reviewed 2026-10-14.
  conformance = {
    -- gated: a failed check makes `scripts/test.sh conformance` exit 1
    gate = true,
    waivers = {
      {
        check = "K6",
        level = "error",
        text = "No picker engine",
        reason = "a picker engine (telescope, fzf-lua, snacks) is external; the minimal conformance editor has none",
        expires = "2027-04-14",
      },
      {
        check = "K5",
        level = "warn",
        text = ":FileGrep takes",
        reason = "the argument is a free-text query that seeds the prompt; there is no closed set to complete",
        expires = "2027-04-14",
      },
      {
        check = "K5",
        level = "warn",
        text = ":FileGrepConfig takes",
        reason = "the argument is a free-text query that seeds the prompt; there is no closed set to complete",
        expires = "2027-04-14",
      },
    },
  },
}
