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

# ========== 方法2改进：生成基础配置后追加 GUNYAH ==========
log "Generating base gki_defconfig..."
make ARCH=arm64 CC="$CC" LD="$LD" gki_defconfig

log "Adding GUNYAH to .config..."

# 直接追加到 .config（而不是修改 gki_defconfig）
# 这样避免 make gki_defconfig 重新生成时过滤掉
cat >> .config << 'EOF'
CONFIG_GH_DBL=y
CONFIG_GH_IRQ_LEND=y
CONFIG_GH_MEM_NOTIFIER=y
CONFIG_GH_MSGQ=y
CONFIG_GH_PROXY_SCHED=y
CONFIG_GH_RM_DRV=y
CONFIG_GH_SECURE_VM_LOADER=y
CONFIG_GUNYAH=y
CONFIG_GUNYAH_DRIVERS=y
EOF

log "✓ GUNYAH appended to .config"

# 使用 olddefconfig 同步依赖（不重新生成整个配置）
log "Syncing configuration with olddefconfig..."
make ARCH=arm64 CC="$CC" LD="$LD" olddefconfig

# 验证 GUNYAH 配置
log "Verifying GUNYAH configuration..."
if grep -q "^CONFIG_GUNYAH=y" .config; then
    log "✓ CONFIG_GUNYAH is enabled"
    log "GUNYAH configs in .config:"
    grep -E "^CONFIG_(GH_|GUNYAH)" .config
else
    # 检查是否被注释或设为 n
    log "GUNYAH status in .config:"
    grep -E "CONFIG_(GH_|GUNYAH)" .config || echo "Not found at all"
    error "CONFIG_GUNYAH not enabled in .config!"
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
grep -E "^CONFIG_(GH_|GUNYAH)" "$DIST_OUTPUT_DIR/config" || log "Warning: GUNYAH not found in output config"

log "========================================"
log "Build Complete!"
ls -lh "$DIST_OUTPUT_DIR"
log "========================================"