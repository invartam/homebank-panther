#!/bin/sh
set -eu
directory=$(mktemp -d "${TMPDIR:-/tmp}/homebank-https-tests.XXXXXX")
trap 'rm -rf "$directory"' EXIT HUP INT TERM
cp tests/fixtures/curl-diagnostic.sh "$directory/curl-test"
chmod 700 "$directory/curl-test"
export CURL_BIN="$directory/curl-test"

DRIVE_CHECK_RESULT=success /bin/sh scripts/check-drive-https.sh > "$directory/output" 2>&1
DRIVE_CHECK_RESULT=version_exit_2 /bin/sh scripts/check-drive-https.sh > "$directory/output" 2>&1
grep -q 'curl --version a renvoye 2' "$directory/output"
for result in legacy certificate http_error legacy_version_exit; do
    if DRIVE_CHECK_RESULT="$result" /bin/sh scripts/check-drive-https.sh > "$directory/output" 2>&1; then
        printf 'FAIL: diagnostic accepte un echec %s\n' "$result" >&2
        exit 1
    fi
    if [ "$result" = legacy_version_exit ]; then
        grep -q 'curl --version a renvoye 2' "$directory/output"
        grep -q 'Date du systeme' "$directory/output"
        grep -q 'Le test HTTPS moderne a echoue' "$directory/output"
    fi
done
if CURL_BIN="$directory/absent" /bin/sh scripts/check-drive-https.sh > "$directory/output" 2>&1; then
    printf '%s\n' 'FAIL: diagnostic accepte un client absent' >&2
    exit 1
fi
printf '%s\n' '7/7 HTTPS diagnostic checks passed (no network)'
