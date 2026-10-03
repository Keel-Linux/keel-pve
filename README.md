# keel-pve

Signed Keel Linux container templates on a Proxmox VE 9 host.

`pveam` reads its template sources from a list built into pve-manager
(`PVE::APLInfo`), and there is no configuration to add one. `keel-pve` does
for the Keel index what `pveam` does for its own: it fetches
`aplinfo.dat.gz` and `aplinfo.dat.asc` from
`https://releases.keellinux.org/pve/`, verifies the signature with `sqv`
against the Keel archive key, and downloads a template into a storage's
`vztmpl` content after checking its sha512 against the signed index. From
there `pct create` and the web UI use it like any other template.

It changes no pve-manager file and survives pve-manager upgrades. Keel
templates do not appear in the web UI's **Templates** download dialog,
whose sources are fixed in pve-manager; they appear in the storage's
template list once downloaded.

## Usage

1. Add the Keel apt source. Fetch the archive key and check its
   fingerprint, `AD09 64BE 3F09 DED4 69A3 B6B2 148E 9513 1470 3180`:

       curl -fsSL https://archive.keellinux.org/keel-archive-keyring.asc \
         -o /tmp/keel-archive-keyring.asc
       gpg --show-keys /tmp/keel-archive-keyring.asc
       gpg --dearmor < /tmp/keel-archive-keyring.asc \
         > /usr/share/keyrings/keel-archive-keyring.gpg

   `/etc/apt/sources.list.d/keel.sources`:

       Types: deb
       URIs: https://archive.keellinux.org
       Suites: trixie
       Components: main
       Signed-By: /usr/share/keyrings/keel-archive-keyring.gpg

2. Install the package. `keel-archive-keyring` comes with it and from then
   on keeps the key current:

       apt update
       apt install keel-pve

   The package installs an apt pin, `/etc/apt/preferences.d/keel-pve`, so
   that on the hypervisor the Keel archive provides `keel-pve` and
   `keel-archive-keyring` and nothing else (priority -1 for every other
   package). Run nothing but this install between adding the source and
   having the pin.

3. Fetch and verify the index:

       keel-pve update
       keel-pve available

4. Download a template into a storage with `vztmpl` content, here `local`:

       keel-pve download local keel-web

5. Create the container in the web UI as usual (**Create CT**, template
   `local:vztmpl/debian-13-keel-web_<version>_amd64.tar.zst`), or:

       pct create 120 local:vztmpl/debian-13-keel-web_19.0-3_amd64.tar.zst \
         --hostname web --unprivileged 1 --net0 name=eth0,bridge=vmbr0,ip=dhcp

`keel-pve list` shows the Keel templates already in the storages. A daily
refresh of the index is shipped disabled:

    systemctl enable --now keel-pve-update.timer

See `keel-pve(8)` for the exit codes.

## Removal

`apt purge keel-pve` removes the program, the timer, the apt pin and
`/var/lib/keel-pve`. Remove `/etc/apt/sources.list.d/keel.sources` too, or
the Keel archive is back at apt's default priority.
Downloaded templates stay in their storage; remove them with
`pveam remove <storage>:vztmpl/<file>` or from the web UI.

## Development

    bats tests/              # the suite
    tests/coverage.sh        # under kcov, 95 percent gate (COVERAGE.md)
    dpkg-buildpackage -us -uc && lintian ../keel-pve_*.changes

The tests run against a fake `pvesm` and a local index served under
`https://keel.test/` (mapped onto a scratch directory) and signed with a
throwaway key generated in the test. No
test uses the project key, needs root or reaches the network.
