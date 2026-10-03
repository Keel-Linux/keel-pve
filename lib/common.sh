# shellcheck shell=bash disable=SC2034
# Paths, exit codes and messages. Sourced by lib/main.sh first.
#
# Every path is overridable from the environment so the tests run against a
# scratch tree:
#   KEEL_PVE_INDEX_URL  the signed index; .gz and .asc are appended
#   KEEL_PVE_KEYRING    the keyring keel-archive-keyring installs, the only
#                       keys an index or a template checksum is trusted from
#   KEEL_PVE_STATE_DIR  where the verified index and its signature are kept
#   KEEL_PVE_PROTOCOLS  curl's --proto list for every transfer
#   KEEL_PVE_CONNECT_TIMEOUT, KEEL_PVE_INDEX_MAX_TIME,
#   KEEL_PVE_TEMPLATE_MAX_TIME  seconds curl may spend connecting, and on
#                       the whole transfer of an index file or a template
#   KEEL_PVE_LOCK_WAIT  seconds to wait for the lock of the state directory

KEEL_PVE_VERSION="0.1.0"
KEEL_PVE_INDEX_URL="${KEEL_PVE_INDEX_URL:-https://releases.keellinux.org/pve/aplinfo.dat}"
KEEL_PVE_KEYRING="${KEEL_PVE_KEYRING:-/usr/share/keyrings/keel-archive-keyring.gpg}"
KEEL_PVE_STATE_DIR="${KEEL_PVE_STATE_DIR:-/var/lib/keel-pve}"
KEEL_PVE_PROTOCOLS="${KEEL_PVE_PROTOCOLS:-=https}"
KEEL_PVE_CONNECT_TIMEOUT="${KEEL_PVE_CONNECT_TIMEOUT:-30}"
# The index is a few kilobytes; a template is a few hundred megabytes, and
# two hours still lets one through at about 50 kB/s.
KEEL_PVE_INDEX_MAX_TIME="${KEEL_PVE_INDEX_MAX_TIME:-120}"
KEEL_PVE_TEMPLATE_MAX_TIME="${KEEL_PVE_TEMPLATE_MAX_TIME:-7200}"
KEEL_PVE_LOCK_WAIT="${KEEL_PVE_LOCK_WAIT:-600}"

# The file name extensions pve-storage accepts for a vztmpl volume
# ($PVE::Storage::VZTMPL_EXT_RE_1), as an extended regular expression.
VZTMPL_NAME_RE='^[A-Za-z0-9][A-Za-z0-9._+-]*\.tar(\.(gz|xz|zst|bz2))?$'

EXIT_OK=0
EXIT_USAGE=1
EXIT_NEEDS_ROOT=2
EXIT_UNVERIFIED=3
EXIT_FETCH_FAILED=4
EXIT_NOT_FOUND=5
EXIT_CHECKSUM=6
EXIT_WRITE_FAILED=7
EXIT_KEYRING_MISSING=8

say() { printf '%s\n' "$*"; }
warn() { printf 'keel-pve: %s\n' "$*" >&2; }

# need_root: update and download write as root; refuse early otherwise.
need_root() {
    if [ "$(id -u)" != 0 ]; then
        warn "must run as root"
        return "$EXIT_NEEDS_ROOT"
    fi
}

# need_keyring: the keyring every verification uses.
need_keyring() {
    if [ ! -s "$KEEL_PVE_KEYRING" ]; then
        warn "no keyring at $KEEL_PVE_KEYRING; install keel-archive-keyring"
        return "$EXIT_KEYRING_MISSING"
    fi
}

# fetch URL OUT MAX_TIME: one transfer with curl, refusing any protocol
# outside KEEL_PVE_PROTOCOLS, also after a redirect, and giving up after
# KEEL_PVE_CONNECT_TIMEOUT seconds connecting or MAX_TIME seconds in all.
fetch() {
    curl --fail --silent --show-error --location \
        --proto "$KEEL_PVE_PROTOCOLS" --proto-redir "$KEEL_PVE_PROTOCOLS" \
        --connect-timeout "$KEEL_PVE_CONNECT_TIMEOUT" --max-time "$3" \
        --output "$2" -- "$1"
}

# with_lock -x|-s COMMAND...: COMMAND under the exclusive or shared lock of
# the state directory, waiting KEEL_PVE_LOCK_WAIT seconds at most. The lock
# is released on every path, COMMAND's status returned.
with_lock() {
    local mode="$1" fd="" status
    shift
    # The group scopes the 2> to the exec; the new descriptor stays open,
    # and fd stays empty when the open fails.
    if [ "$mode" = -x ]; then
        { exec {fd}>> "$KEEL_PVE_STATE_DIR/lock"; } 2> /dev/null
    else
        { exec {fd}< "$KEEL_PVE_STATE_DIR/lock"; } 2> /dev/null
    fi
    if [ -z "$fd" ]; then
        warn "cannot open $KEEL_PVE_STATE_DIR/lock"
        return "$EXIT_WRITE_FAILED"
    fi
    if flock "$mode" -w "$KEEL_PVE_LOCK_WAIT" "$fd"; then
        "$@"
        status=$?
    else
        warn "$KEEL_PVE_STATE_DIR is busy: another keel-pve holds its lock"
        status="$EXIT_WRITE_FAILED"
    fi
    exec {fd}>&-
    return "$status"
}

# verify_signature SIG DATA: the call pveam makes (PVE::APLInfo), with the
# Keel keyring in place of pve-manager's.
verify_signature() {
    sqv --keyring "$KEEL_PVE_KEYRING" "$1" "$2" > /dev/null
}
