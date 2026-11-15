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
