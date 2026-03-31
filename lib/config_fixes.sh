#!/bin/bash
# ==============================================================================
# Kernel Configuration Fixes Module
# ==============================================================================

# Source common functions
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MODULE_DIR/common.sh"

# Apply Gunyah hypervisor configuration
apply_gunyah_config() {
    log "Applying Gunyah hypervisor configuration..."
    
    GKI_DEFCONFIG="$KERNEL_SRC/arch/arm64/configs/gki_defconfig"
    
    # Check if ARM64 architecture (required for GUNYAH_DRIVERS)
    if ! grep -q "CONFIG_ARM64=y" "$GKI_DEFCONFIG"; then
        log "Warning: CONFIG_ARM64 not enabled, skipping Gunyah config"
        return 0
    fi
    
    # Enable core Gunyah virtualization support
    if ! grep -q "CONFIG_GUNYAH=" "$GKI_DEFCONFIG"; then
        echo "CONFIG_GUNYAH=y" >> "$GKI_DEFCONFIG"
        log "Added CONFIG_GUNYAH=y"
    else
        sed -i 's/CONFIG_GUNYAH=.*/CONFIG_GUNYAH=y/' "$GKI_DEFCONFIG"
        log "Updated CONFIG_GUNYAH=y"
    fi
    
    # Enable Gunyah Secure VM Loader
    if ! grep -q "CONFIG_GH_SECURE_VM_LOADER=" "$GKI_DEFCONFIG"; then
        echo "CONFIG_GH_SECURE_VM_LOADER=y" >> "$GKI_DEFCONFIG"
        log "Added CONFIG_GH_SECURE_VM_LOADER=y"
    else
        sed -i 's/CONFIG_GH_SECURE_VM_LOADER=.*/CONFIG_GH_SECURE_VM_LOADER=y/' "$GKI_DEFCONFIG"
        log "Updated CONFIG_GH_SECURE_VM_LOADER=y"
    fi
    
    # Enable Gunyah Proxy Scheduler
    if ! grep -q "CONFIG_GH_PROXY_SCHED=" "$GKI_DEFCONFIG"; then
        echo "CONFIG_GH_PROXY_SCHED=y" >> "$GKI_DEFCONFIG"
        log "Added CONFIG_GH_PROXY_SCHED=y"
    else
        sed -i 's/CONFIG_GH_PROXY_SCHED=.*/CONFIG_GH_PROXY_SCHED=y/' "$GKI_DEFCONFIG"
        log "Updated CONFIG_G_GH_PROXY_SCHEDH_PROXY_SCHED=y"
    fi
    
    # Enable Gunyah Drivers submenu (requires ARM64)
    if ! grep -q "CONFIG_GUNYAH_DRIVERS=" "$GKI_DEFCONFIG"; then
        echo "CONFIG_GUNYAH_DRIVERS=y" >> "$GKI_DEFCONFIG"
        log "Added CONFIG_GUNYAH_DRIVERS=y"
    else
        sed -i 's/CONFIG_GUNYAH_DRIVERS=.*/CONFIG_GUNYAH_DRIVERS=y/' "$GKI_DEFCONFIG"
        log "Updated CONFIG_GUNYAH_DRIVERS=y"
    fi
    
    # Enable Gunyah Virtual Watchdog (requires QCOM_WDT_CORE)
    if grep -q "CONFIG_QCOM_WDT_CORE=" "$GKI_DEFCONFIG"; then
        if ! grep -q "CONFIG_GH_VIRT_WATCHDOG=" "$GKI_DEFCONFIG"; then
            echo "CONFIG_GH_VIRT_WATCHDOG=y" >> "$GKI_DEFCONFIG"
            log "Added CONFIG_GH_VIRT_WATCHDOG=y"
        else
            sed -i 's/CONFIG_GH_VIRT_WATCHDOG=.*/CONFIG_GH_VIRT_WATCHDOG=y/' "$GKI_DEFCONFIG"
            log "Updated CONFIG_GH_VIRT_WATCHDOG=y"
        fi
    else
        log "Warning: CONFIG_QCOM_WDT_CORE not found, skipping GH_VIRT_WATCHDOG"
    fi
    
    # Enable Gunyah sysfs interface (requires SYSFS)
    if grep -q "CONFIG_SYSFS=y" "$GKI_DEFCONFIG"; then
        if ! grep -q "CONFIG_GH_CTRL=" "$GKI_DEFCONFIG"; then
            echo "CONFIG_GH_CTRL=y" >> "$GKI_DEFCONFIG"
            log "Added CONFIG_GH_CTRL=y"
        else
            sed -i 's/CONFIG_GH_CTRL=.*/CONFIG_GH_CTRL=y/' "$GKI_DEFCONFIG"
            log "Updated CONFIG_GH_CTRL=y"
        fi
    else
        log "Warning: CONFIG_SYSFS not enabled, skipping GH_CTRL"
    fi
    
    # Enable Gunyah Doorbell driver (VM-to-VM communication)
    if ! grep -q "CONFIG_GH_DBL=" "$GKI_DEFCONFIG"; then
        echo "CONFIG_GH_DBL=y" >> "$GKI_DEFCONFIG"
        log "Added CONFIG_GH_DBL=y"
    else
        sed -i 's/CONFIG_GH_DBL=.*/CONFIG_GH_DBL=y/' "$GKI_DEFCONFIG"
        log "Updated CONFIG_GH_DBL=y"
    fi
    
    # Enable Gunyah Message Queue driver
    if ! grep -q "CONFIG_GH_MSGQ=" "$GKI_DEFCONFIG"; then
        echo "CONFIG_GH_MSGQ=y" >> "$GKI_DEFCONFIG"
        log "Added CONFIG_GH_MSGQ=y"
    else
        sed -i 's/CONFIG_GH_MSGQ=.*/CONFIG_GH_MSGQ=y/' "$GKI_DEFCONFIG"
        log "Updated CONFIG_GH_MSGQ=y"
    fi
    
    # Enable Gunyah Resource Manager driver (required for IRQ_LEND and MEM_NOTIFIER)
    if ! grep -q "CONFIG_GH_RM_DRV=" "$GKI_DEFCONFIG"; then
        echo "CONFIG_GH_RM_DRV=y" >> "$GKI_DEFCONFIG"
        log "Added CONFIG_GH_RM_DRV=y"
    else
        sed -i 's/CONFIG_GH_RM_DRV=.*/CONFIG_GH_RM_DRV=y/' "$GKI_DEFCONFIG"
        log "Updated CONFIG_GH_RM_DRV=y"
    fi
    
    # Enable Gunyah IRQ Lending Framework (requires GH_RM_DRV)
    if grep -q "CONFIG_GH_RM_DRV=y" "$GKI_DEFCONFIG"; then
        if ! grep -q "CONFIG_GH_IRQ_LEND=" "$GKI_DEFCONFIG"; then
            echo "CONFIG_GH_IRQ_LEND=y" >> "$GKI_DEFCONFIG"
            log "Added CONFIG_GH_IRQ_LEND=y"
        else
            sed -i 's/CONFIG_GH_IRQ_LEND=.*/CONFIG_GH_IRQ_LEND=y/' "$GKI_DEFCONFIG"
            log "Updated CONFIG_GH_IRQ_LEND=y"
        fi
    else
        log "Warning: CONFIG_GH_RM_DRV not enabled, skipping GH_IRQ_LEND"
    fi
    
    # Enable Gunyah Memory Resource Notification (requires GH_RM_DRV)
    if grep -q "CONFIG_GH_RM_DRV=y" "$GKI_DEFCONFIG"; then
        if ! grep -q "CONFIG_GH_MEM_NOTIFIER=" "$GKI_DEFCONFIG"; then
            echo "CONFIG_GH_MEM_NOTIFIER=y" >> "$GKI_DEFCONFIG"
            log "Added CONFIG_GH_MEM_NOTIFIER=y"
        else
            sed -i 's/CONFIG_GH_MEM_NOTIFIER=.*/CONFIG_GH_MEM_NOTIFIER=y/' "$GKI_DEFCONFIG"
            log "Updated CONFIG_GH_MEM_NOTIFIER=y"
        fi
    else
        log "Warning: CONFIG_GH_RM_DRV not enabled, skipping GH_MEM_NOTIFIER"
    fi
    
    log "Gunyah hypervisor configuration applied."
}

# Apply all configuration fixes
apply_config_fixes() {
    log "Applying kernel configuration fixes..."
    
    GKI_DEFCONFIG="$KERNEL_SRC/arch/arm64/configs/gki_defconfig"
    
    # Fix: ZRAM Configuration (Build as Module)
    log "Applying ZRAM Config Fix..."
    if grep -q "CONFIG_ZRAM=y" "$GKI_DEFCONFIG"; then
        sed -i 's/CONFIG_ZRAM=y/CONFIG_ZRAM=m/' "$GKI_DEFCONFIG"
        sed -i 's/CONFIG_ZSMALLOC=y/CONFIG_ZSMALLOC=m/' "$GKI_DEFCONFIG"
        log "Converted ZRAM to module."
    fi
    
    # Enable TMPFS_XATTR (insert after CONFIG_TMPFS=y for correct position)
    log "Enabling TMPFS_XATTR..."
    if ! grep -q "CONFIG_TMPFS_XATTR=y" "$GKI_DEFCONFIG"; then
        sed -i '/^CONFIG_TMPFS=y$/a CONFIG_TMPFS_XATTR=y' "$GKI_DEFCONFIG"
        log "Added CONFIG_TMPFS_XATTR=y"
    fi
    
    # Add ZRAM modules to system_dlkm_modules list
    MODULES_LIST="$KERNEL_SRC/android/gki_system_dlkm_modules"
    if ! grep -q "drivers/block/zram/zram.ko" "$MODULES_LIST"; then
        echo "drivers/block/zram/zram.ko" >> "$MODULES_LIST"
        echo "mm/zsmalloc.ko" >> "$MODULES_LIST"
    fi
    
    # Fix: Export 'task_is_booster' for ZRAM Module
    CPUSET_C="$KERNEL_SRC/kernel/cgroup/cpuset.c"
    if ! grep -q "EXPORT_SYMBOL_GPL(task_is_booster)" "$CPUSET_C"; then
        log "Exporting task_is_booster..."
        echo "" >> "$CPUSET_C"
        echo "EXPORT_SYMBOL_GPL(task_is_booster);" >> "$CPUSET_C"
    fi
    
    # Fix: Add symbol to KMI Allowlist (Strict Mode)
    SYMBOL_LIST="$KERNEL_SRC/android/abi_gki_aarch64"
    if ! grep -q "task_is_booster" "$SYMBOL_LIST"; then
        log "Updating KMI Symbol List..."
        echo "task_is_booster" >> "$SYMBOL_LIST"
    fi

    # Fix: Patch stamp.bzl to remove -maybe-dirty suffix and enable custom timestamp
    if [ -f "$STAMP_BZL" ]; then
        log "Patching stamp.bzl..."
        # Remove -maybe-dirty suffix
        sed -i 's/export LOCALVERSION="-maybe-dirty"/export LOCALVERSION=""/' "$STAMP_BZL"
        
        # Inject current timestamp into stamp.bzl
        # We replace 'export SOURCE_DATE_EPOCH=0' (or 'true' from previous fix) with the actual timestamp
        # This ensures the build uses the correct time instead of 1970-01-01
        CURRENT_EPOCH=$(date +%s)
        
        # Try replacing the original line
        sed -i "s/export SOURCE_DATE_EPOCH=0/export SOURCE_DATE_EPOCH=${CURRENT_EPOCH}/" "$STAMP_BZL"
        
        # Try replacing 'true' (if previous fix was applied)
        # We match the indentation to be safe
        sed -i "s/              true/              export SOURCE_DATE_EPOCH=${CURRENT_EPOCH}/" "$STAMP_BZL"
        
        log "✓ stamp.bzl patched (removed -maybe-dirty, injected timestamp ${CURRENT_EPOCH})"
    fi
    
    # Apply Gunyah hypervisor configuration
    apply_gunyah_config
    
    log "Configuration fixes applied."
}