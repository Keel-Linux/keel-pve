#!/usr/bin/env bats
# apt/keel-pve.pref, installed as /etc/apt/preferences.d/keel-pve: on a
# Proxmox VE host only keel-pve and keel-archive-keyring come from the Keel
# archive. Checked as text and by apt itself against local archives.

bats_require_minimum_version 1.5.0
load helpers

setup() { scratch_setup; PREF="$REPO/apt/keel-pve.pref"; }
teardown() { scratch_teardown; }

# stanzas: the preferences file as "packages|pin|priority" lines.
stanzas() {
    awk '/^#/ { next }
        /^Package:/ { sub(/^Package: */, ""); p = $0 }
        /^Pin:/ { sub(/^Pin: */, ""); n = $0 }
        /^Pin-Priority:/ { print p "|" n "|" $2 }' "$PREF"
}

@test "only keel-pve and keel-archive-keyring have a positive priority" {
    run stanzas
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "keel-pve keel-archive-keyring|release o=Keel Linux|500" ]
    [ "${lines[1]}" = "*|release o=Keel Linux|-1" ]
}

@test "the package installs the pin as a conffile under preferences.d" {
    grep -qE '^\s+install -D -m 0644 apt/keel-pve.pref debian/keel-pve/etc/apt/preferences.d/keel-pve$' \
        "$REPO/debian/rules"
}

# make_archive NAME ORIGIN PKG=VER...: a local archive carrying ORIGIN.
make_archive() {
    local name="$1" origin="$2" spec dir
    shift 2
    dir="$TMP/archives/$name"
    mkdir -p "$dir/dists/trixie/main/binary-amd64"
    for spec in "$@"; do
        printf 'Package: %s\nVersion: %s\nArchitecture: amd64\nMaintainer: t <t@example.org>\nFilename: pool/x.deb\nSize: 1\nSHA256: %064d\nDescription: x\n\n' \
            "${spec%%=*}" "${spec#*=}" 0 >> "$dir/dists/trixie/main/binary-amd64/Packages"
    done
    (cd "$dir/dists/trixie" && apt-ftparchive -o APT::FTPArchive::Release::Origin="$origin" \
        -o APT::FTPArchive::Release::Suite=trixie -o APT::FTPArchive::Release::Codename=trixie \
        release . > Release)
    printf 'Types: deb\nURIs: file:%s\nSuites: trixie\nComponents: main\nTrusted: yes\n' "$dir" \
        > "$TMP/policy/etc/apt/sources.list.d/$name.sources"
}

@test "apt takes keel-pve and its key from Keel, and nothing else, even when newer" {
    command -v apt-ftparchive > /dev/null || skip "apt-ftparchive (apt-utils) is not installed"
    mkdir -p "$TMP/policy/etc/apt/sources.list.d" "$TMP/policy/etc/apt/preferences.d" \
        "$TMP/policy/lists/partial" "$TMP/policy/dpkg"
    cp "$PREF" "$TMP/policy/etc/apt/preferences.d/keel-pve"
    make_archive debian Debian curl=8.14.1-2 sqv=1.3.0-3
    make_archive keel "Keel Linux" keel-pve=0.1.0 keel-archive-keyring=0.2.0 \
        curl=9.0-1+keel1 keel=0.3.5
    printf 'Package: curl\nStatus: install ok installed\nVersion: 8.14.1-2\nArchitecture: amd64\nMaintainer: t <t@example.org>\nDescription: x\n\n' \
        > "$TMP/policy/dpkg/status"
    local o=(-o Dir::Etc="$TMP/policy/etc/apt" -o Dir::State="$TMP/policy"
        -o Dir::State::status="$TMP/policy/dpkg/status" -o Dir::Cache="$TMP/policy")
    apt-get "${o[@]}" update -qq 2> /dev/null
    run apt-get "${o[@]}" -s dist-upgrade
    [ "$status" -eq 0 ]
    [[ "$output" != *"Inst curl"* ]]
    run apt-cache "${o[@]}" policy keel-pve keel-archive-keyring keel curl
    [ "$status" -eq 0 ]
    [[ "$output" == *"keel-pve:"*"Candidate: 0.1.0"* ]]
    [[ "$output" == *"keel-archive-keyring:"*"Candidate: 0.2.0"* ]]
    [[ "$output" == *"keel:"*"Candidate: (none)"* ]]
    [[ "$output" == *"curl:"*"Candidate: 8.14.1-2"* ]]
}
