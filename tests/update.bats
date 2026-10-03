#!/usr/bin/env bats
# keel-pve update: fetch the .gz and .asc, verify with sqv against the
# keyring, as pveam does, and store the index only when it verifies.

bats_require_minimum_version 1.5.0
load helpers

setup() { scratch_setup; }
teardown() { scratch_teardown; }

@test "update stores the verified index and its signature" {
    standard_index
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 0 ]
    [[ "$output" == *"2 templates"* ]]
    cmp "$KEEL_PVE_STATE_DIR/aplinfo.dat" "$SERVE/aplinfo.dat"
    cmp "$KEEL_PVE_STATE_DIR/aplinfo.dat.asc" "$SERVE/aplinfo.dat.asc"
    [ -z "$(find "$KEEL_PVE_STATE_DIR" -name '*.tmp*')" ]
}

@test "the index is the decompressed .gz, not the plain file next to it" {
    standard_index
    printf 'tampered\n' > "$SERVE/aplinfo.dat"
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 0 ]
    grep -q '^Package: keel-web$' "$KEEL_PVE_STATE_DIR/aplinfo.dat"
}

@test "an index signed by a key not in the keyring is refused and nothing is stored" {
    standard_index
    other="$(make_signing_key stranger)"
    publish "$other"
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 3 ]
    [[ "$output" == *"signature"* ]]
    [ ! -e "$KEEL_PVE_STATE_DIR/aplinfo.dat" ]
    [ -z "$(find "$KEEL_PVE_STATE_DIR" -type f ! -name lock)" ]
}

@test "a modified index under a valid signature is refused" {
    standard_index
    sed 's/19.0-3/19.0-4/' "$SERVE/aplinfo.dat" | gzip -n -9 > "$SERVE/aplinfo.dat.gz"
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 3 ]
    [ ! -e "$KEEL_PVE_STATE_DIR/aplinfo.dat" ]
}

@test "a refused update keeps the index that was there" {
    updated
    before="$(sha512sum < "$KEEL_PVE_STATE_DIR/aplinfo.dat")"
    other="$(make_signing_key stranger)"
    publish "$other"
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 3 ]
    [ "$(sha512sum < "$KEEL_PVE_STATE_DIR/aplinfo.dat")" = "$before" ]
}

@test "a missing signature is a fetch failure" {
    standard_index
    rm "$SERVE/aplinfo.dat.asc"
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 4 ]
    [[ "$output" == *"aplinfo.dat.asc"* ]]
}

@test "a missing index is a fetch failure" {
    standard_index
    rm "$SERVE/aplinfo.dat.gz"
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 4 ]
    [[ "$output" == *"aplinfo.dat.gz"* ]]
}

@test "a .gz that is not gzip is refused" {
    standard_index
    printf 'not gzip\n' > "$SERVE/aplinfo.dat.gz"
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 3 ]
    [[ "$output" == *"unpack"* ]]
}

@test "a signed index with an invalid record is refused" {
    KEY="$(make_signing_key keel-test)"
    trust "$KEY"
    record core 19.0-8 "deadbeef" > "$TMP/index"
    publish "$KEY"
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 3 ]
    [[ "$output" == *"sha512sum"* ]]
    [ ! -e "$KEEL_PVE_STATE_DIR/aplinfo.dat" ]
}

@test "a signed but empty index is refused" {
    KEY="$(make_signing_key keel-test)"
    trust "$KEY"
    : > "$TMP/index"
    publish "$KEY"
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 3 ]
    [[ "$output" == *"no template"* ]]
}

@test "update calls sqv the way pveam does" {
    standard_index
    stub sqv 'echo "sqv $*" >> "$TMP/sqv.log"; exec /usr/bin/sqv "$@"'
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 0 ]
    grep -q "^sqv --keyring $KEEL_PVE_KEYRING .*aplinfo.dat.asc.* .*aplinfo.dat" "$TMP/sqv.log"
}

@test "a state directory that cannot be created is a write failure" {
    standard_index
    : > "$TMP/notadir"
    export KEEL_PVE_STATE_DIR="$TMP/notadir/state"
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 7 ]
}

@test "an index that cannot be stored is a write failure" {
    standard_index
    mkdir -p "$KEEL_PVE_STATE_DIR/aplinfo.dat.asc/occupied"
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 7 ]
    [[ "$output" == *"cannot store"* ]]
    [ -z "$(find "$KEEL_PVE_STATE_DIR" -maxdepth 1 -name 'update.tmp.*')" ]
}

@test "a testing version with a label is accepted, as pveam accepts it" {
    KEY="$(make_signing_key keel-test)"
    trust "$KEY"
    sha="$(make_template core 19.0-3+step4-20260930)"
    record core 19.0-3+step4-20260930 "$sha" > "$TMP/index"
    publish "$KEY"
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 0 ]
}

@test "an http Location is refused" {
    KEY="$(make_signing_key keel-test)"
    trust "$KEY"
    sha="$(make_template web 19.0-3)"
    record web 19.0-3 "$sha" "http://keel.test/debian-13-keel-web_19.0-3_amd64.tar.zst" > "$TMP/index"
    publish "$KEY"
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 3 ]
    [[ "$output" == *"Location"* ]]
    [ ! -e "$KEEL_PVE_STATE_DIR/aplinfo.dat" ]
}

@test "a Location ending in .. or with a query is refused" {
    KEY="$(make_signing_key keel-test)"
    trust "$KEY"
    sha="$(make_template web 19.0-3)"
    for loc in "https://keel.test/templates/.." "https://keel.test/../.." \
        "https://keel.test/x.tar.zst?y=debian-13-keel-web_19.0-3_amd64.tar.zst" \
        "https:///debian-13-keel-web_19.0-3_amd64.tar.zst"; do
        record web 19.0-3 "$sha" "$loc" > "$TMP/index"
        publish "$KEY"
        run "$REPO/bin/keel-pve" update
        [ "$status" -eq 3 ] || { echo "accepted: $loc"; false; }
    done
    [ ! -e "$KEEL_PVE_STATE_DIR/aplinfo.dat" ]
}

@test "curl gets a connect timeout and the short index time limit" {
    standard_index
    export KEEL_PVE_CONNECT_TIMEOUT=9 KEEL_PVE_INDEX_MAX_TIME=33
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 0 ]
    [ "$(grep -c -- '--connect-timeout 9 --max-time 33 ' "$TMP/curl.log")" -eq 2 ]
}

@test "an index transfer that stalls is cut at the time limit" {
    standard_index
    hanging_server
    export KEEL_PVE_INDEX_URL="http://127.0.0.1:$PORT/aplinfo.dat" KEEL_PVE_PROTOCOLS="=http"
    export KEEL_PVE_INDEX_MAX_TIME=1
    SECONDS=0
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 4 ]
    [ "$SECONDS" -lt 10 ]
    [ -z "$(find "$KEEL_PVE_STATE_DIR" -mindepth 1 ! -name lock)" ]
}

@test "a state directory where mktemp fails is a write failure, nothing fetched" {
    standard_index
    mkdir -p "$KEEL_PVE_STATE_DIR"
    : > "$KEEL_PVE_STATE_DIR/lock"
    chmod 555 "$KEEL_PVE_STATE_DIR"
    run "$REPO/bin/keel-pve" update
    chmod 755 "$KEEL_PVE_STATE_DIR"
    [ "$status" -eq 7 ]
    [[ "$output" == *"temporary directory"* ]]
    [ ! -e "$TMP/curl.log" ]
}

@test "an update waits for the lock a bounded time, then fails and releases it" {
    standard_index
    mkdir -p "$KEEL_PVE_STATE_DIR"
    # one process holds the lock, so killing it releases it
    (flock -x 8 && exec sleep 5) 8>> "$KEEL_PVE_STATE_DIR/lock" &
    holder=$!
    sleep 0.5
    export KEEL_PVE_LOCK_WAIT=1
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 7 ]
    [[ "$output" == *"busy"* ]]
    kill "$holder" 2> /dev/null || true
    wait "$holder" 2> /dev/null || true
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 0 ]
}

@test "a lock file that cannot be opened is a write failure" {
    standard_index
    mkdir -p "$KEEL_PVE_STATE_DIR/lock"
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 7 ]
    [[ "$output" == *"cannot open"* ]]
}
