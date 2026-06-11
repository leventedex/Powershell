<#
.SYNOPSIS
    Restores NTFS permissions for custom SMB shares from a single consolidated XML file.

.DESCRIPTION
    This script reads a consolidated XML file (generated via CliXml serialization) containing 
    NTFS access control lists (ACLs). It iterates through the recorded paths and reapplies 
    the permissions to the corresponding folders/files on the new server.

.PARAMETER File
    The absolute or relative path to the backup XML file containing the NTFS permissions.
    If this parameter is omitted, the script will interactively prompt the user to input the path.

.EXAMPLE
    .\02_ImportSharePermsConfig.ps1 -File "C:\MigrationBackup\ServerPermissions.xml"
    Runs the restore script pointing directly to the specified XML backup file.

.EXAMPLE
    .\02_ImportSharePermsConfig.ps1
    Runs the script interactively. The script will prompt you to enter the path to your XML file.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$File
)

# Clear the screen for a clean UI presentation
Clear-Host

Write-Host "=========================================================" -ForegroundColor Gray
Write-Host " STARTING SHARE CONFIGURATION & PERMISSIONS IMPORT" -ForegroundColor White -BackgroundColor DarkBlue
Write-Host "=========================================================" -ForegroundColor Gray

# If the -File parameter was not defined, prompt the user for it interactively
if ([string]::IsNullOrWhiteSpace($File)) {
    Write-Host ""
    $InputFile = Read-Host -Prompt "Please enter the full path to the backup XML file (e.g., C:\Backup\All_Share_NTFS_Permissions.xml)"
    Write-Host ""
} else {
    $InputFile = $File
}

# Clean up any accidental wrapping quotes the user might have pasted into the prompt
$InputFile = $InputFile.Trim('"').Trim("'")

if (Test-Path $InputFile) {
    Write-Host "Reading backup file: $InputFile" -ForegroundColor Yellow
    Write-Host "Parsing ACL records... (This may take a moment depending on file size)" -ForegroundColor DarkGray
    
    # Import the permissions collection
    $ImportedAcls = Import-Clixml -Path $InputFile
    
    Write-Host "Found ($($ImportedAcls.Count)) ACL records to restore.`n" -ForegroundColor Green
    Start-Sleep -Seconds 1

    $SuccessCount = 0
    $FailureCount = 0
    $CurrentShare = ""

    foreach ($Acl in $ImportedAcls) {
        # The original path is stored inside the ACL objectProvider notation prefix, strip it out
        $TargetPath = $Acl.Path -replace "Microsoft.PowerShell.Core\\FileSystem::", ""
        
        # Safely extract our custom 'SourceShare' property
        $ShareContext = $Acl.SourceShare
        if ($null -eq $ShareContext) { $ShareContext = "Unknown" }

        # Visual separator when the script moves to a new share group
        if ($ShareContext -ne $CurrentShare) {
            $CurrentShare = $ShareContext
            Write-Host "---------------------------------------------------------" -ForegroundColor Gray
            Write-Host " RESTORING PERMISSIONS FOR SHARE GROUP: [$CurrentShare]" -ForegroundColor DarkCyan -BackgroundColor White
            Write-Host "---------------------------------------------------------" -ForegroundColor Gray
        }

        if (Test-Path $TargetPath) {
            try {
                Write-Host " -> Applying ACL to: $TargetPath" -ForegroundColor Cyan
                Set-Acl -Path $TargetPath -AclObject $Acl -ErrorAction Stop
                $SuccessCount++
            }
            catch {
                Write-Host " [ERROR]: Failed to apply ACL to '$TargetPath'. Reason: $_" -ForegroundColor Red
                $FailureCount++
            }
        } else {
            Write-Host " [WARNING]: Target path '$TargetPath' does not exist. Skipping." -ForegroundColor Yellow
            $FailureCount++
        }
    }
    
    Write-Host "`n---------------------------------------------------------" -ForegroundColor Gray
    Write-Host "Restore processing finalized." -ForegroundColor Cyan
    
    Write-Host "=========================================================" -ForegroundColor Gray
    Write-Host " SUCCESS: Restore operation complete!" -ForegroundColor White -BackgroundColor DarkGreen
    Write-Host " Successfully Restored: $SuccessCount records" -ForegroundColor Green
    if ($FailureCount -gt 0) {
        Write-Host " Skipped/Failed: $FailureCount records (Check warnings/errors above)" -ForegroundColor Yellow
    }
    Write-Host "=========================================================" -ForegroundColor Gray

} else {
    Write-Host "=========================================================" -ForegroundColor Gray
    Write-Host " CRITICAL ERROR: Backup file not found!" -ForegroundColor White -BackgroundColor DarkRed
    Write-Host " Specified Path: $InputFile" -ForegroundColor Yellow
    Write-Host " Please verify the path is correct and try again." -ForegroundColor Red
    Write-Host "=========================================================" -ForegroundColor Gray
}