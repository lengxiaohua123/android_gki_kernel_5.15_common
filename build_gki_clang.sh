#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_SRC="$SCRIPT_DIR"
DIST_OUTPUT_DIR="$SCRIPT_DIR/out/dist"

# 工具链配置
export ARCH=arm64
export CC=clang
export CROSS_COMPILE=aarch64-linux-gnu-
export LLVM=1
export LLVM_IAS=1

# 检查并使用 Google Clang
if [ -n "$CLANG_PATH" ]; then
    export CC="$CLANG_PATH/clang"
    export AR="$CLANG_PATH/llvm-ar"
    export NM="$CLANG_PATH/llvm-nm"
    export STRIP="$CLANG_PATH/llvm-strip"
    export OBJCOPY="$CLANG_PATH/llvm-objcopy"
    export OBJDUMP="$CLANG_PATH/llvm-objdump"
    export READELF="$CLANG_PATH/llvm-readelf"
    export LD="$CLANG_PATH/ld.lld"
    echo "Using Google Clang from $CLANG_PATH"
else
    echo "Using system Clang"
fi

mkdir -p "$DIST_OUTPUT_DIR"

log() { echo "[$(date '+%H:%M:%S')] $1"; }
error() { echo "[ERROR] $1" >&2; exit 1; }

log "Starting build..."

cd "$KERNEL_SRC" || error "Cannot enter $KERNEL_SRC"
[ -d "arch/arm64" ] || error "Kernel source not found"

log "Cleaning..."
make mrproper 2>/dev/null || true

# ========== 关键修复：先确保 scripts/config 存在 ==========
log "Checking scripts/config..."
if [ ! -f "scripts/config" ]; then
    # 先执行一次 make 生成 scripts/config
    log "Generating build scripts..."
    make ARCH=arm64 CC="$CC" prepare scripts 2>/dev/null || true
fi

log "Generating gki_defconfig..."
make ARCH=arm64 CC="$CC" gki_defconfig

# ========== 关键修复：确保配置写入 .config ==========
log "Enabling GUNYAH..."

# 方法1：使用 scripts/config（如果存在）
if [ -f "scripts/config" ]; then
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
    # 方法2：直接修改 .config 文件
    log "Using direct .config modification..."
    for cfg in CONFIG_GH_DBL CONFIG_GH_IRQ_LEND CONFIG_GH_MEM_NOTIFIER CONFIG_GH_MSGQ CONFIG_GH_PROXY_SCHED CONFIG_GH_RM_DRV CONFIG_GH_SECURE_VM_LOADER CONFIG_GUNYAH CONFIG_GUNYAH_DRIVERS; do
        if grep -q "^# $cfg is not set" .config; then
            sed -i "s/^# $cfg is not set/$cfg=y/" .config
        elif ! grep -q "^$cfg=" .config; then
            echo "$cfg=y" >> .config
        fi
    done
fi

# ========== 关键修复：验证配置 ==========
log "Verifying GUNYAH configuration..."
if grep -q "^CONFIG_GUNYAH=y" .config; then
    log "✓ CONFIG_GUNYAH is enabled"
    grep -E "^CONFIG_(GH_|GUNYAH)" .config
else
    error "CONFIG_GUNYAH not found in .config!"
fi

# 同步配置（确保依赖项正确）
log "Syncing configuration..."
make ARCH=arm64 CC="$CC" olddefconfig 2>/dev/null || true

log "Building kernel..."
make ARCH=arm64 CC="$CC" -j$(nproc) Image Image.gz 2>&1 | tee "$DIST_OUTPUT_DIR/build.log"

# 复制输出
cp arch/arm64/boot/Image "$DIST_OUTPUT_DIR/" 2>/dev/null || true
cp arch/arm64/boot/Image.gz "$DIST_OUTPUT_DIR/" 2>/dev/null || true
cp vmlinux "$DIST_OUTPUT_DIR/" 2>/dev/null || true
cp .config "$DIST_OUTPUT_DIR/config"

# 最终验证输出中的 config
log "Checking output config..."
grep -E "^CONFIG_(GH_|GUNYAH)" "$DIST_OUTPUT_DIR/config" || warn "GUNYAH not in output config!"

log "========================================"
log "Build Complete!"
ls -lh "$DIST_OUTPUT_DIR"
log "========================================"