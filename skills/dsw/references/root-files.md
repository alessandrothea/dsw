# Inspecting and comparing ROOT files

`rootls` is broken in this stack (stale python shebang). Use these instead:

| Need | Command |
|---|---|
| What's in the file (dirs, objects, cycles, tree entries/branches) | `dsw ls <file.root>` |
| One tree: entries, branch names + types, first rows | `dsw macro tree_scan <file> <dir/tree> ["b1:b2:b3"] [nrows]` |
| Read every entry of a tree in plain ROOT (null test) | `dsw macro read_all <file> [tree=Events]` |
| Class layout in the file vs loaded dictionary | `dsw macro streamer_cmp <file> <FQN>` (see `dictionaries.md`) |
| Anything else | a PyROOT script: `dsw py <abs>/script.py args` |

## Notes

- **Cycles:** `name;1` and `name;2` usually mean the object was written twice (autosave, or
  an explicit `Write()` of something TFileService already owns). `TFile::Get("name")`
  returns the highest cycle. Compare that one, and treat a lower cycle with fewer entries
  as a partial save.
- **art files:** products are branches of the `Events` tree, named
  `<type>_<label>_<instance>_<process>.`. `dsw ls` shows the trees, and `tree_scan ... Events`
  shows the branch names.
- **TFileService output:** trees sit under `/<module label>/...`. The `info`-style `TNamed`
  objects hold metadata (e.g. JSON in the title).
- PyROOT in this stack: ROOT 6.28 + numpy 1.24 (venv python 3.9). `uproot` is usually
  **not** installed. Use `ROOT.RDataFrame(tree, file).AsNumpy([...])` for columns.

## Comparing two outputs (regression check)

There's no generic tool in dsw. Write a PyROOT script that, for every tree in both files:
1. reports trees present in only one file;
2. compares entry counts;
3. reports branches present in only one tree;
4. compares each common branch entry by entry. Use `AsNumpy`, compare vector branches
   element-wise, and treat NaN == NaN.

Also diff the metadata objects (e.g. the JSON in a `TNamed` title) key by key. Exit 0 if
identical, 1 if different. Projects often already have one (e.g. a `compare_trees.py`):
look before writing a new one.

A "no behaviour change" refactor must give zero differences on the reference input, so
run the job with `-n -1` if the source config limits `maxEvents`.
