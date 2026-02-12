param (
    [switch]$Save
)

# Capture optional path after -Save
$SavePath = $null
if ($Save -and $args.Count -gt 0) {
    $SavePath = $args[0]
}

# -------- Collect Installed Applications --------

$regPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
)

$apps = foreach ($path in $regPaths) {
    if (Test-Path $path) {
        Get-ChildItem $path | ForEach-Object {
            $app = Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue
            if ($app.DisplayName) {
                [PSCustomObject]@{
                    ComputerName = $env:COMPUTERNAME
                    Name         = $app.DisplayName
                    Version      = $app.DisplayVersion
                    Publisher    = $app.Publisher
                    InstallDate  = $app.InstallDate
                    InstallPath  = $app.InstallLocation
                    Collected    = Get-Date
                }
            }
        }
    }
}

# Remove duplicates
$apps = $apps | Sort-Object Name, Version -Unique

# -------- Console Output --------

$apps |
    Sort-Object Name |
    Format-Table Name, Version, Publisher, InstallPath -AutoSize

Write-Host ""
Write-Host "Total Applications: $($apps.Count)"

# -------- Save Logic --------

$hostname  = $env:COMPUTERNAME
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$defaultPath = "C:\Temp\${hostname}_InstalledApps_${timestamp}.csv"

if ($Save) {

    if ([string]::IsNullOrWhiteSpace($SavePath)) {
        $SavePath = $defaultPath
    }

} else {

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

# -------- Write CSV --------

if ($SavePath) {
    $dir = Split-Path $SavePath
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $apps | Export-Csv -Path $SavePath -NoTypeInformation -Encoding UTF8
    Write-Host "CSV saved to $SavePath"
}
