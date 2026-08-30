# vmware-manager FAQ

Frequently Asked Questions about `vmware-manager`, VMware Workstation host modules, Secure Boot, MOK enrollment, kernel updates, and systemd integration on Fedora.

---

## Table of Contents

- [General](#general)
  - [What is vmware-manager?](#what-is-vmware-manager)
  - [Which VMware modules are managed?](#which-vmware-modules-are-managed)
  - [Does vmware-manager install VMware Workstation?](#does-vmware-manager-install-vmware-workstation)
  - [Does vmware-manager install alternative VMware host modules?](#does-vmware-manager-install-alternative-vmware-host-modules)
- [Secure Boot and MOK](#secure-boot-and-mok)
  - [Why must the VMware modules be signed?](#why-must-the-vmware-modules-be-signed)
  - [Where are the signing keys stored?](#where-are-the-signing-keys-stored)
  - [What certificate does vmware-manager use?](#what-certificate-does-vmware-manager-use)
  - [What does genkey do?](#what-does-genkey-do)
  - [Does genkey replace an existing key?](#does-genkey-replace-an-existing-key)
  - [What happens if only one signing-key file exists?](#what-happens-if-only-one-signing-key-file-exists)
  - [What happens if the certificate is no longer enrolled?](#what-happens-if-the-certificate-is-no-longer-enrolled)
  - [How can I check MOK enrollment?](#how-can-i-check-mok-enrollment)
  - [How can I check pending enrollment?](#how-can-i-check-pending-enrollment)
- [Kernels](#kernels)
  - [Which kernel does vmwmanager manage?](#which-kernel-does-vmwmanager-manage)
  - [Why does it use the running kernel instead of the newest installed kernel?](#why-does-it-use-the-running-kernel-instead-of-the-newest-installed-kernel)
  - [What if the default boot kernel differs from the running kernel?](#what-if-the-default-boot-kernel-differs-from-the-running-kernel)
  - [What happens after a Fedora kernel update?](#what-happens-after-a-fedora-kernel-update)
  - [Why do I need kernel-devel for the running kernel?](#why-do-i-need-kernel-devel-for-the-running-kernel)
- [Building and Signing](#building-and-signing)
  - [What is the difference between rebuild and reinstall?](#what-is-the-difference-between-rebuild-and-reinstall)
  - [What does rebuild actually do?](#what-does-rebuild-actually-do)
  - [What does reinstall do?](#what-does-reinstall-do)
  - [Why can vmware-modconfig fail even though the modules were built?](#why-can-vmware-modconfig-fail-even-though-the-modules-were-built)
  - [How does vmwmanager determine whether compilation really succeeded?](#how-does-vmwmanager-determine-whether-compilation-really-succeeded)
  - [What happens if VMware native compilation really fails?](#what-happens-if-vmware-native-compilation-really-fails)
- [needs-rebuild](#needs-rebuild)
  - [What does needs-rebuild do?](#what-does-needs-rebuild-do)
  - [Why does needs-rebuild return 0 when something is wrong?](#why-does-needs-rebuild-return-0-when-something-is-wrong)
  - [Does exit status 1 mean failure?](#does-exit-status-1-mean-failure)
  - [What happens if the modules are signed but the MOK is not enrolled?](#what-happens-if-the-modules-are-signed-but-the-mok-is-not-enrolled)
- [systemd](#systemd)
  - [What is vmware-rebuild.service?](#what-is-vmware-rebuildservice)
  - [Where is the service installed?](#where-is-the-service-installed)
  - [Does the RPM own vmware-rebuild.service?](#does-the-rpm-own-vmware-rebuildservice)
  - [Why does the service use Wants=vmware.service?](#why-does-the-service-use-wantsvmwareservice)
  - [Why not Requires=vmware.service?](#why-not-requiresvmwareservice)
  - [What happens at boot?](#what-happens-at-boot)
  - [Does enable-systemd immediately run the check?](#does-enable-systemd-immediately-run-the-check)
  - [What does disable-systemd remove?](#what-does-disable-systemd-remove)
- [Status and Troubleshooting](#status-and-troubleshooting)
  - [What does status check?](#what-does-status-check)
  - [How do I check the module signer manually?](#how-do-i-check-the-module-signer-manually)
  - [How do I check whether vmmon and vmnet are loaded?](#how-do-i-check-whether-vmmon-and-vmnet-are-loaded)
  - [How do I inspect systemd logs?](#how-do-i-inspect-systemd-logs)
- [Uninstallation](#uninstallation)
  - [Does vmwmanager uninstall VMware Workstation?](#does-vmwmanager-uninstall-vmware-workstation)
  - [What does vmwmanager uninstall remove?](#what-does-vmwmanager-uninstall-remove)
  - [Does uninstall automatically delete the MOK?](#does-uninstall-automatically-delete-the-mok)
  - [Does uninstall delete vmmon.ko and vmnet.ko?](#does-uninstall-delete-vmmonko-and-vmnetko)
  - [How do I completely remove VMware Workstation?](#how-do-i-completely-remove-vmware-workstation)

---

# General

## What is vmware-manager?

`vmware-manager` is a Fedora-oriented management utility for VMware Workstation host kernel modules.

It installs the command:

```text
/usr/bin/vmwmanager
```

The manager handles building, signing, verifying, reinstalling and maintaining VMware's host modules when Secure Boot is in use.

---

## Which VMware modules are managed?

Two modules:

```text
vmmon.ko
vmnet.ko
```

These are the VMware Workstation host kernel modules managed by `vmwmanager`.

---

## Does vmware-manager install VMware Workstation?

No.

VMware Workstation must already be installed separately.

Operations such as:

```text
genkey
needs-rebuild
rebuild
reinstall
enable-systemd
```

require VMware Workstation.

Other operations including:

```text
status
disable-systemd
uninstall
```

are designed to remain usable when VMware Workstation is absent.

---

## Does vmware-manager install alternative VMware host modules?

No.

`vmwmanager` deliberately does not automatically download, patch, compile or install an alternative host-module implementation.

It uses VMware's native:

```bash
vmware-modconfig --console --install-all
```

If native compilation fails, the manager may display the upstream `vmware-host-modules` project as information, but no fallback is performed automatically.

---

# Secure Boot and MOK

## Why must the VMware modules be signed?

When Secure Boot policy requires trusted kernel modules, locally compiled VMware modules need a trusted signature before they can be accepted by the kernel.

`vmwmanager` therefore signs VMware's `vmmon.ko` and `vmnet.ko` using a dedicated local key and certificate.

---

## Where are the signing keys stored?

Under:

```text
/var/lib/shim-signed/mok/
```

Specifically:

```text
/var/lib/shim-signed/mok/vmware.key
/var/lib/shim-signed/mok/vmware.der
```

The private key is created with mode:

```text
0600
```

The DER certificate is created with mode:

```text
0644
```

---

## What certificate does vmware-manager use?

The certificate generated by `vmwmanager` has the common name:

```text
CN=VMware Module Signing
```

The module-signature checks expect the signer to contain:

```text
VMware Module Signing
```

---

## What does genkey do?

Run:

```bash
sudo vmwmanager genkey
```

If no key exists, the command generates the private key and DER certificate.

It then checks whether the certificate is already enrolled.

If it is not enrolled, the manager requests enrollment using:

```bash
mokutil --import /var/lib/shim-signed/mok/vmware.der
```

You create a temporary password and complete the enrollment manually from MOK Manager during the next reboot.

---

## Does genkey replace an existing key?

No.

If both:

```text
vmware.key
vmware.der
```

already exist, the existing key pair is preserved.

This is intentional because replacing the private key would also change the identity used to sign the VMware modules.

---

## What happens if only one signing-key file exists?

`vmwmanager` considers this an inconsistent state.

For example:

```text
vmware.key → exists
vmware.der → missing
```

or:

```text
vmware.key → missing
vmware.der → exists
```

The manager refuses to silently generate a replacement pair.

The inconsistent state must be investigated explicitly.

---

## What happens if the certificate is no longer enrolled?

Run:

```bash
sudo vmwmanager genkey
```

If the existing key pair is complete, `genkey` preserves it.

It then requests enrollment of the **existing** certificate instead of generating a new one.

Afterward reboot:

```bash
sudo reboot
```

and complete MOK enrollment.

---

## How can I check MOK enrollment?

Use:

```bash
sudo mokutil --test-key \
    /var/lib/shim-signed/mok/vmware.der
```

`vmwmanager status` also performs this check.

---

## How can I check pending enrollment?

Use:

```bash
sudo mokutil --list-new
```

If the certificate has just been submitted with `genkey`, it remains pending until MOK Manager enrollment is completed during reboot.

---

# Kernels

## Which kernel does vmwmanager manage?

The currently running kernel:

```bash
uname -r
```

This is an intentional design choice.

---

## Why does it use the running kernel instead of the newest installed kernel?

Because VMware's native:

```bash
vmware-modconfig --console --install-all
```

builds VMware host modules for the running kernel.

Therefore `vmwmanager` deliberately follows the same model.

---

## What if the default boot kernel differs from the running kernel?

`vmwmanager status` attempts to determine Fedora's default boot kernel using:

```bash
grubby --default-kernel
```

If it differs from:

```bash
uname -r
```

the difference is reported.

This is informational.

`vmwmanager` still manages modules for the running kernel.

---

## What happens after a Fedora kernel update?

Installing a new kernel does not change the kernel currently running.

After reboot, the new kernel becomes the running kernel if Fedora boots it.

If `vmware-rebuild.service` is enabled, it then executes:

```text
vmwmanager needs-rebuild
```

for that running kernel.

If `vmmon.ko` or `vmnet.ko` is missing or incorrectly signed, a rebuild is requested.

---

## Why do I need kernel-devel for the running kernel?

Module signing uses:

```text
/usr/src/kernels/<kernel>/scripts/sign-file
```

Therefore the corresponding `kernel-devel` package must be available.

Check:

```bash
uname -r
```

and, if required:

```bash
sudo dnf install "kernel-devel-$(uname -r)"
```

---

# Building and Signing

## What is the difference between rebuild and reinstall?

The main difference is whether compilation is conditional.

### rebuild

```bash
sudo vmwmanager rebuild
```

checks first.

If both modules already exist and are correctly signed, nothing is rebuilt.

### reinstall

```bash
sudo vmwmanager reinstall
```

forces VMware's native module compilation even if the existing modules are already valid.

Therefore:

```text
rebuild
   │
   └── build only when required

reinstall
   │
   └── always force native compilation
```

For normal maintenance, use `rebuild`.

---

## What does rebuild actually do?

When rebuilding is necessary:

```text
check modules
      ↓
vmware-modconfig
      ↓
verify fresh module files
      ↓
sign vmmon.ko
      ↓
sign vmnet.ko
      ↓
depmod
      ↓
verify signatures
      ↓
restart vmware.service
```

---

## What does reinstall do?

`reinstall` skips the initial decision about whether rebuilding is necessary.

It forces:

```bash
vmware-modconfig --console --install-all
```

and then performs signing, verification and VMware service restart.

---

## Why can vmware-modconfig fail even though the modules were built?

With Secure Boot, VMware may:

1. successfully compile `vmmon.ko`;
2. successfully compile `vmnet.ko`;
3. install both modules;
4. attempt to start `vmware.service`;
5. fail because the newly compiled modules have not yet been signed.

Consequently:

```text
vmware-modconfig exit != 0
```

does not necessarily mean:

```text
module compilation failed
```

`vmwmanager` accounts for this behavior.

---

## How does vmwmanager determine whether compilation really succeeded?

Before invoking `vmware-modconfig`, the manager creates a temporary build marker.

After the command completes, it locates both modules and verifies that:

```text
vmmon.ko
vmnet.ko
```

were actually rebuilt after that marker was created.

Therefore stale modules from a previous build are not accepted as evidence that the current compilation succeeded.

---

## What happens if VMware native compilation really fails?

The operation stops.

`vmwmanager` does not automatically switch to another source tree.

It may mention:

```text
https://github.com/mkubecek/vmware-host-modules
```

as an alternative project to investigate.

Choosing and installing an alternative implementation remains a manual user decision.

---

# needs-rebuild

## What does needs-rebuild do?

Run:

```bash
vmwmanager needs-rebuild
```

It examines `vmmon.ko` and `vmnet.ko` for the running kernel.

For each module it checks:

```text
exists?
   │
signed?
   │
signed by expected certificate?
```

---

## Why does needs-rebuild return 0 when something is wrong?

Because the command was designed specifically for systemd:

```ini
ExecCondition=/usr/bin/vmwmanager needs-rebuild
```

For `ExecCondition`, success means that `ExecStart` should execute.

Therefore:

```text
module requires rebuilding
        ↓
needs-rebuild returns 0
        ↓
ExecCondition succeeds
        ↓
ExecStart runs
        ↓
vmwmanager rebuild
```

---

## Does exit status 1 mean failure?

Not in the normal `needs-rebuild` case.

Its intentional semantics are:

```text
0 = rebuild required
1 = nothing to rebuild
```

If VMware Workstation is not installed, it also returns `1` because rebuilding cannot be performed.

This allows systemd to skip `ExecStart`.

---

## What happens if the modules are signed but the MOK is not enrolled?

The modules themselves do not require rebuilding.

Re-signing them with the same certificate would not fix the trust problem.

Therefore `needs-rebuild` returns `1` and instructs you to re-enroll the certificate.

Run:

```bash
sudo vmwmanager genkey
```

then reboot and complete MOK enrollment.

---

# systemd

## What is vmware-rebuild.service?

It is an optional `oneshot` systemd service created by:

```bash
sudo vmwmanager enable-systemd
```

Its purpose is to check whether the VMware modules for the running kernel need rebuilding.

---

## Where is the service installed?

At:

```text
/etc/systemd/system/vmware-rebuild.service
```

---

## Does the RPM own vmware-rebuild.service?

No.

With the current design, `vmwmanager` dynamically creates the service when:

```bash
sudo vmwmanager enable-systemd
```

is executed.

Likewise, `disable-systemd` removes it.

---

## Why does the service use Wants=vmware.service?

The generated unit contains:

```ini
Wants=vmware.service
After=local-fs.target vmware.service
```

`Wants=` establishes a weak dependency on VMware's service.

`After=` establishes startup ordering.

---

## Why not Requires=vmware.service?

The design intentionally avoids making `vmware.service` a hard requirement of `vmware-rebuild.service`.

The unit therefore uses:

```ini
Wants=vmware.service
```

rather than:

```ini
Requires=vmware.service
```

---

## What happens at boot?

systemd evaluates:

```ini
ExecCondition=/usr/bin/vmwmanager needs-rebuild
```

If modules require rebuilding:

```text
needs-rebuild → 0
        ↓
ExecStart executes
        ↓
vmwmanager rebuild
```

If both modules are valid:

```text
needs-rebuild → 1
        ↓
ExecStart skipped
```

---

## Does enable-systemd immediately run the check?

Yes.

After creating and enabling the unit, `vmwmanager` starts:

```text
vmware-rebuild.service
```

This performs an immediate `needs-rebuild` evaluation.

---

## What does disable-systemd remove?

Run:

```bash
sudo vmwmanager disable-systemd
```

It can:

1. disable `vmware-rebuild.service`;
2. remove `/etc/systemd/system/vmware-rebuild.service`;
3. run `systemctl daemon-reload`;
4. clear the service's failed state if necessary.

The operation does not require VMware Workstation to remain installed.

---

# Status and Troubleshooting

## What does status check?

Run:

```bash
vmwmanager status
```

It reports:

```text
VMware Workstation
running kernel
default boot kernel
Secure Boot
signing keys
MOK enrollment
vmmon.ko
vmnet.ko
module signatures
loaded-module state
vmware.service
vmware-rebuild.service
```

`status` does not automatically build or reinstall VMware modules.

---

## How do I check the module signer manually?

Use:

```bash
modinfo -F signer vmmon
modinfo -F signer vmnet
```

The expected signer contains:

```text
VMware Module Signing
```

---

## How do I check whether vmmon and vmnet are loaded?

Use:

```bash
lsmod | grep -E '^(vmmon|vmnet)'
```

A module being installed and correctly signed does not necessarily mean that it is currently loaded.

`vmwmanager status` distinguishes these states.

---

## How do I inspect systemd logs?

For the current boot:

```bash
journalctl -b -u vmware-rebuild.service
```

Also inspect:

```bash
systemctl status vmware-rebuild.service
```

and VMware's service:

```bash
systemctl status vmware.service
```

---

# Uninstallation

## Does vmwmanager uninstall VMware Workstation?

No.

The command:

```bash
sudo vmwmanager uninstall
```

removes `vmwmanager` integration.

VMware Workstation is treated as separate software.

---

## What does vmwmanager uninstall remove?

It first disables/removes the `vmware-rebuild.service` integration.

It can then optionally:

```text
stage VMware MOK deletion
remove local vmware.key
remove local vmware.der
```

These destructive operations require user confirmation where appropriate.

---

## Does uninstall automatically delete the MOK?

No.

If the VMware certificate is found, the manager asks whether MOK deletion should be staged.

If confirmed, it uses:

```bash
mokutil --delete <certificate>
```

The deletion must then be completed during a subsequent reboot.

---

## Does uninstall delete vmmon.ko and vmnet.ko?

No.

`vmwmanager` deliberately does not manually delete VMware's host modules.

The modules belong to the VMware Workstation installation lifecycle.

---

## How do I completely remove VMware Workstation?

After cleaning the manager integration, VMware Workstation can be removed separately using VMware's native installer:

```bash
sudo vmware-installer -u vmware-workstation
```

Removing the `vmware-manager` RPM and removing VMware Workstation are therefore separate operations.