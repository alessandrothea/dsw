# Source to put dsw on PATH:  source <path>/dsw/setup_env.sh
_HERE_=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
case ":$PATH:" in *":$_HERE_/bin:"*) ;; *) export PATH="$_HERE_/bin:$PATH" ;; esac
unset _HERE_
