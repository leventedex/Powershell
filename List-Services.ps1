# Get-SystemStatus.ps1
# Lists running services and processes. Optionally exports running services to CSV.
# Default path+filename when left blank: C:\Temp\<hostname>_Services_<yyyyMMdd_HHmmss>.csv

# --- Config & helpers ---
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$hostname  = $env:COMPUTERNAME
$defaultDir = 'C:\Temp'
$defaultFileName = "{0}_Services_{1}.csv" -f $hostname, $timestamp
$defaultFullPath = Join-Path -Path $defaultDir -ChildPath $defaultFileName

Write-Host "==== System Status Report ====" -ForegroundColor Yellow
Write-Host ("Generated: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Write-Host ""

# --- Running Services (console) ---
Write-Host "=== Running Services ===" -ForegroundColor Cyan
$runningServices = Get-Service | Where-Object { $_.Status -eq "Running" } | Sort-Object DisplayName
$runningServices |
    Select-Object DisplayName, Status, ServiceName |
    Format-Table -AutoSize

# --- Running Processes (console) ---
Write-Host "`n=== Running Processes ===" -ForegroundColor Cyan
try {
    Get-Process |
        Sort-Object CPU -Descending |
        Select-Object ProcessName, Id, CPU, WS, StartTime |
        Format-Table -AutoSize
}
catch {
    Get-Process |
        Sort-Object CPU -Descending |
        Select-Object ProcessName, Id, CPU, WS |
        Format-Table -AutoSize
}

# --- Prompt: Export running services to CSV (single prompt with default full path) ---
Write-Host ""
$doExport = Read-Host "Do you want to export RUNNING SERVICES to CSV? (Y/N)"
if ($doExport -match '^(Y|y)$') {

    # Show default path+filename and allow user to override in a single input
    $inputPath = Read-Host "Enter full path and filename for CSV (default: $defaultFullPath)"
    if ([string]::IsNullOrWhiteSpace($inputPath)) {
        $fullPath = $defaultFullPath
    } else {
        $fullPath = $inputPath
    }

    # Ensure the directory exists (create if needed)
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

    # Ensure file has .csv extension (if user omitted it)
    if (-not ($fullPath.ToLower().EndsWith(".csv"))) {
        $fullPath = "$fullPath.csv"
    }

    # Resolve StartType via CIM (modern API). Fallback gracefully if query fails.
    $cimServices = @{}
    try {
        $cim = Get-CimInstance -ClassName Win32_Service -ErrorAction Stop
        foreach ($svc in $cim) {
            $cimServices[$svc.Name] = $svc.StartMode
        }
    }
    catch {
        Write-Host "Warning: Could not query StartMode via CIM. StartType will be blank." -ForegroundColor DarkYellow
    }

    # Prepare clean export dataset
    $exportData = $runningServices | ForEach-Object {
        [pscustomobject]@{
            ComputerName             = $hostname
            DisplayName              = $_.DisplayName
            ServiceName              = $_.ServiceName
            Status                   = $_.Status
            StartType                = $(if ($cimServices.ContainsKey($_.ServiceName)) { $cimServices[$_.ServiceName] } else { $null })
            DependentServicesCount   = ($_.DependentServices | Measure-Object).Count
            Timestamp                = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
    }

    try {
        $exportData | Export-Csv -Path $fullPath -NoTypeInformation -Encoding UTF8
        Write-Host "Exported running services to: $fullPath" -ForegroundColor Green
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