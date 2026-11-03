# backtrace.gdb — run a program under gdb in batch mode; on a crash, print backtraces
# of all threads.
# usage: dsw exec gdb -batch -x <dsw>/share/gdb/backtrace.gdb --args lar -c job.fcl in.root -n 5
set pagination off
set confirm off
set print thread-events off
# art and ROOT use these signals internally; don't stop on them
handle SIGPIPE nostop noprint pass
handle SIG32 nostop noprint pass
handle SIG33 nostop noprint pass
run
echo \n===== backtrace (all threads) =====\n
thread apply all bt
echo \n===== frame 0..3 locals =====\n
bt full 4
quit
