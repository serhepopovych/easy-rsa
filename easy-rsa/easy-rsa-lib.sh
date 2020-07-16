#!/bin/sh

# Requires: cat(1), mv(1), rm(1), chmod(1), awk(1), tr(1), head(1)

[ -z "${__easy_rsa_lib_sh__-}" ] || return 0
__easy_rsa_lib_sh__=1

# Source functions libraries
. "$EASY_RSA/lib/librtti.sh"
. "$EASY_RSA/lib/libstring.sh"
. "$EASY_RSA/lib/libfile.sh"
. "$EASY_RSA/lib/libopenssl.sh"
. "$EASY_RSA/lib/libutil.sh"

# Usage: make_bundle <dir> <file> <bundle> [<force>]
make_bundle()
{
	local func="${FUNCNAME:-make_bundle}"

	local dir="${1:?missing 1st arg to ${func}() (<dir>)}"
	local file="${2:?missing 2d arg to ${func}() (<file>)}"
	local bundle="${3:?missing 3d arg to ${func}() (<bundle>)}"
	local force="$4"

	local bundle_tmp bundle_name rc=0 oldpwd="${PWD}"

	cd "${dir}" || return

	# make sure <bundle> is absolute path if not so
	# and initialize temporary bundle file
	if  bundle="$(readlink -m "${bundle}")" && \
	    bundle_tmp="$(mktemp "${bundle}.XXXXXXXX")"; then
		bundle_name="${bundle##*/}"
	else
		rc=$?
		cd "${oldpwd}" ||:
		return $rc
	fi

	while :; do
		# it is supposed to be a symlink to parent <dir> with <file>
		[ -L 'parent' ] || break

		# we care about symlink pointing to '.' in all variations
		[ ! 'parent' -ef '.' ] || break

		# kernel care about broken or recusive symlinks
		cd 'parent' || break

		# optimization: use <bundle> if it is valid
		if [ -z "$force"] && (V=0 valid_file "${bundle_name}"); then
			cat "${bundle_name}" >"${bundle_tmp}" ||:
			cd .. ||:
			break
		fi
	done

	# concatenate <file> from root to <dir>
	while :; do
		# <file> is optional
		cat "${file}" >>"${bundle_tmp}" ||:

		# stop at <dir>
		[ ! '.' -ef "${dir}" ] || break

		if cd ..; then
			continue
		else
			rc=$?
			cd "${oldpwd}" ||:
			# race with directory removal: no partial bundle
			rm -f "${bundle_tmp}" ||:
			return $rc
		fi
	done

	# atomically replace bundle with new: cleanup on error
	mv -f "${bundle_tmp}" "${bundle}" && chmod -f go+r "${bundle}" || \
		rc=$? && rm -f "${bundle_tmp}" ||:

	cd "${oldpwd}" ||:

	return $rc
}

# Usage: unmake_bundle <dir> <file> <bundle>
unmake_bundle()
{
	local func="${FUNCNAME:-unmake_bundle}"

	local dir="${1:?missing 1st arg to ${func}() (<dir>)}"
	local file="${2:?missing 2d arg to ${func}() (<file>)}"
	local bundle="${3:?missing 3d arg to ${func}() (<bundle>)}"

	local rc=0 oldpwd="${PWD}" f

	cd "${dir}" || return

	# rfc7468
	# 2. General considerations
	awk -vc=0 -vfile="${file}" '
		/^-----BEGIN [A-Z0-9 ]+-----$/ {c++}
		{print > file c ".pem"}' \
		"${bundle}" || rc=$?

	cd "${oldpwd}" ||:

	return $rc
}

# Usage: for_each_user_ca ...
for_each_user_ca()
{
	local func="${FUNCNAME:-for_each_user_ca}"

	: "${EASY_RSA:?calling of ${func}() requires \$EASY_RSA to be defined}"

	# Usage: do_exec_ca <line> ...
	do_exec_ca()
	{
		local line="${1:?missing 1st arg to do_exec_ca() (<line>)}"
		shift

		local IN_EXEC_CA VARS_DIR
		local ca u="${line%%:*}" rc=0

		eval "VARS_DIR=~$u/easy-rsa" && [ -d "$VARS_DIR" ] || continue

		for ca in "$VARS_DIR/vars-"*; do
			# Skip backups
			[ -n "${ca##*\~}" -a -n "${ca##\#*\#}" ] || continue
			# File is readable
			[ -f "$ca" -a -r "$ca" ] || continue

			IN_EXEC_CA="${ca##*/vars-}"

			# Restart itself with clean environment
			env_run --runas "$u" \
				"IN_EXEC_CA=$IN_EXEC_CA" \
				"EASY_RSA=$EASY_RSA" \
				"VARS_DIR=$VARS_DIR" \
				-- "$0" "$@" ||
			rc=$((rc + $?))
		done

		return $rc
	}
	for_each_passwd '-1' '-1' 'do_exec_ca' "$@"
}

# Usage: pwmake [<length>]
pwmake()
{
	tr -dc '[:graph:]' </dev/urandom | \
	tr -d '[\"'\''\\&|]' | head -c "${1:-64}"
	echo
}

################################################################################

# Set program name
[ -n "${prog_name-}" ] || prog_name="${0##*/}"

# Set program (Easy-RSA bundle) version
prog_version='2.7'

# Safe umask
umask $(printf -- '%04o\n' $(($(umask) | 0022))) ||:

# Check for environment variables file correctness
[ -n "$KEY_DIR" ] ||
    abort 'easy-rsa-lib.sh: no KEY_DIR variable defined.

Make sure you are running via "exec-ca <ca> ..."
with <ca> pointing to valid "vars-<ca>" file.
'
