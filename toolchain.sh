#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN="$ROOT/.bin"
LLVM_ROOT="$HOME/.toolchains/llvm-13"
LIBTINFO_ROOT="$HOME/.toolchains/libtinfo5"
LIBTINFO_DIR="$LIBTINFO_ROOT/lib/x86_64-linux-gnu"

if [[ -d "$LIBTINFO_DIR" ]]; then
    export LD_LIBRARY_PATH="$LIBTINFO_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

mkdir -p "$BIN"

echo "=============================================="
echo " FAA KERNEL TOOLCHAIN ENV"
echo "=============================================="
echo "ROOT      : $ROOT"
echo "BIN       : $BIN"
echo "LLVM_ROOT : $LLVM_ROOT"
echo

# ------------------------------------------------------------
# LLVM 13 portable
# ------------------------------------------------------------

if [[ ! -x "$LLVM_ROOT/bin/clang" ]]; then
    echo "[FAA][ERROR] LLVM 13 belum tersedia:"
    echo "  $LLVM_ROOT"
    echo
    echo "Jalankan bootstrap-toolchain.sh terlebih dahulu."
    exit 1
fi

echo "[FAA] Linking LLVM 13 tools..."

for tool in \
    clang \
    clang++ \
    ld.lld \
    llvm-ar \
    llvm-nm \
    llvm-objcopy \
    llvm-objdump \
    llvm-strip
do
    src="$LLVM_ROOT/bin/$tool"

    if [[ ! -x "$src" ]]; then
        echo "[FAA][ERROR] Missing LLVM tool: $src"
        exit 1
    fi

    ln -sfn "$src" "$BIN/$tool"

    case "$tool" in
        clang)       ln -sfn "$src" "$BIN/clang-13" ;;
        clang++)     ln -sfn "$src" "$BIN/clang++-13" ;;
        ld.lld)      ln -sfn "$src" "$BIN/ld.lld-13" ;;
        llvm-ar)     ln -sfn "$src" "$BIN/llvm-ar-13" ;;
        llvm-nm)     ln -sfn "$src" "$BIN/llvm-nm-13" ;;
        llvm-objcopy) ln -sfn "$src" "$BIN/llvm-objcopy-13" ;;
        llvm-objdump) ln -sfn "$src" "$BIN/llvm-objdump-13" ;;
        llvm-strip)  ln -sfn "$src" "$BIN/llvm-strip-13" ;;
    esac
done

# ------------------------------------------------------------
# Cross compiler discovery
# ------------------------------------------------------------

echo "[FAA] Checking cross toolchains..."

required_cross=(
    aarch64-linux-gnu-gcc
    aarch64-linux-gnu-ld
    arm-linux-gnueabihf-gcc
    arm-linux-gnueabihf-as
    arm-linux-gnueabihf-ld
)

missing=0

for tool in "${required_cross[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        src="$(command -v "$tool")"
        ln -sfn "$src" "$BIN/$tool"
        echo "[OK] $tool -> $src"
    else
        echo "[MISS] $tool"
        missing=1
    fi
done

if (( missing )); then
    echo
    echo "[FAA][ERROR] Cross compiler belum tersedia."
    echo
    echo "Install sekali di Codespace:"
    echo
    echo "  sudo apt update"
    echo "  sudo apt install -y \\"
    echo "      gcc-aarch64-linux-gnu \\"
    echo "      binutils-aarch64-linux-gnu \\"
    echo "      gcc-arm-linux-gnueabihf \\"
    echo "      binutils-arm-linux-gnueabihf \\"
    echo "      bc flex"
    echo
    exit 1
fi

# ------------------------------------------------------------
# Kernel build environment
# ------------------------------------------------------------

export PATH="$BIN:$PATH"

export LLVM=1
export LLVM_IAS=1

export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabihf-

export CC=clang-13
export LD=ld.lld-13
export AR=llvm-ar-13
export NM=llvm-nm-13
export OBJCOPY=llvm-objcopy-13
export OBJDUMP=llvm-objdump-13
export STRIP=llvm-strip-13

# ------------------------------------------------------------
# Validation
# ------------------------------------------------------------

echo
echo "=============================================="
echo " TOOLCHAIN VALIDATION"
echo "=============================================="

printf '%-25s %s\n' "CC"       "$(command -v "$CC")"
printf '%-25s %s\n' "LD"       "$(command -v "$LD")"
printf '%-25s %s\n' "AR"       "$(command -v "$AR")"
printf '%-25s %s\n' "NM"       "$(command -v "$NM")"
printf '%-25s %s\n' "OBJCOPY"  "$(command -v "$OBJCOPY")"
printf '%-25s %s\n' "CROSS"    "$(command -v aarch64-linux-gnu-gcc)"
printf '%-25s %s\n' "ARM32"    "$(command -v arm-linux-gnueabihf-gcc)"

echo
echo "[LLVM]"
clang-13 --version | head -n 1
ld.lld-13 --version | head -n 1

echo
echo "[CROSS]"
aarch64-linux-gnu-gcc --version | head -n 1
arm-linux-gnueabihf-gcc --version | head -n 1

echo
echo "=============================================="
echo " ENVIRONMENT READY"
echo "=============================================="
echo
echo "Run:"
echo
echo "  source ./toolchain.sh"
echo
echo "Then:"
echo
echo "  echo \$CC"
echo "  echo \$CROSS_COMPILE"
echo
