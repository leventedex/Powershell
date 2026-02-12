# Get-FirewallRules.ps1
# Lists configured Windows Firewall rules and optionally exports to CSV with a single prompt.
# Default CSV: C:\Temp\<hostname>_FirewallRules_<yyyyMMdd_HHmmss>.csv

# --- Config & helpers ---
$timestamp      = Get-Date -Format "yyyyMMdd_HHmmss"
$hostname       = $env:COMPUTERNAME
$defaultDir     = 'C:\Temp'
$defaultFile    = "{0}_FirewallRules_{1}.csv" -f $hostname, $timestamp
$defaultFull    = Join-Path -Path $defaultDir -ChildPath $defaultFile

Write-Host "==== Firewall Rules Report ====" -ForegroundColor Yellow
Write-Host ("Generated: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Write-Host ""

# --- Retrieve firewall rules from Active policy store (current machine state) ---
# You can switch to -PolicyStore PersistentStore if you need persisted rules only.
$rules = Get-NetFirewallRule -PolicyStore ActiveStore | Sort-Object DisplayName

# --- Build a rich dataset by pulling associated filters (ports, addresses, programs, services) ---
$dataset = foreach ($r in $rules) {
    # Attempt to pull associated filters; not all rules have all filter types
    $portFilter  = $null
    $addrFilter  = $null
    $appFilter   = $null
    $svcFilter   = $null

    try { $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $r -ErrorAction SilentlyContinue } catch {}
    try { $addrFilter = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $r -ErrorAction SilentlyContinue } catch {}
    try { $appFilter  = Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $r -ErrorAction SilentlyContinue } catch {}
    try { $svcFilter  = Get-NetFirewallServiceFilter -AssociatedNetFirewallRule $r -ErrorAction SilentlyContinue } catch {}

    # Flatten common fields
    [pscustomobject]@{
        ComputerName   = $hostname
        Name           = $r.Name
        DisplayName    = $r.DisplayName
        Group          = $r.Group
        Enabled        = $r.Enabled
        Direction      = $r.Direction
        Action         = $r.Action
        Profile        = ($r.Profile -join ',')              # Domain, Private, Public
        InterfaceType  = ($r.InterfaceType -join ',')        # Wired, Wireless, RemoteAccess, etc.
        Owner          = $r.Owner
        PolicyStore    = $r.PolicyStore
        Program        = $appFilter.Program
        Service        = $svcFilter.Service
        Protocol       = $portFilter.Protocol
        LocalPort      = ($portFilter.LocalPort   -join ',')
        RemotePort     = ($portFilter.RemotePort  -join ',')
        IcmpType       = ($portFilter.IcmpType    -join ',')
        LocalAddress   = ($addrFilter.LocalAddress  -join ',')
        RemoteAddress  = ($addrFilter.RemoteAddress -join ',')
        # For clarity: Status can be inferred from Enabled + Profile. Explicit Status field is not provided by rule.
        Timestamp      = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
}

# --- Console output (concise table) ---
Write-Host "=== Configured Firewall Rules ===" -ForegroundColor Cyan
$dataset |
    Select-Object DisplayName, Enabled, Direction, Action, Profile, LocalAddress, RemoteAddress, Protocol, LocalPort, RemotePort |
    Format-Table -AutoSize

# --- Prompt: Export to CSV (single input with default full path) ---
Write-Host ""
$doExport = Read-Host "Do you want to export FIREWALL RULES to CSV? (Y/N)"
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
        Write-Host "Exported firewall rules to: $fullPath" -ForegroundColor Green
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