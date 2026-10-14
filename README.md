# Entra ID or Intune Device Audit

PowerShell script to audit Microsoft Entra ID device records and correlate them with Microsoft Intune managed-device data.

## What it reports

The script exports CSV reports covering:
- All discovered Entra devices
- Join state by operating system
- Devices inactive for the configured number of days
- Windows 10 devices
- Unmanaged and non-compliant devices
- Duplicate device display names
- Windows Server devices

It also prints a summary to the console.

## Prerequisites

- PowerShell 7 recommended
- Appropriate Microsoft Entra permissions to read devices and users
- Microsoft Graph PowerShell modules:
  - `Microsoft.Graph.Identity.DirectoryManagement`
  - `Microsoft.Graph.DeviceManagement`

Install the modules if needed:

```powershell
Install-Module Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser
Install-Module Microsoft.Graph.DeviceManagement -Scope CurrentUser
```

The script requests these Microsoft Graph delegated scopes when connecting:
- `Device.Read.All`
- `DeviceManagementManagedDevices.Read.All`
- `User.Read.All`

An administrator may need to grant consent. Intune information may be unavailable if the tenant lacks the relevant licensing or permissions.

## Usage

Run from the repository directory:

```powershell
./DeviceAudit.ps1
```

Set a different inactivity threshold:

```powershell
./DeviceAudit.ps1 -StaleDays 60
```

Include a registered owner lookup (takes longer):

```powershell
./DeviceAudit.ps1 -IncludeOwner
```

Choose an output directory:

```powershell
./DeviceAudit.ps1 -StaleDays 120 -OutDir "./DeviceAudit-Results"
```

## Output

By default, the script creates a dated output folder such as `DeviceAudit_20261014` and writes CSV reports into it.

## Notes

- Review the exported data before using it for cleanup or compliance decisions.
- The script is read-oriented; it does not delete or modify devices.
- `ApproximateLastSignInDateTime` can be empty, so devices with no recorded sign-in are flagged as stale.
