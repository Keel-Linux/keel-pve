# shellcheck shell=bash
# pve_main: the argument parsing and dispatch of keel-pve(8).

KEEL_PVE_LIB="${KEEL_PVE_LIB:-/usr/lib/keel-pve}"
. "$KEEL_PVE_LIB/common.sh"
. "$KEEL_PVE_LIB/index.sh"
. "$KEEL_PVE_LIB/storage.sh"
. "$KEEL_PVE_LIB/commands.sh"
. "$KEEL_PVE_LIB/source.sh"

pve_usage() {
    cat << USAGE
usage: keel-pve update
       keel-pve available
       keel-pve download STORAGE TEMPLATE
       keel-pve list

Signed Keel Linux container templates on a Proxmox VE host.

  update      fetch the Keel template index and verify its signature with
              sqv against /usr/share/keyrings/keel-archive-keyring.gpg
  available   list the templates of the verified index
  download STORAGE TEMPLATE
              download TEMPLATE (a package such as keel-web, or a template
              file name) into the vztmpl content of STORAGE, check its
              sha512 against the signed index, and keep it only if it matches
  list        show the Keel templates already in the storages

A downloaded template is used like any other: pct create, or Create CT in
the web UI. Keel templates do not appear in the Templates download dialog,
whose sources are fixed in pve-manager.
USAGE
}

pve_main() {
    local cmd="${1:-}"
    [ "$#" -gt 0 ] && shift
    case "$cmd" in
        -h | --help | help)
            pve_usage
            return "$EXIT_OK"
            ;;
        --version)
            say "keel-pve $KEEL_PVE_VERSION"
            return "$EXIT_OK"
            ;;
        update | available | list)
            pve_args 0 "$cmd" "$@" || return
            ;;
        download)
            pve_args 2 "download STORAGE TEMPLATE" "$@" || return
            ;;
        "")
            pve_usage >&2
            return "$EXIT_USAGE"
            ;;
        *)
            warn "unknown subcommand: $cmd (see keel-pve --help)"
            return "$EXIT_USAGE"
            ;;
    esac
    source_hint
    case "$cmd" in
        update) index_update ;;
        available) cmd_available ;;
        list) cmd_list ;;
        download) cmd_download "$1" "$2" ;;
    esac
}

# pve_args COUNT SHAPE ARGS...: exactly COUNT arguments, or a usage error.
pve_args() {
    local want="$1" shape="$2"
    shift 2
    if [ "$#" -ne "$want" ]; then
        warn "usage: keel-pve $shape"
        return "$EXIT_USAGE"
    fi
}
