#!/bin/sh

# Requires: cat(1), mv(1), rm(1), chmod(1), install(1), readlink(1), sed(1)
#           ls(1), id(1)

[ -z "${__libfile_sh__-}" ] || return 0
__libfile_sh__=1

# Source functions libraries
. "$EASY_RSA/lib/librtti.sh"
. "$EASY_RSA/lib/libstring.sh"

# Usage: push_dir <dir> <var_level> <var_oldpwd>
push_dir()
{
	local func="${FUNCNAME:-push_dir}"

	local pd_dir="${1:?missing 1st arg to ${func}() (<dir>)}"
	local var_level="${2:?missing 2d arg to ${func}() (<var_leve>)}"
	local var_oldpwd="${3:?missing 3rd arg to ${func}() (<var_oldpwd>)}"

	local pd_level pd_oldpwd="${PWD}"

	# change directory first: fail before setting anything
	cd "${pd_dir}" 2>/dev/null || return

	# get level: make sure current level is valid
	eval "pd_level=\"\$${var_level}\""
	[ "${pd_level}" -ge 0 ] 2>/dev/null || pd_level=0

	# store current working directory in variable
	eval "${var_oldpwd}_${pd_level}=${pd_oldpwd}"

	# increment level and store it in variable
	eval "${var_level}=$((pd_level + 1))"

	return 0
}

# Usage: pop_dir <var_level> <var_oldpwd>
pop_dir()
{
	local func="${FUNCNAME:-pop_dir}"

	local var_level="${1:?missing 2d arg to ${func}() (<var_leve>)}"
	local var_oldpwd="${2:?missing 3rd arg to ${func}() (<var_oldpwd>)}"

	local pd_level pd_oldpwd var_name

	# get level: make sure we not going below zero
	eval "pd_level=\"\$${var_level}\""
	[ "${pd_level}" -gt 0 ] 2>/dev/null || return

	# decrement level, store it in or unset variable
	if [ $((pd_level -= 1)) -eq 0 ]; then
		unset "${var_level}"
	else
		eval "${var_level}=${pd_level}"
	fi

	# get old working directory, unset variable
	var_name="${var_oldpwd}_${pd_level}"
	eval "pd_oldpwd=\"\$${var_name}\""
	unset "$var_name"

	cd "$pd_oldpwd" 2>/dev/null
}

# Usage: normalize_path() <path> [<var_result>]
normalize_path()
{
	local func="${FUNCNAME:-normalize_path}"

	local file="${1:?missing 1st arg to ${func}() (<path>)}"
	local path='' f

	# make relative path absolute
	[ -z "${file##/*}" ] || file="/$PWD/$file"

	# squeeze multiple '/' to single one
	strsqueeze "$file" '/' 'file' || return

	# ending with '/'
	file="${file%/}/"

	# not beginning with '/'/
	file="${file#/}"

	while [ -n "$file" ]; do
		f="${file%%/*}"
		case "$f" in
			'.')
				;;
			'..')
				path="${path%/*}"
				;;
			*)
				path="$path/$f"
				;;
		esac
		file="${file#*/}"
	done

	return_var 0 "$path" "${2-}"
}

# Usage: relative_path <src> <dst> [<var_result>]
relative_path()
{
	local func="${FUNCNAME:-relative_path}"

	local rp_src="${1:?missing 1st arg to ${func}() (<src>)}"
	local rp_dst="${2:?missing 2d arg to ${func}() (<dst>)}"

	# add last component from src if dst ends with '/'
	[ -n "${rp_dst##*/}" ] || rp_dst="${rp_dst}${rp_src##*/}"

	# normalize pathes first
	normalize_path "${rp_src}" rp_src || return
	normalize_path "${rp_dst}" rp_dst || return

	# strip leading and add trailing '/'
	rp_src="${rp_src#/}/"
	rp_dst="${rp_dst#/}/"

	while :; do
		[ "${rp_src%%/*}" = "${rp_dst%%/*}" ] || break

		rp_src="${rp_src#*/}" && [ -n "${rp_src}" ] || return
		rp_dst="${rp_dst#*/}" && [ -n "${rp_dst}" ] || return
	done

	# strip trailing '/'
	rp_dst="${rp_dst%/}"
	rp_src="${rp_src%/}"

	# add leading '/' for dst only: for src we will add with sed(1) ../
	rp_dst="/${rp_dst}"

	# add leading '/' to dst, replace (/[^/])+ with ../
	rp_dst="$(echo "${rp_dst%/*}" | \
		  sed -e 's|\(/[^/]\+\)|../|g')${rp_src}" || \
		return

	return_var 0 "${rp_dst}" "${3-}"
}

# Usage: rights_human2octal <rights>
rights_human2octal()
{
	local func="${FUNCNAME:-rights_human2octal}"

	# rwxr-xr-x (755), rwsrwSrwT (7766)
	local rights="${1:?missing 1st arg to ${func}() <rights>}"
	[ ${#rights} -eq 9 ] || return

	local val=0
	local g v s c C r

	# groups: 3  2  1  0
	# bits:  sgtrwxrwxrwx
	for g in 2 1 0; do
		v=0
		s=0

		if [ $g -ge 1 ]; then
			c='s' && C='S'
		else
			c='t' && C='T'
		fi

		r="${rights#[r-][w-][xsStT-]}"
		r="${rights%$r}"

		# [r-]
		case "$r" in
			r??)  v=$((4 + v)) ;;
			-??)  ;;
			*)    return 1 ;;
		esac

		# [w-]
		case "$r" in
			?w?)  v=$((2 + v)) ;;
			?-?)  ;;
			*)    return 1 ;;
		esac

		# [xsStT-]
		case "$r" in
			??x)  v=$((1 + v)) ;;
			??$c) v=$((1 + v)) && s=$((1 << g)) ;;
			??$C) s=$((1 << g)) ;;
			??-)  ;;
			*)    return 1 ;;
		esac

		val=$((val | v << (3 * g) | s << (3 * 3)))

		rights="${rights#$r}"
	done

	printf '%04o\n' "$val"
}

# Usage: file_rights_human <file>
file_rights_human()
{
	local func="${FUNCNAME:-file_rights_human}"

	local file="${1:?missing 1st arg to ${func}() <file>}"

	[ -e "$file" ] || return

	set -- $(ls -l "$file") || return

	local rights="$1"
	rights="${rights#?}"
	[ ${#rights} -eq 9 ] || rights="${rights%?}"

	case "$rights" in
		[r-][w-][xsS-][r-][w-][xsS-][r-][w-][xtT-]) ;;
		*) return 1 ;;
	esac

	echo "$rights"
}

# Usage: file_rights_octal <file>
file_rights_octal()
{
	local func="${FUNCNAME:-file_rights_octal}"

	local file="${1:?missing 1st arg to ${func}() <file>}"

	local rights

	rights="$(file_rights_human "$file")" || return
	rights_human2octal "$rights"
}

# Usage: file_owner_human <file>
file_owner_human()
{
	local func="${FUNCNAME:-file_owner_human}"

	local file="${1:?missing 1st arg to ${func}() <file>}"

	[ -e "$file" ] || return

	set -- $(ls -l "$file") || return

	[ -n "$3" -a -n "$4" ] || return

	echo "$3:$4"
}

# Usage: file_owner_octal <file>
file_owner_octal()
{
	local func="${FUNCNAME:-file_owner_octal}"

	local file="${1:?missing 1st arg to ${func}() <file>}"

	local owner uid gid

	owner="$(file_owner_human "$file")" || return

	uid="$(id -u "${owner%:*}")" || return
	gid="$(id -g "${owner#*:}")" || return

	echo "$uid:$gid"
}

# Usage: valid_file <file>
valid_file()
{
	local func="${FUNCNAME:-valid_file}"

	local file="${1:?missing 1st arg to ${func}() (<file>)}"

	local err

	err='is not regular'  && [ ! -f "${file}" ] || \
	err='is empty'        && [ ! -s "${file}" ] || \
	err='is not readable' && [ ! -r "${file}" ] || \
		return 0

	! : || error '%s: "%s" %s file\n' "${func}" "${file}" "${err}"
}

# Usage: read_link <file>
read_link()
{
	local func="${FUNCNAME:-read_link}"

	local file="${1:?missing 1st arg to ${func}() (<file>)}"

	valid_file "${file}" || return

	readlink -f "${file}" || \
		error '%s: "%s" symlink resolution failed\n' \
			"${func}" "${file}"
}

# Usage: make_copy <src> <dst> [<umask>]
make_copy()
{
	local func="${FUNCNAME:-make_copy}"

	local src="${1:?missing 1st arg to ${func}() (<src>)}"
	local dst="${2:?missing 2d arg to ${func}() (<dst>)}"
	local umask="${3:-022}"

	local rc=0 oldumask='umask 0022'

	src="$(read_link "${src}")" || return

	oldumask="$(umask -p)" && umask "${umask}" && \
	{ [ -n "${dst##*/*}" ] || install -d "${dst%/*}"; } && \
	cat "${src}" >"${dst}" || \
		error '%s: copy "%s" to "%s" failed\n' \
			"${func}" "${src}" "${dst}" || \
	rc=$?

	eval "${oldumask}" ||:

	return $rc
}

# Usage: safe_copy <src> <dst> [<umask>]
safe_copy()
{
	local func="${FUNCNAME:-safe_copy}"

	local src="${1:?missing 1st arg to ${func}() (<src>)}"
	local dst="${2:?missing 2d arg to ${func}() (<dst>)}"
	local umask="${3:-022}"

	local rc=0 oldmask='umask 0022' dst_tmp

	src="$(read_link "${src}")" || return

	# use chmod go+r to fix permissions after mktemp(1)
	oldumask="$(umask -p)" && umask "${umask}" && \
	dst_tmp="${dst##*/*}" &&
	dst_tmp="$(mktemp ${dst_tmp:+--tmpdir} "${dst}.XXXXXXXX")" && \
	cat "${src}" >"${dst_tmp}" && \
	mv -f "${dst_tmp}" "${dst}" && \
	chmod -f go+r "${dst}" || \
		error '%s: copy "%s" to "%s" failed\n' \
			"${func}" "${src}" "${dst}" || \
		rc=$? && rm -f "${dst_tmp}" ||:

	eval "${oldumask}" ||:

	return $rc
}

# Usage: rename_dir <old> <new>
rename_dir()
{
	local func="${FUNCNAME:-rename_dir}"

	local old="${1:?missing 1st arg to ${func}() <old>}"
	local new="${2:?missing 2d arg to ${func}() <new>}"

	# New should be a directory
	[ -d "$old" ] || return

	# Move old directory under new one
	[ ! -e "$new" -a ! -L "$new" ] || mv -f "$new" "$old" || return

	local t="$new" && strrstrip "$t" '/' t && t="${t##*/}"

	# Rename old directory to new
	if mv -f "$old" "$new"; then
		# Remove original new on success
		[ -z "$t" ] || rm -rf "$new/$t"
	else
		# Restore original old on failure
		[ -z "$t" ] || mv  -f "$old/$t" "$new"
	fi ||:
}
