# shellcheck shell=bash
# Proxmox storages, through pvesm only: which storages hold container
# templates, where a template volume lives, what each one holds. No path
# is ever guessed; a storage pvesm does not resolve is refused.

# storage_vztmpl_names: the storages with vztmpl content, one per line.
storage_vztmpl_names() {
    local out
    if ! out="$(pvesm status --content vztmpl 2> /dev/null)"; then
        warn "pvesm cannot report the storages with vztmpl content"
        return "$EXIT_NOT_FOUND"
    fi
    awk 'NR > 1 && NF { print $1 }' <<< "$out"
}

# storage_template_path STORAGE FILE: the absolute path of
# STORAGE:vztmpl/FILE, from pvesm path, after checking that the storage has
# vztmpl content and that the directory exists.
storage_template_path() {
    local names path
    names="$(storage_vztmpl_names)" || return
    if ! grep -qxF -- "$1" <<< "$names"; then
        warn "storage '$1' does not exist or has no vztmpl content (pvesm status --content vztmpl)"
        return "$EXIT_NOT_FOUND"
    fi
    if ! path="$(pvesm path "$1:vztmpl/$2" 2> /dev/null)" || [ "${path:0:1}" != / ]; then
        warn "pvesm gives no path for $1:vztmpl/$2"
        return "$EXIT_NOT_FOUND"
    fi
    if [ ! -d "${path%/*}" ]; then
        warn "${path%/*} does not exist; is storage '$1' active?"
        return "$EXIT_NOT_FOUND"
    fi
    printf '%s\n' "$path"
}

# storage_keel_volumes: the Keel template volumes of every vztmpl storage,
# one volid per line.
storage_keel_volumes() {
    local names name
    names="$(storage_vztmpl_names)" || return
    for name in $names; do
        pvesm list "$name" --content vztmpl 2> /dev/null |
            awk 'NR > 1 && $1 ~ /:vztmpl\/[^\/]*-keel-[^\/]*$/ { print $1 }'
    done
}
