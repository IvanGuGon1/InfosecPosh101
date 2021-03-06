function sync-yumrepo{
    [CmdletBinding()]
    param (
        [parameter(Mandatory=$True, HelpMessage="The url of the repository directory")]
            [Alias("r")]
            [Alias("remote")]
            [string]$remoteloc,
        
        [parameter(Mandatory=$True, HelpMessage="The directory of the local repository")]
            [Alias("dir")]
            [Alias("d")]
            [Alias("local")]
            [string]$locdir,
            
        [parameter(Mandatory=$false, HelpMessage="The location of the download log file")]
            [Alias("log")]
            [string]$LogFileName,
            
        [parameter(Mandatory=$false, HelpMessage="Log the Maximum amount of information")]
            [Switch]$Trace,
                                  
        [parameter(Mandatory=$false, HelpMessage="Re-download the entire repository, ignoring matching files")]
            [Switch]$force
              
    )
    BEGIN {

        $scriptPath = $PSScriptRoot
        $tempPath = [System.IO.Path]::GetTempPath()
        Import-Module "$scriptPath\PS-Log.psm1" -Force
        Import-Module "$scriptPath\Get-DownloadFile.ps1" -Force
        
        #################################
        # Setup Log File
        $datetime = get-date -format "yyyyMd_HHmm"

        if (!$LogFileName) {$LogFileName = $locdir + "\logs\sync_"+$datetime+".log"}
                
        try{ 
            Switch-LogFile -Name $LogFileName 
        }
        catch { 
            $LogFileName = $tempPath + "sync_"+$datetime+".log"
            Write-Warning "Error creating log file, results will be logged to: $($LogFileName)"
        }
                
        # Set logging level for process.  The most verbose logging flag set wins. 
        [int]$LoggingLevel = $GLOBAL:LogLevel # Defaults to Info Logging
        if ($NoLog) {$LoggingLevel = 8} # Do Not Log
        if ($PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent) {$LoggingLevel = 3} 
        if ($PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent) {$LoggingLevel = 2}  
        if ($Trace) {$LoggingLevel = 1}
            
        #Build Logging Object
        try{
            $log = New-LogFile "sync-yumrepo" $LogFileName $LoggingLevel
            $log.Info("Log FileName: $LogFileName") 
        }
        catch{
            Write-Host "Error Creating PS-Log Object"
            Write-Error "$_.Exception.ToString()"
        }

        #Implement Timings to Measure ReportHost processing statistics
        #Courtesy: Joshua Poehls (Jpoehls)
        #https://github.com/jpoehls/hulk-example/blob/master/_posts/2013/2013-01-24-benchmarking-with-Powershell.md

        $swTotal = New-Object Diagnostics.Stopwatch
        $sw = New-Object Diagnostics.Stopwatch


    }#begin

    PROCESS{
        $swTotal.Reset()
        $swTotal.Start()
            
        $log.Info("-----------------------------")
        $log.Info("***Syncing Yum Repository***")
        $log.Info("Remote: $($remoteloc)")
        $log.Info("Local: $($locdir)")
        $log.Info("-----------------------------")
                    
        #################################
        # Verify that the local path exists and contains <X:>\local\path\repodata\repomd.xml

        #If folder does not exist create a new folder.
        #If folder does exist and is not empty, but repomd.xml does not, alert user and fail command to prevent overwriting existing files.
        $locrepomd = $locdir + "\repodata\repomd.xml"

        if (!(Test-Path $locrepomd)) {
            if(!(Test-Path $locdir )){
                New-Item -ItemType directory -Path $locdir | out-null
            }
            elseif (!((Get-ChildItem $locdir -recurse | Measure-Object | %{$_.count}) -eq 0)) {
                $log.Warn("Supplied Directory is not a valid yum repository and is not empty")
                if ($(Read-Host "Continue Y/N") -ne "Y") {
                    $log.fatal("User canceled sync")
                    Break
                } else {
                    $log.info("User chose to continue syncing to folder")
                }
            }
        }else {
            $log.info("Parsing Local Repo")
            $log.info("source: $localrepomd")
            [xml] $locrepomdxml = get-content $locrepomd
        }

#################################
#Attempt to download remote http://repo.org/remote/repo/repodata/repomd.xml

        $remrepomd = $remoteloc + "/repodata/repomd.xml"

        try{

            New-Item -ItemType directory -Path ($locdir + "\repodata_$datetime") | out-null
            
            $temprepomd = $locdir + "\repodata_$datetime\repomd.xml"
            
            Get-DownloadFile -url $remrepomd -path $temprepomd -LogFileName $LogFileName
            
            $log.Info("Checking remote Repomd.xml")
            $log.Info("Source: $remrepomd")
            $log.Info("Destination: $temprepomd")
            [xml] $remrepomdxml =  get-content $temprepomd
        }
        catch{ #If repomd.xml does not exist, alert user and fail.
            $log.fatal("Error Downloading $source")
            $log.fatal("$_.Exception.ToString()")
            Break
        }


#################################
#Download remote primary-xml.gz and expand

        $remPriLoc = $remoteLoc + "/" + ($remrepomdxml.repomd.data | ?{$_.type -eq "primary"} | %{$_.location.href})
        $tgtPriLoc = "$($locdir)\repodata_$($datetime)\$($remPriLoc.split("/")[-1])"
        
        $log.Info("Downloading Primary.xml")
        $log.Info("Source: $remPriLoc")
        $log.Info("Desination: $tgtPriLoc")
        
        $remprixmlloc = Get-DownloadFile -url $remPriLoc -path "$tgtPriLoc" -LogFileName $LogFileName
        
        [xml]$remprixml = Get-Content (Expand-GZipFile $remprixmlloc)
        $remRPMList = $remprixml.metadata.package | select -expandproperty location | select -expandproperty href

#################################
#Compare downloaded repomd.xml with local repomd.xml

        #Compare primary.xml.gz checksums of local and remote repomd.xml.  If checksum has not changed, alert and quit
        #$repo.repomd.data | ?{$_.type -eq "primary"} | %{$_.checksum.'#text'}

        if ($locrepomdxml) {
           $log.Info("Checking Primary.xml")
           $locPrihash = $locrepomdxml.repomd.data | ?{$_.type -eq "primary"} | %{$_.checksum.'#text'}   
           $remPrihash = $remrepomdxml.repomd.data | ?{$_.type -eq "primary"} | %{$_.checksum.'#text'}
           
           if ($locPrihash = $remPrihash){
                $log.Warn("repomd.xml data has not changed.")
                if ($(Read-Host "Continue Y/N") -ne "Y") {
                    $log.fatal("User canceled sync")
                    Break
                } else {
                    $log.info("User chose to continue syncing to folder") 
                }
           }
          
#################################
#Compare downloaded primary.xml with local primary.xml to get repository change (informational only)
           
            $locPriLoc = $locdir + "\$($locrepomdxml.repomd.data | ?{$_.type -eq "primary"} | %{$_.location.href})"
           
            [xml]$locprixml = Get-Content (Expand-GZipFile $locPriLoc)
           
            #Create a list of Removed / New packages
            $log.Info("Building Changed List")
           
            $locRPMList = $locprixml.metadata.package | select -expandproperty location | select -expandproperty href
           
            $prixmldiff = compare-object -referenceobject $locRPMList -differenceobject $remRPMList

            $Removedlist = $prixmldiff | ?{$_.SideIndicator -eq "<="} | Select -ExpandProperty inputObject
            $Addedlist = $prixmldiff | ?{$_.SideIndicator -eq "=>"} | Select -ExpandProperty inputObject
           
            $log.Info("-----------------------------")   
            $log.Info("Yum Repository Changes")
            $log.Info("Added: $($Addedlist.count) ")
            if ($Logginglevel -le 2){ 
                $Addedlist | %{$log.debug("ADD: $($_)")}
            }
            $log.Info("Removed: $($Removedlist.count) ")
            if ($Logginglevel -le 2){ 
                $Removedlist | %{$log.debug("REM: $($_)")}
            }
            $log.Info("-----------------------------")
        }

#################################
#Compare downloaded primary.xml with files in local folder. (used to determine download/removal lists)

        
        $fileRPMlist = get-childitem -path $locdir | ?{!($_.PSIsContainer)} | select -expandproperty name
        if ($fileRPMlist -ne $Null) {
            $filediff = compare-object -referenceobject $fileRPMlist -differenceobject $remRPMList
            $Removefile = $filediff | ?{$_.SideIndicator -eq "<="} | Select -ExpandProperty inputObject | sort-object inputObject
            $log.debug($fileDiff.tostring())
            $Downloadfile = $filediff | ?{$_.SideIndicator -eq "=>"} | Select -ExpandProperty inputObject | sort-object inputObject
        } else {
            $DownloadFile = $remRPMList
        }
        
        $log.Info("-----------------------------")
        $log.Info("Repository File Maintenance Actions")
        $log.Info("Download: $($Downloadfile.count) ")
        if ($Logginglevel -le 2){ 
            $Downloadfile | %{$log.debug("GET: $($_)")}
        }
        $log.Info("Remove: $($Removefile.count) ")
        if ($Logginglevel -le 2){ 
            $Removefile | %{$log.debug("DEL: $($_)")}
        }
        $log.Info("-----------------------------")

#################################
#Download missing files
        $i = 0
        if($Downloadfile -ne $Null){
          foreach ($file in $Downloadfile){
            $i++ | out-null
            $tgtchecksum = $remprixml.metadata.package | ?{$_.location.href -eq $file} | select -expandproperty checksum
            $url = "$remoteloc/$file"
            $localpath = "$locdir\$file"
            try{
                    $fileloc = Get-DownloadFile -url $url -path $localpath -checksum $tgtchecksum.'#text' -checksumtype $tgtchecksum.type -LogFileName $LogFileName -progress
            }
            catch {
                $log.error("Error Downloading File: $file")
                $log.error("$_.Exception.ToString()")
            }
            $log.info("Progress: $i / $($Downloadfile.count)")
            
          }
        }
        
#################################
#Remove orphaned / non-repo files
        if ($Removefile -ne $null) {
          foreach ($file in $Removefile){
            $filepath = "$locdir\$file"
                $log.Info("Removing: $file")
                try{
                    remove-item -path "$locdir\$file"
                }
                catch {
                    $log.error("Error Removing File: $file")
                    $log.error("$_.Exception.ToString()")
                }  
             }          
        }
#################################
#Update <X:>\local\path\repodata\ folder with new repodata

        $downloadrepomd = $remrepomdxml.repomd.data | select -expandproperty location | select -expandproperty href
        
        if (!(Test-Path $locrepomd)) {
            New-Item -ItemType directory -Path ($locdir + "\repodata") | out-null
        } else {
            $repoDataOld = get-ChildItem -Path "$locdir\repodata\"
        }
                
        foreach ($file in $downloadrepomd) {
            $tgtchecksum = $remrepomdxml.repomd.data | ?{$_.location.href -eq $file} | select -expandproperty checksum
            $url = "$remoteloc/$file"
            $localpath = "$locdir\$file"
            $fileloc = Get-DownloadFile -url $url -path $localpath -checksum $tgtchecksum.'#text' -checksumtype $tgtchecksum.type -LogFileName $LogFileName
            $log.debug("Downloaded: $fileloc")
        }
        foreach ($file in $downloadrepomd) {
            if ($filepath -ne $locdir) {
                
            }
        }
    }#process
    
    END{

    }#end

    <#
    .SYNOPSIS
    This function syncronizes a standard linux yum repository with a local folder.  

    .DESCRIPTION
    This function syncronizes yum repositories with a local folder.  It takes the following actions

    Given a local folder (<X:>\local\path\) and remote repository (http://repo.org/remote/repo/)
    1. Verify that the local path exists and contains <X:>\local\path\repodata\repomd.xml
        a. If folder does not exist prompt user and create new new folder.  Download entire repo.
        b. If folder does exist and is not empty, but repomd.xml does not, alert user and fail command to prevent overwriting existing files.
    2. Attempt to download remote http://repo.org/remote/repo/repodata/repomd.xml to a temporary file
        a. If repomd.xml does not exist, alert user and fail.
    3. Compare downloaded repomd.xml with local repomd.xml
        b. Compare primary.xml.gz checksums of local and remote repomd.xml.  If checksum has not changed, alert and quit
            
            
    4. Compare downloaded primary.xml with local primary.xml
        a. Create a list of Changed / New packages
        b. Download New versions
        c. Remove Outdated versions
        e. update 

    5.  Update <X:>\local\path\repodata\ folder with new repodata


    .PARAMETER  <Parameter-Name>


    .EXAMPLE


    .INPUTS


    .OUTPUTS


    .NOTES


    .LINK

    #>

}