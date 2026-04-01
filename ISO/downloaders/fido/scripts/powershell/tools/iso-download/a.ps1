#
# Fido v1.70 - ISO Downloader, for Microsoft Windows and UEFI Shell
# Copyright © 2019-2026 Pete Batard <pete@akeo.ie>
# Command line support: Copyright © 2021 flx5
# ConvertTo-ImageSource: Copyright © 2016 Chris Carter
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#

# NB: You must have a BOM on your .ps1 if you want Powershell to actually
# realise it should use Unicode for the UI rather than ISO-8859-1.

#region Parameters
param(
 # (Optional) The title to display on the application window.
 [string]$AppTitle = "Fido - ISO Downloader",
 # (Optional) '|' separated UI localization strings.
 [string]$LocData,
 # (Optional) Forced locale
 [string]$Locale = "en-US",
 # (Optional) Path to a file that should be used for the UI icon.
 [string]$Icon,
 # (Optional) Name of a pipe the download URL should be sent to.
 # If not provided, a browser window is opened instead.
 [string]$PipeName,
 # (Optional) Specify Windows version (e.g. "Windows 10") [Toggles commandline mode]
 [string]$Win,
 # (Optional) Specify Windows release (e.g. "21H1") [Toggles commandline mode]
 [string]$Rel,
 # (Optional) Specify Windows edition (e.g. "Pro") [Toggles commandline mode]
 [string]$Ed,
 # (Optional) Specify Windows language [Toggles commandline mode]
 [string]$Lang,
 # (Optional) Specify Windows architecture [Toggles commandline mode]
 [string]$Arch,
 # (Optional) Only display the download URL [Toggles commandline mode]
 [switch]$GetUrl = $false,
 # (Optional) Specify the architecture of the underlying CPU.
 # This avoids a VERY TIME CONSUMING call to WMI to autodetect the arch.
 [string]$PlatformArch,
 # (Optional) Increase verbosity
 [switch]$Verbose = $false,
 # (Optional) Produce debugging information
 [switch]$Debug = $false
)
#endregion

try {
 [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$Cmd = $false
if ($Win -or $Rel -or $Ed -or $Lang -or $Arch -or $GetUrl) {
 $Cmd = $true
}

# Return a decimal Windows version that we can then check for platform support.
# Note that because we don't want to have to support this script on anything
# other than Windows, this call returns 0.0 for PowerShell running on Linux/Mac.
function Get-Platform-Version()
{
 $version = 0.0
 $platform = [string][System.Environment]::OSVersion.Platform
 # This will filter out non Windows platforms
 if ($platform.StartsWith("Win")) {
 # Craft a decimal numeric version of Windows
 $version = [System.Environment]::OSVersion.Version.Major * 1.0 + [System.Environment]::OSVersion.Version.Minor * 0.1
 }
 return $version
}

$winver = Get-Platform-Version

# The default TLS for Windows 8.x doesn't work with Microsoft's servers so we must force it
if ($winver -lt 10.0) {
 [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls12
}

#region Assembly Types
$Drawing_Assembly = "System.Drawing"
# PowerShell 7 altered the name of the Drawing assembly...
if ($host.version -ge "7.0") {
 $Drawing_Assembly += ".Common"
}
