#!/bin/sh
# Build SDL3 universal (arm64 + x86_64) for macOS 12+ into build/sdl3, so GOOSE.app runs on older macOS.
set -e
cd "$(dirname "$0")/.."
V=3.4.12
T=build/sdl-src
mkdir -p "$T"
[ -f "$T/SDL3-$V.tar.gz" ] || curl -sSL --fail -o "$T/SDL3-$V.tar.gz" "https://github.com/libsdl-org/SDL/releases/download/release-$V/SDL3-$V.tar.gz"
tar xzf "$T/SDL3-$V.tar.gz" -C "$T"
cmake -S "$T/SDL3-$V" -B "$T/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
      "-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64" -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF \
      -DCMAKE_INSTALL_PREFIX="$PWD/build/sdl3" >/dev/null
cmake --build "$T/build" -j 8 >/dev/null
cmake --install "$T/build" >/dev/null
echo "SDL3 $V -> build/sdl3"
