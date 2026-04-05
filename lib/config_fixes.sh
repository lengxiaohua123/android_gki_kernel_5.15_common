#!/bin/bash
# ==============================================================================
# Kernel Configuration Fixes Module
# ==============================================================================

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MODULE_DIR/common.sh"

# 新增函数：禁用 KMI 严格模式
disable_kmi_strict_mode() {
    log "Disabling KMI strict mode..."
    
    # 方法 1：尝试修改 BUILD.bazel
    local build_bazel="$KERNEL_SRC/../BUILD.bazel"
    [ -f "$build_bazel" ] || build_bazel="$KERNEL_SRC/BUILD.bazel"
    
    if [ -f "$build_bazel" ]; then
        cp "$build_bazel" "$build_bazel.bak"
        sed -i 's/kmi_symbol_list_strict_mode = True/kmi_symbol_list_strict_mode = False/g' "$build_bazel"
        log "✓ Modified BUILD.bazel"
    fi
    
    # 方法 2：设置环境变量（虽然可能无效，但保留）
    export KMI_SYMBOL_LIST_STRICT_MODE=0
    export KMI_ENFORCED=0
    export TRIM_NONLISTED_KMI=0
}

# 新增函数：修补 ABI 符号列表
patch_abi_symbol_list() {
    log "Patching ABI symbol list..."
    
    local symbol_list="$KERNEL_SRC/android/abi_gki_aarch64"
    
    if [ -f "$symbol_list" ]; then
        cp "$symbol_list" "$symbol_list.bak.$(date +%s)"
        
        # 添加 GUNYAH 需要的新符号
        for sym in __cfi_slowpath_diag __ubsan_handle_cfi_check_fail_abort kasan_flag_enabled; do
            grep -q "^$sym$" "$symbol_list" || echo "$sym" >> "$symbol_list"
        done
        
        log "✓ Patched abi_gki_aarch64"
    fi
}

# Apply all configuration fixes
apply_config_fixes() {
    log "Applying kernel configuration fixes..."
    
    GKI_DEFCONFIG="$KERNEL_SRC/arch/arm64/configs/gki_defconfig"
    
    # 检查 defconfig 是否存在
    if [ ! -f "$GKI_DEFCONFIG" ]; then
        error "gki_defconfig not found at: $GKI_DEFCONFIG"
        return 1
    fi
    
    # 备份原文件
    cp "$GKI_DEFCONFIG" "$GKI_DEFCONFIG.bak.$(date +%s)"
    log "Backup created: $GKI_DEFCONFIG.bak.*"
    
    pushd "$KERNEL_SRC" > /dev/null
    
    # ========== 步骤1: 生成基础 .config（保留所有原有配置）==========
    log "Generating base config from gki_defconfig..."
    make ARCH=arm64 gki_defconfig
    
    # ========== 步骤2: ZRAM 配置修改（原有功能保留）==========
    log "Applying ZRAM Config Fix (CONFIG_ZRAM=m, CONFIG_ZSMALLOC=m)..."
    ./scripts/config --module CONFIG_ZRAM
    ./scripts/config --module CONFIG_ZSMALLOC
    
    # ========== 步骤3: TMPFS_XATTR 启用（原有功能保留）==========
    log "Enabling TMPFS_XATTR..."
    ./scripts/config --enable CONFIG_TMPFS_XATTR
    
    # ========== 步骤4: GUNYAH 配置（新增，按字母顺序）==========
    log "Applying GUNYAH configuration..."
    ./scripts/config --enable CONFIG_GH_DBL
    ./scripts/config --enable CONFIG_GH_IRQ_LEND
    ./scripts/config --enable CONFIG_GH_MEM_NOTIFIER
    ./scripts/config --enable CONFIG_GH_MSGQ
    ./scripts/config --enable CONFIG_GH_PROXY_SCHED
    ./scripts/config --enable CONFIG_GH_RM_DRV
    ./scripts/config --enable CONFIG_GH_SECURE_VM_LOADER
    ./scripts/config --enable CONFIG_GUNYAH
    ./scripts/config --enable CONFIG_GUNYAH_DRIVERS
    
    # ========== 步骤5: 生成标准格式 defconfig（自动字母排序）==========
    log "Generating standardized defconfig with savedefconfig..."
    make ARCH=arm64 savedefconfig
    
    # 替换原文件
    mv defconfig arch/arm64/configs/gki_defconfig
    
    # 清理构建产物
    make mrproper
    
    popd > /dev/null
    
    # ========== 步骤6: ZRAM 模块列表（原有功能保留）==========
    MODULES_LIST="$KERNEL_SRC/android/gki_system_dlkm_modules"
    if [ -f "$MODULES_LIST" ]; then
        if ! grep -q "drivers/block/zram/zram.ko" "$MODULES_LIST"; then
            log "Adding ZRAM modules to system_dlkm_modules..."
            echo "drivers/block/zram/zram.ko" >> "$MODULES_LIST"
            echo "mm/zsmalloc.ko" >> "$MODULES_LIST"
            log "✓ ZRAM modules added to dlkm list"
        else
            log "ZRAM modules already in system_dlkm_modules"
        fi
    else
        warn "system_dlkm_modules not found at: $MODULES_LIST"
    fi
    
    # ========== 步骤7: 导出 task_is_booster（原有功能保留）==========
    CPUSET_C="$KERNEL_SRC/kernel/cgroup/cpuset.c"
    if [ -f "$CPUSET_C" ]; then
        if ! grep -q "EXPORT_SYMBOL_GPL(task_is_booster)" "$CPUSET_C"; then
            log "Exporting task_is_booster in cpuset.c..."
            echo "" >> "$CPUSET_C"
            echo "EXPORT_SYMBOL_GPL(task_is_booster);" >> "$CPUSET_C"
            log "✓ task_is_booster exported"
        else
            log "task_is_booster already exported"
        fi
    else
        warn "cpuset.c not found at: $CPUSET_C"
    fi
    
    # ========== 步骤8: KMI 符号列表（原有功能保留）==========
    SYMBOL_LIST="$KERNEL_SRC/android/abi_gki_aarch64"
    if [ -f "$SYMBOL_LIST" ]; then
        if ! grep -q "task_is_booster" "$SYMBOL_LIST"; then
            log "Adding task_is_booster to KMI symbol list..."
            echo "task_is_booster" >> "$SYMBOL_LIST"
            log "✓ KMI symbol list updated"
        else
            log "task_is_booster already in KMI symbol list"
        fi
    else
        warn "KMI symbol list not found at: $SYMBOL_LIST"
    fi

    # ========== 步骤9: stamp.bzl 补丁（原有功能保留）==========
    if [ -f "$STAMP_BZL" ]; then
        log "Patching stamp.bzl..."
        # 移除 -maybe-dirty 后缀
        sed -i 's/export LOCALVERSION="-maybe-dirty"/export LOCALVERSION=""/' "$STAMP_BZL"
        # 注入当前时间戳
        CURRENT_EPOCH=$(date +%s)
        sed -i "s/export SOURCE_DATE_EPOCH=0/export SOURCE_DATE_EPOCH=${CURRENT_EPOCH}/" "$STAMP_BZL"
        sed -i "s/              true/              export SOURCE_DATE_EPOCH=${CURRENT_EPOCH}/" "$STAMP_BZL"
        log "✓ stamp.bzl patched (timestamp: $CURRENT_EPOCH)"
    else
        warn "stamp.bzl not found at: $STAMP_BZL"
    fi

    # ========== 新增：禁用 KMI 严格模式 ==========
    disable_kmi_strict_mode
    
    # ========== 新增：修补 ABI 符号列表 ==========
    patch_abi_symbol_list
    
    log "========================================"
    log "✓ All configuration fixes applied:"
    log "  - ZRAM: module mode"
    log "  - TMPFS_XATTR: enabled"
    log "  - GUNYAH: 9 configs enabled"
    log "  - ZRAM modules: added to dlkm list"
    log "  - task_is_booster: exported"
    log "  - KMI symbol list: updated"
    log "  - stamp.bzl: patched"
    log "========================================"
}