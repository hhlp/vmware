# Contributing to vmware-manager

Thank you for your interest in contributing to `vmware-manager`.

This project provides a Fedora-oriented manager for VMware Workstation host kernel modules with Secure Boot support.

The primary program is:

```text
/usr/bin/vmwmanager
```

Managed modules:

```text
vmmon.ko
vmnet.ko
```

---

## Table of Contents

- [Project Goals](#project-goals)
- [Development Principles](#development-principles)
- [Repository Layout](#repository-layout)
- [Development Requirements](#development-requirements)
- [Getting the Source](#getting-the-source)
- [Branching](#branching)
- [Commit Messages](#commit-messages)
- [Shell Coding Style](#shell-coding-style)
- [Testing Changes](#testing-changes)
- [Secure Boot Tests](#secure-boot-tests)
- [systemd Tests](#systemd-tests)
- [RPM Tests](#rpm-tests)
- [Pull Requests](#pull-requests)
- [Release Preparation](#release-preparation)
- [Release Checklist](#release-checklist)
- [COPR Publishing Policy](#copr-publishing-policy)
- [Security-Sensitive Changes](#security-sensitive-changes)

---

# Project Goals

`vmware-manager` aims to make VMware Workstation host-module maintenance predictable on Fedora systems using Secure Boot.

The project manages:

```text
vmmon.ko
vmnet.ko
```

while continuing to rely on VMware's native module compilation command:

```bash
vmware-modconfig --console --install-all
```

The project does not distribute VMware Workstation.

---

# Development Principles

Changes should preserve the following behavior.

## 1. Preserve existing signing keys

An existing complete signing-key pair must not be silently replaced.

The expected files are:

```text
/var/lib/shim-signed/mok/vmware.key
/var/lib/shim-signed/mok/vmware.der
```

If only one file exists, the manager must fail safely rather than generating a replacement automatically.

---

## 2. Manage the running kernel

VMware's native module builder operates on the currently running kernel.

The manager therefore intentionally uses:

```bash
uname -r
```

as its target kernel.

Do not change this behavior to automatically select the newest installed kernel unless the architecture of VMware module compilation itself changes.

---

## 3. Preserve needs-rebuild semantics

`needs-rebuild` is designed for systemd `ExecCondition`.

Its exit codes are:

```text
0 = rebuild required
1 = rebuild not required
```

This behavior must not be changed casually because:

```ini
ExecCondition=/usr/bin/vmwmanager needs-rebuild
ExecStart=/usr/bin/vmwmanager rebuild
```

depends on it.

---

## 4. Do not rebuild to solve MOK trust problems

If both modules are correctly built and signed but the certificate is not enrolled, rebuilding the modules does not solve the problem.

The correct action is certificate re-enrollment.

---

## 5. Do not trust vmware-modconfig exit status alone

With Secure Boot enabled, VMware may successfully compile and install the modules and then return a non-zero status because it attempts to start `vmware.service` before those modules have been signed.

The manager must continue verifying that both modules were freshly created during the current compilation attempt.

---

## 6. Do not silently install alternative modules

If VMware's native module compilation fails, the manager may display information about alternative host-module projects.

It must not automatically:

```text
download
patch
compile
install
```

an alternative implementation.

---

## 7. Keep cleanup independent from VMware installation

These commands must remain usable when VMware Workstation is absent:

```text
status
disable-systemd
uninstall
```

This allows cleanup even after VMware has already been removed.

---

# Repository Layout

Expected project structure:

```text
vmware/
├── .github/
│   └── workflows/
│       ├── shellcheck.yml
│       ├── rpm-build.yml
│       ├── release.yml
│       └── copr-build.yml
├── scripts/
│   └── prepare-release.sh
├── README.md
├── FAQ.md
├── TEST.md
├── CONTRIBUTING.md
├── SECURITY.md
├── CHANGELOG.md
├── LICENSE
├── vmware.spec
└── vmwmanager.sh
```

The systemd service is deliberately not stored as a repository unit file.

It is generated dynamically by:

```bash
sudo vmwmanager enable-systemd
```

at:

```text
/etc/systemd/system/vmware-rebuild.service
```

---

# Development Requirements

Recommended Fedora development packages include:

```bash
sudo dnf install \
    bash \
    git \
    ShellCheck \
    rpm-build \
    rpmdevtools \
    gcc \
    make \
    kernel-devel \
    openssl \
    mokutil \
    kmod \
    systemd
```

VMware Workstation is required for full functional tests involving native host-module compilation.

---

# Getting the Source

Clone the repository:

```bash
git clone https://github.com/hhlp/vmware.git
cd vmware
```

Check repository status:

```bash
git status
```

---

# Branching

Create a dedicated branch for each logical change.

Examples:

```bash
git switch -c feature/improve-status
```

```bash
git switch -c bugfix/mok-detection
```

```bash
git switch -c docs/update-faq
```

```bash
git switch -c test/kernel-update
```

Avoid mixing unrelated changes in the same branch.

---

# Commit Messages

Use clear commit messages describing the purpose of the change.

Recommended prefixes include:

```text
feat:
fix:
docs:
test:
refactor:
chore:
ci:
build:
```

Examples:

```text
feat: add VMware service diagnostics
```

```text
fix: preserve existing MOK certificate
```

```text
test: add needs-rebuild exit-code coverage
```

```text
docs: document kernel update workflow
```

```text
ci: add RPM build validation
```

Keep commits focused.

---

# Shell Coding Style

`vmwmanager.sh` is a Bash program.

The script should remain compatible with:

```bash
#!/usr/bin/env bash
```

and uses:

```bash
set -Eeuo pipefail
```

New code should preserve this error-handling model.

Prefer:

```bash
[[ ... ]]
```

for Bash conditional expressions.

Prefer explicit quoting:

```bash
"$variable"
```

over unquoted expansion.

Use arrays when handling collections such as managed modules:

```bash
MODULES=(
    "vmmon"
    "vmnet"
)
```

Avoid suppressing errors unless failure is genuinely expected and handled.

For example:

```bash
command || true
```

should only be used where a non-zero status is deliberately acceptable.

---

# Testing Changes

Before submitting a Pull Request, run ShellCheck:

```bash
shellcheck vmwmanager.sh
```

If the release helper exists:

```bash
shellcheck scripts/prepare-release.sh
```

Then execute the relevant tests documented in:

```text
TEST.md
```

At minimum verify:

```bash
vmwmanager help
vmwmanager status
vmwmanager needs-rebuild
```

For changes affecting compilation or signing:

```bash
sudo vmwmanager rebuild
```

and:

```bash
sudo vmwmanager reinstall
```

when appropriate.

---

# Secure Boot Tests

For signing-related changes, verify:

```bash
mokutil --sb-state
```

Check the local certificate:

```bash
sudo mokutil --test-key \
    /var/lib/shim-signed/mok/vmware.der
```

Check module signers:

```bash
modinfo -F signer vmmon
modinfo -F signer vmnet
```

Expected signer:

```text
VMware Module Signing
```

Never use a real private signing key in public test fixtures.

---

# systemd Tests

If a change affects systemd integration, test both enabled and disabled states.

Enable:

```bash
sudo vmwmanager enable-systemd
```

Inspect:

```bash
systemctl status vmware-rebuild.service
```

Inspect logs:

```bash
journalctl -b -u vmware-rebuild.service
```

Disable:

```bash
sudo vmwmanager disable-systemd
```

Run the disable operation twice to verify idempotency.

The generated service must continue to use:

```ini
Wants=vmware.service
After=local-fs.target vmware.service
ConditionPathExists=/usr/bin/vmwmanager
```

and:

```ini
ExecCondition=/usr/bin/vmwmanager needs-rebuild
ExecStart=/usr/bin/vmwmanager rebuild
```

---

# RPM Tests

When modifying:

```text
vmware.spec
vmwmanager
README.md
FAQ.md
TEST.md
CONTRIBUTING.md
SECURITY.md
CHANGELOG.md
```

build the RPM locally.

Example:

```bash
rpmbuild -ba vmware.spec
```

or use the repository's normal source-RPM workflow once configured.

Verify package contents:

```bash
rpm -qlp <rpm-file>
```

The RPM should install:

```text
/usr/bin/vmwmanager
```

The RPM should not own:

```text
/etc/systemd/system/vmware-rebuild.service
```

because that file is dynamically created by `vmwmanager`.

---

# Pull Requests

A Pull Request should contain:

- a clear description of the change;
- why the change is necessary;
- tests performed;
- relevant kernel version;
- relevant Fedora version;
- relevant VMware Workstation version when applicable;
- Secure Boot state when relevant.

For kernel/module problems, useful diagnostics include:

```bash
uname -r
mokutil --sb-state
vmwmanager status
```

and:

```bash
modinfo -n vmmon
modinfo -n vmnet
modinfo -F signer vmmon
modinfo -F signer vmnet
```

Do not include private signing keys.

---

# Release Preparation

Releases use semantic versions:

```text
MAJOR.MINOR.PATCH
```

Example:

```text
1.0.0
1.0.1
1.1.0
2.0.0
```

Release tags use:

```text
vMAJOR.MINOR.PATCH
```

Example:

```text
v1.0.0
```

The intended release helper is:

```bash
./scripts/prepare-release.sh 1.0.0
```

It should update the release metadata while preserving an `[Unreleased]` section for future development.

---

# Release Checklist

Before creating a tag:

```text
[ ] ShellCheck passes
[ ] RPM build passes
[ ] TEST.md applicable tests pass
[ ] vmwmanager status is healthy
[ ] needs-rebuild semantics verified
[ ] rebuild tested
[ ] reinstall tested where applicable
[ ] MOK behavior verified
[ ] systemd behavior verified
[ ] CHANGELOG.md updated
[ ] vmware.spec version updated
[ ] release commit created
```

Then create the release tag:

```bash
git tag -s v1.0.0 -m "v1.0.0"
```

Push:

```bash
git push origin main
git push origin v1.0.0
```

---

# COPR Publishing Policy

Ordinary commits to `main` should not publish a new COPR build.

Expected policy:

```text
push to main
    ↓
ShellCheck
RPM validation
    ↓
NO COPR publish
```

Release tags:

```text
vX.Y.Z
    ↓
GitHub Release
    +
COPR build
```

This separates development validation from public package publishing.

---

# Security-Sensitive Changes

Changes involving any of the following deserve extra review:

```text
MOK generation
private-key handling
certificate enrollment
certificate deletion
kernel-module signing
sudo/root execution
systemd service creation
module verification
uninstall behavior
```

Never weaken key permissions or automatically replace signing material for convenience.

Security issues should be reported according to:

```text
SECURITY.md
```
