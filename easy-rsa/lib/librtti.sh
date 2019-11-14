#!/bin/sh

# Requires: env(1), id(1), hostname(1), sudo(8)

[ -z "${__librtti_sh__-}" ] || return 0
__librtti_sh__=1

# Helpers providing additional functionality or compatibility

true()  {   :; }
false() { ! :; }

# Usage: return_var() <rc> <result> [<var>]
return_var()
{
	local func="${FUNCNAME:-return_var}"

	local rv_rc="${1:?missing 1st arg to ${func}() (<rc>)}"
	local rv_result="${2-}"
	local rv_var="${3-}"

	if [ -n "${rv_var}" ]; then
		eval "${rv_var}='${rv_result}'"
	else
		echo "${rv_result}"
	fi

	return ${rv_rc}
}

# Usage: error <fmt> ...
error()
{
	local rc=$?

	local func="${FUNCNAME:-error}"

	local fmt="${1:?missing 1st arg to ${func}() (<fmt>)}"
	shift

	[ $V -le 0 ] || printf >&2 -- "${fmt}" "$@"

	return $rc
}

# Usage: error_exit
error_exit()
{
	error "$@" || exit
}

# Usage: fatal <fmt> ...
fatal()
{
	error "$@"
	exit
}

# Usage: env_call [NAME=VAL...] [options] [--] <command> [<args>...]
env_call()
{
	local func="${FUNCNAME:-env_call}"

	local n v q runas= exec= rc=0
	local env_vars='' env_list=''

	# Add from current environment
	for v in \
		${PATH:+PATH='$PATH'}             \
		${TERM:+TERM='$TERM'}             \
		${LOGNAME:+LOGNAME='$LOGNAME'}    \
		${USER:+USER='$USER'}             \
		${USERNAME:+USERNAME='$USERNAME'} \
		${HOSTNAME:+HOSTNAME='$HOSTNAME'} \
		${HOME:+HOME='$HOME'}             \
		${SHELL:+SHELL='$SHELL'}          \
		${MAIL:+MAIL='$MAIL'}             \
		${LANG:+LANG='$LANG'}             \
		${LANGUAGE:+LANGUAGE='$LANGUAGE'} \
		${LC_ALL:+LC_ALL='$LC_ALL'}       \
		${LC_CTYPE:+LC_CTYPE='$LC_CTYPE'} \
		#
	do
		env_vars="${env_vars} ${v}"
	done

	# Add from command line
	while [ $# -gt 0 ]; do
		case "$1" in
			*=*)
				n="${1%%=*}"
				if [ -n "${n##*[^[:alnum:]_]*}" ]; then
					v="${1#$n=}"
					[ -z "${v##[\'\"]*}" ] && q='' || q=\'
					env_vars="${env_vars} $n=$q$v$q"
					env_list="${env_list:+${env_list},}$n"
				fi
				;;
			--runas)
				shift && runas="${1##*\'*}"
				;;
			--exec)
				exec='exec'
				;;
			--)
				shift
				break
				;;
			*)
				break
				;;
		esac
		shift
	done

	if [ -z "$runas" -o "$runas" = "$(id -u -n)" ]; then
		runas='"$@"'
	else
		# Environment cannot be preserved with -i (login shell) sudo(8)
		# option. Instead use -s|--shell sudo(8) option and shell
		# interpreter 'exec' as command to re-start interpreter with -l
		# option before running actual command via -c.
		runas="sudo -u '$runas' --preserve-env='${env_list}' -s -- \
		       exec '\$0' -l -c '"
		# Command to be executed via -c is a concatenation of remaining
		# arguments to sudo(8) after '--'. Chars in command string that
		# does not match regular expression [[:alnum:]_$-] are escaped
		# with '\', space is used as separator of argument strings.
		while [ $# -gt 0 ]; do
			if [ -n "${1##*\'*}" ]; then
				runas="$runas '\''$1'\''"
			fi
			shift
		done
		runas="${runas}'"
	fi

	eval ${exec} env -i ${env_vars} ${runas} || rc=$?

	[ $rc -eq 0 ] || [ -z "${exec}" ] || exit $rc

	return $rc
}

# Usage: env_run [NAME=VAL...] [options] [--] <command> [<args>...]
env_run()
{
	env_call "$@"
}

# Usage: env_exec [NAME=VAL...] [options] [--] <command> [<args>...]
env_exec()
{
	env_call --exec "$@"
}

# Usage: abort <fmt> ...
abort()
{
	local rc=$?
	trap - EXIT
	V=1 error "$@"
	exit $rc
}

# Usage: _exit [<rc>]
_exit()
{
	local _rc=$?
	trap - EXIT
	local rc="${1:-${_rc}}"
	[ "$rc" -ge 0 -o "$rc" -lt 0 ] 2>/dev/null || rc=${_rc}
	exit $rc
}

################################################################################

# Verbosity: report errors by default
V=1

# Make sure critical environment variables are set
export USER="${USER:-$(id -u -n 2>/dev/null)}"
export HOSTNAME="$(hostname -f)"
