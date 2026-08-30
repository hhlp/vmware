Name:           vmware-manager
Version:        1.0.0
Release:        1%{?dist}
Summary:        Secure Boot manager for VMware host modules on Fedora

License:        GPL-3.0-only
URL:            https://github.com/hhlp/vmware
Source0:        %{url}/archive/refs/tags/v%{version}.tar.gz

BuildArch:      noarch

Requires:       bash
Requires:       gcc
Requires:       make
Requires:       kernel-devel
Requires:       openssl
Requires:       mokutil
Requires:       kmod
Requires:       systemd
Requires:       sudo

%description
vmware-manager is a Fedora management utility for building, signing,
installing, rebuilding, and maintaining VMware Workstation host kernel
modules.

It supports Secure Boot using Machine Owner Keys (MOK) and can create
an optional systemd service that checks VMware host modules for the
currently running kernel.

The VMware proprietary application itself is not distributed by this
package.

%prep
%autosetup -n vmware-%{version}

%build
# Nothing to build.
# vmwmanager is a Bash script.

%install
install -Dpm0755 vmwmanager.sh \
    %{buildroot}%{_bindir}/vmwmanager

%preun
if [ "$1" -eq 0 ]; then
    if [ -e /etc/systemd/system/vmware-rebuild.service ] ||
       [ -e /var/lib/shim-signed/mok/vmware.key ] ||
       [ -e /var/lib/shim-signed/mok/vmware.der ]; then

        echo
        echo "vmware-manager integration may still be configured."
        echo
        echo "Before removing the package completely, consider running:"
        echo
        echo "    sudo vmwmanager uninstall"
        echo
        echo "This can disable vmware-rebuild.service and optionally"
        echo "remove the VMware MOK/signing-key integration."
        echo
    fi
fi

%files
%license LICENSE

%doc README.md
%doc FAQ.md
%doc TEST.md
%doc CONTRIBUTING.md
%doc SECURITY.md
%doc CHANGELOG.md

%{_bindir}/vmwmanager

%changelog
