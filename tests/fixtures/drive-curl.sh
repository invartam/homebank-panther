#!/bin/sh
# Mock transport: never performs a network request or records stdin credentials.
set -eu
[ "$1" = -q ] || exit 91
output=
proto=no
tls=no
configuration=no
while [ "$#" -gt 0 ]; do
    case "$1" in
        --config) shift; [ "$1" = - ] || exit 92; configuration=yes ;;
        --proto) shift; [ "$1" = '=https' ] || exit 93; proto=yes ;;
        --tlsv1.2) tls=yes ;;
        --output) shift; output=$1 ;;
        *dummy-token*|*assertion*) exit 94 ;;
    esac
    shift
done
[ "$proto:$tls:$configuration" = yes:yes:yes ] || exit 95
case "$output" in /tmp/homebank-drive-*/response) : ;; *) exit 96 ;; esac
found=no
while IFS= read -r line; do
    case "$line" in 'header = "Authorization: Bearer dummy-token"') found=yes ;; esac
done
[ "$found" = yes ] || exit 97
printf '%s' '{"mock":true}' > "$output"
printf '%s' 200
