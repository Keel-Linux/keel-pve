# shellcheck shell=bash
# The Keel template index: fetching and verifying it (update), reading the
# stored copy back only after verifying it again, and parsing its records.
#
# The index is the aplinfo.dat bt-aplinfo writes (buildtasks
# docs/aplinfo.md): records separated by a blank line, "Key: value" lines,
# a Description with one continuation line.

# index_records FILE: one tab separated line per record,
#   package version template sha512 location headline
# and a non-zero status with a message when any record is not what pveam
# would accept, or the file holds none.
index_records() {
    NAME_RE="$VZTMPL_NAME_RE" awk -f "$KEEL_PVE_LIB/aplinfo.awk" "$1"
}

# index_update: fetch the .asc and the .gz, unpack, verify, parse, and only
# then rename both into the state directory, under an exclusive lock.
index_update() {
    need_root || return
    need_keyring || return
    if ! mkdir -p "$KEEL_PVE_STATE_DIR" 2> /dev/null; then
        warn "cannot create $KEEL_PVE_STATE_DIR"
        return "$EXIT_WRITE_FAILED"
    fi
    with_lock -x index_update_locked
}

index_update_locked() {
    local tmp count status
    if ! tmp="$(mktemp -d "$KEEL_PVE_STATE_DIR/update.tmp.XXXXXX" 2> /dev/null)" || [ ! -d "$tmp" ]; then
        warn "cannot create a temporary directory in $KEEL_PVE_STATE_DIR"
        return "$EXIT_WRITE_FAILED"
    fi
    index_fetch_verify "$tmp"
    status=$?
    if [ "$status" -eq 0 ]; then
        count="$(index_records "$tmp/aplinfo.dat" | wc -l)"
        if ! mv -fT "$tmp/aplinfo.dat.asc" "$KEEL_PVE_STATE_DIR/aplinfo.dat.asc" 2> /dev/null ||
            ! mv -fT "$tmp/aplinfo.dat" "$KEEL_PVE_STATE_DIR/aplinfo.dat" 2> /dev/null; then
            warn "cannot store the index in $KEEL_PVE_STATE_DIR"
            status="$EXIT_WRITE_FAILED"
        fi
    fi
    rm -rf "$tmp"
    [ "$status" -eq 0 ] || return "$status"
    say "index updated from $KEEL_PVE_INDEX_URL: $count templates, signature verified"
}

# index_fetch_verify DIR: DIR/aplinfo.dat and DIR/aplinfo.dat.asc, the
# index verified against the keyring and parsed, or a non-zero status.
index_fetch_verify() {
    if ! fetch "$KEEL_PVE_INDEX_URL.asc" "$1/aplinfo.dat.asc" "$KEEL_PVE_INDEX_MAX_TIME"; then
        warn "cannot fetch $KEEL_PVE_INDEX_URL.asc"
        return "$EXIT_FETCH_FAILED"
    fi
    if ! fetch "$KEEL_PVE_INDEX_URL.gz" "$1/aplinfo.dat.gz" "$KEEL_PVE_INDEX_MAX_TIME"; then
        warn "cannot fetch $KEEL_PVE_INDEX_URL.gz"
        return "$EXIT_FETCH_FAILED"
    fi
    if ! gunzip -f "$1/aplinfo.dat.gz" 2> /dev/null; then
        warn "cannot unpack $KEEL_PVE_INDEX_URL.gz"
        return "$EXIT_UNVERIFIED"
    fi
    if ! verify_signature "$1/aplinfo.dat.asc" "$1/aplinfo.dat"; then
        warn "the index signature does not verify against $KEEL_PVE_KEYRING; nothing stored"
        return "$EXIT_UNVERIFIED"
    fi
    index_records "$1/aplinfo.dat" > /dev/null || return "$EXIT_UNVERIFIED"
}

# index_load: the records of the stored index, verified again against the
# keyring under a shared lock, so a checksum is never read from a file
# that changed after update.
index_load() {
    if [ ! -f "$KEEL_PVE_STATE_DIR/aplinfo.dat" ] || [ ! -f "$KEEL_PVE_STATE_DIR/lock" ]; then
        warn "no index yet; run: keel-pve update"
        return "$EXIT_NOT_FOUND"
    fi
    need_keyring || return
    with_lock -s index_load_locked
}

index_load_locked() {
    if ! verify_signature "$KEEL_PVE_STATE_DIR/aplinfo.dat.asc" "$KEEL_PVE_STATE_DIR/aplinfo.dat"; then
        warn "the stored index does not verify any more; run: keel-pve update"
        return "$EXIT_UNVERIFIED"
    fi
    index_records "$KEEL_PVE_STATE_DIR/aplinfo.dat" || return "$EXIT_UNVERIFIED"
}

# index_select RECORDS NAME: the record whose template file name is NAME,
# or the newest version of package NAME.
index_select() {
    local by_file
    by_file="$(awk -F'\t' -v n="$2" '$3 == n' <<< "$1" | head -n 1)"
    if [ -n "$by_file" ]; then
        printf '%s\n' "$by_file"
        return 0
    fi
    awk -F'\t' -v n="$2" '$1 == n' <<< "$1" | sort -t "$(printf '\t')" -k2,2V | tail -n 1
}
