<#
.SYNOPSIS
    Exports NTFS permissions for all custom SMB shares into a single XML file.

.DESCRIPTION
    This script queries all active, non-default SMB file shares on the local Windows Server. 
    By default, it captures the NTFS permissions (ACLs) ONLY for the top-level root folder of 
    each share. If the -Recursive flag is specified, it will perform a deep scan, capturing 
    permissions for all subfolders and files.

.PARAMETER File
    The absolute or relative path where the output XML file should be saved. 
    If omitted, the script automatically defaults to saving the file as 
    '<HOSTNAME>_sharePermissions.xml' inside the script's current directory.

.PARAMETER Recursive
    A switch modifier. If present, the script recursively scans all files and subfolders 
    underneath each share to grab explicit permissions. If absent, only the root share 
    folders are scanned.

.EXAMPLE
    .\01_ExportSharePermsConfig.ps1
    Runs a fast scan capturing ONLY the top-level root folder permissions for each share.

.EXAMPLE
    .\01_ExportSharePermsConfig.ps1 -Recursive
    Runs a deep scan, recursively capturing permissions for every file and folder inside the shares.

.EXAMPLE
    .\01_ExportSharePermsConfig.ps1 -File "C:\MigrationBackup\ServerPermissions.xml" -Recursive
    Performs a deep recursive scan and saves the output to a specific custom file path.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$File,

    [Parameter(Mandatory = $false)]
    [switch]$Recursive
)

# If no file path is provided, default to the script's current directory with the hostname prefix
if ([string]::IsNullOrWhiteSpace($File)) {
    $CurrentDir = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
    $Hostname = $env:COMPUTERNAME
    $OutputFile = Join-Path $CurrentDir "${Hostname}_sharePermissions.xml"
} else {
    $OutputFile = $File
}

Write-Host "=========================================================" -ForegroundColor Gray
Write-Host " STARTING SHARE CONFIGURATION & PERMISSIONS EXPORT" -ForegroundColor White -BackgroundColor DarkBlue
Write-Host "=========================================================" -ForegroundColor Gray
Write-Host "Target Output File: $OutputFile" -ForegroundColor Yellow
if ($Recursive) {
    Write-Host "Scan Mode: DEEP RECURSIVE (Capturing root folders, subfolders, and files)" -ForegroundColor Magenta
} else {
    Write-Host "Scan Mode: TOP-LEVEL ONLY (Capturing root share folders only)" -ForegroundColor Green
}
Start-Sleep -Seconds 1

# Array to hold all ACL data
$AllAcls = @()

# Get all custom shares (excluding default/system admin shares)
$Shares = Get-SmbShare | Where-Object { $_.Special -eq $false -and $_.Name -ne 'NETLOGON' -and $_.Name -ne 'SYSVOL' }

Write-Host "`nFound ($($Shares.Count)) custom shares to process.`n" -ForegroundColor Green

foreach ($Share in $Shares) {
    $ShareName = $Share.Name
    $Path = $Share.Path

    Write-Host "---------------------------------------------------------" -ForegroundColor Gray
    Write-Host " PROCESSING SHARE: [$ShareName]" -ForegroundColor DarkCyan -BackgroundColor White
    Write-Host " Local Path: $Path" -ForegroundColor White

    if (Test-Path $Path) {
        # Initialize an array for this specific iteration's ACLs
        $Acls = @()

        if ($Recursive) {
            Write-Host " -> Scanning entire directory tree and gathering ACLs..." -ForegroundColor DarkGray
            # Get the ACL of all sub-items
            $SubItems = Get-ChildItem -Path $Path -Recurse -ErrorAction SilentlyContinue
            if ($SubItems) { $Acls += $SubItems | Get-Acl }
        } else {
            Write-Host " -> Gathering root folder ACL (Skipping subfolders)..." -ForegroundColor DarkGray
        }
        
        # Always grab the root folder's ACL itself
        $Acls += Get-Acl -Path $Path

        Write-Host " -> Successfully captured ($($Acls.Count)) ACL record(s)." -ForegroundColor Magenta

        foreach ($Acl in $Acls) {
            # Add a custom property so we can easily see which share it belongs to later
            $Acl | Add-Member -NotePropertyName "SourceShare" -NotePropertyValue $ShareName -Force
            $AllAcls += $Acl
        }
    } else {
        Write-Host " [WARNING]: Path '$Path' was not found! Skipping share." -ForegroundColor Yellow
    }
}

Write-Host "---------------------------------------------------------" -ForegroundColor Gray
Write-Host "`nProcessing complete. Finalizing output file..." -ForegroundColor Cyan

# Export everything into a single XML file
if ($AllAcls.Count -gt 0) {
    # Ensure the target directory for the file actually exists
    $TargetDir = Split-Path $OutputFile -Parent
    if ($TargetDir -and -not (Test-Path $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir | Out-Null
    }

    $AllAcls | Export-Clixml -Path $OutputFile
    
    Write-Host "=========================================================" -ForegroundColor Gray
    Write-Host " SUCCESS: Export complete!" -ForegroundColor White -BackgroundColor DarkGreen
    Write-Host " Total ACL Records Saved: $($AllAcls.Count)" -ForegroundColor Green
    Write-Host " Saved to: $OutputFile" -ForegroundColor Yellow
    Write-Host "=========================================================" -ForegroundColor Gray
} else {
    Write-Host "Error: No permissions were gathered." -ForegroundColor Red
}