# ----------------------------------------------------------
# List Scheduled Tasks with Actions, Library, and CSV Export
# ----------------------------------------------------------

# Get all scheduled tasks
$tasks = Get-ScheduledTask

# Build results
$results = foreach ($task in $tasks) {

    # Get scheduling info (times, last result, etc.)
    $info = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath

    # Extract actions
    $actions = $task.Actions | ForEach-Object {
        [PSCustomObject]@{
            ActionType = $_.ActionType
            Execute    = $_.Execute
            Arguments  = $_.Arguments
            WorkingDir = $_.WorkingDirectory
        }
    }

    # Flatten actions for CSV and table display
    $actionString = ($actions | ForEach-Object {
        "$($_.ActionType): $($_.Execute) $($_.Arguments)"
    }) -join "; "

    # Extract Task Scheduler Library name
    # Examples:
    #   \Microsoft\Windows\Defrag\  -> "Microsoft"
    #   \CustomScripts\            -> "CustomScripts"
    #   \                          -> "Root"
    $library = ($task.TaskPath.Trim("\").Split("\")[0])
    if ([string]::IsNullOrWhiteSpace($library)) { $library = "Root" }

    # Build output object
    [PSCustomObject]@{
        Library        = $library
        TaskName       = $task.TaskName
        TaskPath       = $task.TaskPath
        State          = $task.State
        Author         = $task.Author
        Description    = $task.Description
        LastRunTime    = $info.LastRunTime
        NextRunTime    = $info.NextRunTime
        LastTaskResult = $info.LastTaskResult
        Actions        = $actionString
    }
}

# Display output in console
$results | Format-Table -AutoSize


# ----------------------------------------------------------
# CSV EXPORT PROMPT
# ----------------------------------------------------------

# Get FQDN of the current server
try {
    $FQDN = [System.Net.Dns]::GetHostByName($env:COMPUTERNAME).HostName
}
catch {
    $FQDN = $env:COMPUTERNAME  # Fallback if DNS fails
}

$export = Read-Host "Do you want to export the results to a CSV file? (Y/N)"

if ($export -match '^(Y|y)$') {

    $timestamp = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
    $defaultPath = "C:\Temp\ScheduledTasks_${FQDN}_$timestamp.csv"

    $path = Read-Host "Enter the full path for the CSV file or press ENTER to use:`n$defaultPath"

    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = $defaultPath
    }

    try {
        # Create directory if needed
        $folder = Split-Path $path
        if (!(Test-Path $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }

        # Write CSV
        $results | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
        Write-Host "CSV file successfully created at: $path" -ForegroundColor Green
    }
    catch {
        Write-Host "Error writing CSV file: $_" -ForegroundColor Red
    }
}
else {
    Write-Host "CSV export skipped." -ForegroundColor Yellow
}