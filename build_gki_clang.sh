#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_SRC="$SCRIPT_DIR"
DIST_OUTPUT_DIR="$SCRIPT_DIR/out/dist"

# ========== 关键：使用 Google Clang ==========
if [ -n "$CLANG_PATH" ]; then
    # GitHub Actions 环境
    CLANG_DIR="$CLANG_PATH"
elif [ -d "$HOME/toolchains/clang" ]; then
    # 本地缓存
    CLANG_DIR="$HOME/toolchains/clang/bin"
else
    # 尝试自动下载
    echo "Downloading Google Clang..."
    mkdir -p $HOME/toolchains
    cd $HOME/toolchains
    wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/master/clang-r450784e.tar.gz
    tar -xzf clang-r450784e.tar.gz 2>/dev/null || true
    mv clang-r450784e clang 2>/dev/null || true
    CLANG_DIR="$HOME/toolchains/clang/bin"
    cd "$SCRIPT_DIR"
fi

# 验证 Clang
if [ ! -f "$CLANG_DIR/clang" ]; then
    echo "ERROR: Google Clang not found at $CLANG_DIR"
    exit 1
fi

echo "Using Google Clang: $CLANG_DIR"
$CLANG_DIR/clang --version

# 设置工具链
export PATH="$CLANG_DIR:$PATH"
export ARCH=arm64
export CC="$CLANG_DIR/clang"
export CROSS_COMPILE=aarch64-linux-gnu-
export LLVM=1                    # 使用 LLVM 工具链
export LLVM_IAS=1                # 使用集成汇编器

# 显式指定所有 LLVM 工具（避免混用系统工具）
export AR="$CLANG_DIR/llvm-ar"
export NM="$CLANG_DIR/llvm-nm"
export STRIP="$CLANG_DIR/llvm-strip"
export OBJCOPY="$CLANG_DIR/llvm-objcopy"
export OBJDUMP="$CLANG_DIR/llvm-objdump"
export READELF="$CLANG_DIR/llvm-readelf"
export LD="$CLANG_DIR/ld.lld"    # 使用 LLVM linker

mkdir -p "$DIST_OUTPUT_DIR"

log() { echo "[$(date '+%H:%M:%S')] $1"; }
error() { echo "[ERROR] $1" >&2; exit 1; }

log "Starting build with Google Clang..."

cd "$KERNEL_SRC" || error "Cannot enter $KERNEL_SRC"
[ -d "arch/arm64" ] || error "Kernel source not found"

log "Cleaning..."
make mrproper 2>/dev/null || true

log "Generating gki_defconfig..."
make gki_defconfig

log "Enabling GUNYAH..."
./scripts/config --enable CONFIG_GH_DBL
./scripts/config --enable CONFIG_GH_IRQ_LEND
./scripts/config --enable CONFIG_GH_MEM_NOTIFIER
./scripts/config --enable CONFIG_GH_MSGQ
./scripts/config --enable CONFIG_GH_PROXY_SCHED
./scripts/config --enable CONFIG_GH_RM_DRV
./scripts/config --enable CONFIG_GH_SECURE_VM_LOADER
./scripts/config --enable CONFIG_GUNYAH
./scripts/config --enable CONFIG_GUNYAH_DRIVERS

grep -E "^CONFIG_(GH_|GUNYAH)" .config || error "GUNYAH config failed"

log "Building kernel..."
make -j$(nproc) Image Image.gz 2>&1 | tee "$DIST_OUTPUT_DIR/build.log"

# 复制输出
cp arch/arm64/boot/Image "$DIST_OUTPUT_DIR/" 2>/dev/null || true
cp arch/arm64/boot/Image.gz "$DIST_OUTPUT_DIR/" 2>/dev/null || true
cp vmlinux "$DIST_OUTPUT_DIR/" 2>/dev/null || true
cp .config "$DIST_OUTPUT_DIR/config"

[ -f "$DIST_OUTPUT_DIR/Image" ] || [ -f "$DIST_OUTPUT_DIR/Image.gz" ] || error "Build failed"

log "========================================"
log "Build Complete!"
ls -lh "$DIST_OUTPUT_DIR"
log "========================================"