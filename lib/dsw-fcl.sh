# dsw-fcl.sh — `dsw fcl-check`: area-wide FHiCL checks. Sourced by bin/dsw; runs inside
# the container with the run environment set up. Generalises the debug scripts
# construct_all.sh / dump_all.sh / diff_dumps.sh (trgana_refactor/debug/scripts).

dsw_fcl_check_usage() {
  cat <<'EOF'
usage: dsw fcl-check construct [-j N] [-p PKG]... <outdir> [job.fcl...]
       dsw fcl-check dump      [-j N] [-p PKG]... <outdir> [file.fcl...]
       dsw fcl-check diff      <outdirA> <outdirB>

  construct  For every job fcl (a top-level process_name or physics block) in the
             packages under srcs/, run `lar` on an EmptyEvent source with 0 events. This
             builds every module, so it catches missing required keys, wrong module/tool
             names and bad includes, not just parse errors. One dir per job in <outdir>
             (construct.fcl, lar.log).
  dump       fhicl-dump every .fcl in the packages into <outdir>/<name>.dump (.err).
  diff       Compare two dump runs: parse status per file, then every dump present in
             both (e.g. before/after a fcl reorganisation: no diff = no behaviour change).

  -p PKG     limit to srcs/PKG (repeatable; default: every package in srcs/)
  -j N       parallel jobs (default 8)
  <outdir>   must not exist or be empty
  Prints the failures and "N OK / M"; exit code 1 if anything failed.

fcl names are resolved through FHICL_FILE_PATH, i.e. the INSTALLED copies. The check
warns about fcl files that are missing from the install or older than their source
(run `dsw build` first), and about installed fcl files whose source was deleted or renamed:
the install never removes them, so they can still satisfy #includes. Delete those by hand.
EOF
}

# Warn about source/install fcl mismatches for the given package dirs.
_dsw_fcl_install_check() {
  local pdir pkg f b inst missing=() older=() stale=()
  declare -A src_of inst_of
  for pdir in "$@"; do
    pkg=${pdir##*/}
    while IFS= read -r f; do src_of[${f##*/}]=$f; done \
      < <(find "$pdir" -name '*.fcl' -not -path '*/.git/*')
    while IFS= read -r f; do inst_of[${f##*/}]=$f; done \
      < <(find "$MRB_INSTALL/$pkg" -name '*.fcl' 2>/dev/null)
  done
  for b in "${!src_of[@]}"; do
    inst=${inst_of[$b]:-}
    if [ -z "$inst" ]; then missing+=("$b")
    elif [ "${src_of[$b]}" -nt "$inst" ]; then older+=("$b"); fi
  done
  for b in "${!inst_of[@]}"; do [ -n "${src_of[$b]:-}" ] || stale+=("${inst_of[$b]}"); done
  if [ ${#missing[@]} -gt 0 ] || [ ${#older[@]} -gt 0 ]; then
    dsw_msg "warning: ${#missing[@]} fcl not installed, ${#older[@]} installed copies older than the source — run 'dsw build' first"
    [ ${#missing[@]} -gt 0 ] && printf '  not installed: %s\n' "${missing[@]:0:5}" >&2
    [ ${#older[@]} -gt 0 ] && printf '  older:         %s\n' "${older[@]:0:5}" >&2
  fi
  if [ ${#stale[@]} -gt 0 ]; then
    dsw_msg "warning: ${#stale[@]} installed fcl without a source (deleted/renamed?) — they still satisfy #includes:"
    printf '  %s\n' "${stale[@]:0:10}" >&2
  fi
}

_dsw_fcl_diff() {
  local a=$1 b=$2 f n rc=0
  [ -f "$a/summary.txt" ] && [ -f "$b/summary.txt" ] || dsw_die "fcl-check diff: both dirs need a summary.txt from 'fcl-check dump'"
  if diff <(sort -k2 "$a/summary.txt") <(sort -k2 "$b/summary.txt"); then
    echo "status: identical"
  else
    rc=1
  fi
  for f in "$b"/*.dump; do
    n=${f##*/}
    [ -f "$a/$n" ] || { echo "NEW $n"; continue; }
    # fhicl-dump writes a '#' header only when the file has content: ignore comments
    if ! diff -q <(grep -v '^#' "$a/$n") <(grep -v '^#' "$f") > /dev/null; then
      echo "=== CHANGED $n"; diff "$a/$n" "$f"; rc=1
    fi
  done
  for f in "$a"/*.dump; do [ -f "$b/${f##*/}" ] || { echo "GONE ${f##*/}"; rc=1; }; done
  [ $rc -eq 0 ] && echo "dumps: identical"
  return $rc
}

dsw_fcl_check() {
  local fc_sub=${1:-}
  [ $# -gt 0 ] && shift
  case $fc_sub in
    construct|dump) ;;
    diff) [ $# -eq 2 ] || dsw_die "usage: dsw fcl-check diff <outdirA> <outdirB>"
          _dsw_fcl_diff "$1" "$2"; return ;;
    -h|--help|"") dsw_fcl_check_usage; return 0 ;;
    *) dsw_die "fcl-check: unknown mode '$fc_sub' (construct|dump|diff)" ;;
  esac
  local fc_jobs=8 fc_out= fc_pkgs=() fc_files=() fc_dirs=() p
  while [ $# -gt 0 ]; do
    case $1 in
      -j) [ $# -ge 2 ] || dsw_die "-j needs a number"; fc_jobs=$2; shift 2 ;;
      -p) [ $# -ge 2 ] || dsw_die "-p needs a package"; fc_pkgs+=("$2"); shift 2 ;;
      -h|--help) dsw_fcl_check_usage; return 0 ;;
      -*) dsw_die "fcl-check: unknown option $1" ;;
      *) if [ -z "$fc_out" ]; then fc_out=$1; else fc_files+=("$1"); fi; shift ;;
    esac
  done
  [ -n "$fc_out" ] || dsw_die "fcl-check $fc_sub: <outdir> is required"
  fc_out=$(readlink -m "$fc_out")
  if [ -e "$fc_out" ] && [ -n "$(ls -A "$fc_out" 2>/dev/null)" ]; then
    dsw_die "fcl-check: $fc_out exists and is not empty (use a new dir)"
  fi
  if [ ${#fc_pkgs[@]} -gt 0 ]; then
    for p in "${fc_pkgs[@]}"; do
      [ -d "$MRB_SOURCE/$p" ] || dsw_die "fcl-check: no package srcs/$p"
      fc_dirs+=("$MRB_SOURCE/$p")
    done
  else
    for p in "$MRB_SOURCE"/*/; do
      p=${p%/}; [ -f "$p/CMakeLists.txt" ] && fc_dirs+=("$p")
    done
  fi
  [ ${#fc_dirs[@]} -gt 0 ] || dsw_die "fcl-check: no packages under $MRB_SOURCE"
  mkdir -p "$fc_out" || dsw_die "cannot create $fc_out"

  local list=$fc_out/files.txt
  if [ ${#fc_files[@]} -gt 0 ]; then
    printf '%s\n' "${fc_files[@]}" > "$list"
  elif [ "$fc_sub" = construct ]; then
    grep -rlE '^(process_name|physics)[ :.]' --include='*.fcl' --exclude-dir=.git "${fc_dirs[@]}" \
      | xargs -r -n1 basename | sort -u > "$list"
  else
    find "${fc_dirs[@]}" -name '*.fcl' -not -path '*/.git/*' -printf '%f\n' | sort -u > "$list"
  fi
  local total
  total=$(wc -l < "$list")
  [ "$total" -gt 0 ] || dsw_die "fcl-check: no fcl files found"

  _dsw_fcl_install_check "${fc_dirs[@]}"
  dsw_msg "fcl-check $fc_sub: $total files, $fc_jobs in parallel → $fc_out"
  xargs -P "$fc_jobs" -I{} bash "$DSW_HOME/share/dsw_fcl_worker.sh" "$fc_sub" "$fc_out" {} \
    < "$list" | sort -k2 > "$fc_out/summary.txt"
  grep -v '^OK' "$fc_out/summary.txt"
  local nok
  nok=$(grep -c '^OK' "$fc_out/summary.txt")
  echo "$nok OK / $total files  (summary: $fc_out/summary.txt)"
  [ "$nok" -eq "$total" ]
}
