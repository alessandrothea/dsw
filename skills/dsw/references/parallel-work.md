# Parallel work: worktrees and compile-only checks

An MRB area has **one** build dir, bound to `$MRB_TOP/srcs`. Two builds or `fullbuild`s in
the same area at the same time corrupt each other. Rule: one agent (or person) owns the
main tree and does the full build, run and compare. Everyone else works in a git worktree
and checks compile-only.

## Set up a worktree

```bash
A=$(dsw where)                          # the area
git -C $A/srcs/<pkg> worktree add -b wip/<topic> $A/wt-<topic> HEAD
```

Use a throwaway branch name. Keep the worktree **outside** `srcs/` (mrb would treat it as a
package).

## Check it compiles

```bash
dsw compile-check $A/wt-<topic> --tu <pkg-relative path, e.g. pkg/Module/Foo_module.cc>
dsw compile-check $A/wt-<topic> --tu <...> -std=c++20     # extra g++ flags go at the end
```

- It takes the production compile command for that file from `ninja -t compdb`, points the
  source and include paths at the worktree, and writes its output to a temp dir. The build
  dir is not touched, so it is safe to run while the main tree builds.
- It ends with `compile_check rc=N`. It only proves that **one** file compiles. There is no
  linking, no other files and no run.
- A brand-new `.cc` that isn't in the build yet has no compile command. Compile a file that
  includes it instead, or integrate it first.

## Integrate

After the main-tree work is verified:

```bash
git -C $A/wt-<topic> diff | git -C $A/srcs/<pkg> apply     # or commit + cherry-pick
dsw build -q -l <log>          # then run + compare in the main tree
git -C $A/srcs/<pkg> worktree remove $A/wt-<topic>
git -C $A/srcs/<pkg> branch -D wip/<topic>
```

Only steps that should change no behaviour belong on the worktree side. Their
verification happens after integration, so nothing is lost by checking them late.
