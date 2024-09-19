
clear-host
$stopwatch = [System.Diagnostics.Stopwatch]::new()

#If you don't have ShareFile PowerShell installed then you can download it from here (https://github.com/citrix/ShareFile-PowerShell)
#Load ShareFile Modules
Add-PSSnapin Sharefile

#Define authentication file location
$sfAuthPath = "$env:LOCALAPPDATA\SFClient-new3.sfps"

#Check if authentication file exist
if (!(Test-Path $sfAuthPath)){
    New-SFClient -Name $sfAuthPath
}

$sfClient = Get-SfClient -Name $sfAuthPath

#Send GET request to shareFile and store it into a variable.
$clients = Send-SfRequest $sfClient -Method GET -Entity Accounts/clients
$ErrorActionPreference = 'SilentlyContinue'

#Arraylist
$result = [System.Collections.Generic.List[Object]]::new()

Write-Host "Checking the user list as requested, please stand by."

foreach($sfUser in $clients)
{
    $sfSelect = Send-SfRequest -Client $sfClient -Entity Users -Id $sfUser.Id -Expand Security
   
    $obj = [PSCustomObject]@{
        FullName = $sfSelect.FullName
        Email_ID = $sfSelect.Email 
        User_Id = $sfSelect.Id
        Company = $sfSelect.Company
        Last_Login = $sfSelect.Security.LastAnyLogin 
    }
    [void]$result.Add($obj)    
}

$result | Export-csv  -Path ("$env:LOCALAPPDATA\AllClientsList-" + (Get-Date -Format yyyy-MM-dd-ss) + ".csv") -NoTypeInformation 
$stopwatch.Stop()
Write-Output "Script Completed in $($stopwatch.Elapsed.TotalMinutes) Minutes"

