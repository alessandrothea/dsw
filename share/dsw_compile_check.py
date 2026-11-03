#!/usr/bin/env python3
"""Compile one translation unit from an alternative checkout of an MRB package.

Takes the production compile command for the TU from `ninja -t compdb`, points the
source and include paths at the other checkout (e.g. a git worktree), sends the
output to a temporary dir, and runs it. Only the compiler runs; nothing is linked or
installed, and the build dir is not changed.
"""
import argparse
import json
import os
import shlex
import subprocess
import sys
import tempfile


def main():
    p = argparse.ArgumentParser(prog="dsw compile-check")
    p.add_argument("--build-dir", required=True)
    p.add_argument("--source-dir", required=True, help="$MRB_SOURCE")
    p.add_argument("--src-root", required=True,
                   help="the other checkout of the package (dir with its CMakeLists.txt)")
    p.add_argument("--tu", required=True,
                   help="source file path relative to the package root")
    p.add_argument("-v", "--verbose", action="store_true", help="print the command")
    args, extra = p.parse_known_args()

    new_root = os.path.realpath(args.src_root)
    tu = args.tu.strip("/")
    if not os.path.isfile(os.path.join(new_root, tu)):
        sys.exit(f"dsw compile-check: {tu} not found under {new_root}")

    out = subprocess.run(["ninja", "-C", args.build_dir, "-t", "compdb"],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         universal_newlines=True)
    if out.returncode != 0:
        sys.exit(f"dsw compile-check: ninja -t compdb failed:\n{out.stderr}")
    entries = json.loads(out.stdout)

    src_dir = os.path.realpath(args.source_dir) + "/"
    matches = []
    for e in entries:
        f = e["file"] if os.path.isabs(e["file"]) else os.path.join(e["directory"], e["file"])
        if f.endswith("/" + tu) and os.path.realpath(f).startswith(src_dir):
            matches.append((e, f))
    if not matches:
        sys.exit(f"dsw compile-check: no compile command for */{tu} under {src_dir} "
                 f"(is it part of the build?)")
    if len(matches) > 1:
        sys.exit("dsw compile-check: ambiguous TU, matches: "
                 + ", ".join(f for _, f in matches))
    entry, orig_file = matches[0]
    orig_root = orig_file[: -len(tu) - 1]

    cmd = entry.get("arguments") or shlex.split(entry["command"])
    tmp = tempfile.mkdtemp(prefix="dsw-cc.")
    new_cmd = []
    it = iter(cmd)
    for a in it:
        if a == "-o":
            next(it, None); new_cmd += ["-o", os.path.join(tmp, "tu.o")]
        elif a == "-MF":
            next(it, None); new_cmd += ["-MF", os.path.join(tmp, "tu.d")]
        elif a in ("-MT", "-MQ"):
            next(it, None)
        else:
            new_cmd.append(a.replace(orig_root, new_root))
    new_cmd += extra

    if args.verbose:
        print(" ".join(shlex.quote(a) for a in new_cmd), flush=True)
    rc = subprocess.call(new_cmd, cwd=entry["directory"])
    for f in os.listdir(tmp):
        os.remove(os.path.join(tmp, f))
    os.rmdir(tmp)
    print(f"compile_check rc={rc}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
