#!/bin/sh
# Builds the native libraries from pinned source, as static libraries for macOS 12
# (docs/building.md): the security key's libfido2, with the two it needs, libcbor and OpenSSL's
# libcrypto; and libsecp256k1, with its recovery module only, for KIFF's receipts:
#   scripts/fido.sh                 for this Mac's architecture
#   scripts/fido.sh x86_64 arm64    for each one named
# Each architecture gets build/fido/<arch>/include, with a module map Swift imports as CFido and
# CSecp256k1, and build/fido/<arch>/lib. Their licenses go to build/fido/licenses, which the app ships.
# Every source is checked against its pinned SHA-256 before it's unpacked, and nothing prebuilt
# is used. An architecture built by this script, as it is now, isn't built again.
# zlib, which libfido2 links, is the macOS SDK's.
set -eu
cd "$(dirname "$0")/.."

# The pins. Moving one: docs/building.md, "The native libraries".
FIDO_VERSION=1.17.0
FIDO_URL="https://developers.yubico.com/libfido2/Releases/libfido2-$FIDO_VERSION.tar.gz"
# The tarball whose release signature verified (key 78D9 97D5 3E9C 0A2A 2053 92ED 14A1 9784 723C 9988).
FIDO_SHA256=c1012c8871d71b65872fd5ff1a9d6b0838a55683a03e85ba97479ce57129c736
OPENSSL_VERSION=3.5.9
OPENSSL_URL="https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz"
# As openssl.org publishes it (openssl-3.5.9.tar.gz.sha256).
OPENSSL_SHA256=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
# libcbor publishes no tarball of its own: its tag, at a pinned commit, and the SHA-256 of its
# files (each file's SHA-256 and path, sorted, hashed), the version libfido2 1.17.0 builds with.
CBOR_VERSION=0.13.0
CBOR_GIT=https://github.com/PJK/libcbor
CBOR_COMMIT=9826a4315116a588f7416912db9da6fcecd8da11
CBOR_TREE_SHA256=9496e5ef09911b276f2dcbe9f4c47c19643cad71403de3a1a0e8a7cd3beda322
# libsecp256k1: the release the iPad's swift-secp256k1 0.24.0 vendors (its vendir.lock.yml), so
# the Mac recovers a receipt's signer with the same C code. Its tag at a pinned commit, and the
# SHA-256 of its files, as libcbor's.
SECP_VERSION=0.7.1
SECP_GIT=https://github.com/bitcoin-core/secp256k1
SECP_COMMIT=1a53f4961f337b4d166c25fce72ef0dc88806618
SECP_TREE_SHA256=8424a1c5fa69be87e8e5f39f6d64573ebe7a6ade0d120e6d50d75502d5d3adfa

ARCHS="${*:-$(uname -m)}"
OUT="$PWD/build/fido"
SRC="$OUT/src"
# What the stamp of a built architecture holds: this script's own hash.
STAMP=$(shasum -a 256 scripts/fido.sh | cut -d' ' -f1)
JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
export MACOSX_DEPLOYMENT_TARGET=12.0

for tool in cmake pkg-config clang make perl git curl shasum; do
    command -v "$tool" > /dev/null || { echo "scripts/fido.sh needs $tool" >&2; exit 1; }
done

sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }

# Downloads a tarball and unpacks it only if its SHA-256 is the pinned one.
fetch() { # name url sha256
    mkdir -p "$SRC"
    rm -rf "${SRC:?}/$1"
    tarball="$SRC/$1.tar.gz"
    [ -f "$tarball" ] || curl -fsSL --retry 3 -o "$tarball" "$2"
    got=$(sha256 "$tarball")
    if [ "$got" != "$3" ]; then
        rm -f "$tarball"
        echo "$1: SHA-256 $got, not the pinned $3" >&2
        exit 1
    fi
    mkdir -p "$SRC/$1"
    tar -xzf "$tarball" -C "$SRC/$1" --strip-components 1
}

# Clones a tag, then checks the commit and its files' SHA-256 (each file's SHA-256 and path,
# sorted, hashed).
fetch_git() { # name git tag commit tree_sha256
    rm -rf "${SRC:?}/$1"
    mkdir -p "$SRC"
    git -c advice.detachedHead=false clone -q --depth 1 --branch "$3" "$2" "$SRC/$1"
    commit=$(git -C "$SRC/$1" rev-parse HEAD)
    [ "$commit" = "$4" ] || { echo "$1: commit $commit, not the pinned $4" >&2; exit 1; }
    tree=$(cd "$SRC/$1" && find . -type f ! -path './.git/*' -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 | shasum -a 256 | cut -d' ' -f1)
    [ "$tree" = "$5" ] || { echo "$1: files' SHA-256 $tree, not the pinned $5" >&2; exit 1; }
}

# The licenses the app ships, from the sources checked above.
licenses() {
    mkdir -p "$OUT/licenses"
    cp "$SRC/libfido2/LICENSE" "$OUT/licenses/libfido2.txt"
    cp "$SRC/libcbor/LICENSE.md" "$OUT/licenses/libcbor.txt"
    cp "$SRC/openssl/LICENSE.txt" "$OUT/licenses/openssl.txt"
    cp "$SRC/secp256k1/COPYING" "$OUT/licenses/secp256k1.txt"
}

build_openssl() { # arch prefix
    case "$1" in
        x86_64) target=darwin64-x86_64-cc ;;
        arm64) target=darwin64-arm64-cc ;;
        *) echo "No OpenSSL target for $1" >&2; exit 1 ;;
    esac
    dir="$OUT/work/$1/openssl"
    rm -rf "$dir"
    cp -R "$SRC/openssl" "$dir"
    # libcrypto alone is used: no shared library, modules, engines, apps, tests or docs.
    (cd "$dir" && ./Configure "$target" no-shared no-module no-tests no-apps no-docs no-legacy no-engine \
        no-dso no-comp no-quic no-ssl3 no-dtls --prefix="$2" --libdir=lib "-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET" \
        && make -j"$JOBS" build_libs > build.log && make install_dev > install.log) \
        || { tail -40 "$dir/build.log" >&2 2>/dev/null; exit 1; }
}

build_cmake() { # name arch prefix [options]
    name=$1; arch=$2; prefix=$3; shift 3
    dir="$OUT/work/$arch/$name"
    rm -rf "$dir"
    cmake -S "$SRC/$name" -B "$dir" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
        -DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
        -DCMAKE_PREFIX_PATH="$prefix" "$@" > "$dir.log"
    cmake --build "$dir" -j "$JOBS" >> "$dir.log" || { tail -40 "$dir.log" >&2; exit 1; }
    cmake --install "$dir" >> "$dir.log"
}

fetched=false
for arch in $ARCHS; do
    prefix="$OUT/$arch"
    if [ -f "$prefix/.stamp" ] && [ "$(cat "$prefix/.stamp")" = "$STAMP" ] && [ -f "$OUT/licenses/libfido2.txt" ] \
        && [ -f "$OUT/licenses/secp256k1.txt" ]; then
        echo "libfido2 $FIDO_VERSION and libsecp256k1 $SECP_VERSION for $arch: built"
        continue
    fi
    if [ "$fetched" = false ]; then
        fetch libfido2 "$FIDO_URL" "$FIDO_SHA256"
        fetch openssl "$OPENSSL_URL" "$OPENSSL_SHA256"
        fetch_git libcbor "$CBOR_GIT" "v$CBOR_VERSION" "$CBOR_COMMIT" "$CBOR_TREE_SHA256"
        fetch_git secp256k1 "$SECP_GIT" "v$SECP_VERSION" "$SECP_COMMIT" "$SECP_TREE_SHA256"
        licenses
        fetched=true
    fi
    echo "Building libfido2 $FIDO_VERSION, libcbor $CBOR_VERSION, OpenSSL $OPENSSL_VERSION and libsecp256k1 $SECP_VERSION for $arch"
    rm -rf "$prefix"
    mkdir -p "$prefix/lib/pkgconfig" "$OUT/work/$arch"
    build_openssl "$arch" "$prefix"
    build_cmake libcbor "$arch" "$prefix" -DBUILD_SHARED_LIBS=OFF -DWITH_EXAMPLES=OFF -DWITH_TESTS=OFF
    # libfido2 finds its three through pkg-config: libcbor's and libcrypto's as installed above,
    # and the SDK's zlib, which has no .pc of its own.
    printf 'Name: zlib\nDescription: the macOS SDK'"'"'s zlib\nVersion: 1.2\nLibs: -lz\nCflags:\n' > "$prefix/lib/pkgconfig/zlib.pc"
    PKG_CONFIG_PATH="$prefix/lib/pkgconfig" PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig" \
        build_cmake libfido2 "$arch" "$prefix" -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON \
        -DBUILD_EXAMPLES=OFF -DBUILD_MANPAGES=OFF -DBUILD_TOOLS=OFF -DBUILD_TESTS=OFF
    # libsecp256k1 with its recovery module alone: every other module, the tests, the benchmarks
    # and the examples off.
    build_cmake secp256k1 "$arch" "$prefix" -DBUILD_SHARED_LIBS=OFF -DSECP256K1_ENABLE_MODULE_RECOVERY=ON \
        -DSECP256K1_ENABLE_MODULE_ECDH=OFF -DSECP256K1_ENABLE_MODULE_EXTRAKEYS=OFF \
        -DSECP256K1_ENABLE_MODULE_SCHNORRSIG=OFF -DSECP256K1_ENABLE_MODULE_MUSIG=OFF \
        -DSECP256K1_ENABLE_MODULE_ELLSWIFT=OFF -DSECP256K1_BUILD_BENCHMARK=OFF -DSECP256K1_BUILD_TESTS=OFF \
        -DSECP256K1_BUILD_EXHAUSTIVE_TESTS=OFF -DSECP256K1_BUILD_CTIME_TESTS=OFF -DSECP256K1_BUILD_EXAMPLES=OFF
    # What Swift imports: fido.h, linked with the three static libraries, the SDK's zlib and the
    # frameworks libfido2's USB HID code uses; and libsecp256k1's two headers, linked with it.
    cat > "$prefix/include/module.modulemap" <<'MAP'
module CFido [system] {
    header "fido.h"
    link "fido2"
    link "cbor"
    link "crypto"
    link "z"
    link framework "IOKit"
    link framework "CoreFoundation"
    export *
}
module CSecp256k1 [system] {
    header "secp256k1.h"
    header "secp256k1_recovery.h"
    link "secp256k1"
    export *
}
MAP
    for lib in libfido2.a libcbor.a libcrypto.a libsecp256k1.a; do
        [ -f "$prefix/lib/$lib" ] || { echo "$lib wasn't built for $arch" >&2; exit 1; }
    done
    # Only the static libraries: nothing shared is left for the linker to pick instead.
    find "$prefix/lib" -name '*.dylib' -delete
    echo "$STAMP" > "$prefix/.stamp"
    rm -rf "$OUT/work/$arch"
    echo "Built libfido2 $FIDO_VERSION for $arch: $prefix"
done
