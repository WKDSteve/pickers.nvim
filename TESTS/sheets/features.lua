-- TESTS/sheets/features.lua -- the functionalities of pickers.nvim as its user meets them; `testing sheets report`
-- says which ones have a feature sheet (`feature = "<id>"`) and in which state, and K16 warns about a sheet that
-- names an id not listed here. Data: read with an empty environment like a sheet (testing.nvim docs/SHEETS.md).
-- The list follows docs/FEATURES/ (one entry per page there).
-- The sheets of `pickers.items` open the real picker libraries (telescope, fzf-lua, snacks): the workflow checks
-- them out beside this repository and installs fzf (a `requires` skip of a feature sheet is red under CI).
-- `perf` (testing.nvim docs/PERF.md) says why `testing perf` measures a functionality through no sheet of its own:
-- here those that start no process of their own (their code has no spawn site).
return {
  {
    id = "pickers.engines",
    title = "One set of pickers on telescope, fzf-lua or snacks, whichever is installed",
    surface = { "config:engine" },
    docs = "docs/FEATURES/ENGINES.md",
    perf = "skip:the engines' own processes (fzf of fzf-lua) are measured by the sheets of pickers.items on each engine",
  },
  {
    id = "pickers.builtins",
    title = "The native pickers of the engine under one name: git branches, LSP lists, diagnostics, help tags, marks",
    docs = "docs/FEATURES/BUILTINS.md",
  },
  {
    id = "pickers.browse",
    title = "A file browser on the item picker: one directory per list, the file operations as rows",
    docs = "docs/FEATURES/BROWSE.md",
    perf = "skip:starts no process (the listing and the file operations go through vim.uv or fileops.nvim)",
  },
  {
    id = "pickers.actions",
    title = "What to do in a scope (find files, grep and the rest); without an action an action picker appears",
    docs = "docs/FEATURES/ACTIONS.md",
  },
  {
    id = "pickers.items",
    title = "A list of the caller's own rows: keys of the call, several marked rows, a preview per row, the list again after an action",
    docs = "docs/FEATURES/ITEMS.md",
  },
  {
    id = "pickers.refine",
    title = "Narrow a result list by a stack of filter clauses, each one removable",
    docs = "docs/FEATURES/REFINE.md",
    perf = "skip:starts no process (the clauses filter the list in Lua)",
  },
  {
    id = "pickers.scopes",
    title = "Where to search: a scope resolves to roots, works with every action and tab-completes",
    docs = "docs/FEATURES/SCOPES.md",
  },
  {
    id = "pickers.quickfix",
    title = "The quickfix and location window kept as it is, with what it is missing added",
    docs = "docs/FEATURES/QUICKFIX.md",
    perf = "skip:starts no process (the quickfix window and its keys)",
  },
  {
    id = "pickers.persistence",
    title = "What survives a picker closing: the query typed, the picker that was open, the files visited",
    docs = "docs/FEATURES/PERSISTENCE.md",
    perf = "skip:starts no process (state kept in memory and in files)",
  },
  {
    id = "pickers.keys",
    title = "The keys on a result row: open it with the system, show it in the file manager, copy its path, and the rest",
    surface = { "config:keys" },
    docs = "docs/FEATURES/KEYS.md",
  },
}
