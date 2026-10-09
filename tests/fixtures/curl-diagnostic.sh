#!/bin/sh
set -eu
[ "${1:-}" = -q ] || exit 96
shift
if [ "${1:-}" = --version ]; then
    case "${DRIVE_CHECK_RESULT:-success}" in
        legacy_version_exit)
            printf '%s\n' 'curl 7.10.2 (powerpc-apple-darwin7.0) libcurl/7.10.2 OpenSSL/0.9.7b zlib/1.1.4'
            exit 2 ;;
        version_exit_2)
            printf '%s\n' 'curl fictif pour le diagnostic'
            exit 2 ;;
        *) printf '%s\n' 'curl fictif pour le diagnostic'; exit 0 ;;
    esac
fi
proto=no
tls=no
url=no
for argument do
    case "$argument" in
        '=https') proto=yes ;;
        --tlsv1.2) tls=yes ;;
        'https://accounts.google.com/.well-known/openid-configuration') url=yes ;;
        -k|--insecure|--location|-L) exit 99 ;;
    esac
done
[ "$proto:$tls:$url" = yes:yes:yes ] || exit 98
case "${DRIVE_CHECK_RESULT:-success}" in
    success|version_exit_2) printf '200' ;;
    http_error) printf '503' ;;
    legacy) printf '%s\n' 'curl: option --tlsv1.2 inconnue' >&2; exit 2 ;;
    legacy_version_exit) printf '%s\n' 'curl: option --proto inconnue' >&2; exit 2 ;;
    certificate) printf '%s\n' 'curl: verification du certificat impossible' >&2; exit 60 ;;
    *) exit 97 ;;
esac
