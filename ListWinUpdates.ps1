
# Lists Windows Update History (Console Output Only)
# Works in Windows PowerShell 5.1 and PowerShell 7+

# Create COM session
$session  = New-Object -ComObject "Microsoft.Update.Session"
$searcher = $session.CreateUpdateSearcher()

Write-Host "Retrieving update history..."
$historyCount = $searcher.GetTotalHistoryCount()
$history = $searcher.QueryHistory(0, $historyCount)

# Mappings for readability
$opMap = @{
    1 = 'Installation'
    2 = 'Uninstallation'
    3 = 'Other'
}
$resultMap = @{
    1 = 'NotStarted'
    2 = 'Succeeded'
    3 = 'SucceededWithErrors'
    4 = 'Failed'
    5 = 'Aborted'
}

# Build objects first to avoid pipeline quirks
$items = foreach ($e in $history) {
    # Extract KB using regex (returns empty string if none)
    $kbMatch = [regex]::Match($e.Title, 'KB\d+')
    $kbVal = if ($kbMatch.Success) { $kbMatch.Value } else { '' }

    # Categories can be null/empty; handle safely
    $categories = @()
    if ($e.Categories) {
        foreach ($c in $e.Categories) {
            if ($c.Name) { $categories += $c.Name }
        }
    }

    # Decode any HTML entities in SupportUrl (e.g., &amp;)
    $supportUrl = $e.SupportUrl
    try {
        Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($supportUrl) -eq $false -and
            [type]::GetType('System.Web.HttpUtility', $false)) {
            $supportUrl = [System.Web.HttpUtility]::HtmlDecode($supportUrl)
        }
    } catch { }

    [PSCustomObject]@{
        Date        = $e.Date
        Title       = $e.Title
        KB          = $kbVal
        Operation   = $opMap[[int]$e.Operation]
        Result      = $resultMap[[int]$e.ResultCode]
        HResult     = ('0x{0:X8}' -f ($e.HResult -band 0xFFFFFFFF))
        SupportUrl  = $supportUrl
        Category    = ($categories -join '; ')
        Description = $e.Description
    }
}

$items | Sort-Object Date -Descending | Format-Table -AutoSize
