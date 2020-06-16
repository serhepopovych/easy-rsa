#!/bin/sh -e

# Requires: sed(1), tr(1), head(1)

this_prog='users-conf.sh'

if [ ! -e "$0" -o "$0" -ef "/proc/$$/exe" ]; then
    # Executed script is
    #  a) read from stdin through pipe
    #  b) specified via -c option
    #  d) sourced
    this="$this_prog"
    this_dir='./'
else
    # Executed script exists and it's inode differs
    # from process exe symlink (Linux specific)
    this="$0"
    this_dir="${this%/*}/"
fi
this_dir="$(cd "$this_dir" && echo "$PWD")"

# Set program name
prog_name="${this##*/}"

this="$this_dir/$prog_name"

# Change current working directory (sets $PWD) to xbin/..
cd "$this_dir/.." || exit

# Template is a regular and readable file
t='templ.d/user.templ' && [ -f "$t" -a -r "$t" ] || exit

# Module parameters directory
mod="$this_dir/mod"

# Usage: pwmake [<length>]
pwmake()
{
    tr -dc '[:graph:]' </dev/urandom | \
    tr -d '[\"'\''\\&|]' | head -c "${1:-64}"
    echo
}

# templ: templ_dir, templ, templ_name
templ_dir="${PWD}/${t%/*}"
templ="${t##*/}"
templ_name="${templ%.*}"

# templ: conf_dir
conf_dir="${PWD}/conf.d"

text=''

for u in users.d/*; do
    # Skip backups
    [ -n "${u##*\~}" -a -n "${u##\#*\#}" ] || continue
    # It is a symlink pointed to existing directory
    [ -L "$u" -a -d "$u" ] || continue

    # templ: user
    user="${u##*/}"
    # templ: home
    eval "home=~$user" && [ "$home/easy-rsa/.htconf" -ef "$u" ] || continue
    # templ: users_dir
    users_dir="${PWD}/${u%/*}"

    ## module parameters

    # mod_secdownload

    # templ: secdl_secret
      if secdl_secret="$("$mod/secdownload/secret" "$u")"; then
        :
    elif secdl_secret="$(pwmake)" && [ -n "$secdl_secret" ]; then
        :
    else
        continue
    fi

    # templ: secdl_timeout
    if secdl_timeout="$("$mod/secdownload/timeout" "$u")"; then
        :
    else
        continue
    fi

    ## templates expansion

    config="$(
        sed "$t"                                    \
            -e "s|%templ_dir%|$templ_dir|g"         \
            -e "s|%templ%|$templ|g"                 \
            -e "s|%templ_name%|$templ_name|g"       \
            -e "s|%conf_dir%|$conf_dir|g"           \
            -e "s|%users_dir%|$users_dir|g"         \
            -e "s|%user%|$user|g"                   \
            -e "s|%home%|$home|g"                   \
            -e "s|%secdl_secret%|$secdl_secret|g"   \
            -e "s|%secdl_timeout%|$secdl_timeout|g" \
            -e 's/^/  /'                            \
            #
    )"

    # Append $HTTP configuration
    if [ -n "$config" ]; then
        config="
$config
"
        text="${text:+$text
else }\$HTTP[\"url\"] =~ \"^/~$user\" + url_suffix_regex {$config}"
    fi
done

# Append "else { url.access-deny = ( "" ) }"
if [ -n "$text" ]; then
    text="$text
else {
  url.access-deny = ( \"\" )
}"
fi

# Output user configuration
echo "$text"

# Exit successfuly
exit 0
