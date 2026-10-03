# shellcheck shell=bash
# source_hint: the hint printed when no apt source names the Keel archive.
#
# keel-pve and keel-archive-keyring come from the Keel archive; without a
# source for it apt never upgrades them, and the key the index is verified
# with goes stale. The hint goes to stderr and changes no exit status.

# source_present: some apt source apt reads (sources.list, sources.list.d
# *.list and *.sources) names the Keel archive on a line that is not a
# comment. The scheme is ignored, so http and https mirrors both count.
source_present() {
    local host="${KEEL_PVE_ARCHIVE_URI#*://}" files=() f
    host="${host%/}"
    [ -f "$KEEL_PVE_APT_SOURCES_LIST" ] && files+=("$KEEL_PVE_APT_SOURCES_LIST")
    for f in "$KEEL_PVE_APT_SOURCES_DIR"/*.list "$KEEL_PVE_APT_SOURCES_DIR"/*.sources; do
        [ -f "$f" ] && files+=("$f")
    done
    [ "${#files[@]}" -gt 0 ] || return 1
    sed 's/#.*//' -- "${files[@]}" 2> /dev/null | grep -qF -- "$host"
}

# source_hint: the file to create and its deb822 block, on stderr, when no
# source names the Keel archive.
source_hint() {
    source_present && return 0
    warn "no apt source for $KEEL_PVE_ARCHIVE_URI; keel-pve and its key are not upgraded"
    cat >&2 << HINT
keel-pve: create $KEEL_PVE_APT_SOURCES_DIR/keel.sources with:

Types: deb
URIs: $KEEL_PVE_ARCHIVE_URI
Suites: $KEEL_PVE_ARCHIVE_SUITE
Components: main
Signed-By: $KEEL_PVE_KEYRING

HINT
}
