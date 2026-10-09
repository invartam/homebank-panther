#!/bin/sh
# Public connectivity probe only: no wallet, OAuth client or token is read.
set -eu

curl_bin=${CURL_BIN:-curl}
if ! command -v "$curl_bin" >/dev/null 2>&1; then
    printf '%s\n' 'curl introuvable. Un client HTTPS recent compatible PowerPC est necessaire.' >&2
    exit 1
fi

printf '%s\n' '=== Client HTTPS ==='
# curl 7.10.2 exits with 2 after successfully printing --version.
if "$curl_bin" -q --version; then
    :
else
    version_status=$?
    printf 'Avertissement : curl --version a renvoye %s ; poursuite du diagnostic.\n' "$version_status" >&2
fi
printf '\n%s\n' '=== Date du systeme ==='
date -u
printf '\n%s\n' '=== Connexion Google, TLS 1.2 minimum et certificats verifies ==='
if ! status=$("$curl_bin" -q --proto '=https' --tlsv1.2 \
    --connect-timeout 10 --max-time 30 --silent --show-error \
    --output /dev/null --write-out '%{http_code}' \
    'https://accounts.google.com/.well-known/openid-configuration'); then
    printf '%s\n' \
        'Le test HTTPS moderne a echoue.' \
        'Verifier le reseau, la date et les autorites de certification.' \
        'Si curl ne reconnait pas les options, installer un client HTTPS recent.' \
        'Ne pas ajouter --insecure ou -k : ce test ne doit pas contourner les certificats.' >&2
    exit 1
fi
if [ "$status" != 200 ]; then
    printf 'Reponse Google inattendue : HTTP %s. La connexion directe reste a verifier.\n' "$status" >&2
    exit 1
fi
printf '%s\n' \
    'Connexion HTTPS Google validee avec ce client.' \
    'Cela ne valide pas encore OAuth, les API Drive, ni une synchronisation de fichiers.'
