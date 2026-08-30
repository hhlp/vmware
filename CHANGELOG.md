# Changelog

All notable changes to `vmware-manager` will be documented in this file.

The format is based on **Keep a Changelog**, and this project follows **Semantic Versioning**.

---

## [Unreleased]

### Added

### Changed

### Fixed

### Security

---

## [1.0.0] - 2026-08-30

### Added

- Initial `vmware-manager` release.
- Added `/usr/bin/vmwmanager`.
- Added management for VMware Workstation host modules:
  - `vmmon.ko`
  - `vmnet.ko`
- Added VMware Workstation installation detection.
- Added fallback VMware detection using the expected VMware executables.
- Added running-kernel detection using `uname -r`.
- Added Fedora default boot-kernel reporting through `grubby` when available.
- Added Secure Boot state reporting.
- Added dedicated VMware MOK signing-key generation.
- Added signing key storage under:
  - `/var/lib/shim-signed/mok/vmware.key`
  - `/var/lib/shim-signed/mok/vmware.der`
- Added certificate identity:
  - `CN=VMware Module Signing`
- Added safe preservation of existing complete signing-key pairs.
- Added protection against automatically replacing incomplete signing-key pairs.
- Added MOK enrollment detection.
- Added MOK enrollment requests using the existing certificate.
- Added MOK re-enrollment support without regenerating signing keys.
- Added VMware native host-module compilation through:
  - `vmware-modconfig --console --install-all`
- Added build-marker validation to distinguish freshly rebuilt VMware modules from stale existing files.
- Added handling for VMware Secure Boot cases where `vmware-modconfig` returns non-zero after successfully producing the host modules.
- Added SHA-256 kernel-module signing using the running kernel's `scripts/sign-file`.
- Added signing for both `vmmon.ko` and `vmnet.ko`.
- Added module-signature verification.
- Added `depmod` refresh after signing.
- Added VMware service restart after successful module rebuild/signing.
- Added read-only VMware service diagnostics.
- Added VMware service state reporting for:
  - load state
  - unit-file state
  - active state
  - sub-state
  - result
- Added `status` command.
- Added `needs-rebuild` command.
- Added systemd-compatible `needs-rebuild` exit semantics:
  - `0` = rebuild required
  - `1` = rebuild not required
- Added protection against unnecessary rebuilds when modules are valid but the MOK certificate is not enrolled.
- Added conditional `rebuild` command.
- Added forced `reinstall` command.
- Added automatic signature verification after rebuild and reinstall.
- Added optional systemd integration.
- Added dynamic creation of:
  - `/etc/systemd/system/vmware-rebuild.service`
- Added weak dependency on `vmware.service` using:
  - `Wants=vmware.service`
- Added boot ordering using:
  - `After=local-fs.target vmware.service`
- Added conditional systemd execution using:
  - `ExecCondition=/usr/bin/vmwmanager needs-rebuild`
  - `ExecStart=/usr/bin/vmwmanager rebuild`
- Added immediate module check when systemd integration is enabled.
- Added safe `disable-systemd` behavior.
- Added systemd failed-state cleanup.
- Added idempotent systemd cleanup.
- Added `uninstall` command for removing vmwmanager integration.
- Added optional VMware MOK deletion staging.
- Added optional local signing-key removal.
- Added MOK certificate discovery through exported enrolled certificates when the local DER file is unavailable.
- Added safe cleanup behavior when VMware Workstation is already absent.
- Added explicit separation between removing `vmware-manager` integration and removing VMware Workstation itself.
- Added informational VMware uninstall command:
  - `sudo vmware-installer -u vmware-workstation`
- Added explicit policy preventing automatic third-party host-module fallback.
- Added informational reference to:
  - `https://github.com/mkubecek/vmware-host-modules`
- Added README documentation.
- Added FAQ documentation.
- Added functional and regression test documentation.
- Added contribution guidelines.
- Added security policy.
- Added RPM packaging preparation.
- Added GitHub Actions release workflow preparation.
- Added COPR release workflow preparation.

### Security

- Private VMware module-signing keys are created with mode `0600`.
- VMware DER certificates are created with mode `0644`.
- Existing signing identities are preserved rather than silently replaced.
- Incomplete signing-key states fail safely.
- Alternative privileged kernel-module sources are never automatically downloaded or installed.
- Existing administrator-created systemd service files are not overwritten automatically.

[Unreleased]: https://github.com/hhlp/vmware/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/hhlp/vmware/releases/tag/v1.0.0