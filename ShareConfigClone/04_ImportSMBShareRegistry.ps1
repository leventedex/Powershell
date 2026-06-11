<#
.SYNOPSIS
    Imports SMB share definitions from a CSV file directly into the Windows Registry with detailed tracking.
.DESCRIPTION
    This script parses a migration CSV file containing share properties, builds the 
    native Windows MultiString registry blobs, merges them, and restarts the Server service
    while cleanly outputting every attribute being deployed.
    If your paths are changing (e.g., your old server used E:\Shares and your new server uses D:\Shares), 
    open the generated CSV file in Microsoft Excel, use Ctrl + H to replace the paths in the Path column, and save it back as a CSV.
.PARAMETER File
    The path to the CSV file exported from the old server. If omitted, the script prompts the user.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$File
)

Clear-Host
Write-Host "=========================================================" -ForegroundColor Gray
Write-Host " STARTING REGISTRY SMB SHARE IMPORT" -ForegroundColor White -BackgroundColor DarkBlue
Write-Host "=========================================================" -ForegroundColor Gray

if ([string]::IsNullOrWhiteSpace($File)) {
    Write-Host ""
    $InputFile = Read-Host -Prompt "Please enter the full path to the backup CSV file"
    Write-Host ""
} else {
    $InputFile = $File
}

$InputFile = $InputFile.Trim('"').Trim("'")

if (Test-Path $InputFile) {
    $SharesToImport = Import-Csv -Path $InputFile
    $RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Shares"
    
    Write-Host "Found ($($SharesToImport.Count)) shares in CSV. Beginning registry injection...`n" -ForegroundColor Yellow
    Start-Sleep -Seconds 1

    foreach ($Share in $SharesToImport) {
        Write-Host "---------------------------------------------------------" -ForegroundColor Gray
        Write-Host " INJECTING REGISTRY DATA FOR SHARE: [$($Share.ShareName)]" -ForegroundColor DarkCyan -BackgroundColor White
        
        # Build the native multi-string array that Windows expects in the registry
        $MultiStringArray = @()
        
        # Track items for a rich visual presentation output
        $DPath    = if (![string]::IsNullOrWhiteSpace($Share.Path))    { "Path=$($Share.Path)" } else { $null }
        $DRemark  = if (![string]::IsNullOrWhiteSpace($Share.Remark))  { "Remark=$($Share.Remark)" } else { "Remark=[None]" }
        $DMaxUses = if (![string]::IsNullOrWhiteSpace($Share.MaxUses)) { "MaxUses=$($Share.MaxUses)" } else { "MaxUses=Unlimited" }
        $DSec     = if (![string]::IsNullOrWhiteSpace($Share.Security)) { "Security Descriptor String Attached" } else { "No Explicit Security String" }

        Write-Host " -> Building target local path:   $DPath" -ForegroundColor White
        Write-Host " -> Attaching share description:  $DRemark" -ForegroundColor Gray
        Write-Host " -> Enforcing connection limits:  $DMaxUses" -ForegroundColor Gray
        Write-Host " -> Processing security blob:     $DSec" -ForegroundColor Magenta

        if ($DPath) { $MultiStringArray += $DPath }
        if (![string]::IsNullOrWhiteSpace($Share.MaxUses))  { $MultiStringArray += "MaxUses=$($Share.MaxUses)" }
        if (![string]::IsNullOrWhiteSpace($Share.Remark))   { $MultiStringArray += "Remark=$($Share.Remark)" }
        if (![string]::IsNullOrWhiteSpace($Share.Security)) { $MultiStringArray += "Security=$($Share.Security)" }
        if (![string]::IsNullOrWhiteSpace($Share.Type))     { $MultiStringArray += "Type=$($Share.Type)" }

        try {
            # Force write the multi-string element directly into the registry hive
            New-ItemProperty -Path $RegPath -Name $Share.ShareName -PropertyType MultiString -Value $MultiStringArray -Force -ErrorAction Stop | Out-Null
            Write-Host " -> SUCCESS: Registry properties configured cleanly." -ForegroundColor Green
        }
        catch {
            Write-Host " -> [ERROR]: Failed to write registry key for '$($Share.ShareName)'. Reason: $_" -ForegroundColor Red
        }
    }

    Write-Host "---------------------------------------------------------" -ForegroundColor Gray
    Write-Host "`nRegistry entry assignments finalized. Reloading LanmanServer subsystem..." -ForegroundColor Yellow

    # Safely restart the Windows Server service so the changes are applied immediately
    Restart-Service -Name "LanmanServer" -Force
    
    Write-Host "=========================================================" -ForegroundColor Gray
    Write-Host " SUCCESS: Share configurations are now live on this host!" -ForegroundColor White -BackgroundColor DarkGreen
    Write-Host "=========================================================" -ForegroundColor Gray
} else {
    Write-Host "CRITICAL ERROR: CSV file not found at: $InputFile" -ForegroundColor Red
}