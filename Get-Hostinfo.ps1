# ----------------------------------------------------------
# System Inventory Script (NO SMB Shares) + TXT Export
# Windows Server 2012 R2 compatible
# ----------------------------------------------------------

Write-Host "Collecting system information..." -ForegroundColor Cyan

# --- FQDN ---
try {
    $FQDN = [System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName
}
catch {
    $FQDN = $env:COMPUTERNAME
}

# --- IP Addresses (IPv4) ---
# Prefer Get-NetIPAddress (PS 4+), fallback to WMI for older/edge cases
try {
    $ipList = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object { $_.IPAddress -notlike "169.*" -and $_.IPAddress -ne "127.0.0.1" } |
        Select-Object -ExpandProperty IPAddress
}
catch {
    $ipList = (Get-WmiObject Win32_NetworkAdapterConfiguration |
                Where-Object { $_.IPEnabled -eq $true -and $_.IPAddress }) |
              ForEach-Object { $_.IPAddress } |
              Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' -and $_ -ne "127.0.0.1" }
}
$IPAddresses = ($ipList | Sort-Object -Unique) -join ", "

# --- OS Name & Version ---
$OS        = Get-WmiObject Win32_OperatingSystem
$OSName    = $OS.Caption
$OSVersion = $OS.Version

# --- PowerShell Version ---
$PSVersion = $PSVersionTable.PSVersion.ToString()

# --- Storage (Drives with Capacity via WMI) ---
$logicalDisks = Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3"

$driveInfo = foreach ($ld in $logicalDisks) {
    $sizeGB = if ($ld.Size) { [math]::Round(($ld.Size -as [double]) / 1GB, 2) } else { $null }
    $freeGB = if ($ld.FreeSpace) { [math]::Round(($ld.FreeSpace -as [double]) / 1GB, 2) } else { $null }
    $usedGB = if ($sizeGB -ne $null -and $freeGB -ne $null) { [math]::Round($sizeGB - $freeGB, 2) } else { $null }

    [pscustomobject]@{
        Name        = $ld.DeviceID.TrimEnd(':')
        Root        = "$($ld.DeviceID)\"
        CapacityGB  = $sizeGB
        UsedGB      = $usedGB
        FreeGB      = $freeGB
        FileSystem  = $ld.FileSystem
        VolumeName  = $ld.VolumeName
    }
}

# --- RAM (GB) ---
$RAM_GB = [math]::Round((Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)

# --- CPU Info ---
$CPU = Get-WmiObject Win32_Processor |
    Select-Object -First 1 Name, NumberOfCores, NumberOfLogicalProcessors

# --- Build summary object ---
$SystemInfo = [PSCustomObject]@{
    HostFQDN      = $FQDN
    IPAddress     = $IPAddresses
    OSName        = $OSName
    OSVersion     = $OSVersion
    PSVersion     = $PSVersion
    RAM_GB        = $RAM_GB
    CPUName       = $CPU.Name
    Cores         = $CPU.NumberOfCores
    LogicalCPU    = $CPU.NumberOfLogicalProcessors
}

# --- Console Output ---
Write-Host ""
Write-Host "===== SYSTEM INFORMATION =====" -ForegroundColor Green
$SystemInfo | Format-List

Write-Host ""
Write-Host "===== FILE SYSTEM DRIVES =====" -ForegroundColor Green
$driveInfo |
    Select-Object `
        @{n='Drive';e={$_.Name}},
        @{n='Root';e={$_.Root}},
        @{n='Capacity(GB)';e={$_.CapacityGB}},
        @{n='Used(GB)';e={$_.UsedGB}},
        @{n='Free(GB)';e={$_.FreeGB}},
        @{n='FS';e={$_.FileSystem}},
        @{n='Label';e={$_.VolumeName}} |
    Sort-Object Drive |
    Format-Table -AutoSize

# ----------------------------------------------------------
# TXT EXPORT
# ----------------------------------------------------------

$exportTXT = Read-Host "Do you want to export the results to a TXT file? (Y/N)"

if ($exportTXT -match '^(Y|y)$') {

    $timestamp    = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $defaultDir   = 'C:\Temp'
    $defaultName  = "{0}_SystemInventory_{1}.txt" -f $env:COMPUTERNAME, $timestamp
    $defaultPath  = Join-Path -Path $defaultDir -ChildPath $defaultName

    Write-Host "Enter the full path and filename for the TXT export." -ForegroundColor Cyan
    $userPath = Read-Host "Press ENTER to use default:`n$defaultPath"

    $filepath = if ([string]::IsNullOrWhiteSpace($userPath)) { $defaultPath } else { $userPath }

    if (-not ($filepath.ToLower().EndsWith('.txt'))) {
        $filepath = "$filepath.txt"
    }

    # Create directory if missing
    $folder = Split-Path $filepath -Parent
    if (!(Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    # Build TXT Content
    $txtContent = @()
    $txtContent += "===== SYSTEM INFORMATION ====="
    $txtContent += ""
    $txtContent += "Host FQDN:      $FQDN"
    $txtContent += "IP Address(es): $IPAddresses"
    $txtContent += "OS Name:        $OSName"
    $txtContent += "OS Version:     $OSVersion"
    $txtContent += "PowerShell Ver: $PSVersion"
    $txtContent += "RAM (GB):       $RAM_GB"
    $txtContent += "CPU:            $($CPU.Name)"
    $txtContent += "Cores:          $($CPU.NumberOfCores)"
    $txtContent += "Logical CPUs:   $($CPU.NumberOfLogicalProcessors)"
    $txtContent += ""
    $txtContent += "===== FILE SYSTEM DRIVES ====="
    $txtContent += ""

    foreach ($d in ($driveInfo | Sort-Object Name)) {
        $capGB  = if ($d.CapacityGB -ne $null) { $d.CapacityGB } else { 0 }
        $usedGB = if ($d.UsedGB     -ne $null) { $d.UsedGB     } else { 0 }
        $freeGB = if ($d.FreeGB     -ne $null) { $d.FreeGB     } else { 0 }
        $fs     = if ($d.FileSystem) { $d.FileSystem } else { "" }
        $label  = if ($d.VolumeName) { $d.VolumeName } else { "" }

        $txtContent += "Drive $($d.Name): Root=$($d.Root) Capacity=${capGB}GB Used=${usedGB}GB Free=${freeGB}GB FS=$fs Label=$label"
    }

    # Write to TXT
    $txtContent | Out-File -FilePath $filepath -Encoding UTF8

    Write-Host "TXT file successfully created at: $filepath" -ForegroundColor Green
}
else {
    Write-Host "TXT export skipped." -ForegroundColor Yellow
}