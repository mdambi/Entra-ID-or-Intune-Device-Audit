#Requires -Modules Microsoft.Graph.Identity.DirectoryManagement, Microsoft.Graph.DeviceManagement
param(
    [int]$StaleDays = 90,
    [switch]$IncludeOwner,   # adds registered owner per device (slower)
    [string]$OutDir = ".\DeviceAudit_$(Get-Date -Format yyyyMMdd)"
)

New-Item $OutDir -ItemType Directory -Force | Out-Null
Connect-MgGraph -Scopes "Device.Read.All","DeviceManagementManagedDevices.Read.All","User.Read.All" -NoWelcome

# ---------- 1. Entra devices ----------
$devices = Get-MgDevice -All -Property "id,deviceId,displayName,accountEnabled,operatingSystem,operatingSystemVersion,trustType,isCompliant,isManaged,managementType,approximateLastSignInDateTime,registrationDateTime,manufacturer,model,profileType,onPremisesSyncEnabled,enrollmentType"

# ---------- 2. Intune devices (keyed by Entra deviceId) ----------
$intune = @{}
$hasIntune = $true
try {
    Get-MgDeviceManagementManagedDevice -All -ErrorAction Stop | ForEach-Object { $intune[$_.AzureAdDeviceId] = $_ }
} catch {
    $hasIntune = $false
    Write-Warning "Intune data unavailable (no Intune license or missing permission). Managed/compliance columns will be Entra-only."
}

# ---------- 3. Build rows ----------
$cutoff = (Get-Date).AddDays(-$StaleDays)
$dupNames = $devices | Group-Object DisplayName | Where-Object Count -gt 1 | ForEach-Object Name

$rows = foreach ($d in $devices) {
    $join = switch ($d.TrustType) {
        'AzureAd'   { 'Entra joined' }
        'ServerAd'  { 'Hybrid joined' }
        'Workplace' { 'Entra registered' }
        default     { 'Unknown' }
    }

    $osFamily = $d.OperatingSystem
    if ($d.OperatingSystem -match 'Server') { $osFamily = 'Windows Server' }
    elseif ($d.OperatingSystem -eq 'Windows') {
        $build = 0
        try { $build = ([version]$d.OperatingSystemVersion).Build } catch {}
        $osFamily = if ($build -ge 22000) { 'Windows 11' } elseif ($build -gt 0) { 'Windows 10' } else { 'Windows (unknown build)' }
    }

    $im = $intune[$d.DeviceId]
    $owner = $null
    if ($IncludeOwner) {
        $o = Get-MgDeviceRegisteredOwner -DeviceId $d.Id -ErrorAction SilentlyContinue | Select-Object -First 1
        $owner = $o.AdditionalProperties.userPrincipalName
    }

    $last = $d.ApproximateLastSignInDateTime
    [pscustomobject]@{
        DeviceName     = $d.DisplayName
        Owner          = $owner
        JoinState      = $join
        OS             = $osFamily
        OSVersion      = $d.OperatingSystemVersion
        Manufacturer   = $d.Manufacturer
        Model          = $d.Model
        Enabled        = $d.AccountEnabled
        Registered     = $d.RegistrationDateTime
        LastSignIn     = $last
        DaysInactive   = if ($last) { [int]((Get-Date) - $last).TotalDays } else { $null }
        InIntune       = [bool]$im
        IntuneCompliance = $im.ComplianceState
        IntuneLastSync = $im.LastSyncDateTime
        IntuneEncrypted= $im.IsEncrypted
        IntuneSerial   = $im.SerialNumber
        EntraManaged   = $d.IsManaged
        MgmtType       = $d.ManagementType
        Flag_Stale     = (-not $last) -or ($last -lt $cutoff)
        Flag_Win10     = ($osFamily -eq 'Windows 10')
        Flag_Unmanaged = (-not $im) -and (-not $d.IsManaged)
        Flag_NonCompliant = ($im -and $im.ComplianceState -ne 'compliant')
        Flag_DupName   = ($d.DisplayName -in $dupNames)
    }
}

# ---------- 4. Exports ----------
$rows | Export-Csv "$OutDir\1_All_Devices.csv" -NoTypeInformation

$rows | Group-Object JoinState, OS | ForEach-Object {
    [pscustomobject]@{ JoinState = $_.Group[0].JoinState; OS = $_.Group[0].OS; Count = $_.Count }
} | Sort-Object JoinState, OS | Export-Csv "$OutDir\2_JoinState_By_OS.csv" -NoTypeInformation

$rows | Where-Object Flag_Stale        | Sort-Object DaysInactive -Descending | Export-Csv "$OutDir\3_Stale_$StaleDays`d.csv" -NoTypeInformation
$rows | Where-Object Flag_Win10        | Export-Csv "$OutDir\4_Windows10_EndOfSupport.csv" -NoTypeInformation
$rows | Where-Object Flag_Unmanaged    | Export-Csv "$OutDir\5_Unmanaged.csv" -NoTypeInformation
$rows | Where-Object Flag_NonCompliant | Export-Csv "$OutDir\6_NonCompliant.csv" -NoTypeInformation
$rows | Where-Object Flag_DupName      | Sort-Object DeviceName | Export-Csv "$OutDir\7_Duplicate_Names.csv" -NoTypeInformation
$rows | Where-Object { $_.OS -eq 'Windows Server' } | Export-Csv "$OutDir\8_Servers.csv" -NoTypeInformation

# ---------- 5. Console summary ----------
"`n=== SUMMARY ==="
"Total Entra devices:     $($rows.Count)"
$rows | Group-Object JoinState | ForEach-Object { "  $($_.Name): $($_.Count)" }
"Intune-enrolled:         $(@($rows | Where-Object InIntune).Count)$(if (-not $hasIntune) {' (Intune data unavailable)'})"
"Stale $StaleDays+ days:         $(@($rows | Where-Object Flag_Stale).Count)"
"Windows 10:              $(@($rows | Where-Object Flag_Win10).Count)"
"Unmanaged:               $(@($rows | Where-Object Flag_Unmanaged).Count)"
"Non-compliant (Intune):  $(@($rows | Where-Object Flag_NonCompliant).Count)"
"Duplicate names:         $(@($rows | Where-Object Flag_DupName).Count)"
"Output: $OutDir"
