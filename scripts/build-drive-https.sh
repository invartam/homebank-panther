#!/bin/sh
# Offline, isolated build attempt. Never modifies /usr/bin/curl or the system SSL libraries.
set -eu
root=$(CDPATH= cd "$(dirname "$0")" && pwd)
case "$root" in *[!a-zA-Z0-9_./-]*) printf '%s\n' 'Extraire le kit dans un chemin simple, sans espaces ni caracteres speciaux.' >&2; exit 1 ;; esac
arch=${ARCH:-ppc}
jobs=${JOBS:-1}
case "$jobs" in ''|*[!0-9]*|0) printf '%s\n' 'JOBS doit etre un entier positif.' >&2; exit 1 ;; esac
case "$arch" in
    ppc) target_flags='-arch ppc -mcpu=750 -mno-altivec'; deployment=${DEPLOYMENT_TARGET:-10.3.9} ;;
    arm64|x86_64) target_flags="-arch $arch"; deployment=${DEPLOYMENT_TARGET:-13.0} ;;
    *) printf '%s\n' 'ARCH doit etre ppc, arm64 ou x86_64.' >&2; exit 1 ;;
esac
for tool in make unzip tar lipo otool; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'Outil absent : %s\n' "$tool" >&2; exit 1; }
done
for file in wolfssl-5.9.4.zip curl-8.22.0.tar.gz cacert.pem check-architecture.sh check-drive-https.sh check-curl-timeval.c; do
    test -f "$root/$file" || { printf 'Source manquante : %s. Utiliser le kit prepare sur le Mac recent.\n' "$file" >&2; exit 1; }
done
export CC=${CC:-gcc}
export MACOSX_DEPLOYMENT_TARGET="$deployment"
export CFLAGS="$target_flags -O2 -std=gnu99"
export LDFLAGS="$target_flags"
prefix="$root/out/$arch"
logs="$root/logs/$arch"
mkdir -p "$root/src" "$root/work/$arch/wolfssl" "$root/work/$arch/curl" "$prefix/share" "$logs"
cp "$root/cacert.pem" "$prefix/share/cacert.pem"
if [ ! -d "$root/src/wolfssl-5.9.4" ]; then unzip -q "$root/wolfssl-5.9.4.zip" -d "$root/src"; fi
if [ ! -d "$root/src/curl-8.22.0" ]; then tar -xzf "$root/curl-8.22.0.tar.gz" -C "$root/src"; fi

stage() {
    name=$1; shift
    printf '=== %s ===\n' "$name"
    if "$@" > "$logs/$name.log" 2>&1; then
        printf 'OK : %s\n' "$name"
    else
        code=$?
        printf 'Echec : %s (code %s). Journal : %s/%s.log\n' "$name" "$code" "$logs" "$name" >&2
        tail -n 45 "$logs/$name.log" >&2
        exit "$code"
    fi
}
# Keep stages in the main shell: old /bin/sh may continue after a failed subshell.
cd "$root/work/$arch/wolfssl" || exit 1
# Panther provides snprintf; avoid wolfSSL's unbounded sprintf fallback in C89 mode.
printf '%s\n' 'Profil Panther : TLS classique, ML-KEM et hybrides post-quantiques exclus (test PPC en echec).'
stage wolfssl-configure env CFLAGS="$CFLAGS -DXSNPRINTF=snprintf" /bin/sh "$root/src/wolfssl-5.9.4/configure" --prefix="$prefix" \
    --disable-shared --enable-static --enable-curl --enable-c89 --enable-sni --disable-oldtls \
    --disable-asm --disable-sp-asm --disable-sys-ca-certs \
    --disable-mlkem --disable-pqc-hybrids \
    --disable-examples --disable-benchmark --enable-crypttests
stage wolfssl-build make -j "$jobs"
stage wolfssl-crypto-tests ./wolfcrypt/test/testwolfcrypt
stage wolfssl-install make install
export CPPFLAGS="-I$prefix/include"
export LDFLAGS="$target_flags -L$prefix/lib"
export PKG_CONFIG_PATH="$prefix/lib/pkgconfig"
cd "$root/work/$arch/curl" || exit 1
# Cache the system type only after a real compile with legacy BSD include order.
stage curl-system-types "$CC" $CPPFLAGS $CFLAGS -c "$root/check-curl-timeval.c" -o timeval-check.o
export curl_cv_struct_timeval=yes
stage curl-configure /bin/sh "$root/src/curl-8.22.0/configure" --prefix="$prefix" --with-wolfssl="$prefix" \
    --disable-shared --enable-static --disable-dependency-tracking --disable-threaded-resolver \
    --without-libpsl --without-zlib --without-brotli --without-zstd --without-libidn2 --without-libssh2 \
    --without-nghttp2 --without-nghttp3 --without-ngtcp2 --disable-ldap --disable-ldaps \
    --without-apple-sectrust --disable-ca-native \
    --with-ca-bundle="$prefix/share/cacert.pem" --without-ca-path
stage curl-build make -j "$jobs"
stage curl-install make install
stage curl-architecture /bin/sh "$root/check-architecture.sh" "$arch" "$prefix/bin/curl"
stage curl-dependencies otool -L "$prefix/bin/curl"
"$prefix/bin/curl" -q --version
printf '\n%s\n' 'Compilation terminee. Test Google HTTPS avec certificats verifies :'
CURL_BIN="$prefix/bin/curl" CURL_CA_BUNDLE="$prefix/share/cacert.pem" /bin/sh "$root/check-drive-https.sh"
printf '\n%s\n' \
    'Client HTTPS construit et teste sur cette machine ; OAuth et synchronisation Drive ne sont pas encore implementes.' \
    'Le chemin CA est configure dans ce build. Si out est deplace, definir CURL_CA_BUNDLE vers share/cacert.pem.'
