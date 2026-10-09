#!/bin/sh
set -eu
project=$(pwd)
directory=$(mktemp -d /tmp/homebank-https-build-tests.XXXXXX)
trap 'rm -rf "$directory"' EXIT HUP INT TERM
mkdir "$directory/bin"
for tool in make lipo otool cc; do
    cp tests/fixtures/https-build-tool.sh "$directory/bin/$tool"
    chmod 700 "$directory/bin/$tool"
done
export PATH="$directory/bin:$PATH"
export HTTPS_TEST_CURL="$project/tests/fixtures/curl-diagnostic.sh"
export ARCH=ppc
export JOBS=1
export CC="$directory/bin/cc"
unset DRIVE_CHECK_RESULT
checks=0

setup() {
    kit="$directory/$1"
    mkdir -p "$kit/src/wolfssl-5.9.4" "$kit/src/curl-8.22.0" "$kit/work/ppc/wolfssl/wolfcrypt/test"
    cp scripts/build-drive-https.sh "$kit/build.sh"
    cp scripts/check-architecture.sh scripts/check-drive-https.sh "$kit/"
    cp scripts/check-curl-timeval.c "$kit/"
    for file in wolfssl-5.9.4.zip curl-8.22.0.tar.gz cacert.pem; do cp tests/fixtures/https-build-placeholder.txt "$kit/$file"; done
    cp tests/fixtures/https-build-tool.sh "$kit/src/wolfssl-5.9.4/configure"
    cp tests/fixtures/https-build-tool.sh "$kit/src/curl-8.22.0/configure"
    cp tests/fixtures/https-build-tool.sh "$kit/work/ppc/wolfssl/wolfcrypt/test/testwolfcrypt"
    chmod 700 "$kit/work/ppc/wolfssl/wolfcrypt/test/testwolfcrypt"
    export HTTPS_TEST_LOG="$kit/events"
}

for failure in wolfssl-configure wolfssl-build wolfssl-crypto-tests wolfssl-install curl-system-types curl-configure curl-build curl-install curl-architecture curl-dependencies; do
    setup "$failure"
    if HTTPS_TEST_FAIL="$failure" /bin/sh "$kit/build.sh" > "$kit/output" 2>&1; then
        printf 'FAIL: construction acceptee apres %s\n' "$failure" >&2; exit 1
    fi
    [ "$(tail -n 1 "$HTTPS_TEST_LOG")" = "$failure" ] || { printf 'FAIL: poursuite apres %s\n' "$failure" >&2; exit 1; }
    grep -q "Echec : $failure" "$kit/output"
    checks=$((checks + 1))
done
setup success
/bin/sh "$kit/build.sh" > "$kit/output" 2>&1
[ "$(tail -n 1 "$HTTPS_TEST_LOG")" = curl-dependencies ]
grep -q 'Connexion HTTPS Google validee' "$kit/output"
checks=$((checks + 1))

setup wrong-architecture
if HTTPS_TEST_ARCH=i386 /bin/sh "$kit/build.sh" > "$kit/output" 2>&1; then
    printf '%s\n' 'FAIL: architecture incorrecte acceptee' >&2; exit 1
fi
[ "$(tail -n 1 "$HTTPS_TEST_LOG")" = curl-architecture ]
checks=$((checks + 1))

HTTPS_TEST_LIPO_STYLE=fat /bin/sh scripts/check-architecture.sh ppc /fictitious/ppc/binary > "$directory/output" 2>&1
checks=$((checks + 1))
if HTTPS_TEST_LIPO_STYLE=fat /bin/sh scripts/check-architecture.sh arm64 /fictitious/arm64/binary > "$directory/output" 2>&1; then
    printf '%s\n' 'FAIL: architecture absente du binaire universel acceptee' >&2; exit 1
fi
checks=$((checks + 1))
if HTTPS_TEST_LIPO_STYLE=unknown /bin/sh scripts/check-architecture.sh ppc /fictitious/ppc/binary > "$directory/output" 2>&1; then
    printf '%s\n' 'FAIL: sortie lipo inconnue acceptee' >&2; exit 1
fi
checks=$((checks + 1))
printf '%s/15 HTTPS build checks passed (mocked tools, no network)\n' "$checks"
