# dsw

Run dunesw / LArSoft work from an MRB area inside the FNAL SL7 container, from an
AlmaLinux 9 host. One command for developers and for Claude.

```bash
source <path>/dsw/setup_env.sh          # puts dsw on PATH
cd <somewhere in or above an MRB area>
dsw info                                # area, version, dirs, packages, stack
dsw build                               # ninja -k 0 install → log + error summary
dsw run -c job.fcl in.root -n -1 -T out.root
dsw shell                               # interactive, environment set up
```

## Commands

| Command | Does |
|---|---|
| `newarea -v <ver> [-q <quals>] [-p <git-url>[#<ref>]]... [--requirements F] [--no-venv] [--no-build] [-j N] <dir>` | Create a new area: `setup dunesw` → `mrb newDev` → `.venv` (+ `pip install -r F`) → `setup_dunesw.sh`, `lar_wrap.sh`, `dunesw_wrap.sh` (still used by the condor tooling) → `git clone` each package into `srcs/` (+ checkout of `ref`) → `mrb uc` → `fullbuild` (only if packages were given). Stops at the first failure. Replaces `create_larsoft_area.sh`, using `git clone` instead of `mrb g`. See `dsw newarea -h` |
| `where` | Print the detected MRB area (no container) |
| `info` | Area, product/version/quals, source/build/install dirs, packages + git branch, stack versions |
| `shell` | Interactive bash: your `~/.bashrc`, then the run environment, `dsw` on `PATH` (so `dsw` commands in the shell skip the container and the setup), and a `[dsw <version>]` prompt prefix |
| `exec <cmd…>` | Run any command |
| `build [-l LOG] [-q] [ninja args]` | `ninja -C $MRB_BUILDDIR -k 0 install`. Output is shown live and always saved to a log (default `<area>/logs/build-<time>.log`). At the end it prints error/warning counts, the first matching lines, the log path and `rc=` |
| `fullbuild [--clean] [-l LOG] [-q] [-j N] [mrb i args]` | `mrbsetenv` + `mrb i -jN --generator=ninja` (N defaults to `nproc`). Reconfigures with CMake. Use it for a new area, after adding a package or `mrb z`, or after `product_deps` changes. `--clean` first runs `mrb uc` + `mrb z` + `mrb zd`, which **wipes the build and install dirs** (replaces `rebuild_larsoft_area.sh`). Logged like `build` (default `<area>/logs/fullbuild-<time>.log`) |
| `run [-l LOG] [-q] <lar args…>` | `lar` |
| `root [-l LOG] [-q] <args…>` | `root -l -b -q <args>`. Run macros from files: stdin doesn't get through |
| `py [-l LOG] [-q] <args…>` | `python <args>` (area venv if present, otherwise the stack python) |
| `ls <file.root>` | List directories, objects, cycles and tree entries (replaces the broken `rootls`) |
| `compile-check <src-root> --tu <path> [g++ flags]` | Compile one file of another checkout of a package (e.g. a git worktree) with the build's own command from `ninja -t compdb`. Output goes to a temp dir; nothing in the area changes. Extra flags are appended (e.g. `-std=c++20`) |

`-l LOG` also saves the output to LOG and ends with the log path and `rc=`. `-q` (with
`-l`) hides the live output and prints a summary only (for `run`/`root`/`py`, the last
20 lines). Use it when the output is long, e.g. from scripts or Claude.

Exit codes: the command's own; `2` = dsw usage/area error; `3` = environment setup failed.

## How it works

- **Area:** `-C <area>`, else `$DSW_AREA`, else the nearest ancestor of `$PWD` that is an
  MRB area (has `srcs/` and one `localProducts_*/setup`), else the nearest ancestor with
  exactly one such child.
- **Version/quals:** read from `MRB_PROJECT_VERSION` / `MRB_QUALS` in the area's
  `localProducts_*/setup`. The product set up is `dunesw`. No per-area wrapper script is needed.
- **Container:** on a non-SL7 host, dsw re-runs itself in
  `fnal-dev-sl7` via apptainer from cvmfs. It binds `/cvmfs /opt /eos /afs /run/user
  /etc/hostname /etc/hosts /etc/krb5.conf /tmp`, but only those that exist. Inside the
  container, or on a native SL7 host, it runs directly.
- **Setup:** there are two environments:
  - *run* (everything, including the incremental `build`): `setup_dune.sh` →
    `setup dunesw <ver> -q <quals>` → `localProducts_*/setup` → `mrbslp` → `.venv` (if present).
  - *build* (`fullbuild` only): `setup_dune.sh` → `localProducts_*/setup` [→ `mrb uc` → `mrb z` → `mrb zd` with `--clean`] → `mrbsetenv`.
    `mrbsetenv` rewrites CMake inputs in the build dir (`cetpkg_info.sh`, `table_deps_*`)
    on every call. That is why the incremental `build` avoids it: otherwise every build
    would reconfigure.

  Setup output is hidden and shown only on failure, and any failing step stops the
  command. `mrbslp` returns 1 even on success, so it is checked by verifying that every
  product installed in the area is set up.

## Per-area overrides: `<area>/.dsw.conf`

Optional `KEY=VALUE` lines. The file is parsed, not sourced.

```
PRODUCT=dunesw
VERSION=v10_26_00d05
QUALS=e26:prof
UPS_OVERRIDE=-H Linux64bit+3.10-2.17
IMAGE=/cvmfs/unpacked.cern.ch/registry.hub.docker.com/fermilab/fnal-dev-sl7:latest
EXTRA_BINDS=/data,/scratch
VENV=auto        # auto | on | off
SHELL_RC=on      # off: dsw shell skips ~/.bashrc (if it breaks in SL7)
```

## Gotchas

- Don't pipe `ninja`/`lar` output into `head`: SIGPIPE kills the job (exit 141). Use `-l` and
  read the log.
- Each call starts a fresh container (a few seconds). Use `dsw shell`, or put several steps
  in a script and `dsw exec ./script.sh`.
- `lar` writes tracker files (`mem.db`, `time.db`) and other job output into the current
  directory. `cd` to a scratch/output dir first.
- One build dir per area: don't run two `dsw build` at once. Use a worktree +
  `compile-check` for parallel work.
- Exit codes: 134 = SIGABRT (art abort, glibc assertion), 139 = SIGSEGV, 141 = SIGPIPE.
