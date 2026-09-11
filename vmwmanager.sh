#!/usr/bin/env bash
# ============================================================
# vmwmanager
# Fedora VMware host module manager
# Secure Boot compatible
#
# Managed VMware modules:
#   - vmmon.ko
#   - vmnet.ko
#
# Commands:
#   genkey
#   status
#   needs-rebuild
#   rebuild
#   reinstall
#   uninstall
#   purge
#   enable-systemd
#   disable-systemd
#   help
#
# Design:
#   - VMware Workstation must already be installed for:
#       genkey, needs-rebuild, rebuild, reinstall, enable-systemd
#   - status, disable-systemd, uninstall and purge are safe even when
#     VMware Workstation is not installed.
#   - No automatic fallback is used if VMware module compilation
#     fails. Alternative projects may be suggested, but never
#     downloaded or installed automatically.
# ============================================================

set -Eeuo pipefail

# ============================================================
# CONFIGURATION
# ============================================================

MODULES=(
    "vmmon"
    "vmnet"
)

KEY_DIR="/var/lib/shim-signed/mok"
KEY_PRIV="$KEY_DIR/vmware.key"
KEY_DER="$KEY_DIR/vmware.der"

CN_MATCH="CN=VMware Module Signing"

PROGRAM_PATH="/usr/bin/vmwmanager"
PACKAGE_NAME="vmware-manager"

VMWARE_SERVICE_NAME="vmware.service"

SYSTEMD_SERVICE_NAME="vmware-rebuild.service"
SYSTEMD_SERVICE="/etc/systemd/system/$SYSTEMD_SERVICE_NAME"

VMWARE_HOST_MODULES_URL="https://github.com/mkubecek/vmware-host-modules"

# ============================================================
# ROOT HELPER
# ============================================================

run_root() {
    if [[ "$EUID" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

# ============================================================
# VMWARE INSTALLATION CHECK
# ============================================================

vmware_workstation_is_installed() {
    local inventory=""

    if command -v vmware-installer >/dev/null 2>&1; then
        inventory="$(vmware-installer -l 2>/dev/null || true)"

        if awk '
            $1 == "vmware-workstation" {
                found = 1
            }
            END {
                exit(found ? 0 : 1)
            }
        ' <<<"$inventory"; then
            return 0
        fi
    fi

    # Fallback check for installations where the installer inventory
    # is unavailable but the expected VMware tools are present.
    command -v vmware >/dev/null 2>&1 &&
        command -v vmware-modconfig >/dev/null 2>&1
}

require_vmware() {
    if vmware_workstation_is_installed; then
        return 0
    fi

    echo "❌ VMware Workstation is not installed."
    return 1
}

# ============================================================
# KERNEL
#
# VMware's native vmware-modconfig builds host modules for the
# running kernel, so this manager intentionally uses uname -r.
# ============================================================

get_target_kernel() {
    local kver

    kver="$(uname -r)"

    if [[ -z "$kver" ]]; then
        echo "❌ Unable to determine the running kernel." >&2
        return 1
    fi

    if [[ ! -d "/lib/modules/$kver" ]]; then
        echo "❌ Module directory does not exist:" >&2
        echo "   /lib/modules/$kver" >&2
        return 1
    fi

    printf '%s\n' "$kver"
}

get_default_boot_kernel() {
    local kernel_path
    local kver

    if command -v grubby >/dev/null 2>&1; then
        if [[ "$EUID" -eq 0 ]]; then
            kernel_path="$(grubby --default-kernel 2>/dev/null || true)"
        else
            kernel_path="$(sudo grubby --default-kernel 2>/dev/null || true)"
        fi

        if [[ -n "$kernel_path" ]]; then
            kver="$(basename "$kernel_path")"
            kver="${kver#vmlinuz-}"
            printf '%s\n' "$kver"
            return 0
        fi
    fi

    return 1
}

# ============================================================
# MODULE HELPERS
# ============================================================

get_module_path() {
    local module="$1"
    local kver="$2"
    local path

    path="$(
        modinfo \
            -k "$kver" \
            -n "$module" \
            2>/dev/null ||
            true
    )"

    if [[ -z "$path" || "$path" == "(builtin)" || ! -f "$path" ]]; then
        return 1
    fi

    printf '%s\n' "$path"
}

module_signature_is_valid() {
    local module_path="$1"
    local signer
    local expected_signer="${CN_MATCH#CN=}"

    signer="$(modinfo -F signer "$module_path" 2>/dev/null || true)"

    [[ -n "$signer" && "$signer" == *"$expected_signer"* ]]
}

# ============================================================
# MOK ENROLLMENT CHECK
# ============================================================

mok_certificate_is_enrolled() {
    local output

    [[ -f "$KEY_DER" ]] || return 1

    if [[ "$EUID" -eq 0 ]]; then
        output="$(
            LC_ALL=C mokutil --test-key "$KEY_DER" 2>&1 ||
                true
        )"
    else
        output="$(
            sudo env LC_ALL=C mokutil --test-key "$KEY_DER" 2>&1 ||
                true
        )"
    fi

    grep -Fq 'is already enrolled' <<<"$output"
}

# ============================================================
# VMWARE SERVICE
# ============================================================

restart_vmware_service() {
    echo
    echo "🔄 Restarting VMware service:"
    echo "   $VMWARE_SERVICE_NAME"

    if ! systemctl list-unit-files \
        "$VMWARE_SERVICE_NAME" \
        --no-legend 2>/dev/null |
        grep -q "^${VMWARE_SERVICE_NAME}[[:space:]]"; then
        echo "❌ VMware service is not installed:"
        echo "   $VMWARE_SERVICE_NAME"
        return 1
    fi

    if run_root systemctl restart "$VMWARE_SERVICE_NAME"; then
        echo "✅ $VMWARE_SERVICE_NAME restarted."
        return 0
    fi

    echo "❌ Failed to restart $VMWARE_SERVICE_NAME."
    return 1
}

# ============================================================
# VMWARE SERVICE STATUS
#
# Read-only inspection. This function never starts, stops,
# enables, disables or restarts vmware.service.
# ============================================================

show_vmware_service_status() {
    local load_state
    local unit_file_state
    local active_state
    local sub_state
    local result

    echo "⚙️ VMware service:"
    echo "   $VMWARE_SERVICE_NAME"

    load_state="$(
        systemctl show \
            "$VMWARE_SERVICE_NAME" \
            -p LoadState \
            --value 2>/dev/null ||
            true
    )"

    if [[ -z "$load_state" || "$load_state" == "not-found" ]]; then
        echo "   ❌ Service does not exist."
        return 1
    fi

    unit_file_state="$(
        systemctl show \
            "$VMWARE_SERVICE_NAME" \
            -p UnitFileState \
            --value 2>/dev/null ||
            true
    )"

    active_state="$(
        systemctl show \
            "$VMWARE_SERVICE_NAME" \
            -p ActiveState \
            --value 2>/dev/null ||
            true
    )"

    sub_state="$(
        systemctl show \
            "$VMWARE_SERVICE_NAME" \
            -p SubState \
            --value 2>/dev/null ||
            true
    )"

    result="$(
        systemctl show \
            "$VMWARE_SERVICE_NAME" \
            -p Result \
            --value 2>/dev/null ||
            true
    )"

    echo "   Load:    ${load_state:-unknown}"
    echo "   Enabled: ${unit_file_state:-unknown}"
    echo "   Active:  ${active_state:-unknown}"
    echo "   Sub:     ${sub_state:-unknown}"
    echo "   Result:  ${result:-unknown}"

    case "$active_state" in
        active)
            echo "   ✅ VMware service is active."
            return 0
            ;;
        failed)
            echo "   ❌ VMware service has failed."
            return 1
            ;;
        inactive)
            echo "   ⚠️ VMware service is inactive."
            return 1
            ;;
        activating | deactivating | reloading)
            echo "   ⚠️ VMware service is transitioning:"
            echo "      $active_state / ${sub_state:-unknown}"
            return 1
            ;;
        *)
            echo "   ⚠️ VMware service state: ${active_state:-unknown}"
            return 1
            ;;
    esac
}

# ============================================================
# STATUS
# ============================================================

show_status() {
    local kver
    local default_kver=""
    local module
    local module_path
    local signer
    local sb_state
    local result=0

    echo "=== 🔎 VMware host-module status ==="
    echo

    echo "📦 VMware Workstation:"
    if vmware_workstation_is_installed; then
        echo "   ✅ Installed."
    else
        echo "   ❌ Not installed."
        result=1
    fi
    echo

    kver="$(get_target_kernel)"

    echo "🐧 Running kernel:"
    echo "   $kver"

    default_kver="$(get_default_boot_kernel || true)"
    if [[ -n "$default_kver" ]]; then
        echo
        echo "🐧 Fedora default boot kernel:"
        echo "   $default_kver"

        if [[ "$default_kver" != "$kver" ]]; then
            echo "   ℹ️ The default boot kernel is not the running kernel."
            echo "   ℹ️ VMware native modules are managed for the running kernel."
        fi
    fi
    echo

    echo "🔐 Secure Boot:"
    if command -v mokutil >/dev/null 2>&1; then
        sb_state="$(mokutil --sb-state 2>&1 || true)"

        if [[ -n "$sb_state" ]]; then
            echo "   $sb_state"
        else
            echo "   ⚠️ Unable to determine Secure Boot state."
            result=1
        fi
    else
        echo "   ❌ mokutil is not installed."
        result=1
    fi
    echo

    echo "🗝 Signing key files:"
    if [[ -f "$KEY_PRIV" && -f "$KEY_DER" ]]; then
        echo "   ✅ Private key: $KEY_PRIV"
        echo "   ✅ Certificate: $KEY_DER"
    elif [[ ! -f "$KEY_PRIV" && ! -f "$KEY_DER" ]]; then
        echo "   ❌ Signing key and certificate are missing."
        result=1
    else
        echo "   ❌ Signing key files are incomplete."
        [[ -f "$KEY_PRIV" ]] &&
            echo "   ✅ Private key: $KEY_PRIV"
        [[ ! -f "$KEY_PRIV" ]] &&
            echo "   ❌ Private key missing: $KEY_PRIV"
        [[ -f "$KEY_DER" ]] &&
            echo "   ✅ Certificate: $KEY_DER"
        [[ ! -f "$KEY_DER" ]] &&
            echo "   ❌ Certificate missing: $KEY_DER"
        result=1
    fi
    echo

    echo "🔏 MOK enrollment:"
    if [[ ! -f "$KEY_DER" ]]; then
        echo "   ❌ Local signing certificate is not available."
        result=1
    elif mok_certificate_is_enrolled; then
        echo "   ✅ Signing certificate is enrolled."
    else
        echo "   ❌ Signing certificate is NOT enrolled."

        if vmware_workstation_is_installed; then
            echo "   → Run: sudo $PROGRAM_PATH genkey"
            echo "   → Then reboot manually: sudo reboot"
            echo "   → Complete MOK enrollment in the blue MOK Manager screen."
        fi

        result=1
    fi
    echo

    echo "🧩 VMware host modules:"

    if ! vmware_workstation_is_installed; then
        echo "   ℹ️ Module checks skipped because VMware Workstation is not installed."
        echo
    else
        for module in "${MODULES[@]}"; do
            echo
            echo "   $module.ko:"

            module_path="$(get_module_path "$module" "$kver" || true)"

            if [[ -z "$module_path" ]]; then
                echo "      ❌ Module does not exist for $kver."
                result=1
                continue
            fi

            echo "      📦 $module_path"

            signer="$(
                modinfo -F signer "$module_path" 2>/dev/null ||
                    true
            )"

            if [[ -z "$signer" ]]; then
                echo "      ❌ Module is unsigned or signer cannot be read."
                result=1
            elif module_signature_is_valid "$module_path"; then
                echo "      ✅ Signature is valid."
                echo "      Signer: $signer"
            else
                echo "      ❌ Module is signed by another certificate."
                echo "      Signer: $signer"
                result=1
            fi

            if lsmod | grep -q "^${module}[[:space:]]"; then
                echo "      ✅ Loaded."
            else
                echo "      ℹ️ Not currently loaded."
            fi
        done

        echo
    fi

    show_vmware_service_status || result=1
    echo

    echo "⚙️ vmwmanager systemd integration:"
    if systemctl is-enabled \
        "$SYSTEMD_SERVICE_NAME" >/dev/null 2>&1; then
        echo "   ✅ Enabled: $SYSTEMD_SERVICE_NAME"
    elif [[ -f "$SYSTEMD_SERVICE" ]]; then
        echo "   ⚠️ Unit exists but is disabled:"
        echo "   $SYSTEMD_SERVICE"
    else
        echo "   ℹ️ Not installed."
    fi
    echo

    if [[ "$result" -eq 0 ]]; then
        echo "✅ VMware signing state is ready."
    else
        echo "⚠️ VMware requires attention."
    fi

    return "$result"
}

# ============================================================
# NEEDS REBUILD
#
# Exit codes are intentionally designed for systemd ExecCondition:
#
#   0 -> vmmon/vmnet missing or invalid -> rebuild required
#   1 -> nothing to rebuild, or VMware is not installed
# ============================================================

needs_rebuild() {
    local kver
    local module
    local module_path
    local signer
    local rebuild=false

    if ! require_vmware; then
        echo
        echo "ℹ️ Rebuild cannot be performed."
        return 1
    fi

    kver="$(get_target_kernel)"

    echo "🔎 Running kernel:"
    echo "   $kver"
    echo

    for module in "${MODULES[@]}"; do
        echo "🔎 Checking $module.ko..."

        module_path="$(get_module_path "$module" "$kver" || true)"

        if [[ -z "$module_path" ]]; then
            echo "   ❌ Module does not exist for $kver."
            echo "   🔨 Rebuild required."
            rebuild=true
            echo
            continue
        fi

        echo "   📦 $module_path"

        signer="$(
            modinfo -F signer "$module_path" 2>/dev/null ||
                true
        )"

        if [[ -z "$signer" ]]; then
            echo "   ❌ Module is unsigned."
            echo "   🔨 Rebuild/sign required."
            rebuild=true
        elif ! module_signature_is_valid "$module_path"; then
            echo "   ❌ Module is not signed with the expected certificate."
            echo "   Expected: ${CN_MATCH#CN=}"
            echo "   Found:    $signer"
            echo "   🔨 Rebuild/sign required."
            rebuild=true
        else
            echo "   ✅ Module exists and is correctly signed."
            echo "   Signer: $signer"
        fi

        echo
    done

    if [[ "$rebuild" == true ]]; then
        return 0
    fi

    echo "✅ vmmon.ko and vmnet.ko are correctly installed and signed."
    echo

    if [[ ! -f "$KEY_DER" ]]; then
        echo "⚠️ Local signing certificate is not available:"
        echo "   $KEY_DER"
        echo
        echo "ℹ️ The modules themselves do not need rebuilding."
        return 1
    fi

    if mok_certificate_is_enrolled; then
        echo "✅ Signing certificate is enrolled."
        echo "ℹ️ Nothing to rebuild."
        return 1
    fi

    echo "⚠️ Signing certificate is NOT enrolled."
    echo
    echo "The modules are already correctly built and signed."
    echo "Rebuilding them would not fix the trust problem."
    echo
    echo "Re-enroll the existing certificate with:"
    echo "   sudo $PROGRAM_PATH genkey"
    echo
    echo "Then reboot manually:"
    echo "   sudo reboot"
    echo
    echo "Complete MOK enrollment in the blue MOK Manager screen."

    return 1
}

# ============================================================
# GENERATE SIGNING KEY
# ============================================================

gen_signing_key() {
    local generated=false

    echo "=== 🔑 VMware Secure Boot signing key / MOK enrollment ==="
    echo

    if ! require_vmware; then
        echo
        echo "A VMware signing key will not be generated."
        echo "Install VMware Workstation first, then run:"
        echo
        echo "   sudo $PROGRAM_PATH genkey"
        return 1
    fi

    run_root mkdir -p "$KEY_DIR"

    if [[ -f "$KEY_PRIV" && ! -f "$KEY_DER" ]]; then
        echo "❌ Signing key files are incomplete."
        echo
        echo "Private key exists:"
        echo "   $KEY_PRIV"
        echo
        echo "Certificate is missing:"
        echo "   $KEY_DER"
        echo
        echo "Refusing to generate a new key automatically."
        return 1
    fi

    if [[ ! -f "$KEY_PRIV" && -f "$KEY_DER" ]]; then
        echo "❌ Signing key files are incomplete."
        echo
        echo "Certificate exists:"
        echo "   $KEY_DER"
        echo
        echo "Private key is missing:"
        echo "   $KEY_PRIV"
        echo
        echo "Refusing to generate a new key automatically."
        return 1
    fi

    if [[ -f "$KEY_PRIV" && -f "$KEY_DER" ]]; then
        echo "ℹ️ Existing signing key will be preserved:"
        echo "   $KEY_DIR"
        echo

        run_root ls -l "$KEY_PRIV" "$KEY_DER"
    else
        echo "🔨 Generating new VMware signing key..."
        echo

        run_root openssl req \
            -new \
            -x509 \
            -newkey rsa:2048 \
            -keyout "$KEY_PRIV" \
            -outform DER \
            -out "$KEY_DER" \
            -nodes \
            -days 36500 \
            -subj "/CN=VMware Module Signing/"

        run_root chmod 600 "$KEY_PRIV"
        run_root chmod 644 "$KEY_DER"

        generated=true

        echo
        echo "✅ Signing key generated:"
        run_root ls -l "$KEY_PRIV" "$KEY_DER"
    fi

    echo
    echo "🔏 Checking MOK enrollment..."

    if mok_certificate_is_enrolled; then
        echo "✅ Signing certificate is already enrolled."
        echo

        if [[ "$generated" == true ]]; then
            echo "ℹ️ No additional enrollment request is required."
        else
            echo "ℹ️ Existing key and enrollment are valid."
            echo "ℹ️ Nothing to do."
        fi

        return 0
    fi

    echo "⚠️ Signing certificate is not currently enrolled."
    echo
    echo "🔐 Scheduling enrollment of the EXISTING certificate..."
    echo
    echo "The private key will NOT be regenerated."
    echo
    echo "You will be asked to create a temporary password."
    echo "This password is required once in the MOK Manager"
    echo "screen during the next reboot."
    echo

    run_root mokutil --import "$KEY_DER"

    echo
    echo "✅ MOK enrollment scheduled."
    echo
    echo "Check pending enrollment:"
    echo
    echo "   mokutil --list-new"
    echo
    echo "Then reboot manually:"
    echo
    echo "   sudo reboot"
    echo
    echo "After enrollment, verify with:"
    echo
    echo "   mokutil --test-key $KEY_DER"
}

# ============================================================
# BUILD VMWARE HOST MODULES
# ============================================================

build_vmware_modules() {
    local kver="$1"
    local build_marker
    local modconfig_rc=0
    local module
    local module_path
    local modules_ok=true

    echo "🔨 Building VMware host modules for:"
    echo "   $kver"
    echo

    build_marker="$(mktemp)" || {
        echo "❌ Unable to create temporary build marker."
        return 1
    }

    # The marker lets us distinguish modules produced by this invocation
    # from stale vmmon/vmnet files that were already present beforehand.
    touch "$build_marker"

    # Important Secure Boot detail:
    # vmware-modconfig may successfully compile and install vmmon/vmnet,
    # then return a non-zero status because it tries to start
    # vmware.service before those newly installed modules are signed.
    # Therefore its exit status alone is NOT enough to decide whether
    # compilation actually failed.
    if run_root vmware-modconfig --console --install-all; then
        modconfig_rc=0
    else
        modconfig_rc=$?
    fi

    echo

    # Refresh module dependency metadata before locating the freshly
    # installed modules with modinfo.
    run_root depmod -a "$kver" >/dev/null 2>&1 || true

    for module in "${MODULES[@]}"; do
        module_path="$(get_module_path "$module" "$kver" || true)"

        if [[ -z "$module_path" ]]; then
            echo "❌ $module.ko was not installed for kernel:"
            echo "   $kver"
            modules_ok=false
            continue
        fi

        if [[ ! "$module_path" -nt "$build_marker" ]]; then
            echo "❌ $module.ko was not rebuilt during this operation:"
            echo "   $module_path"
            modules_ok=false
            continue
        fi

        echo "✅ $module.ko was rebuilt and installed:"
        echo "   $module_path"
    done

    rm -f "$build_marker"

    if [[ "$modules_ok" != true ]]; then
        echo
        echo "❌ VMware host module compilation/install failed."
        echo

        if ((modconfig_rc != 0)); then
            echo "vmware-modconfig exit code:"
            echo "   $modconfig_rc"
            echo
        fi

        echo "No fallback has been applied."
        echo
        echo "The native VMware module sources may not support"
        echo "the currently running kernel:"
        echo "   $kver"
        echo
        echo "Alternative host-module implementations exist, for example:"
        echo "   $VMWARE_HOST_MODULES_URL"
        echo
        echo "vmwmanager intentionally does NOT download, patch,"
        echo "compile or install alternative modules automatically."
        echo
        echo "Review the VMware compilation error before choosing"
        echo "an alternative implementation."

        return 1
    fi

    echo

    if ((modconfig_rc != 0)); then
        echo "⚠️ vmware-modconfig returned exit code:"
        echo "   $modconfig_rc"
        echo
        echo "However, both VMware host modules were successfully"
        echo "rebuilt and installed."
        echo
        echo "With Secure Boot enabled, this can happen because"
        echo "vmware-modconfig tries to start vmware.service before"
        echo "the newly built modules have been signed."
        echo
        echo "Continuing with module signing..."
    else
        echo "✅ VMware host modules compiled successfully."
    fi

    return 0
}

# ============================================================
# SIGN VMWARE HOST MODULES
# ============================================================

sign_vmware_modules() {
    local kver="$1"
    local kernel_src
    local sign_file
    local module
    local module_path
    local changed=false

    kernel_src="/usr/src/kernels/$kver"
    sign_file="$kernel_src/scripts/sign-file"

    if [[ ! -d "$kernel_src" ]]; then
        echo "❌ kernel-devel is not installed for the running kernel:"
        echo "   $kver"
        echo
        echo "Install it with:"
        echo "   sudo dnf install kernel-devel-$kver"
        return 1
    fi

    if [[ ! -x "$sign_file" ]]; then
        echo "❌ Kernel signing utility not found:"
        echo "   $sign_file"
        return 1
    fi

    if [[ ! -f "$KEY_PRIV" || ! -f "$KEY_DER" ]]; then
        echo "❌ Signing keys not found:"
        echo "   $KEY_PRIV"
        echo "   $KEY_DER"
        echo
        echo "Run first:"
        echo "   sudo $PROGRAM_PATH genkey"
        return 1
    fi

    for module in "${MODULES[@]}"; do
        module_path="$(get_module_path "$module" "$kver" || true)"

        if [[ -z "$module_path" ]]; then
            echo "❌ VMware compilation completed, but $module.ko"
            echo "   cannot be found for kernel:"
            echo "   $kver"
            return 1
        fi

        case "$module_path" in
            *.xz | *.zst | *.gz)
                echo "❌ Refusing to sign a compressed kernel module:"
                echo "   $module_path"
                echo
                echo "The module must be uncompressed before signing."
                return 1
                ;;
        esac

        echo
        echo "🔐 Signing $module.ko:"
        echo "   $module_path"

        run_root "$sign_file" \
            sha256 \
            "$KEY_PRIV" \
            "$KEY_DER" \
            "$module_path"

        changed=true
    done

    echo
    echo "🔄 Updating module dependencies..."

    run_root depmod -a "$kver"

    if [[ "$changed" == true ]]; then
        echo "✅ vmmon.ko and vmnet.ko signed successfully."
    fi
}

# ============================================================
# VERIFY MODULES AFTER BUILD/SIGN
# ============================================================

verify_vmware_modules() {
    local kver="$1"
    local module
    local module_path

    for module in "${MODULES[@]}"; do
        module_path="$(get_module_path "$module" "$kver" || true)"

        if [[ -z "$module_path" ]]; then
            echo "❌ Verification failed: $module.ko is missing."
            return 1
        fi

        if ! module_signature_is_valid "$module_path"; then
            echo "❌ Verification failed: $module.ko has an invalid signature."
            return 1
        fi
    done

    echo "✅ vmmon.ko and vmnet.ko verified successfully."
}

# ============================================================
# REBUILD
# ============================================================

rebuild_module() {
    local kver

    echo "=== 🧰 VMware host-module rebuild ==="
    echo

    if ! require_vmware; then
        return 1
    fi

    kver="$(get_target_kernel)"

    echo
    echo "🐧 Running kernel:"
    echo "   $kver"
    echo

    if [[ ! -f "$KEY_PRIV" || ! -f "$KEY_DER" ]]; then
        echo "❌ VMware signing keys are not available."
        echo
        echo "Run first:"
        echo "   sudo $PROGRAM_PATH genkey"
        return 1
    fi

    if ! needs_rebuild >/dev/null; then
        echo "✅ vmmon.ko and vmnet.ko already exist"
        echo "   and are correctly signed."
        echo
        echo "ℹ️ Nothing to rebuild."
        return 0
    fi

    build_vmware_modules "$kver" || return 1
    sign_vmware_modules "$kver" || return 1
    verify_vmware_modules "$kver" || return 1

    restart_vmware_service || return 1

    echo
    echo "✅ VMware host-module rebuild completed successfully."
}

# ============================================================
# REINSTALL
#
# Force VMware's native module compilation even if the current
# modules already exist and are correctly signed.
# ============================================================

reinstall_module() {
    local kver

    echo "=== 🔄 Reinstalling VMware host modules ==="
    echo

    if ! require_vmware; then
        return 1
    fi

    if [[ ! -f "$KEY_PRIV" || ! -f "$KEY_DER" ]]; then
        echo "❌ VMware signing keys are not available."
        echo
        echo "Run first:"
        echo "   sudo $PROGRAM_PATH genkey"
        return 1
    fi

    kver="$(get_target_kernel)"

    echo "🐧 Running kernel:"
    echo "   $kver"
    echo

    build_vmware_modules "$kver" || return 1
    sign_vmware_modules "$kver" || return 1
    verify_vmware_modules "$kver" || return 1

    restart_vmware_service || return 1

    echo
    echo "✅ VMware host modules reinstalled successfully."
}

# ============================================================
# ENABLE SYSTEMD
# ============================================================

enable_systemd() {
    echo "=== ⚙️ Enabling VMware systemd module check ==="
    echo

    if ! require_vmware; then
        echo
        echo "vmwmanager systemd integration will not be enabled."
        return 1
    fi

    if [[ -f "$SYSTEMD_SERVICE" ]]; then
        echo "ℹ️ systemd service already exists:"
        echo "   $SYSTEMD_SERVICE"
        echo
        echo "ℹ️ Existing service file will NOT be overwritten."
        echo
    else
        echo "📝 Creating systemd service:"
        echo "   $SYSTEMD_SERVICE"
        echo

        run_root tee "$SYSTEMD_SERVICE" >/dev/null <<EOF
[Unit]
Description=Ensure VMware host modules are available and signed
Documentation=$VMWARE_HOST_MODULES_URL
Wants=$VMWARE_SERVICE_NAME
After=local-fs.target $VMWARE_SERVICE_NAME
ConditionPathExists=$PROGRAM_PATH

[Service]
Type=oneshot
ExecCondition=$PROGRAM_PATH needs-rebuild
ExecStart=$PROGRAM_PATH rebuild

[Install]
WantedBy=multi-user.target
EOF

        echo "✅ systemd service created."
        echo

        echo "🔄 Reloading systemd configuration..."
        run_root systemctl daemon-reload
        echo "✅ systemd configuration reloaded."
        echo
    fi

    if systemctl is-enabled \
        "$SYSTEMD_SERVICE_NAME" >/dev/null 2>&1; then
        echo "✅ systemd service is already enabled:"
        echo "   $SYSTEMD_SERVICE_NAME"
    else
        echo "⚙️ Enabling:"
        echo "   $SYSTEMD_SERVICE_NAME"

        run_root systemctl enable "$SYSTEMD_SERVICE_NAME"

        echo "✅ systemd service enabled."
    fi

    echo
    echo "🔎 Running VMware module check now..."
    echo

    run_root systemctl start "$SYSTEMD_SERVICE_NAME"

    echo
    echo "✅ systemd check completed."
    echo
    echo "------------------------------------------------------------"
    echo "systemd service:"
    echo
    echo "   $SYSTEMD_SERVICE_NAME"
    echo
    echo "At boot:"
    echo
    echo "   vmmon.ko + vmnet.ko valid:"
    echo "      → ExecCondition returns 1"
    echo "      → rebuild is skipped"
    echo
    echo "   module missing or invalid signature:"
    echo "      → ExecCondition returns 0"
    echo "      → rebuild is executed"
    echo
    echo "Check service status:"
    echo
    echo "   systemctl status $SYSTEMD_SERVICE_NAME"
    echo
    echo "Check boot logs:"
    echo
    echo "   journalctl -b -u $SYSTEMD_SERVICE_NAME"
}

# ============================================================
# DISABLE SYSTEMD
#
# Does NOT require VMware Workstation to be installed.
# ============================================================

disable_systemd() {
    local changed=false

    echo "=== ⚙️ Disabling VMware systemd module check ==="
    echo

    if systemctl is-enabled \
        "$SYSTEMD_SERVICE_NAME" >/dev/null 2>&1; then
        echo "⚙️ systemd service is enabled:"
        echo "   $SYSTEMD_SERVICE_NAME"
        echo
        echo "→ Disabling service..."

        run_root systemctl disable "$SYSTEMD_SERVICE_NAME"

        echo
        echo "✅ systemd service disabled."

        changed=true
    else
        echo "ℹ️ systemd service is already disabled:"
        echo "   $SYSTEMD_SERVICE_NAME"
    fi

    echo

    if [[ -f "$SYSTEMD_SERVICE" ]]; then
        echo "🗑 Removing systemd service file:"
        echo "   $SYSTEMD_SERVICE"

        run_root rm -f "$SYSTEMD_SERVICE"

        echo
        echo "✅ systemd service file removed."

        changed=true
    else
        echo "ℹ️ systemd service file does not exist:"
        echo "   $SYSTEMD_SERVICE"
    fi

    echo

    if [[ "$changed" == true ]]; then
        echo "🔄 Reloading systemd configuration..."

        run_root systemctl daemon-reload

        echo "✅ systemd configuration reloaded."
    else
        echo "ℹ️ No systemd changes were required."
    fi

    if systemctl is-failed \
        "$SYSTEMD_SERVICE_NAME" >/dev/null 2>&1; then
        echo
        echo "⚠️ Service has a failed state."
        echo "→ Clearing failed state..."

        run_root systemctl reset-failed "$SYSTEMD_SERVICE_NAME"

        echo "✅ Failed state cleared."
    fi

    echo
    echo "✅ vmwmanager systemd integration is disabled."
}

# ============================================================
# UNINSTALL VMWMANAGER INTEGRATION
#
# Does NOT remove VMware Workstation or vmmon/vmnet manually.
# Safe when VMware Workstation is already absent.
# ============================================================

uninstall_manager() {
    local der_to_delete=""
    local tmp_dir=""
    local yn

    echo "=== 🧼 Uninstalling vmwmanager integration ==="
    echo

    disable_systemd

    # --------------------------------------------------------
    # MOK certificate
    # --------------------------------------------------------

    if command -v mokutil >/dev/null 2>&1; then
        echo
        echo "🔐 Checking VMware MOK certificate..."

        if [[ -f "$KEY_DER" ]]; then
            der_to_delete="$KEY_DER"
        else
            tmp_dir="$(mktemp -d)"

            pushd "$tmp_dir" >/dev/null

            run_root mokutil --export >/dev/null 2>&1 || true

            for f in MOK-*.der; do
                [[ -f "$f" ]] || continue

                if openssl x509 \
                    -inform der \
                    -in "$f" \
                    -noout \
                    -subject 2>/dev/null |
                    grep -Fq "$CN_MATCH"; then
                    der_to_delete="$tmp_dir/$f"
                    break
                fi
            done

            popd >/dev/null
        fi

        if [[ -n "$der_to_delete" && -f "$der_to_delete" ]]; then
            echo
            echo "🗝 VMware signing certificate found:"
            echo "   $der_to_delete"
            echo

            read -rp \
                "Stage VMware MOK certificate deletion? [y/N] " \
                yn

            if [[ "$yn" =~ ^[Yy]$ ]]; then
                run_root mokutil --delete "$der_to_delete"

                echo
                echo "✅ MOK deletion scheduled."
                echo
                echo "Complete 'Delete MOK' during the next reboot."
            else
                echo "ℹ️ MOK certificate preserved."
            fi
        else
            echo "ℹ️ VMware MOK certificate was not found."
        fi

        if [[ -n "$tmp_dir" && -d "$tmp_dir" ]]; then
            rm -rf "$tmp_dir"
        fi
    else
        echo
        echo "ℹ️ mokutil is not installed; MOK cleanup skipped."
    fi

    # --------------------------------------------------------
    # Local signing keys
    # --------------------------------------------------------

    echo

    if [[ -f "$KEY_PRIV" || -f "$KEY_DER" ]]; then
        read -rp \
            "Remove local VMware signing keys in $KEY_DIR? [y/N] " \
            yn

        if [[ "$yn" =~ ^[Yy]$ ]]; then
            run_root rm -f \
                "$KEY_PRIV" \
                "$KEY_DER"

            echo "✅ Local VMware signing keys removed."
        else
            echo "ℹ️ VMware signing keys preserved."
        fi
    else
        echo "ℹ️ No local VMware signing keys were found."
    fi

    # --------------------------------------------------------
    # VMware Workstation itself
    # --------------------------------------------------------

    echo
    echo "✅ vmwmanager integration cleanup completed."
    echo

    if vmware_workstation_is_installed; then
        echo "ℹ️ VMware Workstation is still installed."
        echo
        echo "vmwmanager does NOT remove VMware Workstation"
        echo "or manually delete vmmon.ko / vmnet.ko."
        echo
        echo "To completely uninstall VMware Workstation,"
        echo "including its installed host modules, run:"
        echo
        echo "   sudo vmware-installer -u vmware-workstation"
    else
        echo "ℹ️ VMware Workstation is not installed."
        echo "ℹ️ No VMware uninstall action is required."
    fi
}

# ============================================================
# PURGE VMWMANAGER
#
# Performs the existing uninstall cleanup and then removes the
# vmware-manager RPM through DNF. VMware Workstation itself is
# not removed.
# ============================================================

purge_manager() {
    echo "=== 🧹 Purging vmware-manager ==="
    echo

    if ! command -v dnf >/dev/null 2>&1; then
        echo "❌ DNF is not available."
        echo "   Cannot remove the $PACKAGE_NAME RPM."
        return 1
    fi

    uninstall_manager

    echo
    echo "============================================================"
    echo " Local vmware-manager resources have been processed."
    echo
    echo " The $PACKAGE_NAME RPM will now be removed."
    echo " DNF will ask for final transaction confirmation."
    echo "============================================================"
    echo

    if run_root dnf remove "$PACKAGE_NAME"; then
        return 0
    fi

    echo
    echo "⚠️ $PACKAGE_NAME RPM removal was cancelled or failed."
    echo "   Local vmwmanager resources were already processed."
    return 1
}

# ============================================================
# HELP
# ============================================================

show_help() {
    cat <<EOF
Usage:
    $0 <command>

Commands:

    genkey
        Require VMware Workstation to be installed.

        Generate the Secure Boot signing key when it does not exist.

        If the key already exists, preserve it and verify MOK
        enrollment. If enrollment was lost, request re-enrollment
        of the existing certificate without regenerating the key.

    status
        VMware installation is NOT required.

        Show:
            - VMware Workstation installation state
            - running kernel
            - Fedora default boot kernel when available
            - Secure Boot state
            - signing-key files
            - MOK enrollment
            - vmmon.ko and vmnet.ko presence/signatures
            - vmware.service load/enabled/active/sub/result state
            - vmwmanager systemd integration

    needs-rebuild
        Require VMware Workstation to be installed.

        Check vmmon.ko and vmnet.ko for the running kernel.

        Exit status:
            0 = module missing/invalid signature, rebuild required
            1 = nothing to rebuild, or VMware is not installed

        Intended primarily for systemd ExecCondition.

    rebuild
        Require VMware Workstation to be installed.

        Rebuild only when vmmon.ko or vmnet.ko is missing or has
        an invalid signature.

        Uses VMware's native:
            vmware-modconfig --console --install-all

        On success:
            - sign vmmon.ko
            - sign vmnet.ko
            - run depmod
            - verify both signatures
            - restart $VMWARE_SERVICE_NAME

        If compilation fails:
            - stop immediately
            - do NOT apply a fallback
            - inform about alternative host-module projects

    reinstall
        Require VMware Workstation to be installed.

        Force VMware's native module compilation even when the
        current modules already exist and are correctly signed.

        Then sign, verify and restart $VMWARE_SERVICE_NAME.

    uninstall
        VMware Workstation is NOT required.

        Remove vmwmanager integration only:
            - disable/remove $SYSTEMD_SERVICE_NAME
            - optionally stage VMware MOK deletion
            - optionally remove local VMware signing keys

        VMware Workstation and its host modules are NOT manually
        removed by vmwmanager.

        If VMware Workstation is still installed, the command shows:
            sudo vmware-installer -u vmware-workstation

    purge
        VMware Workstation is NOT required.

        Perform the same vmwmanager integration cleanup as uninstall,
        then remove the vmware-manager RPM through DNF.

        DNF asks for final transaction confirmation before removing:
            $PACKAGE_NAME

        VMware Workstation and its host modules are NOT removed.

    enable-systemd
        Require VMware Workstation to be installed.

        Install and enable:
            $SYSTEMD_SERVICE

        At boot:
            vmmon/vmnet missing or invalid:
                rebuild is executed

            both modules valid:
                rebuild is skipped

    disable-systemd
        VMware Workstation is NOT required.

        Disable and remove:
            $SYSTEMD_SERVICE_NAME

        Safe and idempotent even if VMware Workstation is already
        uninstalled or the service no longer exists.

    help
        Show this help.

Managed modules:
    vmmon
    vmnet

Installed command:
    $PROGRAM_PATH

VMware service:
    $VMWARE_SERVICE_NAME

vmwmanager systemd service:
    $SYSTEMD_SERVICE_NAME
EOF
}

# ============================================================
# MAIN
# ============================================================

cmd="${1:-help}"

case "$cmd" in
    genkey)
        gen_signing_key
        ;;

    status)
        show_status
        ;;

    needs-rebuild)
        needs_rebuild
        ;;

    rebuild)
        rebuild_module
        ;;

    reinstall)
        reinstall_module
        ;;

    uninstall)
        uninstall_manager
        ;;

    purge)
        purge_manager
        ;;

    enable-systemd)
        enable_systemd
        ;;

    disable-systemd)
        disable_systemd
        ;;

    help | --help | -h)
        show_help
        ;;

    *)
        echo "❌ Unknown command: $cmd"
        echo
        show_help
        exit 1
        ;;
esac
