#!/bin/bash
# shellcheck shell=bash disable=SC2154
# Shared setup for the bats suite (decision 0004). Every test runs against
# a scratch tree: the index and the templates have https://keel.test/ URLs,
# which a curl wrapper maps onto a scratch directory before it runs the real
# curl with every other argument unchanged; pvesm and id are PATH stubs,
# and the signing key is a throwaway generated inside the test, never the
# project key. Nothing here touches the live system, needs root or reaches
# the network.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# scratch_setup: a fresh tree and environment for one test.
scratch_setup() {
    TMP="$(mktemp -d)"
    export TMP
    export STUBS="$TMP/stubs"
    export SERVE="$TMP/serve"
    export STORE="$TMP/storage"
    export GNUPGHOME="$TMP/gnupg"
    export KEEL_PVE_LIB="$REPO/lib"
    export KEEL_PVE_STATE_DIR="$TMP/state"
    export KEEL_PVE_KEYRING="$TMP/keyring.gpg"
    export KEEL_PVE_INDEX_URL="https://keel.test/aplinfo.dat"
    export KEEL_PVE_PROTOCOLS="=file"
    REAL_CURL="$(command -v curl)"
    export REAL_CURL
    mkdir -p "$STUBS" "$SERVE" "$STORE"
    mkdir -m 700 "$GNUPGHOME"
    export PATH="$STUBS:$PATH"
    stub id 'echo 0'
    stub curl 'echo "curl $*" >> "$TMP/curl.log"
args=()
base="${KEEL_TEST_BASE:-file://$SERVE/}"
for a in "$@"; do args+=("${a/#https:\/\/keel.test\//$base}"); done
exec "$REAL_CURL" "${args[@]}"'
    fake_pvesm
}

scratch_teardown() {
    [ -f "$TMP/server.pid" ] && kill "$(cat "$TMP/server.pid")" 2> /dev/null
    gpgconf --kill gpg-agent 2> /dev/null || true
    rm -rf "$TMP"
}

# stub NAME BODY: an executable first in PATH.
stub() {
    printf '#!/bin/bash\n%s\n' "$2" > "$STUBS/$1"
    chmod +x "$STUBS/$1"
}

# add_storage NAME CONTENT: a storage in the fake storage configuration,
# its directory under $STORE/NAME, with a template/cache directory when
# CONTENT includes vztmpl, the way a dir storage lays it out.
add_storage() {
    printf '%s %s\n' "$1" "$2" >> "$TMP/storage.cfg"
    mkdir -p "$STORE/$1"
    case ",$2," in
        *,vztmpl,*) mkdir -p "$STORE/$1/template/cache" ;;
    esac
}

# fake_pvesm: the three pvesm calls keel-pve makes, answered from
# $TMP/storage.cfg in the column layout of PVE 9.
fake_pvesm() {
    : > "$TMP/storage.cfg"
    stub pvesm 'cfg="$TMP/storage.cfg"
echo "pvesm $*" >> "$TMP/pvesm.log"
case "$1" in
status)
    [ "$2 $3" = "--content vztmpl" ] || exit 2
    printf "%-10s %-8s %-8s %12s %12s %12s %8s\n" Name Type Status Total Used Available %
    while read -r name content; do
        case ",$content," in *,vztmpl,*) ;; *) continue ;; esac
        printf "%-10s %-8s %-8s %12s %12s %12s %8s\n" "$name" dir active 100 10 90 10.00%
    done < "$cfg"
    ;;
path)
    volid="$2"; sid="${volid%%:*}"; vol="${volid#*:}"
    grep -q "^$sid " "$cfg" || { echo "storage '\''$sid'\'' does not exist" >&2; exit 255; }
    case "$vol" in
        vztmpl/*) echo "$STORE/$sid/template/cache/${vol#vztmpl/}" ;;
        *) exit 255 ;;
    esac
    ;;
list)
    sid="$2"
    [ "$3 $4" = "--content vztmpl" ] || exit 2
    printf "%-60s %-8s %-8s %12s %s\n" Volid Format Type Size VMID
    for f in "$STORE/$sid/template/cache"/*; do
        [ -f "$f" ] || continue
        case "$f" in *.tar|*.tar.gz|*.tar.xz|*.tar.zst|*.tar.bz2) ;; *) continue ;; esac
        printf "%-60s %-8s %-8s %12s\n" "$sid:vztmpl/${f##*/}" tzst vztmpl "$(stat -c %s "$f")"
    done
    ;;
*) exit 2 ;;
esac'
}

# make_signing_key NAME: a throwaway signing key; echoes its fingerprint.
make_signing_key() {
    gpg --batch --quiet --passphrase '' --pinentry-mode loopback \
        --quick-generate-key "$1 <$1@example.invalid>" ed25519 sign never 2> /dev/null
    gpg --batch --with-colons --list-keys "$1@example.invalid" |
        awk -F: '$1 == "fpr" { print $10; exit }'
}

# trust KEY: the keyring keel-pve verifies with holds KEY and nothing else,
# in the binary form keel-archive-keyring installs.
trust() {
    gpg --batch --quiet --yes --export "$1" > "$KEEL_PVE_KEYRING" 2> /dev/null
}

# make_template APP VERSION [CONTENT]: a small template file under $SERVE;
# echoes its sha512.
make_template() {
    local file="$SERVE/debian-13-keel-$1_$2_amd64.tar.zst"
    printf '%s\n' "${3:-root filesystem of $1 $2}" > "$file"
    sha512sum "$file" | cut -d' ' -f1
}

# record APP VERSION SHA512 [LOCATION]: one index record, the shape
# bt-aplinfo writes, Location under https://keel.test/, which is $SERVE.
record() {
    local loc="${4:-https://keel.test/debian-13-keel-$1_$2_amd64.tar.zst}"
    cat << RECORD
Package: keel-$1
Version: $2
Type: lxc
OS: debian-13
Section: keellinux
Architecture: amd64
Location: $loc
Infopage: https://keellinux.org/$1
ManageUrl: http://__IPADDRESS__/
sha512sum: $3
Description: Keel $1
 Keel $1 - test record

RECORD
}

# publish SIGNER: aplinfo.dat under $SERVE from $TMP/index, with the .gz
# and the detached armored .asc by SIGNER, the way bt-aplinfo writes them.
publish() {
    cp "$TMP/index" "$SERVE/aplinfo.dat"
    gzip -n -9 -c "$SERVE/aplinfo.dat" > "$SERVE/aplinfo.dat.gz"
    gpg --batch --quiet --yes --local-user "$1" --detach-sign --armor \
        -o "$SERVE/aplinfo.dat.asc" "$SERVE/aplinfo.dat" 2> /dev/null
}

# standard_index: keel-core 19.0-8 and keel-web 19.0-3, as the live index
# lists them, signed by a trusted throwaway key. Sets KEY, CORE_SHA, WEB_SHA.
standard_index() {
    KEY="$(make_signing_key keel-test)"
    trust "$KEY"
    CORE_SHA="$(make_template core 19.0-8)"
    WEB_SHA="$(make_template web 19.0-3)"
    { record core 19.0-8 "$CORE_SHA"; record web 19.0-3 "$WEB_SHA"; } > "$TMP/index"
    publish "$KEY"
}

# updated: standard_index served and keel-pve update run successfully.
updated() {
    standard_index
    run "$REPO/bin/keel-pve" update
    [ "$status" -eq 0 ]
}

# hanging_server: a TCP listener on 127.0.0.1 that accepts and never
# answers, for the time limits; sets PORT. It dies with the test's tree.
hanging_server() {
    python3 -c '
import socket, sys, time
s = socket.socket()
s.bind(("127.0.0.1", 0))
s.listen(8)
print(s.getsockname()[1], flush=True)
held = []
while True:
    c, _ = s.accept()
    held.append(c)
' > "$TMP/port" &
    echo $! > "$TMP/server.pid"
    while [ ! -s "$TMP/port" ]; do sleep 0.1; done
    PORT="$(cat "$TMP/port")"
    export PORT
}
