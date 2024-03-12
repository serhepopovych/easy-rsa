#!/bin/sh

# Requires: date(1), sed(1), cat(1), getent(1)

[ -z "${__libutil_sh__-}" ] || return 0
__libutil_sh__=1

# Source functions libraries
. "$EASY_RSA/lib/librtti.sh"
. "$EASY_RSA/lib/libopenssl.sh"

## Helpers to get lighttpd configuration

# Usage: lighttpd_secdl_url <secret> {<tmo>|''} <ts> <rel_path> <hmac opts>...
lighttpd_secdl_url()
{
	local func="${FUNCNAME:-lighttpd_secdl_url}"

	local secret="${1:?missing 1st arg to ${func}() (<secret>)}"
	local tmo="${2:-60}" # secdownload.timeout=<tmo> (default <tmo> is 60s)
	local ts="${3:?missing 3rd arg to ${func}() (<ts>)}"
	local rel_path="${4:?missing 4th arg to ${func} (<rel_path>)}"
	shift 4

	# Make sure timeout is at least 1s so server
	# at least pushes valid URL to client
	local min_tmo=1
	[ "$tmo" -ge $min_tmo ] 2>/dev/null || return

	# Make sure we can get seconds since epoch (1970-01-01 UTC)
	local now
	now="$(date '+%s')" && ts="$(date --date="$ts" '+%s')" || return

	# Lighttpd mod_secdownload handles timeout like following
	#
	#    if (ts > now && (ts - now) > tmo)
	#        /* (1) now < (ts - tmo) scheduled in future: skip */
	#    else if (ts < now && (now - ts) > tmo)
	#        /* (2) now > (ts + tmo) expired: skip */
	#
	# for (1) URL is unavailable until (now < ts - tmo)
	#      _____now_____ts-tmo______ts______ts+tmo_____
	# and for (now >= ts - tmo)
	#      ________ts-tmo(now)______ts______ts+tmo_____
	# URL becomes available for 2 * tmo + 1 (121s for secdownload.timeout=60)
	#
	# for (2) URL is never awailable if system has correct time (e.g. with NTP)
	#      ________ts___now-tmo_____now_____now+tmo____
	#
	# If (ts > now && (ts - now) <= tmo) URL available for tmo + (ts - now) + 1
	#      ________ts-tmo______now__ts______ts+tmo_____

	# Prepend "/" to relative path if not already done
	[ -z "${rel_path##/*}" ] || rel_path="/$rel_path"
	local protected_path="/$(printf -- '%08x' "$ts")$rel_path"

	local mac

	eval $(
		echo -n "$protected_path" | \
		ossl__hmac '' '' "$secret" "$@" -binary | \
		ossl_base64url | {
			read mac t && echo "mac='$mac'"
		}
	)

	local url="$mac$protected_path"

	local notBefore=$((ts - tmo))
	local notAfter=$((ts + tmo))

	echo "url='$url'; now='$now'; notBefore='$notBefore'; notAfter='$notAfter';"
}

# Usage: lighttpd_secdl_secret
lighttpd_secdl_secret()
{
	"$lighttpd_xbin_dir/mod/secdownload/secret" "$lighttpd_user_dir"
}

# Usage: lighttpd_secdl_timeout
lighttpd_secdl_timeout()
{
	"$lighttpd_xbin_dir/mod/secdownload/timeout" "$lighttpd_user_dir"
}

# Usage: lighttpd_secdl_uri_prefix
lighttpd_secdl_uri_prefix()
{
	"$lighttpd_xbin_dir/mod/secdownload/uri-prefix" "$lighttpd_user_dir"
}

## Helpers to access administrative database entries with getent

# Usage: getvar_login_defs <var_name> [<var_regex]
getvar_login_defs()
{
	local func="${FUNCNAME:-getvar_login_defs}"

	local var_name="${1:?missing 1st arg to ${func}() (<var_name>)}"
	local var_regex="${2-.*}"

	sed 2>/dev/null -n '/etc/login.defs' \
		-e "s/^$var_name\s\+\($var_regex\)\s*$/\1/p" \
		#
}

# Usage: uid_min_login_defs ...
uid_min_login_defs()
{
	getvar_login_defs 'UID_MIN' '[0-9]\+' || echo '1000'
}

# Usage: uid_max_login_defs ...
uid_max_login_defs()
{
	getvar_login_defs 'UID_MAX' '[0-9]\+' || echo '60000'
}

# Usage: for_each_passwd {<uid_min>|''} {<uid_max>|''} [<action> ...]
for_each_passwd()
{
	local func="${FUNCNAME:-for_each_passwd}"

	local uid_min uid_max action
	local n=0

	# uid_min
	[ -n "${1+x}" ] && n=$((n + 1)) && uid_min="$1" &&
		[ "$uid_min" -lt 0 -o "$uid_min" -ge 0 ] 2>/dev/null ||
	uid_min="$(uid_min_login_defs)"

	# uid_max
	[ -n "${2+x}" ] && n=$((n + 1)) && uid_max="$2" &&
		[ "$uid_max" -lt 0 -o "$uid_max" -ge 0 ] 2>/dev/null ||
	uid_max="$(uid_max_login_defs)"

	# action
	[ -n "${3+x}" ] && n=$((n + 1)) && action="$3" &&
		[ -n "$action" ] ||
	{ action='echo'; set --; n=0; }

	shift $n

	if [ $uid_min -gt $uid_max ]; then
		local t=$uid_min
		uid_min=$uid_max
		uid_max=$t
	fi

	[ $uid_min -ge 0 ] || uid_max=2147483647 # 0x7fffffff

	getent passwd | while read line; do
		u="${line#*:}" # username
		u="${u#*:}"    # x
		u="${u%%:*}"   # uid

		[ $u -ge $uid_min -a $u -le $uid_max ] 2>/dev/null || continue

		"$action" "$line" "$@" || exit
	done
}

################################################################################

# vhost_name and vhost_dir
lighttpd_vhost_name="${HTTPD_HOSTNAME:-$HOSTNAME}"
lighttpd_vhosts_d='/etc/lighttpd/vhosts.d'
lighttpd_vhost_dir="$lighttpd_vhosts_d/$lighttpd_vhost_name"

# users_d
lighttpd_users_d="$lighttpd_vhost_dir/users.d"
# user_dir
lighttpd_user_dir="$lighttpd_users_d/$USER"

# xbin_dir
lighttpd_xbin_dir="$lighttpd_vhost_dir/xbin"
