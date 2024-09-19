<#
.SYNOPSIS
    This Script will query all employees and SharedFolders in ShareFile and exports FolderSize, File Count to CSV in LocalAppData. 
    User running this script must be ShareFile Admin. 
.DESCRIPTION
    This Script queries all Employees HomeFolder and captures employee name, email, HomeFolder, FileCount, Personal Folder Size and their last login.
    It also queries all Shared Folders and captures Shared Folder ID, Name, File Count and its Size.   
A longer description of the function, its purpose, common use cases, etc.
.NOTES
    Please review the script and run it at your own risk. Always test first.
    This is not a clean script but you can make changes per your needs. 
.LINK
    NA
.EXAMPLE
    .\Get-FolderSize-filecount-allEmployee-AllSharedfolder.ps1
#>

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

$sfClient = Get-SfClient –Name $sfAuthPath

#Send GET request to shareFile and store it into a variable.
$employees = Send-SfRequest $sfClient -Method GET -Entity Accounts/Employees
$ErrorActionPreference = 'SilentlyContinue'

#Arraylist
$result = [System.Collections.Generic.List[Object]]::new()
$failedUsers = [System.Collections.Generic.List[Object]]::new()

#Run look on each Item in $employees variable
foreach ($employee in $employees)
{   
    #Define PSCustomObject to store the data.
    $object = [pscustomobject]@{
        EmployeeName = $null
        Email = $null
        Owner= $null
        HomeFolderPath = $null
        FileCount = $null
        FoldersizeInGB = $null
        Lastlogin = $null
    }

    $EmployeeHomeFolder = $null 
    Write-Host ("Processing Home Folder: {0}" -f $employee.Email)

    #Store Folder ID into a Variable
    $HomeFolderID =  "Users(" + $employee.Id + ")/HomeFolder"

    #Store Last login into a varaible
    $lastlogin = (Send-SfRequest -Client $sfClient -Entity Users -Id $Employee.Id -Expand Security).Security.LastAnyLogin

    #Send GET request to homeFolder ID to get Children/Owner property
    $EmployeeHomeFolder = Send-SfRequest $sfClient -Method GET -Entity $HomeFolderID -Expand 'Children,Owner'
    
    #Update values in PSCustomObject
    if(!($null -eq $EmployeeHomeFolder)){
        $object.EmployeeName = $employee.Name
        $object.Email = $employee.Email
        $object.Owner= $EmployeeHomeFolder.Owner.Email
        $object.HomeFolderPath = $HomeFolderID
        $object.FileCount = $EmployeeHomeFolder.FileCount
        $object.FoldersizeInGB = $([math]::Round((($EmployeeHomeFolder.FileSizeInKB)/(1024*1024)),4))
        $object.Lastlogin = $lastlogin
    }else{
        Write-host "Unable to Find Personal Folder of $($employee.Name)" -ForegroundColor Red
        $object.EmployeeName = $employee.Name
        $object.Email = $employee.Email
        $object.UnabletoFindPath = $HomeFolderID
        $object.Lastlogin = $lastlogin

        $failedUsers.Add($object)
    }
    $result.Add($object)
}

#All Shared-Folder
$Items = Send-SfRequest $sfClient -Method GET -Entity Items -Id "allshared" -Expand "Children,Owner"

$array =[System.Collections.Generic.List[Object]]::new()
foreach ($item in $Items.Children) {
    Write-Host ("Processing Folder: {0}" -f $item.Name)
    $obj = [PSCustomObject]@{
        ID = $item.Id
        Name = $item.FileName
        FileCount = $item.FileCount
        FileSizeinGB = $([math]::Round((($Item.FileSizeInKB)/(1024*1024)),4))
    }
    $array.Add($obj)
}
$array | Export-Csv -Path ("$env:LOCALAPPDATA" + "\AllSharedFolderSize-" + (Get-Date -Format yyyy-MM-dd) + ".csv") -NoTypeInformation
$result | Export-Csv -Path ("$env:LOCALAPPDATA" + "\PersonalFolder-Size-" + (Get-Date -Format yyyy-MM-dd) + ".csv") -NoTypeInformation
$failedUsers | Export-Csv -Path ("$env:LOCALAPPDATA" + "\FailedUser-" + (Get-Date -Format yyyy-MM-dd) + ".csv") -NoTypeInformation

$stopwatch.Stop()

Write-Output "Script Completed in $($stopwatch.Elapsed.TotalMinutes) Minutes"
