#!/bin/sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
FIREFOX_DIR="$ROOT_DIR/engine/firefox"

TARGET="aarch64-apple-ios"

cd "$ROOT_DIR"

if [ ! -d "$FIREFOX_DIR" ]; then
	echo "Missing firefox source at $FIREFOX_DIR"
	echo "Add the submodule, then run tools/development/update-gecko.sh."
	exit 1
fi

rm -f "$FIREFOX_DIR/.mozconfig"

# moz.configure's own linker autodetection (it probes `clang ... -Wl,--version`)
# can fail against newer Xcode toolchains whose default linker doesn't answer
# that probe the way Firefox's build system expects, surfacing as
# "ERROR: Failed to find an adequate linker" during ./mach build. Point it at
# a real lld (from Homebrew's llvm) instead of leaving it to guess from
# whatever Xcode ships as the default linker.
LLVM_PREFIX="$(brew --prefix llvm 2>/dev/null || true)"
if [ -z "$LLVM_PREFIX" ] || [ ! -x "$LLVM_PREFIX/bin/ld64.lld" ]; then
	echo "Homebrew's llvm (with ld64.lld) is required; run 'brew install llvm' first." >&2
	exit 1
fi

{
	echo "ac_add_options --enable-application=mobile/ios"
	echo "ac_add_options --target=$TARGET"
	echo "ac_add_options --enable-ios-target=13.0"
	echo "ac_add_options --enable-webrtc"
	echo "ac_add_options --enable-optimize"
	echo "ac_add_options --disable-debug"
	echo "ac_add_options --disable-tests"
	echo "ac_add_options --enable-linker=lld"
	echo "mk_add_options 'export PATH=$LLVM_PREFIX/bin:\$PATH'"
} > "$FIREFOX_DIR/.mozconfig"

if ! rustup target list | grep -q "^$TARGET (installed)"; then
	rustup target add "$TARGET"
fi

cd "$FIREFOX_DIR"
./mach build
