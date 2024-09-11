<#
.SYNOPSIS
    Check File path and length and export it into csv
.DESCRIPTION
    Check File path and length and export it into csv
.NOTES
    Information or caveats about the function e.g. 'This function is not supported in Linux'
.LINK
    NA
.EXAMPLE
    .\Get-FilePatchandLength.ps1      
    and enter the path when asked    
#>


Clear-Host
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function get-path {
    Param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({Test-Path $_ })][string]$filepath
    )

    $sharedfolders = Get-ChildItem $filepath
    #Create arraylist, Faster than array as per google.
    $array = [System.Collections.ArrayList]::new()
    foreach ($item in $sharedfolders) {
        
        #Check if the next item is Folder or not.
        if($item.PSIsContainer){
            #Display the 1 level down sub Folder Name 
            Write-Output "Working on $($item.Name)"

            #Uncomment below if the path is longer than 260 (Microsoft Character limitation on Full patch)
            #$newpath = "\\?\"+ $item.Fullname
            
            #Store FullPath in varaible
            $newpath = $item.Fullname

            #You can also use this but slower
            #$a = Get-ChildItem -LiteralPath $newpath -Recurse -Force -ErrorAction SilentlyContinue

            #faster way to enumerate files in a directory . Lots of google, Co-Pilot and ChatGPT mentioned it that's why I added it and it is definitely faster than Get-ChildItem.
            $a = [System.IO.Directory]::EnumerateFiles($newpath, '*', [System.IO.SearchOption]::AllDirectories) 

            #Run a loop on each item
            foreach ($b in $a){
                
                #Change 50  to your desired value
                if($b.Length -ge 50){
                    #Store FullPath and its length into PSCustomObject 
                    $obj = [PSCustomObject]@{
                        FullPath = $b
                        Length = $b.Length
                    }
                    #Add PSCustomObject into Arraylist
                    [void]$array.Add($obj)
                }
            }
        }        
    }
    #Export Result to a csv file to C:\Users\%username%\AppData\Roaming
    $array | Export-Csv ($env:APPDATA + "\Length-200-" + (Get-Date -Format yyyy-MM-dd-ss) + ".csv") -NoTypeInformation
    $stopwatch.Stop()
    Write-Output "Script Completed in $($stopwatch.Elapsed.TotalMinutes) Minutes"
}
Get-Path 

