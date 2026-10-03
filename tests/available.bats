#!/usr/bin/env bats
# keel-pve available: the templates of the stored, verified index.

bats_require_minimum_version 1.5.0
load helpers

setup() { scratch_setup; }
teardown() { scratch_teardown; }

@test "available lists every template with version, file name and description" {
    updated
    run "$REPO/bin/keel-pve" available
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == PACKAGE*VERSION*TEMPLATE*DESCRIPTION ]]
    [[ "$output" == *"keel-core"*"19.0-8"*"debian-13-keel-core_19.0-8_amd64.tar.zst"*"Keel core"* ]]
    [[ "$output" == *"keel-web"*"19.0-3"*"debian-13-keel-web_19.0-3_amd64.tar.zst"*"Keel web"* ]]
    [ "${#lines[@]}" -eq 3 ]
}

@test "available works without root" {
    updated
    stub id 'echo 1000'
    run "$REPO/bin/keel-pve" available
    [ "$status" -eq 0 ]
}

@test "available without an index says to run update" {
    run "$REPO/bin/keel-pve" available
    [ "$status" -eq 5 ]
    [[ "$output" == *"keel-pve update"* ]]
}

@test "available refuses an index whose stored signature no longer verifies" {
    updated
    printf '\n' >> "$KEEL_PVE_STATE_DIR/aplinfo.dat"
    run "$REPO/bin/keel-pve" available
    [ "$status" -eq 3 ]
}

@test "a stored index that verifies but does not parse is refused" {
    updated
    record core 19.0-8 deadbeef > "$KEEL_PVE_STATE_DIR/aplinfo.dat"
    gpg --batch --quiet --yes --local-user "$KEY" --detach-sign --armor \
        -o "$KEEL_PVE_STATE_DIR/aplinfo.dat.asc" "$KEEL_PVE_STATE_DIR/aplinfo.dat" 2> /dev/null
    run "$REPO/bin/keel-pve" available
    [ "$status" -eq 3 ]
    [[ "$output" == *"sha512sum"* ]]
}
