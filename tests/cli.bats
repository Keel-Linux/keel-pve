#!/usr/bin/env bats
# bin/keel-pve and pve_main: the arguments, the help, and the refusals that
# happen before any subcommand starts.

bats_require_minimum_version 1.5.0
load helpers

setup() { scratch_setup; }
teardown() { scratch_teardown; }

@test "the executable prints its version" {
    run "$REPO/bin/keel-pve" --version
    [ "$status" -eq 0 ]
    [ "$output" = "keel-pve 0.1.1" ]
}

@test "the help names every subcommand and what it does not do" {
    run "$REPO/bin/keel-pve" --help
    [ "$status" -eq 0 ]
    [[ "$output" == usage:* ]]
    [[ "$output" == *"update"* ]]
    [[ "$output" == *"available"* ]]
    [[ "$output" == *"download STORAGE TEMPLATE"* ]]
    [[ "$output" == *"list"* ]]
    [[ "$output" == *"Templates download dialog"* ]]
}

@test "-h and help are the same as --help" {
    run "$REPO/bin/keel-pve" -h
    [ "$status" -eq 0 ]
    [[ "$output" == usage:* ]]
    run "$REPO/bin/keel-pve" help
    [ "$status" -eq 0 ]
    [[ "$output" == usage:* ]]
}

@test "no subcommand is a usage error" {
    run "$REPO/bin/keel-pve"
    [ "$status" -eq 1 ]
    [[ "$output" == *"usage:"* ]]
}

@test "an unknown subcommand is a usage error and points at the help" {
    run "$REPO/bin/keel-pve" frobnicate
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown subcommand: frobnicate"* ]]
    [[ "$output" == *"--help"* ]]
}

@test "extra arguments are refused for every subcommand" {
    run "$REPO/bin/keel-pve" update now
    [ "$status" -eq 1 ]
    run "$REPO/bin/keel-pve" available x
    [ "$status" -eq 1 ]
    run "$REPO/bin/keel-pve" list x
    [ "$status" -eq 1 ]
    run "$REPO/bin/keel-pve" download local
    [ "$status" -eq 1 ]
    [[ "$output" == *"download STORAGE TEMPLATE"* ]]
    run "$REPO/bin/keel-pve" download local keel-web extra
    [ "$status" -eq 1 ]
}

@test "update and download refuse to run without root" {
    stub id 'echo 1000'
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 2 ]
    [[ "$output" == *"must run as root"* ]]
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 2 ]
}

@test "a missing keyring is refused with the package to install" {
    rm -f "$KEEL_PVE_KEYRING"
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 8 ]
    [[ "$output" == *"keel-archive-keyring"* ]]
}
