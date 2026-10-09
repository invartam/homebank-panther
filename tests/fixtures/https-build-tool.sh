#!/bin/sh
set -eu
tool=$(basename "$0")
case "$tool" in
    configure)
        case "$(pwd)" in */wolfssl) name=wolfssl-configure ;; */curl) name=curl-configure ;; *) exit 90 ;; esac
        if [ "$name" = wolfssl-configure ]; then
            case " $* " in *' --disable-asm '*) : ;; *) exit 91 ;; esac
            case " $* " in *' --disable-oldtls '*) : ;; *) exit 92 ;; esac
            case " $* " in *' --disable-sys-ca-certs '*) : ;; *) exit 96 ;; esac
            case " ${CFLAGS:-} " in *' -DXSNPRINTF=snprintf '*) : ;; *) exit 100 ;; esac
            case " $* " in *' --disable-mlkem '*) : ;; *) exit 101 ;; esac
            case " $* " in *' --disable-pqc-hybrids '*) : ;; *) exit 102 ;; esac
            case " $* " in *' --enable-crypttests '*) : ;; *) exit 103 ;; esac
        else
            [ "${curl_cv_struct_timeval:-}" = yes ] || exit 104
            case " $* " in *' --without-apple-sectrust '*) : ;; *) exit 97 ;; esac
            case " $* " in *' --disable-ca-native '*) : ;; *) exit 98 ;; esac
            case " $* " in *' --with-ca-bundle='*'/share/cacert.pem '*) : ;; *) exit 99 ;; esac
        fi ;;
    make)
        case "$(pwd)" in */wolfssl) name=wolfssl ;; */curl) name=curl ;; *) exit 93 ;; esac
        if [ "${1:-}" = install ]; then name="$name-install"; else name="$name-build"; fi ;;
    testwolfcrypt) name=wolfssl-crypto-tests ;;
    cc)
        name=curl-system-types
        case " $* " in *' -c '*'/check-curl-timeval.c '*) : ;; *) exit 105 ;; esac ;;
    lipo)
        [ "${1:-}" = -info ] || exit 94
        name=curl-architecture ;;
    otool) name=curl-dependencies ;;
    *) exit 95 ;;
esac
printf '%s\n' "$name" >> "$HTTPS_TEST_LOG"
if [ "${HTTPS_TEST_FAIL:-}" = "$name" ]; then exit 17; fi
if [ "$name" = curl-install ]; then
    root=$(CDPATH= cd ../../.. && pwd)
    arch=$(basename "$(dirname "$(pwd)")")
    mkdir -p "$root/out/$arch/bin"
    cp "$HTTPS_TEST_CURL" "$root/out/$arch/bin/curl"
    chmod 700 "$root/out/$arch/bin/curl"
fi
if [ "$tool" = lipo ]; then
    case "${HTTPS_TEST_LIPO_STYLE:-thin}" in
        thin) printf 'Non-fat file: %s is architecture: %s\n' "$2" "${HTTPS_TEST_ARCH:-ppc}" ;;
        fat) printf 'Architectures in the fat file: %s are: ppc i386\n' "$2" ;;
        unknown) printf '%s\n' 'unrecognized lipo output' ;;
    esac
fi
if [ "$tool" = otool ]; then printf '%s\n' '/usr/lib/libSystem.B.dylib'; fi
