#!/usr/bin/env bats
# keel-pve download STORAGE TEMPLATE: into the directory pvesm names, with
# the file name the index gives, checked against the signed sha512, and
# renamed into place only when it matches.

bats_require_minimum_version 1.5.0
load helpers

setup() { scratch_setup; add_storage local iso,vztmpl,backup; }
teardown() { scratch_teardown; }

CACHE() { echo "$STORE/local/template/cache"; }

@test "download by package name writes the template under the index's file name" {
    updated
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 0 ]
    f="$(CACHE)/debian-13-keel-web_19.0-3_amd64.tar.zst"
    cmp "$f" "$SERVE/debian-13-keel-web_19.0-3_amd64.tar.zst"
    [[ "$output" == *"local:vztmpl/debian-13-keel-web_19.0-3_amd64.tar.zst"* ]]
    [ "$(find "$(CACHE)" -type f | wc -l)" -eq 1 ]
}

@test "download asks pvesm for the path, it never guesses one" {
    updated
    run "$REPO/bin/keel-pve" download local keel-core
    [ "$status" -eq 0 ]
    grep -q '^pvesm path local:vztmpl/debian-13-keel-core_19.0-8_amd64.tar.zst$' "$TMP/pvesm.log"
}

@test "download by template file name works too" {
    updated
    run "$REPO/bin/keel-pve" download local debian-13-keel-core_19.0-8_amd64.tar.zst
    [ "$status" -eq 0 ]
    [ -f "$(CACHE)/debian-13-keel-core_19.0-8_amd64.tar.zst" ]
}

@test "download by package name takes the newest version of a cumulative index" {
    KEY="$(make_signing_key keel-test)"
    trust "$KEY"
    a="$(make_template core 19.0-9)"
    b="$(make_template core 19.0-10)"
    c="$(make_template core 19.0-8)"
    { record core 19.0-9 "$a"; record core 19.0-10 "$b"; record core 19.0-8 "$c"; } > "$TMP/index"
    publish "$KEY"
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 0 ]
    run "$REPO/bin/keel-pve" download local keel-core
    [ "$status" -eq 0 ]
    [ -f "$(CACHE)/debian-13-keel-core_19.0-10_amd64.tar.zst" ]
    [ "$(find "$(CACHE)" -type f | wc -l)" -eq 1 ]
}

@test "a checksum mismatch is refused and leaves nothing in the storage" {
    updated
    printf 'swapped on the mirror\n' > "$SERVE/debian-13-keel-web_19.0-3_amd64.tar.zst"
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 6 ]
    [[ "$output" == *"sha512"* ]]
    [ -z "$(find "$(CACHE)" -mindepth 1)" ]
}

@test "a mismatch leaves the file already there untouched" {
    updated
    printf 'older\n' > "$(CACHE)/debian-13-keel-web_19.0-3_amd64.tar.zst"
    printf 'swapped on the mirror\n' > "$SERVE/debian-13-keel-web_19.0-3_amd64.tar.zst"
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 6 ]
    [ "$(cat "$(CACHE)/debian-13-keel-web_19.0-3_amd64.tar.zst")" = older ]
    [ "$(find "$(CACHE)" -type f | wc -l)" -eq 1 ]
}

@test "a template already present and matching is not fetched again" {
    updated
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 0 ]
    rm "$SERVE/debian-13-keel-web_19.0-3_amd64.tar.zst"
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 0 ]
    [[ "$output" == *"already present"* ]]
}

@test "a file of that name that does not match is replaced by the verified one" {
    updated
    printf 'stale\n' > "$(CACHE)/debian-13-keel-web_19.0-3_amd64.tar.zst"
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 0 ]
    cmp "$(CACHE)/debian-13-keel-web_19.0-3_amd64.tar.zst" "$SERVE/debian-13-keel-web_19.0-3_amd64.tar.zst"
}

@test "a failed transfer leaves nothing in the storage" {
    updated
    rm "$SERVE/debian-13-keel-web_19.0-3_amd64.tar.zst"
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 4 ]
    [ -z "$(find "$(CACHE)" -mindepth 1)" ]
}

@test "an unknown template is refused and the available ones are named" {
    updated
    run "$REPO/bin/keel-pve" download local keel-nope
    [ "$status" -eq 5 ]
    [[ "$output" == *"keel-nope"* ]]
    [[ "$output" == *"keel-pve available"* ]]
}

@test "a storage that does not exist is refused" {
    updated
    run "$REPO/bin/keel-pve" download nosuch keel-web
    [ "$status" -eq 5 ]
    [[ "$output" == *"nosuch"* ]]
}

@test "a storage without vztmpl content is refused" {
    updated
    add_storage images images,rootdir
    run "$REPO/bin/keel-pve" download images keel-web
    [ "$status" -eq 5 ]
    [[ "$output" == *"vztmpl"* ]]
}

@test "a template directory that does not exist is refused, never created" {
    updated
    rmdir "$(CACHE)"
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 5 ]
    [[ "$output" == *"does not exist"* ]]
    [ ! -e "$(CACHE)" ]
}

@test "pvesm failing to give a path is refused" {
    updated
    stub pvesm 'case "$1" in status) printf "Name Type\nlocal dir active\n" ;; *) exit 255 ;; esac'
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 5 ]
}

@test "download without an index says to run update" {
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 5 ]
    [[ "$output" == *"keel-pve update"* ]]
}

@test "download re-verifies the stored index before trusting its checksum" {
    updated
    sed -i "s/$WEB_SHA/$(printf 'x' | sha512sum | cut -d' ' -f1)/" "$KEEL_PVE_STATE_DIR/aplinfo.dat"
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 3 ]
    [ -z "$(find "$(CACHE)" -mindepth 1)" ]
}

@test "a Location whose file name is not a template is refused" {
    KEY="$(make_signing_key keel-test)"
    trust "$KEY"
    sha="$(make_template web 19.0-3)"
    record web 19.0-3 "$sha" "https://keel.test/payload.sh" > "$TMP/index"
    publish "$KEY"
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 3 ]
    [[ "$output" == *"Location"* ]]
}

@test "the protocol allow-list reaches curl" {
    updated
    export KEEL_PVE_PROTOCOLS="=https"
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 4 ]
    [ -z "$(find "$(CACHE)" -mindepth 1)" ]
}

@test "a verified template that cannot be renamed into place is a write failure" {
    updated
    mkdir -p "$(CACHE)/debian-13-keel-web_19.0-3_amd64.tar.zst/occupied"
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 7 ]
    [ -z "$(find "$(CACHE)" -maxdepth 1 -name '.keel-pve.*')" ]
    [ ! -e "$(CACHE)/debian-13-keel-web_19.0-3_amd64.tar.zst/occupied/debian-13-keel-web_19.0-3_amd64.tar.zst" ]
}

@test "a refused download leaves no partial file behind" {
    updated
    printf 'swapped\n' > "$SERVE/debian-13-keel-web_19.0-3_amd64.tar.zst"
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 6 ]
    [ -z "$(find "$(CACHE)" -mindepth 1)" ]
}

@test "a symlink planted at the final name is replaced, its target never written" {
    updated
    printf 'victim\n' > "$TMP/victim"
    ln -s "$TMP/victim" "$(CACHE)/debian-13-keel-web_19.0-3_amd64.tar.zst"
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 0 ]
    [ "$(cat "$TMP/victim")" = victim ]
    [ ! -L "$(CACHE)/debian-13-keel-web_19.0-3_amd64.tar.zst" ]
    cmp "$(CACHE)/debian-13-keel-web_19.0-3_amd64.tar.zst" "$SERVE/debian-13-keel-web_19.0-3_amd64.tar.zst"
}

@test "a symlink to a matching file at the final name is not taken as present" {
    updated
    cp "$SERVE/debian-13-keel-web_19.0-3_amd64.tar.zst" "$TMP/elsewhere"
    ln -s "$TMP/elsewhere" "$(CACHE)/debian-13-keel-web_19.0-3_amd64.tar.zst"
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 0 ]
    [[ "$output" == *"downloaded and verified"* ]]
    [ ! -L "$(CACHE)/debian-13-keel-web_19.0-3_amd64.tar.zst" ]
}

@test "symlinks planted at predictable temporary names are never written through" {
    updated
    printf 'victim\n' > "$TMP/victim"
    for n in .debian-13-keel-web_19.0-3_amd64.tar.zst.keel-pve.part .keel-pve.part \
        debian-13-keel-web_19.0-3_amd64.tar.zst.part; do
        ln -s "$TMP/victim" "$(CACHE)/$n"
    done
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 0 ]
    [ "$(cat "$TMP/victim")" = victim ]
    [ -z "$(find "$(CACHE)" -maxdepth 1 -name '.keel-pve.*' ! -name .keel-pve.part)" ]
}

@test "a template directory where no temporary directory can be made is a write failure" {
    updated
    chmod 555 "$(CACHE)"
    run "$REPO/bin/keel-pve" download local keel-web
    chmod 755 "$(CACHE)"
    [ "$status" -eq 7 ]
    [[ "$output" == *"temporary directory"* ]]
}

@test "the downloaded template is world readable, as pveam leaves it" {
    updated
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 0 ]
    [ "$(stat -c %a "$(CACHE)/debian-13-keel-web_19.0-3_amd64.tar.zst")" = 644 ]
}

@test "curl gets a connect timeout and the template time limit" {
    updated
    export KEEL_PVE_CONNECT_TIMEOUT=7 KEEL_PVE_TEMPLATE_MAX_TIME=4321
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 0 ]
    grep -q -- '--connect-timeout 7 --max-time 4321 .*debian-13-keel-web_19.0-3_amd64.tar.zst$' "$TMP/curl.log"
}

@test "a template transfer that stalls is cut at the time limit and leaves nothing" {
    updated
    hanging_server
    export KEEL_TEST_BASE="http://127.0.0.1:$PORT/" KEEL_PVE_PROTOCOLS="=http" KEEL_PVE_TEMPLATE_MAX_TIME=1
    SECONDS=0
    run "$REPO/bin/keel-pve" download local keel-web
    [ "$status" -eq 4 ]
    [ "$SECONDS" -lt 10 ]
    [ -z "$(find "$(CACHE)" -mindepth 1)" ]
}
