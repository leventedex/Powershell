# Get-OpenPorts.ps1
# Lists open (listening) TCP and UDP ports with owning process, service name mapping,
# interface binding info, and optionally exports to CSV (single prompt).
# Default CSV: C:\Temp\<hostname>_OpenPorts_<yyyyMMdd_HHmmss>.csv

# --- Config & helpers ---
$timestamp   = Get-Date -Format "yyyyMMdd_HHmmss"
$hostname    = $env:COMPUTERNAME
$defaultDir  = 'C:\Temp'
$defaultFile = "{0}_OpenPorts_{1}.csv" -f $hostname, $timestamp
$defaultFull = Join-Path -Path $defaultDir -ChildPath $defaultFile

# Common well-known ports mapping (extend as needed)
# Separate mappings for TCP and UDP where relevant
$WellKnownTcp = @{
    20='FTP-Data'; 21='FTP'; 22='SSH'; 23='Telnet'; 25='SMTP'; 53='DNS'; 67='DHCP-Server'; 68='DHCP-Client';
    69='TFTP'; 80='HTTP'; 88='Kerberos'; 110='POP3'; 123='NTP'; 135='MS-RPC'; 137='NetBIOS-Name'; 138='NetBIOS-Datagram'; 139='NetBIOS-Session';
    143='IMAP'; 161='SNMP'; 162='SNMP-Trap'; 389='LDAP'; 443='HTTPS'; 445='SMB'; 465='SMTPS'; 500='ISAKMP';
    514='Syslog'; 587='SMTP-Submission'; 636='LDAPS'; 993='IMAPS'; 995='POP3S'; 1433='MSSQL'; 1521='Oracle-TNS';
    1723='PPTP'; 1883='MQTT'; 1900='SSDP'; 3306='MySQL'; 3389='RDP'; 5432='PostgreSQL';
    5671='AMQP-TLS'; 5672='AMQP'; 5900='VNC'; 5985='WinRM-HTTP'; 5986='WinRM-HTTPS'; 6379='Redis';
    6443='Kubernetes-API'; 8080='HTTP-Alt'; 8443='HTTPS-Alt'
}
$WellKnownUdp = @{
    53='DNS'; 67='DHCP-Server'; 68='DHCP-Client'; 69='TFTP'; 88='Kerberos'; 123='NTP'; 137='NetBIOS-Name';
    138='NetBIOS-Datagram'; 161='SNMP'; 162='SNMP-Trap'; 1900='SSDP'; 500='ISAKMP'; 514='Syslog'; 51820='WireGuard'
}

function Resolve-ServiceName {
    param(
        [ValidateSet('TCP','UDP')][string]$Protocol,
        [int]$Port
    )
    if ($Protocol -eq 'TCP' -and $WellKnownTcp.ContainsKey($Port)) { return $WellKnownTcp[$Port] }
    if ($Protocol -eq 'UDP' -and $WellKnownUdp.ContainsKey($Port)) { return $WellKnownUdp[$Port] }
    return 'Unknown'
}

# Build a lookup of IP -> interface info for fast binding resolution
$ipIndex = @{}
try {
    $ipList = Get-NetIPAddress -ErrorAction Stop
    foreach ($ip in $ipList) {
        # Some systems may have duplicate IPs across contexts; last write wins (acceptable for display)
        $ipIndex[$ip.IPAddress] = [pscustomobject]@{
            InterfaceIndex   = $ip.InterfaceIndex
            InterfaceAlias   = $ip.InterfaceAlias
            AddressFamily    = if ($ip.AddressFamily -eq 23) { 'IPv4' } elseif ($ip.AddressFamily -eq 2) { 'IPv6' } else { 'Unknown' }
        }
    }
} catch {
    Write-Host "Warning: Failed to query local IP addresses. Interface binding info may be incomplete. $($_.Exception.Message)" -ForegroundColor DarkYellow
}

function Get-ProcessNameSafe {
    param([int]$ProcessId)
    try {
        (Get-Process -Id $ProcessId -ErrorAction Stop).ProcessName
    } catch {
        $null
    }
}

function Get-BindingInfo {
    param([string]$LocalAddress)

    if ([string]::IsNullOrWhiteSpace($LocalAddress)) {
        return [pscustomobject]@{
            BindScope       = 'Unknown'
            AddressFamily   = 'Unknown'
            InterfaceAlias  = $null
            InterfaceIndex  = $null
            IsLoopback      = $false
        }
    }

    # Determine address family
    $isIPv6 = $LocalAddress -like '*:*'
    $family = if ($isIPv6) { 'IPv6' } else { 'IPv4' }

    # Special bindings
    if ($LocalAddress -in @('0.0.0.0','::')) {
        return [pscustomobject]@{
            BindScope       = 'All'
            AddressFamily   = $family
            InterfaceAlias  = 'All (Any)'
            InterfaceIndex  = $null
            IsLoopback      = $false
        }
    }
    if ($LocalAddress -in @('127.0.0.1','::1')) {
        return [pscustomobject]@{
            BindScope       = 'Loopback'
            AddressFamily   = $family
            InterfaceAlias  = 'Loopback'
            InterfaceIndex  = $null
            IsLoopback      = $true
        }
    }

    # Specific interface binding
    if ($ipIndex.ContainsKey($LocalAddress)) {
        $info = $ipIndex[$LocalAddress]
        return [pscustomobject]@{
            BindScope       = 'Specific'
            AddressFamily   = $info.AddressFamily
            InterfaceAlias  = $info.InterfaceAlias
            InterfaceIndex  = $info.InterfaceIndex
            IsLoopback      = $false
        }
    }

    # Fallback when IP isn't on local interface list (e.g., transient or scope-limited addresses)
    [pscustomobject]@{
        BindScope       = 'Specific (unresolved)'
        AddressFamily   = $family
        InterfaceAlias  = $null
        InterfaceIndex  = $null
        IsLoopback      = $false
    }
}

Write-Host "==== Open Ports Report ====" -ForegroundColor Yellow
Write-Host ("Generated: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
Write-Host ""

# --- Collect listening TCP ports ---
$tcpListening = @()
try {
    $tcpListening = Get-NetTCPConnection -State Listen -ErrorAction Stop
} catch {
    Write-Host "Warning: Failed to query TCP connections. $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# --- Collect UDP endpoints ---
$udpEndpoints = @()
try {
    $udpEndpoints = Get-NetUDPEndpoint -ErrorAction Stop
} catch {
    Write-Host "Warning: Failed to query UDP endpoints. $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# --- Build unified dataset with service names and binding info ---
$dataset = New-Object System.Collections.Generic.List[object]

foreach ($t in $tcpListening) {
    $procName   = Get-ProcessNameSafe -ProcessId ([int]$t.OwningProcess)
    $service    = Resolve-ServiceName -Protocol 'TCP' -Port ([int]$t.LocalPort)
    $binding    = Get-BindingInfo -LocalAddress $t.LocalAddress

    $dataset.Add([pscustomobject]@{
        ComputerName    = $hostname
        Protocol        = 'TCP'
        LocalAddress    = $t.LocalAddress
        LocalPort       = [int]$t.LocalPort
        ServiceName     = $service
        RemoteAddress   = $t.RemoteAddress
        RemotePort      = $t.RemotePort
        State           = $t.State
        OwningProcess   = [int]$t.OwningProcess
        ProcessName     = $procName
        BindScope       = $binding.BindScope
        AddressFamily   = $binding.AddressFamily
        InterfaceAlias  = $binding.InterfaceAlias
        InterfaceIndex  = $binding.InterfaceIndex
        IsLoopback      = $binding.IsLoopback
        Timestamp       = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    })
}

foreach ($u in $udpEndpoints) {
    $procName   = Get-ProcessNameSafe -ProcessId ([int]$u.OwningProcess)
    $service    = Resolve-ServiceName -Protocol 'UDP' -Port ([int]$u.LocalPort)
    $binding    = Get-BindingInfo -LocalAddress $u.LocalAddress

    $dataset.Add([pscustomobject]@{
        ComputerName    = $hostname
        Protocol        = 'UDP'
        LocalAddress    = $u.LocalAddress
        LocalPort       = [int]$u.LocalPort
        ServiceName     = $service
        RemoteAddress   = $null
        RemotePort      = $null
        State           = 'Listen'
        OwningProcess   = [int]$u.OwningProcess
        ProcessName     = $procName
        BindScope       = $binding.BindScope
        AddressFamily   = $binding.AddressFamily
        InterfaceAlias  = $binding.InterfaceAlias
        InterfaceIndex  = $binding.InterfaceIndex
        IsLoopback      = $binding.IsLoopback
        Timestamp       = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    })
}

# --- Console output (with service + binding info) ---
Write-Host "=== Listening TCP Ports ===" -ForegroundColor Cyan
$dataset |
    Where-Object { $_.Protocol -eq 'TCP' } |
    Sort-Object LocalPort |
    Select-Object LocalAddress, LocalPort, ServiceName, State, InterfaceAlias, BindScope, OwningProcess, ProcessName |
    Format-Table -AutoSize

Write-Host "`n=== UDP Endpoints ===" -ForegroundColor Cyan
$dataset |
    Where-Object { $_.Protocol -eq 'UDP' } |
    Sort-Object LocalPort |
    Select-Object LocalAddress, LocalPort, ServiceName, InterfaceAlias, BindScope, OwningProcess, ProcessName |
    Format-Table -AutoSize

# --- Prompt: Export to CSV (single input with default full path) ---
Write-Host ""
$doExport = Read-Host "Do you want to export OPEN PORTS to CSV? (Y/N)"
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
        Write-Host "Exported open ports to: $fullPath" -ForegroundColor Green
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