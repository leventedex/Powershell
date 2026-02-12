# ==========================================
# List ALL Members of Entra ID Group
# Including Nested Groups + Device Primary User
# ==========================================
param(
    [string]$GroupName,
    [switch]$Csv,
    [string]$CsvFileName
)

# Prompt for GroupName if not provided
if ([string]::IsNullOrWhiteSpace($GroupName)) {
    $GroupName = Read-Host "Enter the Entra ID Security Group name"

    if ([string]::IsNullOrWhiteSpace($GroupName)) {
        throw "Group name cannot be empty. Script aborted."
    }
}

Connect-MgGraph -Scopes "Group.Read.All","Directory.Read.All","Device.Read.All"

$group = Get-MgGroup -Filter "displayName eq '$GroupName'"

if (-not $group) {
    Write-Host "Group not found!" -ForegroundColor Red
    return
}

$processedGroups = @()

function Get-GroupMembersRecursive {
    param ($GroupId)

    if ($processedGroups -contains $GroupId) {
        return
    }

    $processedGroups += $GroupId

    $members = Get-MgGroupMember -GroupId $GroupId -All

    foreach ($member in $members) {

        $type = $member.AdditionalProperties.'@odata.type'

        switch ($type) {

            "#microsoft.graph.user" {
                $user = Get-MgUser -UserId $member.Id
                [PSCustomObject]@{
                    Name            = $user.DisplayName
                    Type            = "User"
                    UserPrincipalName = $user.UserPrincipalName
                    PrimaryUser     = ""
                    Id              = $user.Id
                }
            }

            "#microsoft.graph.device" {
                $device = Get-MgDevice -DeviceId $member.Id

                # Get primary user (registered owner)
                $owners = Get-MgDeviceRegisteredOwner -DeviceId $member.Id -All |
                          Where-Object { $_.AdditionalProperties.'@odata.type' -eq "#microsoft.graph.user" }

                $primaryUser = if ($owners) {
                    ($owners | ForEach-Object {
                        (Get-MgUser -UserId $_.Id).UserPrincipalName
                    }) -join ", "
                }
                else {
                    ""
                }

                [PSCustomObject]@{
                    Name            = $device.DisplayName
                    Type            = "Device"
                    UserPrincipalName = ""
                    PrimaryUser     = $primaryUser
                    Id              = $device.Id
                }
            }

            "#microsoft.graph.servicePrincipal" {
                $sp = Get-MgServicePrincipal -ServicePrincipalId $member.Id
                [PSCustomObject]@{
                    Name            = $sp.DisplayName
                    Type            = "ServicePrincipal"
                    UserPrincipalName = ""
                    PrimaryUser     = ""
                    Id              = $sp.Id
                }
            }

            "#microsoft.graph.group" {
                $nestedGroup = Get-MgGroup -GroupId $member.Id

                [PSCustomObject]@{
                    Name            = $nestedGroup.DisplayName
                    Type            = "Group"
                    UserPrincipalName = ""
                    PrimaryUser     = ""
                    Id              = $nestedGroup.Id
                }

                # Recursion
                Get-GroupMembersRecursive -GroupId $member.Id
            }
        }
    }
}

$allMembers = Get-GroupMembersRecursive -GroupId $group.Id
$allMembers = $allMembers | Sort-Object Id -Unique

$allMembers | Format-Table -AutoSize

# ================================
# Optional CSV Export
# ================================

if ($Csv) {

    # Default filename logic
    if ([string]::IsNullOrWhiteSpace($CsvFileName)) {
        $defaultFile = ".\$($GroupName)_members.csv"
    }
    else {
        $defaultFile = $CsvFileName
    }

    Write-Host ""
    $userInput = Read-Host "Enter export filename or press Enter to use default [$defaultFile]"

    if ([string]::IsNullOrWhiteSpace($userInput)) {
        $exportPath = $defaultFile
    }
    else {
        $exportPath = $userInput
    }

    # Ensure .csv extension
    if (-not $exportPath.EndsWith(".csv")) {
        $exportPath = "$exportPath.csv"
    }

    $allMembers | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8

    Write-Host "Exported to $exportPath" -ForegroundColor Green
}
