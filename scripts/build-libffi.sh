#!/usr/bin/env bash
# Build libffi for Switch and install it into $DEVKITPRO/portlibs/switch
# (Clearwing uses it for method reflection; devkitPro has no package for it).
# Locally this needs write access to $DEVKITPRO, e.g. run it with sudo -E.
set -euo pipefail

: "${DEVKITPRO:=/opt/devkitpro}"
export DEVKITPRO
VER=3.4.6
PORTLIBS="$DEVKITPRO/portlibs/switch"

if [ -f "$PORTLIBS/lib/libffi.a" ] && [ -f "$PORTLIBS/include/ffi.h" ]; then
    echo "libffi already installed"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
curl -sSLf -o libffi.tar.gz "https://github.com/libffi/libffi/releases/download/v$VER/libffi-$VER.tar.gz"
tar xf libffi.tar.gz
cd "libffi-$VER"

if [ -f "$DEVKITPRO/switchvars.sh" ]; then
    # shellcheck disable=SC1091
    source "$DEVKITPRO/switchvars.sh"
else
    export PATH="$DEVKITPRO/devkitA64/bin:$PATH"
    export CC=aarch64-none-elf-gcc AR=aarch64-none-elf-ar RANLIB=aarch64-none-elf-ranlib
fi
CFLAGS="-g -O2 -march=armv8-a -mtune=cortex-a57 -mtp=soft -fPIC -ftls-model=local-exec" \
    ./configure --prefix="$PORTLIBS" --host=aarch64-none-elf --disable-shared --enable-static \
    --disable-docs --disable-multi-os-directory
make -j"$(nproc)"
make install
ls -la "$PORTLIBS/lib/libffi.a" "$PORTLIBS/include/ffi.h"
