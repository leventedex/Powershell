[CmdletBinding()]
param (
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$InputFile = "hosts.txt",

    [Parameter(Mandatory = $false)]
    [Alias("file")]
    [string]$ExportFile
)

# Verify input file exists
if (-not (Test-Path -Path $InputFile)) {
    Write-Error "Input file '$InputFile' was not found."
    return
}

# Read hosts and strip blank lines or trailing spaces
$hosts = Get-Content -Path $InputFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() }

if ($hosts.Count -eq 0) {
    Write-Warning "No hosts found in '$InputFile'."
    return
}

# Initialize ping object compatible with Windows PowerShell 5.1 & PowerShell Core
$ping = New-Object System.Net.NetworkInformation.Ping

$results = foreach ($targetHost in $hosts) {
    $status = "Offline"
    $ipAddress = "N/A"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Attempt DNS Resolution to retrieve IP address
    try {
        $dnsResult = [System.Net.Dns]::GetHostAddresses($targetHost) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1
        if ($dnsResult) {
            $ipAddress = $dnsResult.IPAddressToString
        }
    }
    catch {
        $ipAddress = "DNS Resolution Failed"
    }

    # Ping host using .NET System.Net.NetworkInformation.Ping (1000 ms timeout)
    try {
        $pingReply = $ping.Send($targetHost, 1000)
        if ($pingReply.Status -eq "Success") {
            $status = "Online"
            # If DNS resolution failed earlier but ping succeeded, grab IP from reply
            if ($ipAddress -eq "DNS Resolution Failed" -and $pingReply.Address) {
                $ipAddress = $pingReply.Address.IPAddressToString
            }
        }
    }
    catch {
        $status = "Offline"
    }

    # Display real-time output in console
    $statusColor = if ($status -eq "Online") { "Green" } else { "Red" }
    Write-Host ("[{0}] {1,-20} - IP: {2,-15} - Status: " -f $timestamp, $targetHost, $ipAddress) -NoNewline
    Write-Host $status -ForegroundColor $statusColor

    # Pass custom object to pipeline
    [PSCustomObject]@{
        hostname = $targetHost
        ip       = $ipAddress
        status   = $status
        datetime = $timestamp
    }
}

# Export results to CSV if requested
if ($ExportFile) {
    try {
        $results | Export-Csv -Path $ExportFile -NoTypeInformation -Encoding UTF8
        Write-Host "`nResults successfully exported to: $ExportFile" -ForegroundColor Cyan
    }
    catch {
        Write-Error "Failed to export results to '$ExportFile': $_"
    }
}