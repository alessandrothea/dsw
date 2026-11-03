# dsw-common.sh — shared functions for dsw. Sourced, not executed.
# Works on the host (AlmaLinux 9) and inside the SL7 container.

DSW_DEFAULT_PRODUCT=dunesw
DSW_DEFAULT_UPS_OVERRIDE="-H Linux64bit+3.10-2.17"
DSW_DEFAULT_IMAGE=/cvmfs/unpacked.cern.ch/registry.hub.docker.com/fermilab/fnal-dev-sl7:latest
DSW_APPTAINER=/cvmfs/oasis.opensciencegrid.org/mis/apptainer/current/bin/apptainer
DSW_DUNE_SETUP=/cvmfs/dune.opensciencegrid.org/products/dune/setup_dune.sh
# Bound only if they exist on the host.
DSW_BIND_CANDIDATES="/cvmfs /opt /eos /afs /run/user /etc/hostname /etc/hosts /etc/krb5.conf /tmp"

dsw_die() { echo "dsw: $*" >&2; exit 2; }
dsw_msg() { echo "dsw: $*" >&2; }

# An MRB area has srcs/ and exactly one localProducts_*/setup.
dsw_is_area() {
  local d=$1 lp
  [ -d "$d/srcs" ] || return 1
  lp=( "$d"/localProducts_*/setup )
  [ ${#lp[@]} -eq 1 ] && [ -f "${lp[0]}" ]
}

# Area lookup: $DSW_AREA, else nearest ancestor of $PWD that is an area,
# else nearest ancestor with exactly one child that is an area.
dsw_find_area() {
  if [ -n "${DSW_AREA:-}" ]; then
    dsw_is_area "$DSW_AREA" || dsw_die "DSW_AREA=$DSW_AREA is not an MRB area (needs srcs/ and localProducts_*/setup)"
    readlink -f "$DSW_AREA"; return 0
  fi
  local d c hits
  d=$(pwd -P)
  while :; do
    if dsw_is_area "$d"; then echo "$d"; return 0; fi
    hits=()
    for c in "$d"/*/; do
      c=${c%/}
      dsw_is_area "$c" && hits+=("$c")
    done
    if [ ${#hits[@]} -eq 1 ]; then echo "${hits[0]}"; return 0; fi
    if [ ${#hits[@]} -gt 1 ]; then
      dsw_die "several MRB areas under $d: ${hits[*]##*/} — pick one with -C <area> or DSW_AREA"
    fi
    [ "$d" = "/" ] && break
    d=$(dirname "$d")
  done
  dsw_die "no MRB area found above $(pwd) — use -C <area> or DSW_AREA"
}

# Reads a value set by `setenv KEY "VALUE"` in the localProducts setup file.
dsw_lp_value() {
  sed -n "s/^setenv $2 \"\(.*\)\"$/\1/p" "$1" | head -1
}

# Fills DSW_* variables for area $1: localProducts setup, then .dsw.conf overrides.
# .dsw.conf is parsed (KEY=VALUE lines), never sourced.
dsw_load_area() {
  local area=$1 lp
  lp=( "$area"/localProducts_*/setup ); lp=${lp[0]}
  DSW_AREA=$area
  DSW_LP_SETUP=$lp
  DSW_PRODUCT=$DSW_DEFAULT_PRODUCT
  DSW_VERSION=$(dsw_lp_value "$lp" MRB_PROJECT_VERSION)
  DSW_QUALS=$(dsw_lp_value "$lp" MRB_QUALS)
  DSW_UPS_OVERRIDE=$DSW_DEFAULT_UPS_OVERRIDE
  DSW_IMAGE=$DSW_DEFAULT_IMAGE
  DSW_EXTRA_BINDS=
  DSW_VENV=auto
  DSW_SHELL_RC=on
  local conf=$area/.dsw.conf key val
  if [ -f "$conf" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line=${line%%#*}
      [[ $line =~ ^[[:space:]]*([A-Z_]+)[[:space:]]*=[[:space:]]*(.*[^[:space:]])?[[:space:]]*$ ]] || continue
      key=${BASH_REMATCH[1]}; val=${BASH_REMATCH[2]}
      val=${val#\"}; val=${val%\"}
      case $key in
        PRODUCT) DSW_PRODUCT=$val ;;
        VERSION) DSW_VERSION=$val ;;
        QUALS) DSW_QUALS=$val ;;
        UPS_OVERRIDE) DSW_UPS_OVERRIDE=$val ;;
        IMAGE) DSW_IMAGE=$val ;;
        EXTRA_BINDS) DSW_EXTRA_BINDS=$val ;;
        VENV) DSW_VENV=$val ;;
        SHELL_RC) DSW_SHELL_RC=$val ;;
        *) dsw_msg "warning: unknown key $key in $conf" ;;
      esac
    done < "$conf"
  fi
  [ -n "$DSW_VERSION" ] || dsw_die "cannot read MRB_PROJECT_VERSION from $lp; set VERSION in $conf"
  [ -n "$DSW_QUALS" ] || dsw_die "cannot read MRB_QUALS from $lp; set QUALS in $conf"
}

# True when running inside an SL7 userland (the container, or a native SL7 host).
# Clean-room ROOT inside the run environment: drop every library dir that carries
# experiment .rootmap files (ROOT's dictionary autoload) except ROOT's own, and the
# experiment headers. ROOT still works, but knows only its own classes.
dsw_clean_room() {
  local d keep=()
  for d in ${LD_LIBRARY_PATH//:/ }; do
    if [ "$d" != "$ROOTSYS/lib" ] && compgen -G "$d/*.rootmap" > /dev/null; then continue; fi
    keep+=("$d")
  done
  LD_LIBRARY_PATH=$(IFS=:; echo "${keep[*]}")
  export LD_LIBRARY_PATH
  unset ROOT_INCLUDE_PATH
  export DSW_CLEAN_ROOM=1
}

# Replaces this process with `apptainer exec <image> $DSW_SELF "$@"`, binding the
# default paths that exist plus $DSW_EXTRA_BINDS. Uses $DSW_IMAGE (default if unset).
dsw_reexec_in_container() {
  [ -x "$DSW_APPTAINER" ] || dsw_die "apptainer not found at $DSW_APPTAINER (is /cvmfs mounted?)"
  local b binds=() bind_arg
  for b in $DSW_BIND_CANDIDATES ${DSW_EXTRA_BINDS//,/ }; do
    [ -e "$b" ] && binds+=("$b")
  done
  bind_arg=$(IFS=,; echo "${binds[*]}")
  exec "$DSW_APPTAINER" exec -B "$bind_arg" --ipc --pid "${DSW_IMAGE:-$DSW_DEFAULT_IMAGE}" "$DSW_SELF" "$@"
}

dsw_in_sl7() {
  [ -n "${APPTAINER_CONTAINER:-}${SINGULARITY_CONTAINER:-}" ] && return 0
  grep -qE 'release 7' /etc/redhat-release 2>/dev/null
}

# Environment setup for the loaded area, in one of two modes:
#   run   (default; everything incl. incremental `build`):
#          setup_dune.sh -> setup <product> <ver> -q <quals> -> localProducts setup
#          -> mrbslp -> .venv (if present)
#   build (only `fullbuild`): setup_dune.sh -> localProducts setup
#          [-> mrb uc -> mrb z -> mrb zd, if DSW_CLEAN=1] -> mrbsetenv
# Quiet: setup output goes to a temporary log that is printed only on failure.
_dsw_setup_common() {
  DSW_STEP="source $DSW_DUNE_SETUP"
  [ -f "$DSW_DUNE_SETUP" ] || { echo "missing $DSW_DUNE_SETUP (is /cvmfs mounted?)"; return 1; }
  source "$DSW_DUNE_SETUP" || return 1
}

_dsw_setup_run_steps() {
  _dsw_setup_common || return 1
  DSW_STEP="setup $DSW_PRODUCT $DSW_VERSION -q $DSW_QUALS"
  setup "$DSW_PRODUCT" "$DSW_VERSION" -q "$DSW_QUALS" || return 1
  DSW_STEP="source $DSW_LP_SETUP"
  source "$DSW_LP_SETUP" || return 1
  # mrbslp's return code is unreliable (1 even on success), so check its effect:
  # every product installed in the area must now be set up.
  DSW_STEP="mrbslp"
  mrbslp
  local p var missing=
  for p in "$MRB_INSTALL"/*/; do
    p=${p%/}; p=${p##*/}
    [[ $p =~ ^[A-Za-z][A-Za-z0-9_]*$ ]] || continue
    var=SETUP_$(echo "$p" | tr '[:lower:]' '[:upper:]')
    [ -n "${!var:-}" ] || missing="$missing $p"
  done
  [ -z "$missing" ] || { echo "local products not set up:$missing"; return 1; }
}

_dsw_setup_build_steps() {
  _dsw_setup_common || return 1
  DSW_STEP="source $DSW_LP_SETUP"
  source "$DSW_LP_SETUP" || return 1
  # fullbuild --clean (DSW_CLEAN=1): regenerate srcs/CMakeLists.txt and wipe the build
  # and install dirs before mrbsetenv. stdin is /dev/null so a prompt fails, not hangs.
  if [ "${DSW_CLEAN:-0}" = 1 ]; then
    DSW_STEP="mrb uc"; mrb uc < /dev/null || return 1
    DSW_STEP="mrb z";  mrb z  < /dev/null || return 1
    DSW_STEP="mrb zd"; mrb zd < /dev/null || return 1
  fi
  # mrbsetenv rewrites cetpkg_info.sh, table_deps_* etc. in the build dir (CMake
  # inputs), so it is used only by fullbuild, which reconfigures anyway.
  DSW_STEP="mrbsetenv"
  local rc
  pushd "$DSW_AREA" > /dev/null || return 1
  mrbsetenv
  rc=$?
  popd > /dev/null
  [ $rc -eq 0 ] || return 1
  [ -n "${CETPKG_BUILD:-}" ] || { echo "mrbsetenv did not set CETPKG_BUILD"; return 1; }
}

dsw_setup() {
  local mode=${1:-run} log rc
  if [ "${DSW_SETUP_DONE:-}" = "$DSW_AREA:$mode" ]; then return 0; fi
  log=$(mktemp "${TMPDIR:-/tmp}/dsw-setup.XXXXXX")
  export UPS_OVERRIDE=$DSW_UPS_OVERRIDE
  case $mode in
    run)   _dsw_setup_run_steps > "$log" 2>&1 ;;
    build) _dsw_setup_build_steps > "$log" 2>&1 ;;
    *)     echo "unknown setup mode $mode" > "$log"; false ;;
  esac
  rc=$?
  if [ $rc -ne 0 ]; then
    dsw_msg "environment setup ($mode) failed at: $DSW_STEP"
    sed 's/^/  | /' "$log" | tail -40 >&2
    rm -f "$log"; return 1
  fi
  rm -f "$log"
  if [ "$mode" = run ]; then
    if [ "$DSW_VENV" != "0" ] && [ "$DSW_VENV" != "off" ] && [ -f "$DSW_AREA/.venv/bin/activate" ]; then
      source "$DSW_AREA/.venv/bin/activate"
    elif [ "$DSW_VENV" = "1" ] || [ "$DSW_VENV" = "on" ]; then
      dsw_msg "VENV=on but $DSW_AREA/.venv/bin/activate does not exist"; return 1
    fi
  fi
  export DSW_SETUP_DONE=$DSW_AREA:$mode
}
