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

# ========== 关键修复：设置所有工具链变量 ==========
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export PATH="$CLANG_DIR:$PATH"
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

# ========== 关键修复：确保 scripts/config 可用 ==========
log "Checking scripts/config..."
if [ ! -x "scripts/config" ]; then
    log "Generating build scripts..."
    make ARCH=arm64 CC="$CC" LD="$LD" scripts 2>/dev/null || true
fi

log "Generating gki_defconfig..."
make ARCH=arm64 CC="$CC" LD="$LD" gki_defconfig

# ========== 关键修复：确保配置正确写入 ==========
log "Enabling GUNYAH..."
if [ -x "scripts/config" ]; then
    # 方法1：使用 scripts/config（推荐）
    ./scripts/config --enable CONFIG_GH_DBL
    ./scripts/config --enable CONFIG_GH_IRQ_LEND
    ./scripts/config --enable CONFIG_GH_MEM_NOTIFIER
    ./scripts/config --enable CONFIG_GH_MSGQ
    ./scripts/config --enable CONFIG_GH_PROXY_SCHED
    ./scripts/config --enable CONFIG_GH_RM_DRV
    ./scripts/config --enable CONFIG_GH_SECURE_VM_LOADER
    ./scripts/config --enable CONFIG_GUNYAH
    ./scripts/config --enable CONFIG_GUNYAH_DRIVERS
else
    # 方法2：直接修改 .config（备选）
    log "Using direct .config modification..."
    for cfg in CONFIG_GH_DBL CONFIG_GH_IRQ_LEND CONFIG_GH_MEM_NOTIFIER CONFIG_GH_MSGQ CONFIG_GH_PROXY_SCHED CONFIG_GH_RM_DRV CONFIG_GH_SECURE_VM_LOADER CONFIG_GUNYAH CONFIG_GUNYAH_DRIVERS; do
        if grep -q "^# $cfg is not set" .config; then
            sed -i "s/^# $cfg is not set/$cfg=y/" .config
        elif ! grep -q "^$cfg=" .config; then
            echo "$cfg=y" >> .config
        fi
    done
fi

# ========== 关键修复：同步配置依赖项 ==========
log "Syncing configuration..."
make ARCH=arm64 CC="$CC" LD="$LD" olddefconfig

# ========== 关键修复：验证配置 ==========
log "Verifying GUNYAH configuration..."
if grep -q "^CONFIG_GUNYAH=y" .config; then
    log "✓ CONFIG_GUNYAH is enabled"
    grep -E "^CONFIG_(GH_|GUNYAH)" .config
else
    error "CONFIG_GUNYAH not found in .config!"
fi

log "Building kernel..."
make ARCH=arm64 CC="$CC" LD="$LD" -j$(nproc) Image Image.gz 2>&1 | tee "$DIST_OUTPUT_DIR/build.log"

# 复制输出
cp arch/arm64/boot/Image "$DIST_OUTPUT_DIR/" 2>/dev/null || true
cp arch/arm64/boot/Image.gz "$DIST_OUTPUT_DIR/" 2>/dev/null || true
cp vmlinux "$DIST_OUTPUT_DIR/" 2>/dev/null || true
cp .config "$DIST_OUTPUT_DIR/config"

# ========== 关键修复：验证输出 ==========
[ -f "$DIST_OUTPUT_DIR/Image" ] || [ -f "$DIST_OUTPUT_DIR/Image.gz" ] || error "Build failed"

log "Checking GUNYAH in output config..."
grep -E "^CONFIG_(GH_|GUNYAH)" "$DIST_OUTPUT_DIR/config" || warn "GUNYAH not in output config!"

log "========================================"
log "Build Complete!"
ls -lh "$DIST_OUTPUT_DIR"
log "========================================"