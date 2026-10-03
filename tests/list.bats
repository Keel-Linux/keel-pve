#!/usr/bin/env bats
# keel-pve list: the Keel templates already in the storages with vztmpl
# content, as pvesm lists them.

bats_require_minimum_version 1.5.0
load helpers

setup() { scratch_setup; add_storage local iso,vztmpl,backup; add_storage nfs vztmpl; }
teardown() { scratch_teardown; }

@test "list shows the Keel templates of every vztmpl storage and nothing else" {
    updated
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 0 ]
    run "$REPO/bin/keel-pve" download nfs keel-core
    [ "$status" -eq 0 ]
    : > "$STORE/local/template/cache/debian-13-standard_13.1-2_amd64.tar.zst"
    run "$REPO/bin/keel-pve" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"local:vztmpl/debian-13-keel-web_19.0-3_amd64.tar.zst"* ]]
    [[ "$output" == *"nfs:vztmpl/debian-13-keel-core_19.0-8_amd64.tar.zst"* ]]
    [[ "$output" != *"standard"* ]]
}

@test "list marks a Keel template the current index does not list" {
    updated
    : > "$STORE/local/template/cache/debian-13-keel-core_19.0-1_amd64.tar.zst"
    run "$REPO/bin/keel-pve" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"debian-13-keel-core_19.0-1_amd64.tar.zst"*"not in index"* ]]
}

@test "list with no Keel template says so" {
    updated
    run "$REPO/bin/keel-pve" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"no Keel template"* ]]
}

@test "list works before any update" {
    : > "$STORE/local/template/cache/debian-13-keel-core_19.0-1_amd64.tar.zst"
    run "$REPO/bin/keel-pve" list
    [ "$status" -eq 0 ]
    [[ "$output" == *"local:vztmpl/debian-13-keel-core_19.0-1_amd64.tar.zst"* ]]
}

@test "list fails when pvesm cannot report the storages" {
    stub pvesm 'exit 255'
    run "$REPO/bin/keel-pve" list
    [ "$status" -eq 5 ]
    [[ "$output" == *"pvesm"* ]]
}
