param (
    [switch]$Save
)

# Capture optional value after -Save
$SavePath = $null
if ($Save -and $args.Count -gt 0) {
    $SavePath = $args[0]
}


# ----------------- Storage Summary Script -----------------

$diskDrives = Get-WmiObject Win32_DiskDrive

$results = foreach ($disk in $diskDrives) {

    $partitions = Get-WmiObject -Query "
        ASSOCIATORS OF {Win32_DiskDrive.DeviceID='$($disk.DeviceID)'}
        WHERE AssocClass = Win32_DiskDriveToDiskPartition
    "

    $totalSize = 0
    $totalFree = 0
    $driveLetters = @()

    foreach ($part in $partitions) {

        $logicalDisks = Get-WmiObject -Query "
            ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($part.DeviceID)'}
            WHERE AssocClass = Win32_LogicalDiskToPartition
        "

        foreach ($ld in $logicalDisks) {
            $totalSize += [int64]$ld.Size
            $totalFree += [int64]$ld.FreeSpace

            $label = if ($ld.VolumeName) { $ld.VolumeName } else { "NoLabel" }
            $driveLetters += "$($ld.DeviceID) ($label)"
        }
    }

    $used = $totalSize - $totalFree

    [PSCustomObject]@{
        Drives       = ($driveLetters -join ", ")
        Capacity_GB  = [math]::Round($totalSize / 1GB, 2)
        Capacity_TB  = [math]::Round($totalSize / 1TB, 2)
        Used_GB      = [math]::Round($used / 1GB, 2)
        Free_GB      = [math]::Round($totalFree / 1GB, 2)
        Used_Pct     = if ($totalSize -eq 0) { 0 } else { [math]::Round(($used / $totalSize) * 100, 2) }
        Free_Pct     = if ($totalSize -eq 0) { 0 } else { [math]::Round(($totalFree / $totalSize) * 100, 2) }
    }
}

# -------- System Totals --------

$totalCap  = ($results.Capacity_GB | Measure-Object -Sum).Sum
$totalFree = ($results.Free_GB | Measure-Object -Sum).Sum
$totalUsed = $totalCap - $totalFree

$usedPct = [math]::Round(($totalUsed / $totalCap) * 100, 2)
$freePct = [math]::Round(($totalFree / $totalCap) * 100, 2)

# Build output text
$output = @()
$output += ($results | Format-Table -AutoSize | Out-String)
$output += ""
$output += "=== TOTAL SUMMARY ==="
$output += "Capacity: $totalCap GB  ($([math]::Round($totalCap / 1024, 2)) TB)"
$output += "Used:     $totalUsed GB ($usedPct %)"
$output += "Free:     $totalFree GB ($freePct %)"

# Display to screen
$output | ForEach-Object { Write-Host $_ }

# -------- Save Logic --------

$hostname  = $env:COMPUTERNAME
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$defaultPath = "C:\Temp\${hostname}_StorageSummary_${timestamp}.txt"

if ($Save) {

    # Non-interactive
    if ([string]::IsNullOrWhiteSpace($SavePath)) {
        $SavePath = $defaultPath
    }

} else {

    # Interactive
    $savePrompt = Read-Host "Save output to file? (Y/N) [Y]"
    if ([string]::IsNullOrWhiteSpace($savePrompt)) {
        $savePrompt = "Y"
    }

    if ($savePrompt -notmatch '^[Yy]') {
        return
    }

    $filePath = Read-Host "Enter file path [$defaultPath]"
    if ([string]::IsNullOrWhiteSpace($filePath)) {
        $SavePath = $defaultPath
    } else {
        $SavePath = $filePath
    }
}

# Write file
if ($SavePath) {
    $dir = Split-Path $SavePath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $output | Out-File -FilePath $SavePath -Encoding UTF8
    Write-Host "Output saved to $SavePath"
}

