# Run this script with parameters
#.\entra_Remove_devices2Groupfromcsv.ps1 -File "C:\temp\devices.csv" -GroupName "My Device Group"
# If a parameter is not provided the script will prompt for the values
#------------------------------------------------------------------------------------------------------
param(
    [Parameter(Mandatory = $false)]
    [string]$File,

    [Parameter(Mandatory = $false)]
    [string]$GroupName
)

# Ensure Graph SDK is installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Write-Host "Installing Microsoft.Graph SDK..." -ForegroundColor Yellow
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}

# Import only the submodules we need
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Identity.DirectoryManagement  # for Get-MgDevice

# Prompt for missing parameters
if (-not $File) {
    $File = Read-Host "Enter path to CSV file (headerless, one device name per line)"
}

if (-not $GroupName) {
    $GroupName = Read-Host "Enter Entra ID Group Name"
}

# Validate file exists
if (-not (Test-Path $File)) {
    Write-Host "ERROR: File not found at '$File'" -ForegroundColor Red
    exit 1
}

# Connect to Graph if not already connected
if (-not (Get-MgContext)) {
    # Directory.Read.All allows reading devices; Group.ReadWrite.All allows removal from groups
    Connect-MgGraph -Scopes "Group.ReadWrite.All","Directory.Read.All"
}

# --- Read headerless single-column CSV safely ---
$devices = Get-Content -Path $File -Encoding UTF8 `
    | ForEach-Object { ($_ | Out-String).Trim() } `
    | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } `
    | Select-Object -Unique

if (-not $devices -or $devices.Count -eq 0) {
    Write-Host "ERROR: No device names found in file after trimming." -ForegroundColor Red
    exit 1
}

Write-Host "Loaded $($devices.Count) device name(s) from file." -ForegroundColor Cyan

# Retrieve the group
$escapedGroupName = $GroupName.Replace("'", "''")
$group = Get-MgGroup -Filter ("displayName eq '{0}'" -f $escapedGroupName) -ErrorAction SilentlyContinue

if (-not $group) {
    Write-Host "ERROR: Group '$GroupName' not found in Entra ID." -ForegroundColor Red
    exit 1
}

Write-Host "Processing device removals for group: $GroupName" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------"

$results = @()

foreach ($deviceNameRaw in $devices) {

    # Sanitize device name
    $deviceName = $deviceNameRaw.ToString().Trim()

    if ([string]::IsNullOrWhiteSpace($deviceName)) {
        Write-Host "Skipping empty or invalid row..." -ForegroundColor Yellow
        continue
    }

    # Escape single quotes for OData filter
    $deviceNameEsc = $deviceName.Replace("'", "''")

    # Find device by displayName
    $device = Get-MgDevice -Filter ("displayName eq '{0}'" -f $deviceNameEsc) -ErrorAction SilentlyContinue

    if (-not $device) {
        Write-Host "$deviceName : Device not found" -ForegroundColor Yellow
        $results += [pscustomobject]@{
            Device  = $deviceName
            Status  = "Missing"
            Details = "Device not found in Entra ID"
        }
        continue
    }

    # Attempt to remove device from group using the correct cmdlet
    try {
        Remove-MgGroupMemberByRef -GroupId $group.Id -DirectoryObjectId $device.Id -ErrorAction Stop
        Write-Host "$deviceName : Removed from group $GroupName" -ForegroundColor Green

        $results += [pscustomobject]@{
            Device  = $deviceName
            Status  = "Removed"
            Details = "Success"
        }
    }
    catch {
        $errorMsg = $_.Exception.Message

        # Common "not a member" indicators from Graph API errors
        $notMemberPatterns = @(
            'One or more removed object references do not exist',
            'Resource.*does not exist',
            'does not exist or one of its queried reference-property objects are not present',
            'Not Found'
        )
        $isNotMember = $false
        foreach ($p in $notMemberPatterns) {
            if ($errorMsg -match $p) { $isNotMember = $true; break }
        }

        if ($isNotMember) {
            Write-Host "$deviceName : Not a member of group $GroupName" -ForegroundColor Yellow
            $results += [pscustomobject]@{
                Device  = $deviceName
                Status  = "NotMember"
                Details = "Device is not a member of the group"
            }
        }
        else {
            Write-Host "$deviceName : Failed to remove from group ($errorMsg)" -ForegroundColor Red
            $results += [pscustomobject]@{
                Device  = $deviceName
                Status  = "Failed"
                Details = $errorMsg
            }
        }
    }
}

Write-Host "`n================= SUMMARY TABLE =================" -ForegroundColor Cyan
$results | Format-Table -AutoSize
Write-Host "=================================================`n" -ForegroundColor Cyan