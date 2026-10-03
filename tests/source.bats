#!/usr/bin/env bats
# The hint keel-pve prints when no apt source names the Keel archive, so the
# package it came from would never be upgraded. The hint goes to stderr and
# changes no exit status.

bats_require_minimum_version 1.5.0
load helpers

setup() { scratch_setup; add_storage local vztmpl; }
teardown() { scratch_teardown; }

no_keel_source() {
    rm -f "$KEEL_PVE_APT_SOURCES_DIR"/*
}

@test "no hint when a deb822 .sources file names the Keel archive" {
    run --separate-stderr "$REPO/bin/keel-pve" list
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
}

@test "with no Keel source, the hint names the file and the deb822 block" {
    no_keel_source
    run --separate-stderr "$REPO/bin/keel-pve" list
    [ "$status" -eq 0 ]
    [ "$output" = "no Keel template in any vztmpl storage" ]
    [[ "$stderr" == *"no apt source for https://archive.keellinux.org"* ]]
    [[ "$stderr" == *"create $KEEL_PVE_APT_SOURCES_DIR/keel.sources"* ]]
    [[ "$stderr" == *"Types: deb"* ]]
    [[ "$stderr" == *"URIs: https://archive.keellinux.org"* ]]
    [[ "$stderr" == *"Suites: trixie-testing"* ]]
    [[ "$stderr" == *"Components: main"* ]]
    [[ "$stderr" == *"Signed-By: $KEEL_PVE_KEYRING"* ]]
}

@test "the hint leaves the exit status of a failing command as it was" {
    no_keel_source
    rm -f "$KEEL_PVE_KEYRING"
    run --separate-stderr "$REPO/bin/keel-pve" update
    [ "$status" -eq 8 ]
    [[ "$stderr" == *"keel-archive-keyring"* ]]
    [[ "$stderr" == *"keel.sources"* ]]
}

@test "with no sources directory at all, the hint is printed" {
    rm -rf "$KEEL_PVE_APT_SOURCES_DIR"
    run --separate-stderr "$REPO/bin/keel-pve" list
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"keel.sources"* ]]
}

@test "a one-line entry in sources.list counts" {
    no_keel_source
    echo "deb [signed-by=/usr/share/keyrings/keel-archive-keyring.gpg] https://archive.keellinux.org trixie-testing main" \
        > "$KEEL_PVE_APT_SOURCES_LIST"
    run --separate-stderr "$REPO/bin/keel-pve" list
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
}

@test "a one-line entry in a .list file counts" {
    no_keel_source
    echo "deb https://archive.keellinux.org/ trixie main" > "$KEEL_PVE_APT_SOURCES_DIR/keel.list"
    run --separate-stderr "$REPO/bin/keel-pve" list
    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
}

@test "a commented-out entry does not count" {
    no_keel_source
    echo "# deb https://archive.keellinux.org trixie main" > "$KEEL_PVE_APT_SOURCES_DIR/keel.list"
    run --separate-stderr "$REPO/bin/keel-pve" list
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"keel.sources"* ]]
}

@test "a file apt does not read does not count" {
    no_keel_source
    keel_source > "$KEEL_PVE_APT_SOURCES_DIR/keel.sources.disabled"
    run --separate-stderr "$REPO/bin/keel-pve" list
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"keel.sources"* ]]
}

@test "help, version and usage errors print no hint" {
    no_keel_source
    run --separate-stderr "$REPO/bin/keel-pve" --version
    [ -z "$stderr" ]
    run --separate-stderr "$REPO/bin/keel-pve" --help
    [ -z "$stderr" ]
    run --separate-stderr "$REPO/bin/keel-pve" list extra
    [ "$status" -eq 1 ]
    [[ "$stderr" != *"keel.sources"* ]]
}
