# Browse

A file browser on the engine's own item picker — `pickers.browse`. One
directory per list, directories first (with a trailing `/`), then files,
`../` to go up, and the file operations as rows at the bottom:

```
../
src/
TESTS/
README.md
init.lua
[+] new file…
[+] new directory…
[~] rename…
[-] delete…
```

Picking a directory reopens the list there; picking a file edits it (the
engine's file previewer shows it first, since every file entry carries
`file`); picking an action row asks for a name with `vim.ui.input` — rename
and delete first ask *which* entry, with a second list over the same
directory — and reopens the browser so the result is visible.

**The order is the tree's.** Directories and files are each sorted by name,
case-insensitively (names that differ in case only: by their bytes) — the rule
of filetree.nvim's own tree, so the same folder reads the same in both. A link
to a directory (a Windows junction too) is listed as a directory. The rule is
written out here rather than called from filetree.nvim: the browser works
without it, and it reads the directory fresh every time (the tree's listing
sits behind a cache its watchers keep current, which a folder outside the tree
does not have). Measured on 2026-11-14: both read with the same `scandir`, a
4860-entry folder takes about 11 ms either way.

The operations go through fileops.nvim when it is installed (`edit_new`
for a new file, `delete_path` for delete — trash-aware there — and its
`notify_change` so open explorers refresh) and through `vim.uv` otherwise.
A rename refuses to overwrite, and a buffer showing the renamed file
follows it.

It is the telescope-file-browser harvest, and it is what fzf-lua — the one
engine with no explorer of its own — gets as `explorer`. It is not a tree:
a list of one directory at a time is what a picker draws well; the tree is
snacks' explorer or filetree.nvim.

- **Module:** [`browse/init.lua`](../../lua/pickers/browse/init.lua)
  (`open`, `entries`, `new_file`, `new_dir`, `rename`, `delete`)
- **Usercmds:** `:Pickers browse [dir]`, `:Pickers builtin browse`,
  `:Pickers builtin explorer` on fzf-lua
