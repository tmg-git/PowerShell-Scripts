#This script will query All Shared Folder, its Admin, last modification date and export it into CSV

clear-host
$stopwatch = [System.Diagnostics.Stopwatch]::new()

Add-PSSnapin ShareFile

################################################################################
# This script will list 1 level down subfolders from Root Shared Folder and get its size and type (Folder of File)
# Notes: Script should be run as a super user or user who has access to all shared

$sfAuthPath = "$env:LOCALAPPDATA\SFClient-new3.sfps"

#Check if authentication file exist
if (!(Test-Path $sfAuthPath)){
    New-SFClient -Name $sfAuthPath
}

$sfClient = Get-SfClient -Name $sfAuthPath
#All Shared-Folder Including Root
$Items = Send-SfRequest $sfClient -Method GET -Entity Items -Id "allshared" -Expand "Children,Owner"

$array = [System.Collections.Generic.List[Object]]::new()
Write-Output "Please wait Script is running...."
Write-Output ""
Write-Output ""

#Get the API URL 
$uri = $sfClient.PrimaryDomain.Uri
$bearertoken = $sfClient.PrimaryDomain.OAuthToken

foreach ($item in $Items.Children) {
    <#
    This will check all Shared Folders including the folders of the user who are no longer with the company. 
    You may want to exclude @yourcompanyname that way script won't query the folders of the user who are no longer with the company.
    #>
    #Replace *@yourcompanyname.com* with your company name
    if($item.FileName -notlike '*@yourcompanyname.com*'){
        #Get id of SubFolder
        $id = $item.Id
        Write-Output "Working on $($item.FileName)" 
        $subFolder = Send-SfRequest -Client $sfClient -Method GET -Entity Items -Id $id -Expand "Children,Owner" 
       
        foreach ($child in $subFolder.children) {
            $folderid = $child.Id
            $folderurl = $uri +  "/items($folderid)/AccessControls"
            $response = Invoke-RestMethod -Uri $folderurl -Method Get -Headers @{Authorization = "Bearer $bearertoken"}

            if(!($null -eq $response.value.principal)){
                $adminemails = ($response.value.principal.id | ForEach-Object {(Send-SfRequest -Client $sfClient -Method GET -Entity Users -Id $_ -ErrorAction SilentlyContinue).Email}) -join ','
            }else {
                $adminemails = ""
            } 
            
            $obj = [PSCustomObject]@{
                RootFolderName = $item.FileName
                RootFolderPath = $item.Path
                SubFolderName = $child.Name
                SubFolderPath = $child.Path
                FileCount = $child.FileCount 
                SizeinGB = $([math]::Round((($child.FileSizeInKB)/(1024*1024)),4)) 
                AdminEmails =$adminemails
                LastActivity = $child.ProgeneyEditDate
            }
            $array += $obj
        }
    }
}
#$array | Format-Table
$array | Export-Csv ("$env:LOCALAPPDATA\" + "Folders-Admins-" + (Get-Date -Format yyyy-MM-dd) + ".csv") -NoTypeInformation
$stopwatch.Stop()
Write-Output "Script Completed in $($stopwatch.Elapsed.TotalMinutes) Minutes"
