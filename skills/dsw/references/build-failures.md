# Build failures

## Which build?

| Situation | Command |
|---|---|
| Edited `.cc`/`.h`/`.fcl`/`CMakeLists.txt` in an existing package | `dsw build` (ninja re-runs CMake by itself when CMake inputs changed) |
| Added a package under `srcs/` | `mrb uc` (via `dsw exec mrb uc`), then `dsw fullbuild` |
| Changed `ups/product_deps`, or the build dir is wiped / broken | `dsw fullbuild` |
| The build dir is in a state you can't explain | `dsw fullbuild --clean`: **ask the user first**, since it wipes build and install |

`dsw build` runs in the *run* environment (`mrbslp`). `dsw fullbuild` uses `mrbsetenv`,
which rewrites CMake inputs in the build dir (`cetpkg_info.sh`, `table_deps_*`). The next
incremental build therefore re-runs CMake once. That is expected.

## Reading a failed build

1. `dsw build -q -l <abs>/build.log`. The summary prints error/warning counts and the first
   30 matching lines. ninja runs with `-k 0`, so all failing targets are attempted.
2. Find the **first** error in the log: `grep -n -m5 -E "error:|FAILED:" <log>`. Later errors
   are often fallout (a missing header cascades). Read ~20 lines above it for the
   `In file included from` chain and template instantiation context.
3. The `FAILED: <target>` line names the object. The compile command that ninja ran can be
   printed with `dsw exec ninja -C <build dir> -t commands <target> | tail -1`.
4. The build uses `-Werror`, `-pedantic` and the cetmodules "CAUTIOUS" diagnostics (on
   dunetrigger), so **warnings are errors**. Typical ones: sign comparison, unused
   variables/parameters, `-Winvalid-offsetof` on non-standard-layout structs, shadowing.
   Fix the cause; don't add pragmas.
5. Link errors (`undefined reference`) mean a library is missing from the target's
   `LIBRARIES` in `CMakeLists.txt`, or a symbol is declared but not defined. A new `.cc`
   that is not listed in the plugin/library sources gives the same error.

## Fast loops

- **One translation unit:** `dsw compile-check <src-root> --tu <pkg-relative path>` compiles
  just that file with the production flags (~30 s), without touching the build dir. Add
  `-std=c++20` (or other flags) at the end to test variants. `<src-root>` can be the main
  checkout (`$MRB_SOURCE/<pkg>`) or a worktree.
- Don't loop on `dsw fullbuild`. It reconfigures everything.

## Things that look like build problems but aren't

- **A data-product header was changed, and the build passes but `lar` crashes in ROOT I/O:**
  the dictionary is stale. See `dictionaries.md`.
- **New or renamed `.fcl` not found at run time:** the fcl install glob runs at configure
  time. `touch` the package's fcl `CMakeLists.txt`, then `dsw build`. Deleted or renamed fcl
  files stay in the install dir and keep satisfying `#include`s (`dsw fcl-check` warns
  about them).
- **`dsw` exits 3:** the environment setup failed, not the build. The failing setup step
  and its output are printed. Check `dsw info`, and whether the area's dunesw version
  still exists on cvmfs.
