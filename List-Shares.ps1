# Get-SharesAndPermissions.ps1
# Lists all SMB shares and their access rights (share-level + NTFS).
# Optionally exports to CSV via a single prompt.
# Default CSV: C:\Temp\<hostname>_Shares_<yyyyMMdd_HHmmss>.csv

# --- Config & helpers ---
$timestamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$hostname    = $env:COMPUTERNAME
$defaultDir  = 'C:\Temp'
$defaultFile = "{0}_Shares_{1}.csv" -f $hostname, $timestamp
$defaultFull = Join-Path -Path $defaultDir -ChildPath $defaultFile

Write-Host "==== SMB Shares & Permissions Report ====" -ForegroundColor Yellow
Write-Host ("Generated: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Write-Host ""

# --- Retrieve all SMB shares ---
try {
    $shares = Get-SmbShare -ErrorAction Stop | Sort-Object Name
} catch {
    Write-Host "ERROR: Failed to enumerate SMB shares. $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# --- Helper: safe ACL retrieval for NTFS ---
function Get-NTFSPermissionsSafe {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return @() }
    if (-not (Test-Path -LiteralPath $Path)) { return @() }

    try {
        $acl = Get-Acl -LiteralPath $Path
        return $acl.Access
    } catch {
        # Access may be denied or path inaccessible
        return @()
    }
}

# --- Build unified dataset: one row per permission entry (share or NTFS) ---
$dataset = New-Object System.Collections.Generic.List[object]

foreach ($s in $shares) {
    # Derive flags and safe share type
    $isHidden   = $s.Name.EndsWith('$')
    $shareType  = $s.ShareType
    if (-not $shareType) { $shareType = if ($s.Path) { 'FileSystem' } else { 'Special' } }

    # --- Share-level permissions ---
    $sharePerms = @()
    try {
        $sharePerms = Get-SmbShareAccess -Name $s.Name -ErrorAction Stop
    } catch {
        Write-Host "Warning: Could not read share permissions for '$($s.Name)'. $($_.Exception.Message)" -ForegroundColor DarkYellow
    }

    foreach ($p in $sharePerms) {
        $dataset.Add([pscustomobject]@{
            ComputerName      = $hostname
            ShareName         = $s.Name
            Path              = $s.Path
            Description       = $s.Description
            ShareType         = $shareType
            IsHidden          = $isHidden
            AccessSource      = 'Share'                  # Share-level ACL
            Principal         = $p.AccountName
            AccessControlType = $p.AccessControlType     # Allow / Deny
            Rights            = $p.AccessRight           # Full / Change / Read
            IsInherited       = $null                    # Not applicable for share ACL
            Timestamp         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        })
    }

    # --- NTFS permissions on backing folder (if applicable) ---
    if ($s.Path) {
        $ntfsRules = Get-NTFSPermissionsSafe -Path $s.Path
        foreach ($r in $ntfsRules) {
            $dataset.Add([pscustomobject]@{
                ComputerName      = $hostname
                ShareName         = $s.Name
                Path              = $s.Path
                Description       = $s.Description
                ShareType         = $shareType
                IsHidden          = $isHidden
                AccessSource      = 'NTFS'                 # Filesystem ACL
                Principal         = $r.IdentityReference.ToString()
                AccessControlType = $r.AccessControlType   # Allow / Deny
                Rights            = $r.FileSystemRights.ToString()
                IsInherited       = $r.IsInherited
                Timestamp         = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            })
        }
    }
}

# --- Console output: concise tables ---
Write-Host "=== SMB Share Permissions ===" -ForegroundColor Cyan
$dataset |
    Where-Object { $_.AccessSource -eq 'Share' } |
    Select-Object ShareName, Path, Principal, Rights, AccessControlType, IsHidden |
    Sort-Object ShareName, Principal |
    Format-Table -AutoSize

Write-Host "`n=== NTFS Permissions (Share Paths) ===" -ForegroundColor Cyan
$dataset |
    Where-Object { $_.AccessSource -eq 'NTFS' } |
    Select-Object ShareName, Path, Principal, Rights, AccessControlType, IsInherited |
    Sort-Object ShareName, Principal |
    Format-Table -AutoSize

# --- Prompt: Export to CSV (single input with default full path) ---
Write-Host ""
$doExport = Read-Host "Do you want to export SHARE & NTFS permissions to CSV? (Y/N)"
if ($doExport -match '^(Y|y)$') {
    $inputPath = Read-Host "Enter full path and filename for CSV (default: $defaultFull)"
    $fullPath  = if ([string]::IsNullOrWhiteSpace($inputPath)) { $defaultFull } else { $inputPath }

    # Ensure directory exists (create if needed)
    try {
        $targetDir = Split-Path -Path $fullPath -Parent
        if (-not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            Write-Host "Created directory: $targetDir" -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "ERROR: Could not ensure directory for '$fullPath'. $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }

    # Ensure .csv extension
    if (-not ($fullPath.ToLower().EndsWith(".csv"))) {
        $fullPath = "$fullPath.csv"
    }

    try {
        $dataset | Export-Csv -Path $fullPath -NoTypeInformation -Encoding UTF8
        Write-Host "Exported shares & permissions to: $fullPath" -ForegroundColor Green
    }
    catch {
        Write-Host "ERROR: Failed to export CSV. $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "Skipped CSV export." -ForegroundColor DarkGray
}

Write-Host "`nDone."