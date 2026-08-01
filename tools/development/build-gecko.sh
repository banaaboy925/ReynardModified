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
# a real lld (from Homebrew's lld formula) instead of leaving it to guess
# from whatever Xcode ships as the default linker.
LLD_PREFIX="$(brew --prefix lld 2>/dev/null || true)"
if [ -z "$LLD_PREFIX" ] || [ ! -x "$LLD_PREFIX/bin/ld64.lld" ]; then
	echo "Homebrew's lld (with ld64.lld) is required; run 'brew install lld' first." >&2
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
} > "$FIREFOX_DIR/.mozconfig"

# Prepend lld's bin dir to PATH here, in a real shell, rather than via
# mozconfig's `mk_add_options 'export PATH=...'`. That directive is only
# partially parsed by mozbuild's Python mozconfig reader (not run through an
# actual shell), so a trailing "$PATH" in it is never expanded - it ends up
# replacing PATH with a literal string missing /bin, breaking mozconfig's own
# `sh` lookup (FileNotFoundError: No such file or directory: 'sh') before the
# build even starts. Exporting it in this script's real environment instead
# means every subprocess mach spawns inherits a correctly expanded PATH.
export PATH="$LLD_PREFIX/bin:$PATH"

if ! rustup target list | grep -q "^$TARGET (installed)"; then
	rustup target add "$TARGET"
fi

cd "$FIREFOX_DIR"
./mach build
