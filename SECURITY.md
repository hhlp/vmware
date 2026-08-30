# Security Policy

This document describes the security model and reporting policy for `vmware-manager`.

---

## Table of Contents

- [Supported Versions](#supported-versions)
- [Security Scope](#security-scope)
- [Signing-Key Security](#signing-key-security)
- [MOK Security](#mok-security)
- [Root Privileges](#root-privileges)
- [Kernel-Module Trust](#kernel-module-trust)
- [VMware Module Compilation](#vmware-module-compilation)
- [Alternative Host Modules](#alternative-host-modules)
- [systemd Security](#systemd-security)
- [Sensitive Information](#sensitive-information)
- [Reporting a Vulnerability](#reporting-a-vulnerability)
- [What to Include](#what-to-include)
- [What Not to Include](#what-not-to-include)
- [Responsible Disclosure](#responsible-disclosure)

---

# Supported Versions

Security fixes are intended for the current maintained release line.

During initial development, the current stable release should be considered the supported version.

Example:

| Version | Supported |
|---|---|
| 1.x | Yes |
| Older unsupported releases | No |

The exact supported-version table may be updated as additional release branches are created.

---

# Security Scope

`vmware-manager` manages privileged operations involving:

```text
kernel modules
Secure Boot
MOK enrollment
private signing keys
systemd
VMware host-module compilation
```

Security-sensitive commands include:

```text
genkey
rebuild
reinstall
enable-systemd
disable-systemd
uninstall
```

Several of these operations require root privileges.

---

# Signing-Key Security

The VMware signing material is stored under:

```text
/var/lib/shim-signed/mok/
```

Files:

```text
/var/lib/shim-signed/mok/vmware.key
/var/lib/shim-signed/mok/vmware.der
```

The private key:

```text
vmware.key
```

must remain private.

Expected permissions:

```text
0600
```

The certificate:

```text
vmware.der
```

is public certificate material and is created with:

```text
0644
```

The project must never intentionally:

```text
upload
publish
log
commit
transmit
```

the private signing key.

---

# MOK Security

The certificate identity used by the manager is:

```text
CN=VMware Module Signing
```

MOK enrollment changes which locally signed modules are trusted by the machine's Secure Boot chain.

Enrollment is therefore deliberately interactive.

`vmwmanager` may request enrollment with:

```bash
mokutil --import /var/lib/shim-signed/mok/vmware.der
```

but the final trust decision must be completed manually through MOK Manager during reboot.

The manager does not bypass this process.

---

# Key Preservation

Existing complete signing material is preserved.

If both:

```text
vmware.key
vmware.der
```

exist, `genkey` does not silently replace them.

If only one exists, the manager treats the state as incomplete and stops.

This prevents accidental trust migration to a newly generated signing identity.

---

# MOK Re-enrollment

A certificate can be absent from the enrolled MOK database even when the local key files and signed modules remain valid.

In that case, the correct action is re-enrollment.

Rebuilding modules is not considered a trust repair mechanism.

`vmwmanager` therefore preserves the existing signing identity and requests enrollment of the existing certificate.

---

# Root Privileges

Some operations require access to privileged paths or commands such as:

```text
/var/lib/shim-signed/mok
/etc/systemd/system
/usr/src/kernels
systemctl
depmod
mokutil
kernel sign-file
```

The manager uses elevated privileges only where required.

Users should inspect source code before executing privileged shell utilities obtained from untrusted sources.

Never execute a modified `vmwmanager` as root unless the modification is trusted.

---

# Kernel-Module Trust

`vmwmanager` validates the signer recorded in the VMware modules.

Expected signer:

```text
VMware Module Signing
```

The manager considers a module invalid for its own managed state when the module:

```text
is missing
is unsigned
is signed by another certificate
```

The corresponding rebuild/sign workflow is then triggered.

---

# Kernel Signing Utility

The signing utility is obtained from the running kernel's development tree:

```text
/usr/src/kernels/<running-kernel>/scripts/sign-file
```

The manager uses:

```text
sha256
```

when signing VMware host modules.

The correct `kernel-devel` package must therefore match the currently running kernel.

---

# VMware Module Compilation

`vmwmanager` invokes VMware's native command:

```bash
vmware-modconfig --console --install-all
```

The manager does not assume that a zero or non-zero return code alone fully describes compilation success.

With Secure Boot enabled, VMware can create the host modules successfully and later fail while attempting to load or start services before signing has occurred.

The manager therefore verifies that both module files were freshly produced during the current build operation.

---

# Stale Module Protection

A pre-existing `vmmon.ko` or `vmnet.ko` must not be mistaken for a successful current compilation.

`vmwmanager` uses a temporary marker to distinguish freshly generated files from stale files.

Both managed modules must have been created or updated by the active build attempt before the compilation stage is accepted as successful.

---

# Alternative Host Modules

The manager may reference:

```text
https://github.com/mkubecek/vmware-host-modules
```

when VMware's native sources fail to compile.

This is informational only.

The project deliberately does not automatically:

```text
clone
download
patch
build
install
```

third-party VMware host modules.

This reduces the risk of silently introducing external privileged kernel code.

---

# systemd Security

`vmware-rebuild.service` is dynamically created by:

```bash
sudo vmwmanager enable-systemd
```

at:

```text
/etc/systemd/system/vmware-rebuild.service
```

The unit executes:

```ini
ExecCondition=/usr/bin/vmwmanager needs-rebuild
ExecStart=/usr/bin/vmwmanager rebuild
```

Because this service executes privileged module-management operations during boot, `/usr/bin/vmwmanager` must not be writable by unprivileged users.

The expected RPM installation mode is executable but not user-modifiable.

---

# Service File Ownership

The RPM does not own:

```text
/etc/systemd/system/vmware-rebuild.service
```

The file belongs to the runtime configuration created by the manager.

`disable-systemd` is therefore allowed to remove it.

An existing service file is deliberately not silently overwritten by `enable-systemd`.

This protects local administrator changes from unexpected replacement.

---

# Sensitive Information

Do not include the following in public issue reports:

```text
private MOK keys
private certificates containing unintended personal data
passwords
MOK enrollment passwords
system credentials
SSH private keys
API tokens
COPR API tokens
GitHub tokens
```

The following information is generally useful and safe:

```bash
uname -r
mokutil --sb-state
vmware --version
vmwmanager status
```

Module signers may also be useful:

```bash
modinfo -F signer vmmon
modinfo -F signer vmnet
```

Review logs for private information before publishing them.

---

# Reporting a Vulnerability

Do not open a public issue for a vulnerability that could expose users to active exploitation before a fix is available.

Use GitHub's private security-reporting mechanism when enabled for the repository.

Repository:

```text
https://github.com/hhlp/vmware
```

If private security reporting is not available, contact the project maintainer through an appropriate private channel listed in the repository profile or metadata.

---

# What to Include

A useful report should include:

```text
affected vmware-manager version
Fedora version
running kernel
VMware Workstation version
Secure Boot state
affected command
expected behavior
actual behavior
reproduction steps
security impact
```

Include logs only after removing sensitive information.

---

# What Not to Include

Never attach:

```text
/var/lib/shim-signed/mok/vmware.key
```

Do not provide temporary MOK passwords.

Do not provide GitHub or COPR credentials.

Do not upload complete credential stores or unrelated system configuration.

---

# Responsible Disclosure

Please allow reasonable time for:

```text
validation
fix development
regression testing
release preparation
package publication
```

before publicly disclosing a confirmed vulnerability.

Security fixes may require testing across:

```text
Fedora kernels
Secure Boot
MOK enrollment
VMware Workstation versions
systemd boot behavior
```

because a change in one area can affect privileged kernel-module loading elsewhere.