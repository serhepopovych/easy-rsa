#!/bin/sh

# Requires: tr(1), head(1)

[ -z "${__libpwquality_sh__-}" ] || return 0
__libpwquality_sh__=1

# Usage: pw_valid <passphrase>
pw_valid()
{
	local pp="${1-}"

	[ -n "${pp##*passphrase*}" ] &&
	[ -n "${pp#*[\"\'\\&|]*}" ] || return
}

# Usage: pw_good [<passphrase>] [<min_length>] [<opts>]
pw_good()
{
	local pp="${1-}"

	pw_valid "$pp" || return 1

	# at least $mlen symbols
	local mlen="${2-0}" _mlen=8
	[ "${mlen}" -ge ${_mlen} ] 2>/dev/null || mlen=${_mlen}

	[ ${#pp} -ge $mlen ] || return $mlen

	local _opts='ludp'
	local opts
	opts="${3-${_opts}}"            # omitted          : default
	opts="${opts:-x}"               # given, but empty : skip all
	opts="${opts##*[^LlUuDdPpXx]*}" # given, not valid : default
	opts="${opts:-${_opts}}"

	# at least one lower case letter
	[ -n "${opts##*[Ll]*}" ] || [ -z "${pp##*[[:lower:]]*}" ] || return 1
	# at least one upper case letter
	[ -n "${opts##*[Uu]*}" ] || [ -z "${pp##*[[:upper:]]*}" ] || return 1
	# at least one digit
	[ -n "${opts##*[Dd]*}" ] || [ -z "${pp##*[[:digit:]]*}" ] || return 1
	# at least one special symbol
	[ -n "${opts##*[Pp]*}" ] || [ -z "${pp##*[[:punct:]]*}" ] || return 1

	# Common patterns (e.g. 123, abc, Abc, xYz, etc)
	# Simple dictionary checks
	# ...

	return 0
}

# Usage: pw_make [<length>]
pw_make()
{
	local plen=${1:-64}

	local t max_attempts=8
	while [ $((max_attempts -= 1)) -ge 0 ]; do
		# Try password from system pseudo-random generator
		t="$(
			tr -dc '[:graph:]' </dev/urandom | \
			tr -d '[\"'\''\\&|]' | head -c $plen
			echo
		)" || continue

		# Check it's quality
		if pw_good "$t" $plen; then
			echo "$t"
			return 0
		else
			t=$? && [ $t -le 1 ] || plen=$t
		fi
	done

	return 1
}
