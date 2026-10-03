# Coverage of keel-pve

Standard: 95 percent of executed lines for code the project writes
(decision 0003), measured with bats under kcov (decision 0004). The
threshold lives in `tests/coverage.sh` (`COVERAGE_THRESHOLD`, default 95)
and in `.github/workflows/tests.yml`.

```
bats tests/
tests/coverage.sh
```

Needs `bats`, `kcov`, `gnupg`, `sqv`, `curl`, `apt-utils` and `python3`.
The index and the templates have `https://keel.test/` URLs that a curl
wrapper maps onto a scratch directory before running the real curl. They
are signed with a throwaway Ed25519 key generated in the test and verified
with the real sqv. The time limits are tested against a python3 listener
on 127.0.0.1 that never answers; `pvesm` and `id` are PATH stubs. No test
uses the project key, needs root or reaches the network.

`lib/aplinfo.awk`, the record parser, is not a shell file and kcov does not
measure it; every rule in it is exercised by `tests/update.bats` and
`tests/available.bats`.

## Measured at the first release

2026-10-03, 69 tests, kcov 43 on Debian 13:

| File | Lines | Covered | Percent |
| --- | --- | --- | --- |
| `bin/keel-pve` | 3 | 3 | 100.00 |
| `lib/main.sh` | 29 | 29 | 100.00 |
| `lib/common.sh` | 42 | 42 | 100.00 |
| `lib/index.sh` | 50 | 50 | 100.00 |
| `lib/storage.sh` | 22 | 22 | 100.00 |
| `lib/commands.sh` | 53 | 53 | 100.00 |
| total | | | 100.00 |
