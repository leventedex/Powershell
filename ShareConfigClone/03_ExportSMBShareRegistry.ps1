<#
.SYNOPSIS
    Exports registry-level SMB share configurations to a CSV file with detailed execution logging.
.DESCRIPTION
    This script reads the LanmanServer\Shares registry definitions from HKLM 
    and exports the share names, paths, and their encrypted security configurations 
    into a structured CSV file named after the host, displaying explicit item details during runtime.
.PARAMETER File
    Optional custom output path for the CSV file. If omitted, it defaults to 
    the current folder as '<HOSTNAME>_SMBRegistryShares.csv'.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$File
)

if ([string]::IsNullOrWhiteSpace($File)) {
    $CurrentDir = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
    $OutputFile = Join-Path $CurrentDir "$($env:COMPUTERNAME)_SMBRegistryShares.csv"
} else {
    $OutputFile = $File
}

Write-Host "=========================================================" -ForegroundColor Gray
Write-Host " STARTING REGISTRY SMB SHARE EXPORT" -ForegroundColor White -BackgroundColor DarkBlue
Write-Host "=========================================================" -ForegroundColor Gray

$RegPath = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\LanmanServer\Shares"

if (Test-Path $RegPath) {
    $RegKey = Get-Item $RegPath
    $ShareProperties = $RegKey.GetValueNames()
    
    $ExportData = @()
    
    Write-Host "Found ($($ShareProperties.Count)) registry share definitions to export.`n" -ForegroundColor Green

    foreach ($Property in $ShareProperties) {
        Write-Host "---------------------------------------------------------" -ForegroundColor Gray
        Write-Host " READING REGISTRY BLOCK FOR SHARE: [$Property]" -ForegroundColor DarkCyan -BackgroundColor White
        
        # Registry shares are stored as multi-string (array of strings)
        $RegValue = Get-ItemProperty -Path $RegPath -Name $Property
        $RawStrings = $RegValue.$Property
        
        # Extract individual configuration lines from the registry blob
        $PathLine = $RawStrings | Where-Object { $_ -like "Path=*" }
        $RemarkLine = $RawStrings | Where-Object { $_ -like "Remark=*" }
        $TypeLine = $RawStrings | Where-Object { $_ -like "Type=*" }
        $MaxUsesLine = $RawStrings | Where-Object { $_ -like "MaxUses=*" }
        $SecurityLine = $RawStrings | Where-Object { $_ -like "Security=*" }

        # Clean the strings for reporting and objects
        $CleanPath    = if ($PathLine) { $PathLine -replace "Path=", "" } else { "[Not Set]" }
        $CleanRemark  = if ($RemarkLine) { $RemarkLine -replace "Remark=", "" } else { "[Not Set]" }
        $CleanType    = if ($TypeLine) { $TypeLine -replace "Type=", "" } else { "0" }
        $CleanMaxUses = if ($MaxUsesLine) { $MaxUsesLine -replace "MaxUses=", "" } else { "Unlimited" }
        $HasSecurity  = if ($SecurityLine) { "Yes (Security Descriptor Array Present)" } else { "No (Default Permissions)" }

        # Detailed item logging during execution
        Write-Host " -> Path:      $CleanPath" -ForegroundColor White
        Write-Host " -> Description: $CleanRemark" -ForegroundColor Gray
        Write-Host " -> Max Users:  $CleanMaxUses" -ForegroundColor Gray
        Write-Host " -> SMB Type:   $CleanType" -ForegroundColor Gray
        Write-Host " -> Security:   $HasSecurity" -ForegroundColor Magenta

        $ExportData += [PSCustomObject]@{
            ShareName = $Property
            Path      = if ($PathLine) { $PathLine -replace "Path=", "" } else { "" }
            Remark    = if ($RemarkLine) { $RemarkLine -replace "Remark=", "" } else { "" }
            Type      = if ($TypeLine) { $TypeLine -replace "Type=", "" } else { "" }
            MaxUses   = if ($MaxUsesLine) { $MaxUsesLine -replace "MaxUses=", "" } else { "" }
            Security  = if ($SecurityLine) { $SecurityLine -replace "Security=", "" } else { "" }
        }
    }

    $ExportData | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
    
    Write-Host "---------------------------------------------------------" -ForegroundColor Gray
    Write-Host "=========================================================" -ForegroundColor Gray
    Write-Host " SUCCESS: Registry export complete!" -ForegroundColor White -BackgroundColor DarkGreen
    Write-Host " Saved to: $OutputFile" -ForegroundColor Yellow
    Write-Host "=========================================================" -ForegroundColor Gray
} else {
    Write-Host "Error: LanmanServer registry path not found. Ensure you are running as Administrator." -ForegroundColor Red
}