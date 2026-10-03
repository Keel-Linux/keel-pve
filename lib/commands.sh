# shellcheck shell=bash
# The subcommands: available, download and list. update is index_update.

cmd_available() {
    local records
    records="$(index_load)" || return
    printf '%-16s %-10s %-48s %s\n' PACKAGE VERSION TEMPLATE DESCRIPTION
    awk -F'\t' '{ printf "%-16s %-10s %-48s %s\n", $1, $2, $3, $6 }' <<< "$records"
}

# cmd_download STORAGE TEMPLATE: the template into STORAGE under the name
# the index gives. It is written into a private directory that mktemp
# creates (mode 0700, a fresh name) inside the template directory, so no
# planted file or symlink is ever opened for writing, and renamed into place
# only after its sha512 matched the signed index. rename(2) replaces a
# symlink at the final name; it never writes through it.
cmd_download() {
    local storage="$1" want="$2" records rec file sha url path work status
    need_root || return
    records="$(index_load)" || return
    rec="$(index_select "$records" "$want")"
    if [ -z "$rec" ]; then
        warn "no template '$want' in the index; see: keel-pve available"
        return "$EXIT_NOT_FOUND"
    fi
    IFS=$'\t' read -r _ _ file sha url _ <<< "$rec"
    path="$(storage_template_path "$storage" "$file")" || return
    if [ -f "$path" ] && [ ! -L "$path" ] && [ "$(sha512sum < "$path" | cut -d' ' -f1)" = "$sha" ]; then
        say "already present and verified: $storage:vztmpl/$file"
        return 0
    fi
    if ! work="$(mktemp -d "${path%/*}/.keel-pve.XXXXXXXX" 2> /dev/null)" || [ ! -d "$work" ]; then
        warn "cannot create a temporary directory in ${path%/*}"
        return "$EXIT_WRITE_FAILED"
    fi
    # A global, so the traps never quote a path into code.
    KEEL_PVE_WORK="$work"
    trap 'rm -rf -- "$KEEL_PVE_WORK"' EXIT
    trap 'rm -rf -- "$KEEL_PVE_WORK"; exit 130' INT TERM
    download_verified "$url" "$work/$file" "$sha"
    status=$?
    if [ "$status" -eq 0 ]; then
        chmod 0644 "$work/$file"
        if ! mv -fT "$work/$file" "$path" 2> /dev/null; then
            warn "cannot rename the verified template to $path"
            status="$EXIT_WRITE_FAILED"
        fi
    fi
    rm -rf -- "$work"
    trap - EXIT INT TERM
    [ "$status" -eq 0 ] || return "$status"
    say "downloaded and verified: $storage:vztmpl/$file"
}

# download_verified URL OUT SHA512: OUT, a new file, holds URL's bytes and
# they match SHA512, or a non-zero status.
download_verified() {
    local got
    say "downloading $1"
    if ! fetch "$1" "$2" "$KEEL_PVE_TEMPLATE_MAX_TIME"; then
        warn "cannot fetch $1"
        return "$EXIT_FETCH_FAILED"
    fi
    got="$(sha512sum < "$2" | cut -d' ' -f1)"
    if [ "$got" != "$3" ]; then
        warn "sha512 mismatch for ${1##*/}: the index says $3, the file is $got; refused"
        return "$EXIT_CHECKSUM"
    fi
}

cmd_list() {
    local volumes records="" volid file
    volumes="$(storage_keel_volumes)" || return
    if [ -z "$volumes" ]; then
        say "no Keel template in any vztmpl storage"
        return 0
    fi
    records="$(index_load 2> /dev/null)" || records=""
    while read -r volid; do
        file="${volid#*:vztmpl/}"
        if awk -F'\t' -v n="$file" '$3 == n { found = 1 } END { exit !found }' <<< "$records"; then
            say "$volid"
        else
            say "$volid  (not in index)"
        fi
    done <<< "$volumes"
}
