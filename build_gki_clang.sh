#!/bin/bash
set -e

# ==============================================================================
# GKI Kernel Build Script - Clang Native Compile
# 内核源码在仓库根目录 (arch/, block/, drivers/ 等)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_SRC="$SCRIPT_DIR"                    # 内核源码 = 当前目录
DIST_OUTPUT_DIR="$SCRIPT_DIR/out/dist"      # 输出路径

# 工具链配置
export ARCH=arm64
export CC=clang
export CROSS_COMPILE=aarch64-linux-gnu-
export LLVM=1
export LLVM_IAS=1

mkdir -p "$DIST_OUTPUT_DIR"

log() { echo "[$(date '+%H:%M:%S')] $1"; }
error() { echo "[ERROR] $1" >&2; exit 1; }

# ==============================================================================
# MAIN BUILD
# ==============================================================================

log "Starting Clang build in $KERNEL_SRC..."

cd "$KERNEL_SRC" || error "Cannot enter $KERNEL_SRC"

# 检查内核源码
[ -d "arch/arm64" ] || error "Kernel source not found (no arch/arm64 directory)"

# 清理
log "Cleaning..."
make mrproper 2>/dev/null || true

# 配置
log "Generating gki_defconfig..."
make gki_defconfig

# 启用 GUNYAH
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

# 验证
grep -E "^CONFIG_(GH_|GUNYAH)" .config || error "GUNYAH config failed"

# 编译
log "Building kernel..."
make -j$(nproc) Image Image.gz 2>&1 | tee "$DIST_OUTPUT_DIR/build.log"

# 复制输出
log "Copying artifacts..."
cp arch/arm64/boot/Image "$DIST_OUTPUT_DIR/" 2>/dev/null || true
cp arch/arm64/boot/Image.gz "$DIST_OUTPUT_DIR/" 2>/dev/null || true
cp vmlinux "$DIST_OUTPUT_DIR/" 2>/dev/null || true
cp .config "$DIST_OUTPUT_DIR/config"

# 验证
[ -f "$DIST_OUTPUT_DIR/Image" ] || [ -f "$DIST_OUTPUT_DIR/Image.gz" ] || error "Build failed"

# 显示版本
if [ -f "$DIST_OUTPUT_DIR/Image.gz" ]; then
    zcat "$DIST_OUTPUT_DIR/Image.gz" | strings | grep "Linux version" | head -n1 || true
elif [ -f "$DIST_OUTPUT_DIR/Image" ]; then
    strings "$DIST_OUTPUT_DIR/Image" | grep "Linux version" | head -n1 || true
fi

log "========================================"
log "Build Complete!"
ls -lh "$DIST_OUTPUT_DIR"
log "========================================"