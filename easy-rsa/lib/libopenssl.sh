#!/bin/sh

# Requires: cat(1), mv(1), rm(1), sed(1), tr(1), date(1), cmp(1), openssl(1)

[ -z "${__libopenssl_sh__-}" ] || return 0
__libopenssl_sh__=1

# Source functions libraries
. "$EASY_RSA/lib/libstring.sh"
. "$EASY_RSA/lib/libfile.sh"

# Usage: ossl__cmd_in_file <cmd> <file> ...
ossl__cmd_in_file()
{
	local func="${func:-ossl__cmd_in_file}"

	local cmd="${1:?missing 1st arg to ${func}() <cmd>}"
	local file="${2:?missing 2d arg to ${func}() <file>}"
	shift 2

	[ -e "$file" ] || return

	${OPENSSL:-openssl} "$cmd" "$@" -in "$file"
}

# Usage: ossl_pkey <file> ...
ossl_pkey()
{
	ossl__cmd_in_file pkey "$@"
}

# Usage: ossl_req <file> ...
ossl_req()
{
	ossl__cmd_in_file req "$@"
}

# Usage: ossl_x509 <file> ...
ossl_x509()
{
	ossl__cmd_in_file x509 "$@"
}

# Usage: ossl_dgst <file> ...
ossl_dgst()
{
	local func="${FUNCNAME:-ossl_dgst}"

	local file="${1:?missing 1st arg to ${func}() <file>}"
	shift

	# dgst(1) does not accept '-in'
	${OPENSSL:-openssl} dgst "$@" "$file"
}

# Usage: ossl_sha256 <file>
ossl_sha256()
{
	local val
	val="$(ossl_dgst "$1" -r -sha256)" || return
	set -- $val
	echo "$1"
}

# Usage: ossl_sha512 <file>
ossl_sha512()
{
	local val
	val="$(ossl_dgst "$1" -r -sha512)" || return
	set -- $val
	echo "$1"
}

# Usage: ossl__hmac {<in>|''} {<out>|''} <secret> ...
ossl__hmac()
{
    local func="${func:-${FUNCNAME:-ossl__hmac}}"

    local  f_in="${1:-/dev/stdin}"  && shift && [ -r "$f_in" ]  || return
    local f_out="${1:-/dev/stdout}" && shift || return

    local secret="${1:?missing 3rd arg to ${func}() (<secret>)}" && shift

    # Note that while standard input is supported it must be used with care
    # as it may expose plain text message that is being hashed via command
    # line arguments. For example this could happen in following command
    #
    #  echo -n 'plain text' | ossl__hmac '' '' -sha256
    #
    # when echo isn't shell builtin but external executable (e.g. /bin/echo).

    # 0 < /dev/stdin - here-document
    # 1 > /dev/null  - openssl(1) prompt (i.e. "OpenSSL> " w/o double-quotes)
    # 2 > "$f_out"   - output file (e.g. standard output to next pipe command)
    # 3 < "$f_in"    - input file (e.g. standard input from prev pipe command)
    if openssl 3<"$f_in"  2>"$f_out" >/dev/null <<EOF
dgst $@ -hmac '$secret' -out /dev/fd/2 /dev/fd/3
EOF
    then
        :
    else
        return
    fi
}

# Usage: ossl_hmac_sha1() <secret> ...
ossl_hmac_sha1()
{
    local func="${FUNCNAME:-ossl_hmac_sha1}"
    ossl__hmac '' '' "$@" -sha1
}

# Usage: ossl_hmac_sha256() <secret> ...
ossl_hmac_sha256()
{
    local func="${FUNCNAME:-ossl_hmac_sha256}"
    ossl__hmac '' '' "$@" -sha256
}

# Usage: ossl_hmac_sha512() <secret> ...
ossl_hmac_sha512()
{
    local func="${FUNCNAME:-ossl_hmac_sha512}"
    ossl__hmac '' '' "$@" -sha512
}

# Usage: ossl_base64() ...
ossl_base64()
{
    openssl base64 "$@"
}

# Usage: ossl_base64url() ...
ossl_base64url()
{
    # see perldoc MIME::Base64 encode_base64url()
    ossl_base64 "$@" | sed -e 's/\+/-/g' -e 's/\//_/g' -e 's/=\+$//'
}

# Usage: ossl__pubkey_pem <crt_file> ...
ossl__pubkey_pem()
{
	# $cmd are expected to come from caller
	local func="ossl_${cmd}_pubkey_pem"

	local crt="${1:?missing 1st arg to ${func}() <crt_file>}"
	shift

	ossl__cmd_in_file "$cmd" "$crt" "$@" -noout -pubkey
}

# Usage: ossl__pubkey_der <crt_file> ...
ossl__pubkey_der()
{
	local func="ossl_${cmd}_pubkey_der"

	local pk
	pk="$(ossl__pubkey_pem "$@")" || return

	echo "$pk" | ossl_pkey /dev/stdin -pubin -inform pem -outform der
}

# Usage: ossl__pubkey_same <crt1_file> <crt2_file>
ossl__pubkey_same()
{
	local func="ossl_${cmd}_pubkey_same"

	local crt1="${1:?missing 1st arg to ${func}() <crt_file1>}"
	local crt2="${2:?missing 2d arg to ${func}() <crt_file2>}"

	[ ! "$crt1" -ef "$crt2" ] || return 0

	local pk1 pk2

	pk1="$(ossl__pubkey_pem "$crt1")" || return 2
	pk2="$(ossl__pubkey_pem "$crt2")" || return 2

	[ "$pk1" = "$pk2" ]
}

# Usage: ossl__pubkey_fp <dgst> <crt_file> ...
ossl__pubkey_fp()
{
	local func="ossl_${cmd}_pubkey_fp"

	local dgst="${1:-sha256}"
	shift

	local dg

	dg="$(ossl__pubkey_der "$@")" ||
		return

	dg="$(echo "$dg" | ossl_dgst /dev/stdin -keyform der -r "-$dgst")" ||
		return

	set -- $dg
	echo "$1"
}

# Usage: ossl__pubkey_fp_same <dgst> <crt_file1> <crt_file2>
ossl__pubkey_fp_same()
{
	local func="ossl_${cmd}_pubkey_fp_same"

	local dgst="$1"
	local crt1="${2:?missing 2d arg to ${func}() <crt_file1>}"
	local crt2="${3:?missing 3rd arg to ${func}() <crt_file2>}"

	[ ! "$crt1" -ef "$crt2" ] || return 0

	local fp1 fp2

	fp1="$(ossl__pubkey_fp "$dgst" "$crt1")" || return 2
	fp2="$(ossl__pubkey_fp "$dgst" "$crt2")" || return 2

	[ "$fp1" = "$fp2" ]
}

# Usage: ossl_req_pubkey_pem <crt_file> ...
ossl_req_pubkey_pem()     { local cmd='req';   ossl__pubkey_pem     "$@"; }
# Usage: ossl_req_pubkey_der <crt_file> ...
ossl_req_pubkey_der()     { local cmd='req';   ossl__pubkey_der     "$@"; }
# Usage: ossl_req_pubkey_same <crt1_file> <crt2_file>
ossl_req_pubkey_same()    { local cmd='req';   ossl__pubkey_same    "$@"; }
# Usage: ossl_req_pubkey_fp <dgst> <crt_file> ...
ossl_req_pubkey_fp()      { local cmd='req';   ossl__pubkey_fp      "$@"; }
# Usage: ossl_req_pubkey_fp_same <dgst> <crt_file1> <crt_file2>
ossl_req_pubkey_fp_same() { local cmd='req';   ossl__pubkey_fp_same "$@"; }

# Usage: ossl_x509_pubkey_pem <crt_file> ...
ossl_x509_pubkey_pem()     { local cmd='x509'; ossl__pubkey_pem     "$@"; }
# Usage: ossl_x509_pubkey_der <crt_file> ...
ossl_x509_pubkey_der()     { local cmd='x509'; ossl__pubkey_der     "$@"; }
# Usage: ossl_x509_pubkey_same <crt1_file> <crt2_file>
ossl_x509_pubkey_same()    { local cmd='x509'; ossl__pubkey_same    "$@"; }
# Usage: ossl_x509_pubkey_fp <dgst> <crt_file> ...
ossl_x509_pubkey_fp()      { local cmd='x509'; ossl__pubkey_fp      "$@"; }
# Usage: ossl_x509_pubkey_fp_same <dgst> <crt_file1> <crt_file2>
ossl_x509_pubkey_fp_same() { local cmd='x509'; ossl__pubkey_fp_same "$@"; }

# Usage: ossl_x509_get_var <crt_file> <var_regex> <var_name> ...
ossl_x509_get_var()
{
	local func="${FUNCNAME:-ossl_x509_get_var}"

	local crt="${1:?missing 1st arg to ${func}() <crt_file>}"
	local var_regex="$2"
	local var_name="${3:-\1}"
	shift 3

	#        \1             \2
	# \(${var_regex}\) = \(.\+\)
	local n=2

	if [ -z "$var_regex" ]; then
		var_regex='\w\+'
	else
		local curr="$var_regex"
		local prev

		while :; do
			prev="$curr"
			curr="${curr#*\(}"
			[ -n "$curr" -a "$curr" != "$prev" ] || break
			n=$((n + 1))
		done
	fi

	local var

	var="$(
	    ossl_x509 "$crt" "$@" \
	        -noout \
	        -nameopt oneline,-space_eq,sep_comma_plus,use_quote \
	        #
	)" || return

	echo "$var" |
	sed -n -e "s/^\(${var_regex}\)\s*=\s*\(.\+\)\s*\$/${var_name}='\\$n'/p"
}

# Usage: ossl_get_field4dn_by_name() <dn> <fn>
ossl_get_field4dn_by_name()
{
	local func="${FUNCNAME:-ossl_get_field4dn_by_name}"

	local dn="${1:?missing 1st arg to ${func}() <dn>}"
	local fn="${2:?missing 2d arg to ${func}() <fn>}"

	local t=",$dn,"

	t="${t##*,$fn=}" && [ "$t" != "$dn" ] || return
	if [ -n "${t##\"*}" ]; then
		t="${t%%,*}"
	else
		t="${t#\"}" && t="${t%%\",*}"
	fi

	[ -n "$t" ] && echo "$t" || return
}

# Usage: ossl_date2ts [<ossl_date>]
ossl_date2ts()
{
	local func="${FUNCNAME:-ossl_date2ts}"

	local ossl_date="$1"
	local next_pos=1 len=2
	local Y M D h m s

	[ -n "$ossl_date" ] || return 0

	# OpenSSL GeneralizedTime format is YYMMDDhhmmssZ
	# where
	#    YY - last two digits of the year (00.99)
	#    MM - month (01..12)
	#    DD - day (01..31)
	#    hh - hour (01..23)
	#    mm - minute (00..59)
	#    ss - second (00..60)

	substr "$ossl_date" $next_pos $len Y # YY
	substr "$ossl_date" $next_pos $len M # MM
	substr "$ossl_date" $next_pos $len D # DD
	substr "$ossl_date" $next_pos $len h # hh
	substr "$ossl_date" $next_pos $len m # mm
	substr "$ossl_date" $next_pos $len s # ss

	substr "$ossl_date" $next_pos 1 Z    # Zulu time
	[ "$Z" = 'Z' ] || return

	date --date="$Y-$M-$D $h:$m:$s" '+%s'
}

# Usage: ossl_cert_read_date2ts <crt_file> -(start|end)
ossl_cert_read_date2ts()
{
	local func="${FUNCNAME:-ossl_cert_read_date2ts}"

	local crt="${1:?missing 1st arg to ${func}() <crt_file>}"
	local arg="${2:?missing 2d arg to ${func}() -(start|end)}"

	case "$arg" in
		-start) ;; # notBefore
		-end)   ;; # notAfter
		*) echo >&2 "invalid $arg to ${func}"; return 1 ;;
	esac
	arg="${arg}date"

	local ts

	eval "$(ossl_x509_get_var "$crt" 'not\(Before\|After\)' 'ts' $arg)" ||
		return

	[ -n "$ts" ] || return

	date --date="$ts" '+%s'
}

# Usage: ossl_ts2human <timestamp>
ossl_ts2human()
{
	[ -n "$1" ] || return
	date --utc --date="@$1" '+%d %b %Y %H:%M:%S (UTC)'
}

# Usage: ossl_date2human ...
ossl_date2human()
{
	local ts
	ts="$(ossl_date2ts "$@")" || return
	ossl_ts2human "$ts"
}

# Usage: ossl_cert_read_date2human ...
ossl_cert_read_date2human()
{
	local ts
	ts="$(ossl_cert_read_date2ts "$@")" || return
	ossl_ts2human "$ts"
}

# Usage: ossl_cert_expires_in_days <notAfter>
ossl_cert_expires_in_days()
{
	local func="${FUNCNAME:-ossl_cert_expires_in_days}"

	local notAfter="${1:?missing 1st arg to ${func}() <notAfter>}"
	notAfter="$(date --date="@${notAfter}" '+%s' 2>/dev/null)" ||
	notAfter="$(date --date="${notAfter}"  '+%s' 2>/dev/null)" ||
	notAfter="$(ossl_date2ts "${notAfter}")" || return

	local now=$(date '+%s')

	local days=$((notAfter - now))
	if [ "$days" -ge 0 ] 2>/dev/null; then
		echo "$((days / 60 / 60 / 24))"
	else
		echo '-1'
	fi
}

# Usage: ossl_cert_is_expired <crt_file>
ossl_cert_is_expired()
{
	local func="${FUNCNAME:-ossl_cert_is_expired}"

	local crt="${1:?missing 1st arg to ${func}() <crt_file>}"

	local notAfter

	notAfter="$(ossl_cert_read_date2ts "$crt" -end)"    || return 2
	notAfter="$(ossl_cert_expires_in_days "$notAfter")" || return 2

	[ "$notAfter" -lt 0 ] 2>/dev/null
}

# Usage: ossl_index_txt_line2args <line> [<file>|'']
ossl_index_txt_line2args()
{
	local line="$1"
	if [ -z "$line" ]; then
		local file="$2"
		[ -n "$file" -a -e "$file" ] || file='/dev/stdin'
		read -r line <"$file" && [ -n "$line" ] || return
	fi

	# OpenSSL index.txt file format
	# https://pki-tutorial.readthedocs.io/en/latest/cadb.html
	#
	#   1 - Certificate status flag (V=valid, R=revoked, E=expired).
	#   2 - Certificate expiration date in YYMMDDHHMMSSZ format.
	#   3 - Certificate revocation date in YYMMDDHHMMSSZ[,reason] format.
	#       Empty if not revoked.
	#   4 - Certificate serial number in hex.
	#   5 - Certificate filename or literal string ‘unknown’.
	#   6 - Certificate distinguished name.
	#
	# Tab (\t) used as field separators.
	local status
	local expires expires_days
	local revoked revoked_reason
	local serial
	local filename
	local dn

	local ifs="$IFS"
	IFS=','
	set -- $(echo "$line" | tr '\t' ',')
	IFS="$ifs"

	# Status
	status="$1"

	# Expires
	expires="$(ossl_date2ts "$2")" || return

	# Expires (days)
	expires_days="$(ossl_cert_expires_in_days "$expires")" || return

	if [ -n "$3" ]; then
		# Revoked
		revoked="$(ossl_date2ts "${3%%,*}")" || return
		# Revoked reason (optional)
		revoked_reason="${3#*,}"
	else
		revoked=''
		revoked_reason=''
	fi

	# Serial
	serial="$4"

	# Filename
	filename="$5"

	# DN
	dn="$(IFS='/' && set -- ${6#/} && IFS=',' && echo "$*")"

	line="\
		'$line' \
		'$status' \
		'$expires' '$expires_days' \
		'$revoked' '$revoked_reason' \
		'$serial' \
		'$filename' \
		'$dn' \
	"
	echo "$line"
}

# Usage: ossl_index_txt_match_serial <serial> <line> [<file>|'']
ossl_index_txt_match_serial()
{
	local func="${FUNCNAME:-ossl_index_txt_match_serial}"

	# It is assumed that certificate serial numbers are unique.
	# Thus we can [q]uit from sed(1) on first match.
	local serial="${1:?missing 1st arg to ${func}() <serial>}"

	local line="$2"
	if [ -z "$line" ]; then
		local file="$3"
		[ -n "$file" -a -e "$file" ] || file='/dev/stdin'
		cat "$file"
	else
		echo "$line"
	fi | sed -n -e "/	$serial	\S\+	.\+\$/{p;q}"
}

# Usage: ossl_intex_txt_status <status>
ossl_index_txt_status()
{
	local func="${FUNCNAME:-ossl_index_txt_status}"

	local status="${1:?missing 1st arg to ${func}() <status>}"

	case "$status" in
		'V') echo 'Valid'   ;;
		'R') echo 'Revoked' ;;
		'E') echo 'Expired' ;;
		'__mlen__') echo 7  ;;
		*)   echo 'Unknown' ;;
	esac
}

# Usage: ossl_index_txt_filename <serial> ...
ossl_index_txt_filename()
{
	local serial="$1"
	shift

	if [ "$1" != 'unknown' ]; then
		echo "$1"
	elif [ -n "$serial" ]; then
		echo "$serial.pem"
	fi
}

# Usage: ossl_index_txt_for_each_line <cb> <index_txt>
ossl_index_txt_for_each_line()
{
	local func="${FUNCNAME:-ossl_index_txt_for_each_line}"

	local cb="${1:?missing 1st arg to ${func}() <cb>}"
	local index_txt="${2:?missing 2d arg to ${func}() <index_txt>}"

	[ -s "$index_txt" ] || return

	local line args
	local rc=0

	while read -r line; do
		args="$(ossl_index_txt_line2args "$line")"
		#    $1     $2  $3  $4   $5  $6   $7   $8   $9
		# cb <line> <s> <e> <ed> <r> <rr> <sn> <fn> <dn>
		eval "'$cb' $args" || rc=$((rc + 1))
	done <"$index_txt"

	return $rc
}

# Usage: ossl_index_txt_same_pubkey_flist <crt_file>
ossl_index_txt_same_pubkey_flist()
{
	local func="${FUNCNAME:-ossl_index_txt_same_pubkey_flist}"

	local crt="${1:?missing 1st arg to ${func}() <crt_file>}"

	local pk1
	pk1="$(ossl_x509_pubkey_pem "$crt")" || return

	local same_pk_flist="'$crt' "

	# If unique_subject = no there might be more than one certificate
	# using same private key by hardlinking or symlinking existing
	# private key file.

	# Usage: cb <line> \                      # $1
	#	    <status> \                    # $2
	#	    <expires> <expires_days> \    # $3 $4
	#	    <revoked> <revoked_reason> \  # $5 $6
	#	    <serial> \                    # $7
	#	    <filename> \                  # $8
	#	    <dn>                          # $9
	ossl_index_txt_same_pubkey_flist_cb()
	{
		# <serial>.pem if 'unknown' or specific name from index.txt
		local pem="$(ossl_index_txt_filename "$7" "$8")"

		if ! (V=0 valid_file "$pem"); then
			pem="$(ossl_get_field4dn_by_name "$9" 'CN').crt"
			if ! (V=0 valid_file "$pem"); then
				return 0
			fi
		fi

		# Skip same file given at command line
		if [ "$pem" -ef "$crt" ] || cmp -s "$pem" "$crt"; then
			return 0
		fi

		local pk2
		pk2="$(ossl_x509_pubkey_pem "$pem")" || return 0

		# Not doing fingerprint compare as hashes, even
		# with very low probability are not collision free
		[ "$pk2" = "$pk1" ] || return 0

		same_pk_flist="$same_pk_flist'$pem' "
	}

	ossl_index_txt_for_each_line \
		'ossl_index_txt_same_pubkey_flist_cb' \
		'index.txt' ||:

	echo "$same_pk_flist"
}

# Usage: ossl_index_txt_revoke_certs <crt_name1>...
ossl_index_txt_revoke_certs()
{
	local index_txt index_txt_revoke subject serial revoked CN
	local FN='' revoked_list=''
	local rc=0

	# There are non-empty arguments
	[ -n "$*" ] || return

	# There is non-empty database: backup it
	index_txt="$KEY_DIR/index.txt"
	[ -s "$index_txt" ] || return

	index_txt_revoke="$index_txt.revoke"

	safe_copy "$index_txt" "$index_txt_revoke" || return

	# If there are multiple certificates to revoke due to
	# same public key then private key is the same too and
	# stored in separate, possibly hardlinked or symlinked
	# to the "$1" private key file.

	while [ $# -gt 0 ]; do
		FN="$1"
		shift
		[ -n "$FN" ] || continue

		# subject=...
		eval "$(ossl_x509_get_var "$FN" 'subject' '' -subject)" &&
			[ -n "$subject" ] ||
			{ rc=$? && break; }

		# serial=...
		eval "$(ossl_x509_get_var "$FN" 'serial' '' -serial)" &&
			[ -n "$serial" ] ||
			{ rc=$? && break; }

		# Not skipping expired, but not removed from database
		# certificates as their private key and/or csr can be
		# reused to issue new certificate with same CN before
		# they removed from database (e.g. moved to expired/).

		# Skip revoked: there is nothing to do with these certs
		revoked="$(ossl_index_txt_match_serial \
				"$serial" '' "$index_txt" | \
			   ossl_index_txt_line2args)" &&
			[ -n "$revoked" ] ||
			{ rc=$? && break; }

		$(eval set -- $revoked && [ -z "$5" ]) ||
			{ continue; }

		# Revoke certificate
		"$OPENSSL" ca -revoke "$FN" \
			${CA_PASSPHRASE:+-passin env:CA_PASSPHRASE} \
			-config "$KEY_CONFIG" ||
			{ rc=$? && break; }

		# Suffix crt, csr and key files to make sure newly
		# issued certificates with the same CN will never reuse
		# possibly compromised private key and we have a copy.

		if CN="$(ossl_get_field4dn_by_name "$subject" 'CN')"; then
			mv -f "$CN.crt" "$CN.crt.$serial.revoked" ||:
			mv -f "$CN.csr" "$CN.csr.$serial.revoked" ||:
			mv -f "$CN.key" "$CN.key.$serial.revoked" ||:

			# Store in list of revoked certificates for rollback
			revoked_list="'$CN.$serial' $revoked_list"
		fi 2>/dev/null
	done

	if [ $rc -eq 0 ]; then
		rm -f "$index_txt_revoke" ||:
	else
		# Rollback certificate revocation on failure
		eval "set -- $revoked_list"

		for FN in "$@"; do
			serial="${FN##*.}"
			FN="${FN%.*}"
			mv -f "$FN.key.$serial.revoked" "$FN" ||:
			mv -f "$FN.csr.$serial.revoked" "$FN" ||:
			mv -f "$FN.crt.$serial.revoked" "$FN" ||:
		done 2>/dev/null

		mv -f "$index_txt_revoke" "$index_txt" ||:
	fi
}
