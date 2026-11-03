# lar crashes, aborts and exceptions

## 1. Reproduce small, with a log

```bash
cd <scratch outdir>      # lar writes mem.db/time.db/TFileService files here
dsw run -q -l <abs>/run.log -c job.fcl <abs>/input.root -n 10 -T <abs>/out.root
```

- Narrow the event range: `-n N` (number of events), `--nskip K` (skip the first K),
  `-e run:subrun:event` (start at an event). `dsw run --help` lists them all (it's `lar --help`).
- art prints `Begin processing the Nth record. run: R subRun: S event: E` per event. The
  last one before the failure brackets where it was *detected*, which is not always where
  it was *caused*.
- Keep a failing input as `<file>.broken` before regenerating anything (forensics).

## 2. Classify the failure

| Signature in the log | Likely cause | Next |
|---|---|---|
| `---- <Category> BEGIN` ... `cet::exception caught in art` with a module label and `@Construction` | Configuration: a missing/mistyped fcl key, wrong tool name, product not found at construction | `fhicl.md` |
| Same, but with `@analyze` / `@produce` / `@beginJob` | A `throw` in module code: `ProductNotFound` (wrong `InputTag`, producer didn't run), `std::out_of_range` from `.at()`, explicit `cet::exception` | Read the message, check `lar --trace` output for the module order, check the tags |
| exit 134, `*** Error in 'lar': corrupted size vs. prev_size`, `malloc(): ...`, `free(): invalid pointer` | **Heap corruption.** Detected later than it happened | Section 4; if the backtrace goes through `TBasket`/`RootDelayedReader`/`getMany`, see `dictionaries.md` |
| exit 139 (SIGSEGV) in module code | Null `art::Ptr`/pointer dereference, out-of-bounds index, use of a dangling reference | gdb (section 3) |
| exit 139 inside ROOT/art I/O frames | Often a stale dictionary or a file written with one | `dictionaries.md` |
| Job runs, but trees are empty or values wrong | Tag regexes not matching, a feature flag off, silent narrowing in row structs | `root-files.md`, `art-module-review.md` |

Useful art switches:
- `lar --trace ...` lists every module call per event, which shows which module was
  running when it died and which producers ran.
- Message facility: raise limits per category instead of drowning in banners:
  `services.message.destinations.<dest>.categories.<Category>: { limit: -1 }`.
- `source.saveMemoryObjectThreshold: 0` disables ROOT basket hold-out, which can hide
  timing-dependent read crashes. Set it when debugging input-file problems.

## 3. Backtrace with gdb

```bash
dsw exec gdb -batch -x $(dsw where --home)/share/gdb/backtrace.gdb \
  --args lar -c job.fcl <abs>/input.root -n <just past the crash> > <abs>/gdb.log 2>&1
```

The script runs the program, ignores the signals art/ROOT use internally, and on a crash
prints all thread backtraces plus `bt full 4`. Find the first frame in *your* package
(below the glibc/ROOT frames). The build type is `RelWithDebInfo`, so line numbers are
available. Running under gdb is slow: reduce `-n` first.

## 4. Heap corruption (exit 134)

- glibc reports the damage at the first `malloc`/`free` that trips over it, so the
  backtrace shows the *victim*. Walk up to the art read or the module fill, then suspect
  **earlier** activity.
- **First do the null test:** does the input file itself crash in plain ROOT?
  `dsw macro -q -l <abs>/read_all.log read_all <abs>/input.root` (reads every `Events`
  entry). If that crashes, the module is not the culprit: go to `dictionaries.md`.
- Otherwise use valgrind on 1–2 events:
  ```bash
  dsw exec valgrind --error-limit=no --num-callers=40 \
    --suppressions=<root etc dir>/valgrind-root.supp lar -c job.fcl <abs>/in.root -n 2 \
    > <abs>/vg.log 2>&1
  ```
  Get `<root etc dir>` from `dsw exec root-config --etcdir`. The first `Invalid write`
  in your code is the cause. Expect it to be very slow, and expect noise from ROOT/Geant4.

## 5. Verify a fix

1. `dsw build -q -l ...` is clean.
2. Rerun the failing job over **all** events (`-n -1` if the source sets `maxEvents`):
   `Art has completed and will exit with status 0`.
3. Compare the output with a baseline (`root-files.md`). Entry counts must match, and rows
   that used to crash should now carry sentinel values.
