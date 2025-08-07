<#
.SYNOPSIS
    Script to Update MasterImage of MCS Catalogs
.DESCRIPTION
    This Script updates MasterImageVM of MCS Machine Catalogs. It takes a Text file as an input. Text file should include name of the MCS Machine Catalog that needs update.
    This script currently works for VMware and Nutanix Hypervisors. It should also work for other hypervisors but needs testing.  
.NOTES
    Path of the text file must be valid for this script to run. 
    Script will create a log file, output file and skippped file at the same location as this script. 
.LINK
    Specify a URI to a help page, this will show when Get-Help -Online is used.
.EXAMPLE
    .\UpdateMCSCatalogMasterImageVM.ps1 -inputpath c:\temp\list.txt
    
#>


[CmdletBinding()]
param (
    [Parameter(Mandatory=$true, HelpMessage="Enter a valid path")]
    [validatescript({
        Test-Path $_
    })][string]$inputpath
)

#Start Timer
$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Create a global log file variable with timestamp
$global:LogTimestamp = Get-Date -Format "yyyy_MM_dd_HHmmss"
$global:LogFile = "$PSScriptRoot\Script_$LogTimestamp.log"
$global:OutputFile = "$PSScriptRoot\Imagelist_$LogTimestamp.csv"
$global:Skipped = "$PSScriptRoot\Skipped_$LogTimestamp.csv"
$global:failed = "$PSScriptRoot\failes_$LogTimestamp.csv"

function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logEntry = "[$timestamp] [$Level] $Message"

    # Write to file
    try {
        Add-Content -Path $global:LogFile -Value $logEntry
    } catch {
        Write-Error "Failed to write to log file: $global:LogFile"
    }

    # Write to console with color
    switch ($Level) {
        "INFO"  { Write-Host $logEntry -ForegroundColor Cyan }
        "WARN"  { Write-Host $logEntry -ForegroundColor Yellow }
        "ERROR" { Write-Host $logEntry -ForegroundColor Red }
    }
}

#Log who started the script
Write-Log "Script started by $($env:Username)"

#Load Citrix Snapins 
if (-not (Get-PSSnapin -Name Citrix* -ErrorAction SilentlyContinue)) {
    try {
        Add-PSSnapin Citrix* -ErrorAction Stop
        Write-Log "Citrix Snap-in loaded successfully." 
    } catch {
        Write-Log "Failed to load Citrix snap-ins'. $_" -Level ERROR
        exit 1 
    }
} else {
    Write-Log "Citrix Snap-ins already loaded."
}

# Gather Machine Catalogs, Hyperpervisor Connections, Hosting Units, available template info
Write-Log "Getting all Hypervisor Hosting Units"
$allHostingunits = Get-childitem XDHyp:\HostingUnits\*

Write-Log "Getting all Hosting Unit Connections"
$allHostingconnections = $allHostingunits | ForEach-Object {"XDHyp:\HostingUnits\" + $_.HostingUnitName}

Write-log "Getting all available Templates. Please wait...."
$allavailableimages = $allHostingconnections | ForEach-Object {Get-ChildItem $_ | Where-Object {$_.ObjectType -eq 'vm' -or $_.ObjectType -eq 'Template'}}

#Array to track current and new image
$imageshistory = @()

#Array to keep track of skipped catalogs
$skippedcatalogs  = @()

#Array to keep track of failed catalogs
$failedcatalogs  = @()

#function to Extract Date and time from Template VMs
function Get-DateFromString($str) {
    if ($str -match '\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.\d{3}') {
        return [datetime]::ParseExact($matches[0], 'yyyy-MM-dd_HH-mm-ss.fff', $null)
    }
    return $null
}

#Function to Grab the image similar with MasterImage VM
function Get-LatestMatchingImage {
    param (
        [string]$CurrentImage,
        [string[]]$AllImages
    )

    # Extract HostingUnitRoot
    if ($CurrentImage -match '^(XDHyp:\\HostingUnits\\[^\\]+\\)') {
        $hostingUnitRoot = $matches[1]
    } else {
        $null
    }

    # Extract ImageBaseName
    if ($CurrentImage -match '\\([^\\]+)-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.\d{3}\.vm\\') {
        $imageBaseName = $matches[1]
    } else {
        return $null
    }

    # Filter all matching entries
    $matching = $AllImages | Where-Object {$_ -like "$hostingUnitRoot*" -and $_ -like "*$imageBaseName*"}

    if (-not $matching) {
        return $null
    }

    # Sort by date and get the latest one
    $latest = $matching | Sort-Object { Get-DateFromString $_ } -Descending | Select-Object -First 1
    return $latest
}

#Get List of all Catalogs from Input File
$catalogs = Get-content $inputpath

#Actual Code to update the Masterimage
#Loop through the list
foreach ($catalog in $catalogs) {
    Write-Log "Working on ""$catalog"" Machine Catalog"
    try {
        $mc = Get-provscheme -ProvisioningSchemeName $catalog -ErrorAction Stop        
    }
    catch {
        #Write-Log $_.Exception.message -Level ERROR
        Write-log "Unable to find ""$catalog"". $($_.Exception.Message)" -Level ERROR
        $skippedcatalogs += $catalog
        continue
    }

    #Extract MasterImage VM Base Name
    if ($mc.MasterImageVM -match '\\([^\\]+?)-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.\d{3}') {
            $baseName = $matches[1]
    }

    Write-Log "Gathering all available images with base name ""$basename"""
    $allimages = $allavailableimages.Fullpath -match $baseName
    
    if($null -ne $allimages){
        
        $vmimage = Get-LatestMatchingImage -CurrentImage $mc.MasterImageVM -AllImages $allimages

        if($mc.MasterImageVM -like "*Layered Image Deployed.snapshot*"){
            $latestvmimage = $vmimage + "\Layered Image Deployed.snapshot"
        }
        else {
            $latestvmimage = $vmimage
        }
        Write-Log "latest image is ""$latestvmimage"""
    }else {
        Write-Log "No Images found with base name ""$basename""." -Level WARN
        #Exit 1
    }

    if ($latestvmimage -ne $mc.MasterImageVM){
        Write-Log "Latest image is available for Machine Catalog ""$catalog"""
        Write-Log "Applying latest image ""$latestvmimage"""
        try {
            $publishimage = Publish-ProvMasterVMImage -ProvisioningSchemeName $catalog -MasterImageVM $latestvmimage -MasterImageNote "$LogTimestamp Image applied by Script" -RunAsynchronously
            Write-Log "Image is published with TaskID ""$publishimage.Taskid"""
        }
        catch {
            Write-Log "Failed to apply latest image for $mc. $_"
        }

        #PSCustomobject to store Machine Catalog and its image information
        $obj = [PSCustomObject]@{
            MachineCatalog = $catalog
            DateStarted = $publishimage.DateStarted
            CurrentImage = $mc.MasterImageVM
            LatestImage = $latestvmimage
            PublishImageTask = $publishimage.Guid
        }
        $imageshistory += $obj

    }else {
        Write-Log "No Update for ""$catalog"". Current Masterimage is same as Latest Master Image" -Level WARN
    }   
}

if ($skippedCatalogs.Count -gt 0) {
    Write-Log "List to SKIPPED Catalogs are exported to $PSScriptRoot" -Level WARN
    $skippedCatalogs | Export-Csv -Path $skipped -NoTypeInformation
}

if ($imageshistory.Count -gt 0) {
    $imageshistory | Format-Table
    Write-Log "List of updated Machine Catalog is exported to $PSScriptRoot"
    $imageshistory | Export-Csv $outputfile -NoTypeInformation
} else {
    Write-Log "No Machine Catalogs were updated" -Level WARN
}

$Stopwatch.Stop()
Write-Log "Script Completed in $([Math]::Round($Stopwatch.Elapsed.TotalMinutes, 2)) minutes"

