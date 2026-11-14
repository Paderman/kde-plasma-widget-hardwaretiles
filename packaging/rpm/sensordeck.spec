# SPDX-FileCopyrightText: 2026 Paderman
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build: packaging/rpm/build-rpm.sh   (Fedora, openSUSE; needs rpm-build and gettext)

%global plasmoid_id io.github.paderman.sensordeck

Name:           plasma-widget-sensordeck
Version:        %{?version_override}%{!?version_override:1.0.0}
Release:        1%{?dist}
Summary:        GPU & system monitor widget for KDE Plasma 6
License:        GPL-2.0-or-later
URL:            https://github.com/Paderman/kde-plasma-widget-sensordeck
Source0:        sensordeck-%{version}.tar.gz
BuildArch:      noarch
BuildRequires:  gettext
Requires:       (plasma-workspace >= 6.0 or plasma6-workspace)
Recommends:     (lm_sensors or sensors)
Recommends:     pciutils
Suggests:       python3

%description
Sensor Deck shows the graphics card in detail – VRAM temperature, throttling
reason, PCIe link and a self-learning fan curve – plus CPU, memory, SSDs,
mainboard fans and network, as rings, bars and graphs. Includes a setup
wizard, desktop notifications for critical values and plain-language tooltips.

%prep
%autosetup -n sensordeck-%{version}

%build
# nothing to compile – translations are built while staging

%install
sh packaging/stage.sh %{buildroot}

%files
%license LICENSE
%doc README.md README.de.md
%{_datadir}/plasma/plasmoids/%{plasmoid_id}/
%{_datadir}/sensordeck/
%exclude %{_datadir}/doc/sensordeck/
%exclude %{_datadir}/licenses/sensordeck/
