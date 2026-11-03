#!/bin/bash
# Worker for `dsw fcl-check`: checks ONE fcl file and prints one summary line.
# usage: dsw_fcl_worker.sh construct|dump <outdir> <fcl-name>
# Runs inside the dsw run environment (fcl names resolve via FHICL_FILE_PATH, i.e. the
# INSTALLED fcl files).
mode=$1 out=$2 fcl=$3
case $mode in
  construct)
    # Build every module of the job: lar on an EmptyEvent source with 0 events. Catches
    # missing required keys, wrong module/tool names, bad includes.
    d=$out/${fcl%.fcl}
    mkdir -p "$d" && cd "$d" || { echo "FAIL $fcl cannot create $d"; exit 0; }
    printf '#include "%s"\nsource: { module_type: EmptyEvent maxEvents: 0 }\n' "$fcl" > construct.fcl
    lar -c construct.fcl -n 0 > lar.log 2>&1
    rc=$?
    if [ $rc -eq 0 ]; then
      echo "OK   $fcl"
    else
      where=$(grep -oE '[A-Za-z]+:[A-Za-z0-9_]+@Construction' lar.log | head -1)
      why=$(sed -n '/cet::exception caught/,$p' lar.log \
              | grep -v -e 'cet::exception caught' -e '^ *----' -e '^ *$' | head -1 | sed 's/^ *//')
      [ -n "$why" ] || why=$(grep -m1 -iE 'error|exception' lar.log | sed 's/^ *//')
      echo "FAIL $fcl rc=$rc ${where:+$where }$why"
    fi
    ;;
  dump)
    if fhicl-dump "$fcl" > "$out/$fcl.dump" 2> "$out/$fcl.err"; then
      echo "OK   $fcl"
    else
      echo "FAIL $fcl $(grep -m1 -v '^\s*$' "$out/$fcl.err")"
    fi
    ;;
  *) echo "FAIL $fcl unknown mode $mode" ;;
esac
exit 0
