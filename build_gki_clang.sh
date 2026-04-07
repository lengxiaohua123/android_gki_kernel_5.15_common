#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_SRC="$SCRIPT_DIR"
DIST_OUTPUT_DIR="$SCRIPT_DIR/out/dist"

# ========== 关键：使用 Google Clang ==========
if [ -n "$CLANG_PATH" ]; then
    CLANG_DIR="$CLANG_PATH"
elif [ -d "$HOME/toolchains/clang" ]; then
    CLANG_DIR="$HOME/toolchains/clang/bin"
else
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
export CROSS_COMPILE=aarch64-linux-gnu-
export CC="$CLANG_DIR/clang"
export AR="$CLANG_DIR/llvm-ar"
export NM="$CLANG_DIR/llvm-nm"
export STRIP="$CLANG_DIR/llvm-strip"
export OBJCOPY="$CLANG_DIR/llvm-objcopy"
export OBJDUMP="$CLANG_DIR/llvm-objdump"
export READELF="$CLANG_DIR/llvm-readelf"
export LD="$CLANG_DIR/ld.lld"
export LLVM=1
export LLVM_IAS=1

mkdir -p "$DIST_OUTPUT_DIR"

log() { echo "[$(date '+%H:%M:%S')] $1"; }
error() { echo "[ERROR] $1" >&2; exit 1; }

log "Starting build with Google Clang..."

cd "$KERNEL_SRC" || error "Cannot enter $KERNEL_SRC"
[ -d "arch/arm64" ] || error "Kernel source not found"

# ========== 关键：检查并确保 GUNYAH Kconfig 被包含 ==========
log "Checking GUNYAH Kconfig location..."

GUNYAH_KCONFIG="drivers/virt/gunyah/Kconfig"

if [ -f "$GUNYAH_KCONFIG" ]; then
    log "✓ Found $GUNYAH_KCONFIG"
    
    # 检查是否被包含在 drivers/virt/Kconfig 中
    if [ -f "drivers/virt/Kconfig" ]; then
        if ! grep -q "gunyah" drivers/virt/Kconfig; then
            log "Adding gunyah to drivers/virt/Kconfig..."
            echo 'source "drivers/virt/gunyah/Kconfig"' >> drivers/virt/Kconfig
        else
            log "✓ Gunyah already included in drivers/virt/Kconfig"
        fi
    fi
    
    # 检查是否被包含在 drivers/Kconfig 中
    if [ -f "drivers/Kconfig" ]; then
        if ! grep -q "virt" drivers/Kconfig; then
            log "Adding virt to drivers/Kconfig..."
            echo 'source "drivers/virt/Kconfig"' >> drivers/Kconfig
        fi
    fi
else
    error "$GUNYAH_KCONFIG not found! Gunyah driver source missing."
fi

log "Cleaning..."
make ARCH=arm64 CC="$CC" LD="$LD" mrproper 2>/dev/null || true

log "Generating base gki_defconfig..."
make ARCH=arm64 CC="$CC" LD="$LD" gki_defconfig

# ========== 关键：检查 GUNYAH 选项是否存在于 Kconfig 系统 ==========
log "Checking if GUNYAH is in Kconfig system..."
if grep -r "config GUNYAH" drivers/virt/gunyah/ 2>/dev/null; then
    log "✓ GUNYAH Kconfig option found"
else
    log "Warning: GUNYAH Kconfig option not found in search"
fi

log "Adding GUNYAH to .config..."

cat >> .config << 'EOF'
# Gunyah Hypervisor Support
CONFIG_GUNYAH=y
CONFIG_GH_SECURE_VM_LOADER=y
CONFIG_GH_PROXY_SCHED=y
CONFIG_GUNYAH_DRIVERS=y
CONFIG_GH_DBL=y
CONFIG_GH_MSGQ=y
CONFIG_GH_RM_DRV=y
CONFIG_GH_IRQ_LEND=y
CONFIG_GH_MEM_NOTIFIER=y
CONFIG_GH_CTRL=y
EOF

log "✓ GUNYAH appended to .config"

# 检查追加后的状态
if grep -q "^CONFIG_GUNYAH=y" .config; then
    log "✓ CONFIG_GUNYAH is in .config before build"
else
    error "CONFIG_GUNYAH missing after append!"
fi

# ========== 关键：不使用 olddefconfig，直接编译 ==========
# 让 Kbuild 在编译时验证配置

log "Building kernel..."
make ARCH=arm64 CC="$CC" LD="$LD" -j$(nproc) Image Image.gz 2>&1 | tee "$DIST_OUTPUT_DIR/build.log" || {
    log "Build failed, checking for config errors..."
    # 如果失败，显示相关错误
    grep -i "gunyah\|GUNYAH" "$DIST_OUTPUT_DIR/build.log" || true
    exit 1
}

# 复制输出
cp arch/arm64/boot/Image "$DIST_OUTPUT_DIR/" 2>/dev/null || true
cp arch/arm64/boot/Image.gz "$DIST_OUTPUT_DIR/" 2>/dev/null || true
cp vmlinux "$DIST_OUTPUT_DIR/" 2>/dev/null || true
cp .config "$DIST_OUTPUT_DIR/config"

[ -f "$DIST_OUTPUT_DIR/Image" ] || [ -f "$DIST_OUTPUT_DIR/Image.gz" ] || error "Build failed"

# 验证输出
log "Checking GUNYAH in output config..."
grep -E "^CONFIG_(GH_|GUNYAH)" "$DIST_OUTPUT_DIR/config" || log "Warning: GUNYAH not in output config"

log "========================================"
log "Build Complete!"
ls -lh "$DIST_OUTPUT_DIR"
log "========================================"