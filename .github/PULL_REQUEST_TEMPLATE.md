# Pull Request

## Summary

Describe clearly what this pull request changes and why.

## Type of change

* [ ] Bug fix
* [ ] New feature
* [ ] Refactor
* [ ] Documentation
* [ ] Packaging / RPM
* [ ] GitHub Actions / CI
* [ ] systemd integration
* [ ] VMware module build/signing logic
* [ ] Other

## Related issue

Closes #

## Changes

Describe the main changes introduced by this pull request.

## Testing

Describe how the changes were tested.

Example:

```bash
shellcheck vmwmanager
sudo vmwmanager status
sudo vmwmanager needs-rebuild
sudo vmwmanager rebuild

systemctl status vmware-rebuild.service
journalctl -u vmware-rebuild.service -b
```

## Environment

* Fedora version:
* Kernel:
* VMware version:
* Secure Boot enabled: Yes / No
* vmwmanager version / commit:

Useful commands:

```bash
cat /etc/fedora-release
uname -r
vmware --version
mokutil --sb-state
```

## VMware host modules

If the problem or change concerns the upstream VMware kernel modules themselves rather than `vmwmanager`, please verify whether it belongs upstream:

https://github.com/mkubecek/vmware-host-modules

`vmwmanager` manages building, installing, rebuilding, and signing those modules, but does not maintain their kernel compatibility patches.

## Checklist

* [ ] I tested the change on Fedora.
* [ ] ShellCheck passes where applicable.
* [ ] Existing functionality has not been intentionally removed.
* [ ] Documentation was updated if behavior changed.
* [ ] `CHANGELOG.md` was updated when appropriate.
* [ ] RPM packaging still works when packaging-related files were changed.
* [ ] systemd behavior was tested when service-related files were changed.
* [ ] Secure Boot behavior was considered when module signing logic changed.
