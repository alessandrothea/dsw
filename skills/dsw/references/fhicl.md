# FHiCL configuration

## Key facts

- fcl files resolve through `FHICL_FILE_PATH`: the **installed** copies in
  `localProducts_*/<pkg>/<ver>/fcl` come first, then the products. A source edit has no
  effect until `dsw build` installs it.
- The fcl install glob runs at configure time. **New or renamed** fcl files need a `touch`
  of the package's fcl `CMakeLists.txt`, then `dsw build`.
- **Deleted or renamed** fcl files are never removed from the install dir. They keep
  satisfying `#include`s, so a broken reference can stay hidden. `dsw fcl-check` lists
  them. Delete them by hand (ask the user).
- Later definitions override earlier ones, and `#include` order matters. A file that
  includes a shared config can silently pick up settings meant for another detector.

## Inspect one job

```bash
dsw exec fhicl-dump job.fcl > <abs>/job.dump            # fully resolved config
dsw run --debug-config <abs>/job.resolved.fcl -c job.fcl  # what lar would run, then exit
```

To find where a file comes from, put this in a script file and run it with
`dsw exec bash <file>`:

```bash
for d in ${FHICL_FILE_PATH//:/ }; do ls "$d"/job.fcl 2>/dev/null; done
```

Overrides for a quick experiment: write a small `override.fcl` that does
`#include "job.fcl"` and then sets `physics.analyzers.<label>.<key>: value`. Run it with
`dsw run -c <abs>/override.fcl ...`. Don't edit installed copies.

`TFileService.fileName` placeholders: `%ifb` = input file base name. A job without
`fileName` leaves `TFileService-<uuid>.root` files in the current dir (leftovers, safe to
delete).

## Area-wide checks: `dsw fcl-check`

| Mode | What it proves | Use |
|---|---|---|
| `dump [-p PKG] <outdir>` | Every `.fcl` parses (`fhicl-dump` of each into `<name>.dump`) | Before and after any fcl change |
| `diff <outA> <outB>` | Two dump runs are identical file by file | **fcl reorganisation:** dump before, refactor, `dsw build`, dump after, then diff. No diff means no behaviour change |
| `construct [-p PKG] <outdir> [jobs...]` | Every job (top-level `process_name`/`physics`) constructs all its modules: `lar` on an `EmptyEvent` source with 0 events | Catches missing required keys, wrong module/tool types and bad includes, which `fhicl-dump` cannot see |

- `<outdir>` must be new or empty. Use an absolute scratch path.
- Output: failures plus `N OK / M`, exit code 1 if anything failed. Details are in
  `<outdir>/summary.txt` and, for construct, `<outdir>/<job>/lar.log`.
- A `construct` FAIL line shows `module_type:label@Construction` and the first exception
  line. Read the full `lar.log` for the rest.
- Jobs that need real input at construction time (e.g. reading geometry from the input
  file) can fail `construct` for reasons unrelated to the config. Check the reason before
  "fixing" anything.
