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

log "Cleaning..."
make ARCH=arm64 CC="$CC" LD="$LD" mrproper 2>/dev/null || true

# ========== 关键修复：正确的配置顺序 ==========
log "Generating base gki_defconfig..."
make ARCH=arm64 CC="$CC" LD="$LD" gki_defconfig

log "Adding GUNYAH to .config..."

# 关键：必须按依赖顺序添加
# 1. 先启用 GUNYAH（基础）
# 2. 再启用 GUNYAH_DRIVERS（菜单容器）
# 3. 最后启用具体驱动

cat >> .config << 'EOF'
# Gunyah Hypervisor Support
CONFIG_GUNYAH=y
CONFIG_GH_SECURE_VM_LOADER=y
CONFIG_GH_PROXY_SCHED=y

# Gunyah Drivers Menu (必须在前，才能包含后面的选项)
CONFIG_GUNYAH_DRIVERS=y

# Gunyah Drivers (在 if GUNYAH_DRIVERS 块内)
CONFIG_GH_DBL=y
CONFIG_GH_MSGQ=y
CONFIG_GH_RM_DRV=y
CONFIG_GH_IRQ_LEND=y
CONFIG_GH_MEM_NOTIFIER=y
CONFIG_GH_CTRL=y
EOF

log "✓ GUNYAH appended to .config"

# 使用 syncconfig 或 olddefconfig 同步（不要重新生成）
log "Syncing configuration..."
make ARCH=arm64 CC="$CC" LD="$LD" syncconfig 2>/dev/null || \
make ARCH=arm64 CC="$CC" LD="$LD" olddefconfig

# 关键：检查 GUNYAH_DRIVERS 是否为 y（不是 m！）
log "Checking GUNYAH_DRIVERS status..."
grep "^CONFIG_GUNYAH_DRIVERS" .config || echo "GUNYAH_DRIVERS not set!"

# 验证 GUNYAH 配置
log "Verifying GUNYAH configuration..."
if grep -q "^CONFIG_GUNYAH=y" .config; then
    log "✓ CONFIG_GUNYAH is enabled"
    log "All GUNYAH configs:"
    grep -E "^CONFIG_(GH_|GUNYAH)" .config || true
else
    log "GUNYAH status:"
    grep -E "CONFIG_GUNYAH" .config || echo "Not found"
    error "CONFIG_GUNYAH not enabled!"
fi

log "Building kernel..."
make ARCH=arm64 CC="$CC" LD="$LD" -j$(nproc) Image Image.gz 2>&1 | tee "$DIST_OUTPUT_DIR/build.log"

# 复制输出
cp arch/arm64/boot/Image "$DIST_OUTPUT_DIR/" 2>/dev/null || true
cp arch/arm64/boot/Image.gz "$DIST_OUTPUT_DIR/" 2>/dev/null || true
cp vmlinux "$DIST_OUTPUT_DIR/" 2>/dev/null || true
cp .config "$DIST_OUTPUT_DIR/config"

[ -f "$DIST_OUTPUT_DIR/Image" ] || [ -f "$DIST_OUTPUT_DIR/Image.gz" ] || error "Build failed"

# 验证输出 config
log "Checking GUNYAH in output config..."
grep -E "^CONFIG_(GH_|GUNYAH)" "$DIST_OUTPUT_DIR/config" || log "Warning: GUNYAH not in output config"

log "========================================"
log "Build Complete!"
ls -lh "$DIST_OUTPUT_DIR"
log "========================================"