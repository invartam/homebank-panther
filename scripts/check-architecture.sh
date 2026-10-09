#!/bin/sh
# lipo -verify_arch is unavailable in Panther's developer tools.
set -efu
if [ "$#" -ne 2 ]; then
    printf '%s\n' 'Usage: check-architecture.sh architecture binaire' >&2
    exit 1
fi
expected=$1
if ! info=$(lipo -info "$2" 2>&1); then
    printf '%s\n' "$info" >&2
    exit 1
fi
printf '%s\n' "$info"
case "$info" in
    *'architecture:'*|*'are:'*) architectures=${info##*:} ;;
    *) printf '%s\n' 'Sortie lipo non reconnue : architecture non validee.' >&2; exit 1 ;;
esac
for architecture in $architectures; do
    if [ "$architecture" = "$expected" ]; then exit 0; fi
done
printf 'Architecture %s absente : paquet refuse.\n' "$expected" >&2
exit 1
