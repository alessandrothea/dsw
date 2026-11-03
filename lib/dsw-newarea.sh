# dsw-newarea.sh — `dsw newarea`: create a new MRB development area. Sourced by bin/dsw,
# runs inside the SL7 container. Replaces dunetrg-pipes/scripts/create_larsoft_area.sh
# (which is kept for now), but uses git clone + mrb uc instead of mrb g, and stops on
# the first failure.

dsw_newarea_usage() {
  cat <<'EOF'
usage: dsw newarea -v <version> [-q <quals>] [-p <git-url>[#<ref>]]... [--requirements <file>]
                   [--no-venv] [--no-build] [-j N] <dir>

  -v, --version VERSION    dunesw version, e.g. v10_26_00d05 (required)
  -q, --qualifiers QUALS   qualifiers (default e26:prof)
  -p, --package URL[#REF]  git clone URL into srcs/ and check out REF (branch or tag) if
                           given; repeatable. srcs/CMakeLists.txt is regenerated (mrb uc).
  --requirements FILE      pip install -r FILE into the area's .venv
  --no-venv                don't create .venv
  --no-build               don't run `dsw fullbuild` at the end
  -j N                     parallel jobs for the first build (default nproc)
  <dir>                    the new area (must not exist)

Steps: setup dunesw → mrb newDev → .venv [+ pip] → setup_dunesw.sh, lar_wrap.sh,
dunesw_wrap.sh (for the condor tooling) → git clone packages → mrb uc → dsw fullbuild
(only if packages were given). Stops at the first failure; the partial area is left in
place for inspection.
EOF
}

dsw_newarea() {
  local na_version= na_quals=e26:prof na_reqs= na_venv=1 na_build=1 na_jobs na_dir= na_pkgs=()
  na_jobs=$(nproc)
  while [ $# -gt 0 ]; do
    case $1 in
      -v|--version)    [ $# -ge 2 ] || dsw_die "$1 needs a value"; na_version=$2; shift 2 ;;
      -q|--qualifiers) [ $# -ge 2 ] || dsw_die "$1 needs a value"; na_quals=$2; shift 2 ;;
      -p|--package)    [ $# -ge 2 ] || dsw_die "$1 needs a value"; na_pkgs+=("$2"); shift 2 ;;
      --requirements)  [ $# -ge 2 ] || dsw_die "$1 needs a value"; na_reqs=$(readlink -f "$2"); shift 2
                       [ -f "$na_reqs" ] || dsw_die "requirements file not found: $na_reqs" ;;
      --no-venv)       na_venv=0; shift ;;
      --no-build)      na_build=0; shift ;;
      -j)              [ $# -ge 2 ] || dsw_die "-j needs a number"; na_jobs=$2; shift 2 ;;
      -h|--help)       dsw_newarea_usage; return 0 ;;
      -*)              dsw_die "newarea: unknown option $1 (see dsw newarea -h)" ;;
      *)               [ -z "$na_dir" ] || dsw_die "newarea: only one <dir> allowed"; na_dir=$1; shift ;;
    esac
  done
  [ -n "$na_version" ] || dsw_die "newarea: -v <version> is required (see dsw newarea -h)"
  [ -n "$na_dir" ] || dsw_die "newarea: <dir> is required (see dsw newarea -h)"
  na_dir=$(readlink -m "$na_dir")
  [ -e "$na_dir" ] && dsw_die "newarea: $na_dir already exists"
  [ -n "$na_reqs" ] && [ "$na_venv" = 0 ] && dsw_die "newarea: --requirements needs the venv (drop --no-venv)"

  _na_step() { DSW_STEP="$*"; echo "dsw: >> $*" >&2; }
  _na_fail() {
    dsw_msg "newarea failed at: $DSW_STEP"
    [ -d "$na_dir" ] && dsw_msg "the partial area is left in $na_dir (remove it before retrying)"
    exit 1
  }

  export UPS_OVERRIDE=$DSW_DEFAULT_UPS_OVERRIDE
  _na_step "source $DSW_DUNE_SETUP"
  source "$DSW_DUNE_SETUP" > /dev/null 2>&1 || _na_fail
  _na_step "setup dunesw $na_version -q $na_quals"
  setup dunesw "$na_version" -q "$na_quals" || {
    dsw_msg "dunesw $na_version -q $na_quals is not available (list: ups list -aK+ dunesw)"; _na_fail; }

  _na_step "mkdir $na_dir"
  mkdir -p "$na_dir" && cd "$na_dir" || _na_fail
  _na_step "mrb newDev -v $na_version -q $na_quals"
  mrb newDev -v "$na_version" -q "$na_quals" || _na_fail

  if [ "$na_venv" = 1 ]; then
    _na_step "python -m venv .venv ($(python --version 2>&1))"
    python -m venv .venv || _na_fail
    if [ -n "$na_reqs" ]; then
      _na_step "pip install -r $na_reqs"
      .venv/bin/pip install -r "$na_reqs" || _na_fail
    fi
  fi

  # Same files as create_larsoft_area.sh: the condor tooling sources setup_dunesw.sh and
  # the cards point at lar_wrap.sh. dsw itself does not use them.
  _na_step "write setup_dunesw.sh, lar_wrap.sh, dunesw_wrap.sh"
  cat > setup_dunesw.sh <<EOF || _na_fail
#!/bin/bash

HERE=\$(cd \$(dirname \$(readlink -f \${BASH_SOURCE})) && pwd)

export DUNESW_VERSION=${na_version}  # Version of the software to be used
export DUNESW_QUALS=${na_quals}  # Qualifiers for the software packages
export UPS_OVERRIDE="${DSW_DEFAULT_UPS_OVERRIDE}"

# Source the setup script for the DUNE software
source ${DSW_DUNE_SETUP}

# Setup the specific version of the DUNE software
setup dunesw ${na_version} -q ${na_quals}

# Source the setup script for the local products associated to the development area
source \${HERE}/localProducts_larsoft_*/setup

# Set up the MRB source local products
mrbslp

# Activate the virtual environment
[ -f \${HERE}/.venv/bin/activate ] && source \${HERE}/.venv/bin/activate

# Cleanup
unset HERE

#
alias dsb='ninja -C \${MRB_BUILDDIR} -k 0 install | grep -v "Up-to-date" '
EOF
  local na_w
  for na_w in lar_wrap.sh dunesw_wrap.sh; do
    {
      echo '#!/bin/bash'
      echo
      echo 'HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE})) && pwd)'
      echo
      echo 'source ${HERE}/setup_dunesw.sh'
      if [ $na_w = lar_wrap.sh ]; then echo 'exec lar "$@"'; else echo 'exec "$@"'; fi
    } > $na_w || _na_fail
  done
  chmod a+x setup_dunesw.sh lar_wrap.sh dunesw_wrap.sh || _na_fail

  local na_lp
  na_lp=( localProducts_*/setup )
  _na_step "source ${na_lp[0]}"
  [ ${#na_lp[@]} -eq 1 ] && [ -f "${na_lp[0]}" ] || { dsw_msg "expected one localProducts_*/setup"; _na_fail; }
  source "${na_lp[0]}" > /dev/null || _na_fail

  local na_spec na_url na_ref na_name
  for na_spec in "${na_pkgs[@]}"; do
    na_url=${na_spec%%#*}; na_ref=
    [[ $na_spec == *#* ]] && na_ref=${na_spec#*#}
    na_name=$(basename "$na_url" .git)
    _na_step "git clone $na_url srcs/$na_name${na_ref:+ (ref $na_ref)}"
    git clone "$na_url" "srcs/$na_name" || _na_fail
    if [ -n "$na_ref" ]; then
      git -C "srcs/$na_name" checkout "$na_ref" || _na_fail
    fi
  done
  if [ ${#na_pkgs[@]} -gt 0 ]; then
    _na_step "mrb uc"
    mrb uc < /dev/null || _na_fail
  fi

  dsw_msg "area created: $na_dir"
  if [ ${#na_pkgs[@]} -eq 0 ]; then
    dsw_msg "no packages given: add some under srcs/ (then mrb uc), then: dsw -C $na_dir fullbuild"
    return 0
  fi
  if [ "$na_build" = 0 ]; then
    dsw_msg "skipping the build (--no-build); later: dsw -C $na_dir fullbuild"
    return 0
  fi
  # Start the build from a clean environment: this shell has the run setup (setup dunesw)
  # loaded, and fullbuild sets up the build environment (mrbsetenv) itself.
  _na_step "dsw fullbuild -j $na_jobs"
  exec env -i HOME="$HOME" USER="${USER:-}" LOGNAME="${LOGNAME:-}" TERM="${TERM:-dumb}" \
    LANG="${LANG:-C}" PATH=/usr/bin:/bin TMPDIR="${TMPDIR:-/tmp}" \
    ${SSH_AUTH_SOCK:+SSH_AUTH_SOCK="$SSH_AUTH_SOCK"} ${KRB5CCNAME:+KRB5CCNAME="$KRB5CCNAME"} \
    ${APPTAINER_CONTAINER:+APPTAINER_CONTAINER="$APPTAINER_CONTAINER"} \
    "$DSW_SELF" -C "$na_dir" fullbuild -j "$na_jobs"
}
