#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

TOOLCHAIN_ROOT="$HOME/.toolchains"
LLVM_ROOT="$TOOLCHAIN_ROOT/llvm-13"
TINFO_ROOT="$TOOLCHAIN_ROOT/libtinfo5"

LLVM_VERSION="13.0.1"
LLVM_ARCHIVE="clang+llvm-${LLVM_VERSION}-x86_64-linux-gnu-ubuntu-18.04.tar.xz"
LLVM_URL="https://github.com/llvm/llvm-project/releases/download/llvmorg-${LLVM_VERSION}/${LLVM_ARCHIVE}"

TINFO_DEB="libtinfo5_6.2+20201114-2+deb11u2_amd64.deb"
TINFO_URL="https://deb.debian.org/debian/pool/main/n/ncurses/${TINFO_DEB}"

CACHE="$TOOLCHAIN_ROOT/cache"

mkdir -p "$TOOLCHAIN_ROOT" "$CACHE"

echo "=============================================="
echo " FAA KERNEL TOOLCHAIN BOOTSTRAP"
echo "=============================================="
echo
echo "ROOT : $ROOT"
echo

# ------------------------------------------------------------
# LLVM 13
# ------------------------------------------------------------

if [[ -x "$LLVM_ROOT/bin/clang" ]]; then
    echo "[OK] LLVM 13 already installed:"
    echo "     $LLVM_ROOT"
else
    echo "[FAA] Installing LLVM ${LLVM_VERSION}..."

    ARCHIVE="$CACHE/$LLVM_ARCHIVE"

    if [[ ! -f "$ARCHIVE" ]]; then
        wget -O "$ARCHIVE" "$LLVM_URL"
    else
        echo "[OK] LLVM archive already cached."
    fi

    TMP="$TOOLCHAIN_ROOT/.llvm-extract"
    rm -rf "$TMP"
    mkdir -p "$TMP"

    tar -xf "$ARCHIVE" -C "$TMP"

    EXTRACTED="$TMP/clang+llvm-${LLVM_VERSION}-x86_64-linux-gnu-ubuntu-18.04"

    if [[ ! -d "$EXTRACTED" ]]; then
        echo "[ERROR] LLVM extraction directory missing:"
        echo "        $EXTRACTED"
        exit 1
    fi

    rm -rf "$LLVM_ROOT"
    mv "$EXTRACTED" "$LLVM_ROOT"
    rm -rf "$TMP"

    echo "[OK] LLVM 13 installed."
fi

# ------------------------------------------------------------
# libtinfo.so.5
# ------------------------------------------------------------

TINFO_DIR="$TINFO_ROOT/lib/x86_64-linux-gnu"

if [[ -f "$TINFO_DIR/libtinfo.so.5" ]]; then
    echo "[OK] libtinfo.so.5 already installed."
else
    echo "[FAA] Installing private libtinfo5..."

    DEB="$CACHE/$TINFO_DEB"

    if [[ ! -f "$DEB" ]]; then
        wget -O "$DEB" "$TINFO_URL"
    else
        echo "[OK] libtinfo5 package already cached."
    fi

    rm -rf "$TINFO_ROOT"
    mkdir -p "$TINFO_ROOT"

    dpkg-deb -x "$DEB" "$TINFO_ROOT"

    if [[ ! -f "$TINFO_DIR/libtinfo.so.5" ]]; then
        echo "[ERROR] libtinfo.so.5 installation failed."
        exit 1
    fi

    echo "[OK] libtinfo.so.5 installed."
fi

# ------------------------------------------------------------
# Cross compiler
# ------------------------------------------------------------

echo
echo "[FAA] Checking cross compilers..."

missing=()

for tool in \
    gcc-aarch64-linux-gnu \
    binutils-aarch64-linux-gnu \
    gcc-arm-linux-gnueabihf \
    binutils-arm-linux-gnueabihf \
    bc \
    flex
do
    if dpkg-query -W -f='${Status}' "$tool" 2>/dev/null \
        | grep -q "install ok installed"; then
        echo "[OK] $tool"
    else
        missing+=("$tool")
        echo "[MISS] $tool"
    fi
done

if (( ${#missing[@]} )); then
    echo
    echo "[FAA] Installing missing packages..."
    sudo apt-get update
    sudo apt-get install -y "${missing[@]}"
else
    echo "[OK] All cross-build packages installed."
fi

# ------------------------------------------------------------
# Generate repo .bin symlinks
# ------------------------------------------------------------

echo
echo "[FAA] Generating .bin..."

mkdir -p "$ROOT/.bin"

link_tool() {
    local src="$1"
    local dst="$2"

    if [[ ! -x "$src" ]]; then
        echo "[ERROR] Missing tool:"
        echo "        $src"
        exit 1
    fi

    ln -sfn "$src" "$ROOT/.bin/$dst"
}

link_tool "$LLVM_ROOT/bin/clang"       clang
link_tool "$LLVM_ROOT/bin/clang"       clang-13

link_tool "$LLVM_ROOT/bin/clang++"     clang++
link_tool "$LLVM_ROOT/bin/clang++"     clang++-13

link_tool "$LLVM_ROOT/bin/ld.lld"      ld.lld
link_tool "$LLVM_ROOT/bin/ld.lld"      ld.lld-13

link_tool "$LLVM_ROOT/bin/llvm-ar"     llvm-ar
link_tool "$LLVM_ROOT/bin/llvm-ar"     llvm-ar-13

link_tool "$LLVM_ROOT/bin/llvm-nm"     llvm-nm
link_tool "$LLVM_ROOT/bin/llvm-nm"     llvm-nm-13

link_tool "$LLVM_ROOT/bin/llvm-objcopy" llvm-objcopy
link_tool "$LLVM_ROOT/bin/llvm-objcopy" llvm-objcopy-13

link_tool "$LLVM_ROOT/bin/llvm-objdump" llvm-objdump
link_tool "$LLVM_ROOT/bin/llvm-objdump" llvm-objdump-13

link_tool "$LLVM_ROOT/bin/llvm-strip"  llvm-strip
link_tool "$LLVM_ROOT/bin/llvm-strip"  llvm-strip-13

link_cross() {
    local tool="$1"

    local path
    path="$(command -v "$tool" || true)"

    if [[ -z "$path" ]]; then
        echo "[ERROR] Missing cross tool: $tool"
        exit 1
    fi

    ln -sfn "$path" "$ROOT/.bin/$tool"
}

link_cross aarch64-linux-gnu-gcc
link_cross aarch64-linux-gnu-ld

link_cross arm-linux-gnueabihf-gcc
link_cross arm-linux-gnueabihf-as
link_cross arm-linux-gnueabihf-ld

# ------------------------------------------------------------
# Final validation
# ------------------------------------------------------------

export PATH="$ROOT/.bin:$PATH"
export LD_LIBRARY_PATH="$TINFO_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

echo
echo "=============================================="
echo " BOOTSTRAP VALIDATION"
echo "=============================================="

clang-13 --version | head -n 1
ld.lld-13 --version | head -n 1

aarch64-linux-gnu-gcc --version | head -n 1
arm-linux-gnueabihf-gcc --version | head -n 1

echo
echo "[OK] LLVM 13"
echo "[OK] LLD 13"
echo "[OK] ARM64 cross compiler"
echo "[OK] ARM32 cross compiler"
echo "[OK] libtinfo.so.5"
echo
echo "=============================================="
echo " BOOTSTRAP COMPLETE"
echo "=============================================="
echo
echo "Next:"
echo "  source ./toolchain.sh"
echo
