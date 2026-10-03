# aplinfo.awk: the records of a Keel template index, one tab separated
# line each: package, version, template file name, sha512, location and the
# Description headline. Exits non-zero with a message on stderr when a
# record is not one pveam would accept (PVE::APLInfo::read_aplinfo_from_fh,
# the version pattern included) or the index holds no record.
#
#   NAME_RE=<template file name pattern> awk -f aplinfo.awk aplinfo.dat
function flush() {
    if (!seen) return
    n++
    if (f["Package"] !~ /^[a-z0-9][a-z0-9.+-]*$/) bad("Package")
    if (f["Version"] !~ /^[0-9][A-Za-z0-9.+:~-]*$/) bad("Version")
    if (f["Type"] != "lxc") bad("Type")
    if (f["sha512sum"] !~ /^[0-9a-f]+$/ || length(f["sha512sum"]) != 128) bad("sha512sum")
    loc = f["Location"]
    tmpl = loc
    sub(/.*\//, "", tmpl)
    # https only, a host, and a last path segment that is a template name
    # (no "..", no leading dot, no slash, no query).
    if (loc !~ /^https:\/\/[^\/?#]+\/[^?#]*$/ || tmpl !~ ENVIRON["NAME_RE"]) bad("Location")
    if (f["Description"] == "") bad("Description")
    out[n] = f["Package"] "\t" f["Version"] "\t" tmpl "\t" f["sha512sum"] "\t" loc "\t" f["Description"]
    delete f
    seen = 0
}
function bad(key) {
    printf "keel-pve: index record %d (%s): invalid or missing %s\n", n, f["Package"], key > "/dev/stderr"
    err = 1
}
/^[[:space:]]*$/ { flush(); next }
/^[[:space:]]/ { next }
{
    i = index($0, ":")
    if (i == 0) { next }
    key = substr($0, 1, i - 1)
    val = substr($0, i + 1)
    sub(/^[[:space:]]+/, "", val)
    sub(/[[:space:]]+$/, "", val)
    f[key] = val
    seen = 1
}
END {
    flush()
    if (err) exit 1
    if (n == 0) {
        print "keel-pve: the index lists no template" > "/dev/stderr"
        exit 1
    }
    for (i = 1; i <= n; i++) print out[i]
}
