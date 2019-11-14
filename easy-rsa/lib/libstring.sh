#!/bin/sh

# Requires: tr(1), sed(1), expr(1)

[ -z "${__libstring_sh__-}" ] || return 0
__libstring_sh__=1

# Source functions libraries
. "$EASY_RSA/lib/librtti.sh"

# Usage: toupper() <str> [<var_result>]
toupper()
{
	local func="${FUNCNAME:-toupper}"

	local u_str="${1:?missing 1st arg to ${func}() (<str>)}"

	u_str="$(echo "${u_str}" | tr '[:lower:]' '[:upper:]')" || return

	return_var 0 "${u_str}" "${2-}"
}

# Usage: tolower() <str> [<var_result>]
tolower()
{
	local func="${FUNCNAME:-tolower}"

	local l_str="${1:?missing 1st arg to ${func}() (<str>)}"

	l_str="$(echo "${l_str}" | tr '[:upper:]' '[:lower:]')" || return

	return_var 0 "${l_str}" "${2-}"
}

# Usage: substr <str> [<pos>] [<len>] [<substr_var>]
substr()
{
	local func="${FUNCNAME:-substr}"

	local str="${1:?missing 1st arg to ${func}() <str>}"
	local pos="${2-}"
	local len="${3-}"
	local substr_var="${4:-substr}"
	local strlen="${#str}"

	[ "$pos" -gt 0 -a "$pos" -le $strlen ] 2>/dev/null || pos=1
	strlen=$((strlen - pos + 1))
	[ "$len" -gt 0 -a "$len" -le $strlen ] 2>/dev/null || len=$strlen

	eval "$substr_var='$(expr substr "$str" $pos $len)'"
	eval "next_pos=$((pos + len))"
}

# Usage: __stripdir__=[#%] _strstrip <str> [chars]
_strstrip()
{
	local func="${func:-_strstrip}"

	local str="${1:?missing 1st arg to ${func}() (<str>)}"
	local chars="${2:-
	 }"

	local prev_str="$str"

	while :; do
		eval "str=\"\${str${__stripdir__}[\$chars]}\""
		[ "$str" != "$prev_str" ] || break
		prev_str="$str"
	done

	return_var 0 "$str" '__stripret__'
}

# Usage: strlstrip <str> [chars] [<var_result>]
strlstrip()
{
	local func="${FUNCNAME:-strlstrip}"
	local __stripdir__='#'
	local __stripret__

	_strstrip "$@" || return

	return_var 0 "${__stripret__}" "${3-}"
}

# Usage: strrstrip <str> [chars] [<var_result>]
strrstrip()
{
	local func="${FUNCNAME:-strrstrip}"
	local __stripdir__='%'
	local __stripret__

	_strstrip "$@" || return

	return_var 0 "${__stripret__}" "${3-}"
}

# Usage: strstrip <str> [chars] [<var_result>]
strstrip()
{
	local func="${FUNCNAME:-strstrip}"
	local __stripdir__
	local __stripret__

	__stripdir__='#' && _strstrip "$@" || return

	shift && set -- "${__stripret__}" "$@"

	__stripdir__='%' && _strstrip "$@" || return

	return_var 0 "${__stripret__}" "${3-}"
}

# Usage: make_shlvar_name <str> [<var_result>]
make_shlvar_name()
{
	local func="${FUNCNAME:-make_shlvar_name}"

	local msn_str="${1:?missing 1st arg to ${func}() (<str>)}"

	msn_str="$(
	    echo "$msn_str" | sed -e 's/\W/_/g' -e 's/^[0-9]/_/'
	)" || return

	return_var 0 "$msn_str" "${2-}"
}

# Usage: make_envvar_name() <str> [<var_result>]
make_envvar_name()
{
	local func="${FUNCNAME:-make_envvar_name}"

	local men_str="${1:?missing 1st arg to ${func}() (<str>)}"

	make_shlvar_name "$men_str" men_str && \
		 toupper "$men_str" men_str || return

	return_var 0 "$men_str" "${2-}"
}
