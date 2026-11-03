---
name: dsw
description: Build, run and debug DUNE dunesw/LArSoft MRB development areas with the dsw tool (FNAL SL7 apptainer container + UPS + mrb). Use whenever a task needs lar, art/FHiCL jobs, ROOT or PyROOT, ninja/mrb builds, or when diagnosing build errors, lar crashes (exit 134/139, art exceptions), FHiCL configuration errors, ROOT file contents, ROOT dictionary/streamer mismatches, or reviewing an art module for robustness. Never run lar, root, ninja or fhicl-dump on the bare AlmaLinux 9 host.
---

# dsw: dunesw areas in the SL7 container

dunesw/LArSoft products are SL7/UPS builds. The host is AlmaLinux 9. Everything goes
through `dsw`, which finds the MRB area, starts the `fnal-dev-sl7` apptainer container,
sets up the environment and runs the command. Scope: SL7 + UPS + mrb only (no Spack, no
native AL9).

## Getting started

- **Finding dsw:** `dsw` if it is on `PATH`. Otherwise it is `bin/dsw` in the repo this
  skill lives in: `$(readlink -f <this skill dir>/../..)/bin/dsw`. Use that absolute path.
- **First call in a session:** `dsw where` (finds the area without starting the
  container), then `dsw info` (versions, dirs, packages + branches). Don't trust MRB paths
  from notes or old prompts: areas are renamed when dunesw is bumped.
- **Choosing the area:** run from inside or above it, or pass `-C <area>` (or set
  `DSW_AREA`). With several areas side by side, always pass `-C`.
- **Help:** `dsw help`, `dsw newarea -h`, `dsw fcl-check -h`, `dsw macro` (lists macros).
  `dsw where --home` prints the dsw repo path (for `share/gdb/backtrace.gdb`).

## Rules

1. **Never** run `lar`, `root`, `ninja`, `mrb`, `fhicl-dump`, `gdb` or PyROOT directly. Use
   `dsw <cmd>` or `dsw exec <cmd>`.
2. **No inline shell in the container.** Avoid `dsw exec bash -c '...'` and heredocs, since
   stdin does not get through. Write a script or macro file (the scratchpad works, `/tmp`
   is bound) and run it with `dsw exec bash <file>`, `dsw root <file.C>` or `dsw py <file.py>`.
3. **Long output goes to a log.** Use `-q -l <abs path>.log` (build/run/root/py/macro), then
   read or grep the log. Never pipe `ninja`/`lar` into `head` (SIGPIPE kills them, exit 141).
4. **Absolute paths** for logs, outputs and inputs, especially when shells run in parallel.
5. **Run `lar` from an output/scratch directory.** It writes `mem.db`, `time.db`, TFileService
   files and debris into the current directory and overwrites earlier ones.
6. **One build per area at a time** (there is a single build dir). For parallel work see
   `references/parallel-work.md`.
7. **Ask the user first** before anything destructive or slow: `dsw fullbuild --clean`
   (wipes build + install), `dsw newarea`, deleting files in an area, regenerating input
   files, editing `classes_def.xml`. Never `dsw build` an area that someone else is
   building.
8. Each `dsw` call starts a fresh container (a few seconds). For many steps, put them in
   one script and use `dsw exec bash <script>`.

## Command map

| Need | Command |
|---|---|
| Incremental build (fast, day to day) | `dsw build -q -l <log>` → summary (errors/warnings, first lines, `rc=`) |
| Reconfigure + full build (new package, after `mrb z`, `product_deps` changed) | `dsw fullbuild -q -l <log>`; `--clean` also wipes build + install (ask first) |
| Compile one file of a worktree/other checkout | `dsw compile-check <src-root> --tu <path rel. to package> [g++ flags]` |
| Run an art job | `cd <outdir> && dsw run -q -l <log> -c job.fcl in.root -n N -T out.root` |
| Any command | `dsw exec <cmd> [args]` |
| ROOT macro / PyROOT script | `dsw root [--clean-room] file.C` / `dsw py script.py args` |
| Bundled macros | `dsw macro` lists them: `read_all`, `streamer_cmp`, `class_checksum`, `tree_scan` |
| List a ROOT file (rootls is broken) | `dsw ls file.root` |
| FHiCL checks over a whole area | `dsw fcl-check construct\|dump\|diff ...` |
| gdb backtrace | `dsw exec gdb -batch -x $(dsw where --home)/share/gdb/backtrace.gdb --args lar ...` |
| New area | `dsw newarea -v <ver> [-p <git-url>[#ref]] ... <dir>` (ask first) |

## Exit codes

- dsw itself: `2` = usage or area not found; `3` = environment setup failed (the failing
  setup step is printed). Otherwise the command's own exit code.
- `134` = SIGABRT (glibc heap check such as `corrupted size vs. prev_size`, or an art abort),
  `139` = SIGSEGV, `141` = SIGPIPE (usually your own pipe was cut short). Any other non-zero
  code from `lar` usually means art stopped on an exception: read the exception block in
  the log (`references/runtime-crashes.md`). A clean run ends with
  `Art has completed and will exit with status 0`.

## Playbooks: read the one that matches

| Situation | Read |
|---|---|
| Compile/link errors, `dsw build` fails, unsure whether `build` or `fullbuild` is needed | `references/build-failures.md` |
| `lar` crashes or aborts (134/139), art exception, wrong behaviour at runtime | `references/runtime-crashes.md` |
| FHiCL errors, missing keys, which fcl is used, checking a fcl reorganisation | `references/fhicl.md` |
| Inspecting or comparing ROOT/TFileService output files | `references/root-files.md` |
| Crash inside ROOT I/O, data-product header changed, streamer/checksum questions | `references/dictionaries.md` |
| Several agents or branches at once, git worktrees | `references/parallel-work.md` |
| Reviewing an art analyzer/producer for crash and silent-data risks | `references/art-module-review.md` |
