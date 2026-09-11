# vmware-manager Test Plan

This document defines the functional, regression, Secure Boot, kernel, systemd, module-signing, and cleanup tests for `vmware-manager`.

The primary command under test is:

```text
/usr/bin/vmwmanager
```

Managed VMware host modules:

```text
vmmon.ko
vmnet.ko
```

---

## Table of Contents

- [1. Test Goals](#1-test-goals)
- [2. Test Environment](#2-test-environment)
- [3. Safety Notes](#3-safety-notes)
- [4. Baseline Information](#4-baseline-information)
- [5. Command Availability](#5-command-availability)
- [6. VMware Detection](#6-vmware-detection)
- [7. Status Tests](#7-status-tests)
- [8. Secure Boot Tests](#8-secure-boot-tests)
- [9. Signing-Key Tests](#9-signing-key-tests)
- [10. MOK Enrollment Tests](#10-mok-enrollment-tests)
- [11. Kernel Selection Tests](#11-kernel-selection-tests)
- [12. Module Detection Tests](#12-module-detection-tests)
- [13. needs-rebuild Tests](#13-needs-rebuild-tests)
- [14. rebuild Tests](#14-rebuild-tests)
- [15. reinstall Tests](#15-reinstall-tests)
- [16. Module Signature Tests](#16-module-signature-tests)
- [17. VMware Service Tests](#17-vmware-service-tests)
- [18. systemd Integration Tests](#18-systemd-integration-tests)
- [19. Kernel Update Tests](#19-kernel-update-tests)
- [20. VMware Compilation Failure Tests](#20-vmware-compilation-failure-tests)
- [21. disable-systemd Tests](#21-disable-systemd-tests)
- [22. uninstall Tests](#22-uninstall-tests)
- [23. purge Tests](#23-purge-tests)
- [24. VMware-Absent Tests](#24-vmware-absent-tests)
- [25. Idempotency Tests](#25-idempotency-tests)
- [26. Regression Matrix](#26-regression-matrix)
- [27. Final Acceptance Test](#27-final-acceptance-test)
- [28. Expected Final State](#28-expected-final-state)

---

# 1. Test Goals

The test plan verifies that `vmwmanager`:

1. detects VMware Workstation correctly;
2. manages the currently running kernel;
3. generates and preserves the VMware signing key;
4. handles MOK enrollment correctly;
5. detects missing or invalid VMware modules;
6. rebuilds modules only when necessary;
7. forces compilation with `reinstall`;
8. signs `vmmon.ko` and `vmnet.ko`;
9. verifies module signatures;
10. handles VMware's `vmware-modconfig` Secure Boot behavior;
11. integrates correctly with systemd;
12. rebuilds modules after a kernel change;
13. does not silently install alternative host-module implementations;
14. safely removes manager integration;
15. remains usable for cleanup when VMware Workstation is absent;
16. preserves the original `uninstall` behavior;
17. removes the RPM only when `purge` reaches its DNF transaction.

---

# 2. Test Environment

Recommended test environment:

```text
Fedora
VMware Workstation installed
Secure Boot enabled
UEFI firmware
kernel-devel installed for running kernel
mokutil installed
systemd
```

Record the Fedora release:

```bash
cat /etc/fedora-release
```

Record the running kernel:

```bash
uname -r
```

Record the default boot kernel:

```bash
grubby --default-kernel
```

Check Secure Boot:

```bash
mokutil --sb-state
```

Check VMware:

```bash
vmware --version
```

Check VMware installer inventory:

```bash
vmware-installer -l
```

---

# 3. Safety Notes

Several tests modify:

```text
/etc/systemd/system/vmware-rebuild.service
/var/lib/shim-signed/mok/vmware.key
/var/lib/shim-signed/mok/vmware.der
```

Some MOK tests also require rebooting into the firmware-assisted MOK Manager.

Before destructive tests, consider backing up the current signing material:

```bash
sudo cp -a \
    /var/lib/shim-signed/mok \
    /var/lib/shim-signed/mok.backup
```

Do not expose or commit:

```text
vmware.key
```

to Git, GitHub, logs, issue reports, or public storage.

---

# 4. Baseline Information

Run:

```bash
uname -r
mokutil --sb-state
vmware --version
vmware-installer -l
vmwmanager status
```

Record:

```text
Fedora version:
Running kernel:
Default boot kernel:
Secure Boot:
VMware version:
MOK enrolled:
vmmon path:
vmnet path:
vmmon signer:
vmnet signer:
vmware.service:
vmware-rebuild.service:
```

The baseline should be saved before regression testing.

---

# 5. Command Availability

## TEST 5.1 — Help

Run:

```bash
vmwmanager help
```

Expected:

```text
PASS:
- help is displayed
- exit code is 0
```

Verify:

```bash
echo $?
```

Expected:

```text
0
```

---

## TEST 5.2 — Short help

Run:

```bash
vmwmanager -h
```

Expected:

```text
PASS:
help displayed
```

---

## TEST 5.3 — Long help

Run:

```bash
vmwmanager --help
```

Expected:

```text
PASS:
help displayed
```

---

## TEST 5.4 — Unknown command

Run:

```bash
vmwmanager invalid-command
echo $?
```

Expected:

```text
PASS:
- unknown-command error displayed
- help displayed
- exit code = 1
```

---

# 6. VMware Detection

## TEST 6.1 — VMware installed

Run:

```bash
vmware-installer -l
```

Expected inventory includes:

```text
vmware-workstation
```

Then:

```bash
vmwmanager status
```

Expected:

```text
VMware Workstation:
   Installed
```

PASS if VMware is detected.

---

## TEST 6.2 — Fallback detection

The script can also detect installations using:

```text
vmware
vmware-modconfig
```

Check:

```bash
command -v vmware
command -v vmware-modconfig
```

Expected:

```text
both commands exist
```

---

# 7. Status Tests

## TEST 7.1 — Normal status

Run:

```bash
vmwmanager status
```

Expected sections:

```text
VMware Workstation
Running kernel
Fedora default boot kernel
Secure Boot
Signing key files
MOK enrollment
VMware host modules
VMware service
vmwmanager systemd integration
```

PASS if all expected sections are displayed.

---

## TEST 7.2 — status exit code when healthy

Run:

```bash
vmwmanager status
echo $?
```

Expected:

```text
0
```

when all managed state is healthy.

---

## TEST 7.3 — status detects attention required

Introduce a controlled invalid state, for example by disabling the systemd integration or testing before MOK enrollment.

Run:

```bash
vmwmanager status
echo $?
```

Expected:

```text
VMware requires attention.
```

and a non-zero status when one or more required checks fail.

Restore the test environment afterward.

---

# 8. Secure Boot Tests

## TEST 8.1 — Secure Boot enabled

Run:

```bash
mokutil --sb-state
```

Expected:

```text
SecureBoot enabled
```

Then:

```bash
vmwmanager status
```

Expected:

```text
Secure Boot:
   SecureBoot enabled
```

---

## TEST 8.2 — Secure Boot state read failure

If this condition can safely be reproduced, verify that `status` reports:

```text
Unable to determine Secure Boot state.
```

The command must not silently assume Secure Boot state.

---

# 9. Signing-Key Tests

Signing directory:

```text
/var/lib/shim-signed/mok
```

Expected files:

```text
vmware.key
vmware.der
```

---

## TEST 9.1 — Generate new key

Precondition:

```text
VMware Workstation installed
vmware.key absent
vmware.der absent
```

Run:

```bash
sudo vmwmanager genkey
```

Expected:

```text
PASS:
- directory created
- vmware.key created
- vmware.der created
- enrollment checked
```

Verify:

```bash
sudo ls -l \
    /var/lib/shim-signed/mok/vmware.key \
    /var/lib/shim-signed/mok/vmware.der
```

Expected permissions:

```text
vmware.key → 600
vmware.der → 644
```

---

## TEST 9.2 — Verify certificate subject

Run:

```bash
openssl x509 \
    -inform DER \
    -in /var/lib/shim-signed/mok/vmware.der \
    -noout \
    -subject
```

Expected subject contains:

```text
CN = VMware Module Signing
```

---

## TEST 9.3 — Preserve existing key

Record checksums:

```bash
sudo sha256sum \
    /var/lib/shim-signed/mok/vmware.key \
    /var/lib/shim-signed/mok/vmware.der
```

Run:

```bash
sudo vmwmanager genkey
```

Record checksums again.

Expected:

```text
PASS:
both checksums are unchanged
```

This verifies that `genkey` does not silently regenerate an existing key.

---

## TEST 9.4 — Private key exists, certificate missing

Backup:

```bash
sudo cp \
    /var/lib/shim-signed/mok/vmware.der \
    /var/lib/shim-signed/mok/vmware.der.test
```

Remove certificate:

```bash
sudo rm \
    /var/lib/shim-signed/mok/vmware.der
```

Run:

```bash
sudo vmwmanager genkey
echo $?
```

Expected:

```text
PASS:
- incomplete key state detected
- certificate is NOT regenerated automatically
- exit code = 1
```

Restore:

```bash
sudo mv \
    /var/lib/shim-signed/mok/vmware.der.test \
    /var/lib/shim-signed/mok/vmware.der
```

---

## TEST 9.5 — Certificate exists, private key missing

Backup:

```bash
sudo cp \
    /var/lib/shim-signed/mok/vmware.key \
    /var/lib/shim-signed/mok/vmware.key.test
```

Remove private key:

```bash
sudo rm \
    /var/lib/shim-signed/mok/vmware.key
```

Run:

```bash
sudo vmwmanager genkey
echo $?
```

Expected:

```text
PASS:
- incomplete key state detected
- private key is NOT regenerated automatically
- exit code = 1
```

Restore:

```bash
sudo mv \
    /var/lib/shim-signed/mok/vmware.key.test \
    /var/lib/shim-signed/mok/vmware.key
```

---

# 10. MOK Enrollment Tests

## TEST 10.1 — Enrolled certificate

Run:

```bash
sudo mokutil --test-key \
    /var/lib/shim-signed/mok/vmware.der
```

Expected:

```text
is already enrolled
```

Then:

```bash
vmwmanager status
```

Expected:

```text
Signing certificate is enrolled.
```

---

## TEST 10.2 — Existing key but certificate not enrolled

Precondition:

```text
vmware.key exists
vmware.der exists
certificate is not enrolled
```

Run:

```bash
sudo vmwmanager genkey
```

Expected:

```text
PASS:
- existing key preserved
- no new key generated
- mokutil --import is requested
```

Check:

```bash
sudo mokutil --list-new
```

Expected pending certificate.

Complete enrollment after reboot.

---

## TEST 10.3 — Confirm enrolled certificate after reboot

After MOK Manager enrollment:

```bash
sudo mokutil --test-key \
    /var/lib/shim-signed/mok/vmware.der
```

Expected:

```text
is already enrolled
```

---

# 11. Kernel Selection Tests

## TEST 11.1 — Running kernel

Run:

```bash
uname -r
```

Then:

```bash
vmwmanager status
```

Expected:

```text
Running kernel:
   <same value as uname -r>
```

---

## TEST 11.2 — Default boot kernel

Run:

```bash
grubby --default-kernel
```

Then:

```bash
vmwmanager status
```

Expected:

```text
Fedora default boot kernel:
```

with the corresponding kernel version.

---

## TEST 11.3 — Running kernel differs from default

Boot an older installed kernel while keeping a newer kernel configured as default.

Run:

```bash
uname -r
grubby --default-kernel
vmwmanager status
```

Expected:

```text
The default boot kernel is not the running kernel.
VMware native modules are managed for the running kernel.
```

PASS if `vmwmanager` continues targeting `uname -r`.

---

# 12. Module Detection Tests

## TEST 12.1 — vmmon exists

Run:

```bash
modinfo -n vmmon
```

Expected existing file.

---

## TEST 12.2 — vmnet exists

Run:

```bash
modinfo -n vmnet
```

Expected existing file.

---

## TEST 12.3 — Correct kernel lookup

Run:

```bash
KVER="$(uname -r)"

modinfo -k "$KVER" -n vmmon
modinfo -k "$KVER" -n vmnet
```

Both paths must belong to the running kernel's module tree.

---

# 13. needs-rebuild Tests

This command has special exit-code semantics:

```text
0 = rebuild required
1 = rebuild not required
```

---

## TEST 13.1 — Both modules valid

Precondition:

```text
vmmon exists and correctly signed
vmnet exists and correctly signed
```

Run:

```bash
vmwmanager needs-rebuild
rc=$?
echo "$rc"
```

Expected:

```text
1
```

Expected output:

```text
vmmon.ko and vmnet.ko are correctly installed and signed.
Nothing to rebuild.
```

PASS if exit code is exactly `1`.

---

## TEST 13.2 — Missing vmmon

Controlled test:

temporarily move the current `vmmon.ko` out of its normal location.

Run:

```bash
vmwmanager needs-rebuild
echo $?
```

Expected:

```text
0
```

Expected message:

```text
vmmon.ko does not exist
Rebuild required
```

Restore the module afterward.

---

## TEST 13.3 — Missing vmnet

Repeat for `vmnet.ko`.

Expected:

```text
exit 0
```

---

## TEST 13.4 — Both modules missing

Expected:

```text
exit 0
```

because rebuild is required.

---

## TEST 13.5 — Unsigned module

Use a controlled test environment.

Expected:

```text
Module is unsigned.
Rebuild/sign required.
```

Exit:

```text
0
```

---

## TEST 13.6 — Wrong signer

Test with a module signed by a different certificate.

Expected:

```text
Module is not signed with the expected certificate.
```

Expected signer:

```text
VMware Module Signing
```

Exit:

```text
0
```

---

## TEST 13.7 — Modules valid but MOK not enrolled

Precondition:

```text
vmmon correctly signed
vmnet correctly signed
certificate not enrolled
```

Run:

```bash
vmwmanager needs-rebuild
echo $?
```

Expected:

```text
modules already correctly built and signed
rebuilding would not fix trust problem
```

Exit:

```text
1
```

This is an important regression test.

---

## TEST 13.8 — VMware not installed

Run:

```bash
vmwmanager needs-rebuild
echo $?
```

Expected:

```text
VMware Workstation is not installed.
Rebuild cannot be performed.
```

Exit:

```text
1
```

---

# 14. rebuild Tests

## TEST 14.1 — Valid modules: no rebuild

Precondition:

```text
vmmon valid
vmnet valid
```

Record timestamps:

```bash
stat "$(modinfo -n vmmon)"
stat "$(modinfo -n vmnet)"
```

Run:

```bash
sudo vmwmanager rebuild
```

Expected:

```text
Nothing to rebuild.
```

The module files should not be rebuilt.

---

## TEST 14.2 — Missing module triggers rebuild

Controlled test environment.

Make one managed module unavailable.

Run:

```bash
sudo vmwmanager rebuild
```

Expected workflow:

```text
vmware-modconfig
build both modules
sign both modules
depmod
verify
restart vmware.service
```

Expected final exit code:

```text
0
```

---

## TEST 14.3 — Invalid signature triggers rebuild

Precondition:

one module has an invalid signer.

Run:

```bash
sudo vmwmanager rebuild
```

Expected:

```text
rebuild and sign
```

Final signer:

```text
VMware Module Signing
```

---

## TEST 14.4 — Missing signing key

Temporarily make the signing-key files unavailable.

Run:

```bash
sudo vmwmanager rebuild
echo $?
```

Expected:

```text
VMware signing keys are not available.
Run first:
sudo /usr/bin/vmwmanager genkey
```

Exit:

```text
1
```

Restore the key files.

---

# 15. reinstall Tests

## TEST 15.1 — Force rebuild when modules already valid

Precondition:

```text
vmmon valid
vmnet valid
```

Record timestamps:

```bash
stat "$(modinfo -n vmmon)"
stat "$(modinfo -n vmnet)"
```

Run:

```bash
sudo vmwmanager reinstall
```

Expected:

```text
VMware native compilation runs anyway.
```

Both module files should have fresh modification times.

---

## TEST 15.2 — Verify signatures after reinstall

Run:

```bash
modinfo -F signer vmmon
modinfo -F signer vmnet
```

Expected:

```text
VMware Module Signing
```

---

## TEST 15.3 — VMware service after reinstall

Run:

```bash
systemctl is-active vmware.service
```

Expected:

```text
active
```

---

# 16. Module Signature Tests

## TEST 16.1 — vmmon signer

Run:

```bash
modinfo -F signer vmmon
```

Expected:

```text
VMware Module Signing
```

---

## TEST 16.2 — vmnet signer

Run:

```bash
modinfo -F signer vmnet
```

Expected:

```text
VMware Module Signing
```

---

## TEST 16.3 — Both modules verified together

Run:

```bash
for module in vmmon vmnet; do
    printf '%-8s %s\n' \
        "$module" \
        "$(modinfo -F signer "$module")"
done
```

Expected both signers contain:

```text
VMware Module Signing
```

---

# 17. VMware Service Tests

## TEST 17.1 — Service exists

Run:

```bash
systemctl show vmware.service -p LoadState --value
```

Expected:

```text
loaded
```

---

## TEST 17.2 — Service status

Run:

```bash
systemctl status vmware.service
```

Expected active state after a successful rebuild/reinstall.

---

## TEST 17.3 — vmwmanager status reports VMware service

Run:

```bash
vmwmanager status
```

Expected fields:

```text
Load
Enabled
Active
Sub
Result
```

---

# 18. systemd Integration Tests

## TEST 18.1 — Enable integration

Start clean:

```bash
sudo vmwmanager disable-systemd
```

Then:

```bash
sudo vmwmanager enable-systemd
```

Expected:

```text
/etc/systemd/system/vmware-rebuild.service
```

exists.

---

## TEST 18.2 — Verify generated unit

Run:

```bash
cat /etc/systemd/system/vmware-rebuild.service
```

Expected:

```ini
[Unit]
Description=Ensure VMware host modules are available and signed
Documentation=https://github.com/mkubecek/vmware-host-modules
Wants=vmware.service
After=local-fs.target vmware.service
ConditionPathExists=/usr/bin/vmwmanager

[Service]
Type=oneshot
ExecCondition=/usr/bin/vmwmanager needs-rebuild
ExecStart=/usr/bin/vmwmanager rebuild

[Install]
WantedBy=multi-user.target
```

---

## TEST 18.3 — Service enabled

Run:

```bash
systemctl is-enabled vmware-rebuild.service
```

Expected:

```text
enabled
```

---

## TEST 18.4 — Immediate start

`enable-systemd` performs:

```text
systemctl start vmware-rebuild.service
```

Check:

```bash
journalctl -u vmware-rebuild.service -n 50
```

Expected an immediate module check.

---

## TEST 18.5 — Existing unit is not overwritten

Record checksum:

```bash
sudo sha256sum \
    /etc/systemd/system/vmware-rebuild.service
```

Run:

```bash
sudo vmwmanager enable-systemd
```

Compare checksum.

Expected:

```text
unchanged
```

when the service already exists.

---

## TEST 18.6 — ExecCondition with valid modules

Precondition:

```text
vmmon valid
vmnet valid
```

Run:

```bash
sudo systemctl start vmware-rebuild.service
```

Inspect:

```bash
systemctl status vmware-rebuild.service
```

Expected behavior:

```text
ExecCondition returns 1
ExecStart skipped
service not treated as failed
```

Check logs:

```bash
journalctl -u vmware-rebuild.service -n 50
```

---

## TEST 18.7 — ExecCondition with rebuild required

Precondition:

one managed module is missing or incorrectly signed.

Run:

```bash
sudo systemctl start vmware-rebuild.service
```

Expected:

```text
ExecCondition returns 0
ExecStart executes
modules rebuilt
modules signed
VMware service restarted
```

---

## TEST 18.8 — Verify dependency

Run:

```bash
systemctl show \
    vmware-rebuild.service \
    -p Wants \
    -p After
```

Expected to include:

```text
vmware.service
```

---

# 19. Kernel Update Tests

This is one of the most important end-to-end regression tests.

## TEST 19.1 — Install new kernel

Run normal Fedora update:

```bash
sudo dnf upgrade
```

Verify installed kernels:

```bash
rpm -q kernel-core
```

Do not expect `vmwmanager` to manage the newly installed kernel before booting it.

---

## TEST 19.2 — Before reboot

Run:

```bash
uname -r
vmwmanager status
```

Expected:

```text
vmwmanager still manages the currently running kernel.
```

---

## TEST 19.3 — Reboot new kernel

Reboot:

```bash
sudo reboot
```

After boot:

```bash
uname -r
```

Verify the new kernel is now running.

---

## TEST 19.4 — Automatic rebuild after kernel change

Run:

```bash
journalctl -b -u vmware-rebuild.service
```

If VMware modules were absent for the new kernel, expected:

```text
needs-rebuild → 0
rebuild executed
vmmon built
vmnet built
modules signed
verification successful
vmware.service restarted
```

---

## TEST 19.5 — Verify modules for new kernel

Run:

```bash
KVER="$(uname -r)"

modinfo -k "$KVER" -n vmmon
modinfo -k "$KVER" -n vmnet

modinfo -k "$KVER" -F signer vmmon
modinfo -k "$KVER" -F signer vmnet
```

Expected signer:

```text
VMware Module Signing
```

---

# 20. VMware Compilation Failure Tests

## TEST 20.1 — Non-zero vmware-modconfig but modules rebuilt

This reproduces the Secure Boot edge case.

Expected situation:

```text
vmware-modconfig returns non-zero
but
vmmon and vmnet were freshly rebuilt
```

Expected `vmwmanager` behavior:

```text
PASS:
- reports non-zero vmware-modconfig result
- recognizes both modules were rebuilt
- continues signing
- verifies signatures
- restarts VMware service
```

The operation should succeed if both module files were genuinely produced.

---

## TEST 20.2 — Non-zero vmware-modconfig with no fresh modules

Expected:

```text
PASS:
- compilation considered failed
- no stale module accepted as fresh build
- signing does not continue
- alternative module project may be mentioned
- no fallback automatically installed
```

Exit:

```text
1
```

---

## TEST 20.3 — One module rebuilt, one stale

Expected:

```text
build failure
```

Both modules must have been rebuilt by the current invocation.

---

# 21. disable-systemd Tests

## TEST 21.1 — Disable enabled integration

Precondition:

```text
vmware-rebuild.service enabled
```

Run:

```bash
sudo vmwmanager disable-systemd
```

Expected:

```text
service disabled
unit removed
daemon-reload executed
```

Verify:

```bash
systemctl is-enabled vmware-rebuild.service
```

Expected non-zero / not found.

Verify:

```bash
test ! -e \
    /etc/systemd/system/vmware-rebuild.service
```

Expected:

```text
success
```

---

## TEST 21.2 — Disable when already disabled

Run twice:

```bash
sudo vmwmanager disable-systemd
sudo vmwmanager disable-systemd
```

Expected second run:

```text
No systemd changes were required.
```

No failure.

---

## TEST 21.3 — Clear failed state

If the unit can safely be put into a failed state, run:

```bash
sudo vmwmanager disable-systemd
```

Expected:

```text
failed state cleared
```

---

# 22. uninstall Tests

## TEST 22.1 — Preserve MOK and key

Run:

```bash
sudo vmwmanager uninstall
```

Answer:

```text
N
```

to MOK deletion.

Answer:

```text
N
```

to local-key deletion.

Expected:

```text
systemd integration removed
MOK preserved
local signing keys preserved
VMware Workstation preserved
```

---

## TEST 22.2 — Remove local keys

Run uninstall and confirm local-key removal.

Expected:

```text
/var/lib/shim-signed/mok/vmware.key removed
/var/lib/shim-signed/mok/vmware.der removed
```

Restore test environment afterward if additional tests remain.

---

## TEST 22.3 — Stage MOK deletion

Run:

```bash
sudo vmwmanager uninstall
```

Confirm MOK deletion.

Expected:

```text
mokutil --delete invoked
MOK deletion scheduled
```

Complete `Delete MOK` during reboot if testing the full lifecycle.

---

## TEST 22.4 — VMware Workstation remains installed

After:

```bash
sudo vmwmanager uninstall
```

check:

```bash
vmware-installer -l
```

Expected VMware Workstation still present.

---

## TEST 22.5 — VMware modules not manually removed

Verify VMware-managed files were not explicitly deleted by `vmwmanager uninstall`.

---

# 23. purge Tests

These tests verify that `purge` is additive and that `uninstall` keeps its original behavior.

---

## TEST 23.1 — uninstall still leaves the RPM installed

Run:

```bash
sudo vmwmanager uninstall
rpm -q vmware-manager
```

Expected:

```text
PASS:
- integration cleanup is offered/performed
- vmware-manager RPM remains installed
```

---

## TEST 23.2 — purge starts RPM removal

Run:

```bash
sudo vmwmanager purge
```

After integration resources are processed, expected output includes:

```text
============================================================
 Local vmware-manager resources have been processed.

 The vmware-manager RPM will now be removed.
 DNF will ask for final transaction confirmation.
============================================================
```

DNF must then present the `vmware-manager` removal transaction.

---

## TEST 23.3 — cancel purge DNF transaction

At the final DNF confirmation, answer `N`.

Expected:

```text
PASS:
- local vmwmanager resources were already processed
- vmware-manager RPM remains installed
- purge returns non-zero because package removal was cancelled
```

Verify:

```bash
rpm -q vmware-manager
```

---

## TEST 23.4 — confirm purge DNF transaction

Reinstall/restore the test state as required, then run:

```bash
sudo vmwmanager purge
```

Confirm the DNF transaction.

Expected:

```text
PASS:
- vmware-manager RPM is removed
- /usr/bin/vmwmanager is removed with the RPM
- VMware Workstation remains installed
- vmmon.ko and vmnet.ko are not manually deleted by vmwmanager
```

Verify:

```bash
rpm -q vmware-manager
command -v vmwmanager
vmware-installer -l
```

---

# 24. VMware-Absent Tests

These tests verify that cleanup remains possible after VMware Workstation has already been removed.

---

## TEST 24.1 — status without VMware

With VMware absent:

```bash
vmwmanager status
```

Expected:

```text
VMware Workstation:
   Not installed
```

The command should continue displaying other available diagnostics.

---

## TEST 24.2 — disable-systemd without VMware

Run:

```bash
sudo vmwmanager disable-systemd
```

Expected:

```text
PASS
```

VMware installation is not required.

---

## TEST 24.3 — uninstall without VMware

Run:

```bash
sudo vmwmanager uninstall
```

Expected:

```text
PASS:
- systemd cleanup available
- MOK cleanup available
- local-key cleanup available
- no VMware uninstall attempted
```

---

## TEST 24.4 — rebuild without VMware

Run:

```bash
sudo vmwmanager rebuild
echo $?
```

Expected:

```text
VMware Workstation is not installed.
```

Exit:

```text
1
```

---

## TEST 24.5 — enable-systemd without VMware

Run:

```bash
sudo vmwmanager enable-systemd
echo $?
```

Expected:

```text
VMware Workstation is not installed.
vmwmanager systemd integration will not be enabled.
```

Exit:

```text
1
```

---

# 25. Idempotency Tests

## TEST 25.1 — genkey twice

Run:

```bash
sudo vmwmanager genkey
sudo vmwmanager genkey
```

Expected:

```text
existing key preserved
```

---

## TEST 25.2 — rebuild twice

Run:

```bash
sudo vmwmanager rebuild
sudo vmwmanager rebuild
```

Expected second run:

```text
Nothing to rebuild.
```

---

## TEST 25.3 — enable-systemd twice

Run:

```bash
sudo vmwmanager enable-systemd
sudo vmwmanager enable-systemd
```

Expected second run:

```text
existing service preserved
service already enabled
```

---

## TEST 25.4 — disable-systemd twice

Run:

```bash
sudo vmwmanager disable-systemd
sudo vmwmanager disable-systemd
```

Expected second run:

```text
already disabled
service file does not exist
no systemd changes required
```

---

# 26. Regression Matrix

Use the following matrix before each release.

| Test | State | Expected |
|---|---|---|
| VMware installed | Yes | detected |
| VMware installed | No | safe diagnostics/cleanup |
| Secure Boot | Enabled | detected |
| Key pair | Missing | `genkey` creates |
| Key pair | Complete | preserved |
| Key pair | Private only | fail safely |
| Key pair | DER only | fail safely |
| MOK | Enrolled | valid |
| MOK | Not enrolled | re-enrollment requested |
| vmmon | Missing | `needs-rebuild=0` |
| vmnet | Missing | `needs-rebuild=0` |
| vmmon | Unsigned | `needs-rebuild=0` |
| vmnet | Unsigned | `needs-rebuild=0` |
| Module signer | Wrong | `needs-rebuild=0` |
| Both modules | Valid | `needs-rebuild=1` |
| Modules valid + MOK absent | Yes | no rebuild |
| rebuild | Modules valid | skipped |
| rebuild | Module invalid | executed |
| reinstall | Modules valid | forced |
| vmware-modconfig | rc=0 | continue |
| vmware-modconfig | rc!=0 + fresh modules | continue |
| vmware-modconfig | rc!=0 + stale/missing modules | fail |
| systemd unit | Missing | created |
| systemd unit | Existing | not overwritten |
| systemd | Valid modules | ExecStart skipped |
| systemd | Invalid modules | ExecStart runs |
| disable-systemd | First run | disable/remove |
| disable-systemd | Second run | idempotent |
| uninstall | VMware installed | VMware preserved |
| uninstall | VMware absent | safe |
| purge | DNF cancelled | RPM remains installed |
| purge | DNF confirmed | RPM removed, VMware preserved |
| New kernel | Before reboot | old running kernel managed |
| New kernel | After reboot | new running kernel managed |

---

# 27. Final Acceptance Test

Before publishing a release, perform the following sequence on a Fedora Secure Boot system.

## Step 1

```bash
vmwmanager status
```

---

## Step 2

```bash
sudo vmwmanager genkey
```

Confirm the key is preserved if already present.

---

## Step 3

```bash
sudo mokutil --test-key \
    /var/lib/shim-signed/mok/vmware.der
```

Expected:

```text
already enrolled
```

---

## Step 4

```bash
sudo vmwmanager reinstall
```

Expected:

```text
compilation
signing
verification
VMware service restart
```

---

## Step 5

Verify signatures:

```bash
modinfo -F signer vmmon
modinfo -F signer vmnet
```

Expected:

```text
VMware Module Signing
```

---

## Step 6

Verify conditional behavior:

```bash
vmwmanager needs-rebuild
echo $?
```

Expected:

```text
1
```

---

## Step 7

Enable integration:

```bash
sudo vmwmanager enable-systemd
```

---

## Step 8

Verify:

```bash
systemctl is-enabled vmware-rebuild.service
```

Expected:

```text
enabled
```

---

## Step 9

Run service manually:

```bash
sudo systemctl start vmware-rebuild.service
```

Expected:

```text
ExecCondition skips rebuild because modules are valid
```

---

## Step 10

Inspect logs:

```bash
journalctl -u vmware-rebuild.service -n 100
```

No unexpected failure should appear.

---

## Step 11

Reboot:

```bash
sudo reboot
```

---

## Step 12

After reboot:

```bash
vmwmanager status
```

Expected final message:

```text
VMware signing state is ready.
```

---

## Step 13

Verify VMware functionality.

Start VMware Workstation and confirm that a virtual machine can power on normally.

---

# 28. Expected Final State

A release candidate passes when the machine reaches:

```text
VMware Workstation
        ✅ installed

Running kernel
        ✅ detected

Secure Boot
        ✅ detected

VMware signing key
        ✅ present

VMware MOK
        ✅ enrolled

vmmon.ko
        ✅ present
        ✅ signed
        ✅ correct signer

vmnet.ko
        ✅ present
        ✅ signed
        ✅ correct signer

vmware.service
        ✅ operational

vmware-rebuild.service
        ✅ enabled

needs-rebuild
        ✅ returns 1 when modules are healthy

Kernel update
        ✅ rebuild occurs after booting a kernel
           whose VMware modules are missing

vmwmanager uninstall
        ✅ keeps its original cleanup-only behavior
        ✅ does not remove the vmware-manager RPM
        ✅ does not uninstall VMware Workstation

vmwmanager purge
        ✅ processes local integration cleanup
        ✅ removes the vmware-manager RPM through DNF when confirmed
        ✅ does not uninstall VMware Workstation

Alternative module fallback
        ✅ never installed automatically
```

The release is considered ready only when the applicable tests pass without introducing regressions.