function Get-DownloadFile
{
[CmdletBinding()]
     Param
     (
          [parameter(Mandatory=$true, ValueFromPipeline=$true, HelpMessage="Remote File to Download")]
          [Alias("url")]
          [String]
          $remote,
          
          [parameter(Mandatory=$false, ValueFromPipeline=$false, HelpMessage="Local Location to Save File") ]
          [Alias("path")]
          [String]
          $local,
          
          [parameter(Mandatory=$false, ValueFromPipeline=$false, HelpMessage="FileChecksum") ]
          [String]
          $checksum,
          
          [parameter(Mandatory=$false, ValueFromPipeline=$false, HelpMessage="FileChecksum") ]
          [ValidateSet("MD5", "SHA", "SHA1", "SHA-256", "SHA-384", "SHA-512", "sha256", "sha384", "sha512")]
          [String]
          $checksumtype = "SHA-1",
                  
          [parameter(Mandatory=$false, HelpMessage="The location of the download log file")]
		  [Alias("log")]
		  [string]
          $LogFileName,
          
          [parameter(Mandatory=$false, HelpMessage="Logging Level")]
		  [Alias("loglevel")]
		  [string]
          $LoggingLevel,
          
          [parameter(Mandatory=$false, HelpMessage="Log the Maximum amount of information")]
		  [Switch]
          $Trace,
          
          [parameter(Mandatory=$false, HelpMessage="Don't Log any information")]
		  [Switch]
          $NoLog,
          
          [parameter(Mandatory=$false, HelpMessage="Display Download Progress?")]
		  [Switch]
          $Progress,  
                  
          [parameter(HelpMessage="A file that contains proxy information")]
		  [string]
          $proxyfile = "$([environment]::getfolderpath("mydocuments"))\proxy.xml"
          
     )
     Begin
     {
        if($proxyfile){
            [xml] $proxyinfo = get-content $proxyfile
            
            $Credential = new-object -typename System.management.automation.pscredential -Argumentlist $proxyinfo.proxy.username, ($proxyinfo.proxy.password | convertto-securestring)
    
            $WebProxy = New-Object System.Net.WebProxy("http://$($proxyinfo.proxy.proxy):$($proxyinfo.proxy.port)",$true)
            $Credentials = New-Object Net.NetworkCredential($credential.GetNetworkCredential().Username,
                                                            $credential.GetNetworkCredential().Password,
                                                            $credential.GetNetworkCredential().Domain)
                                                    
            $Credentials = $Credentials.GetCredential($proxyurl,$port, "KERBEROS")
            $WebProxy.Credentials = $Credentials
     
        }
        
        #Setup Logging.
        if ($LogFileName){
            if (!(Get-Command New-LogFile -errorAction SilentlyContinue)) {Import-Module "$scriptPath\PS-Log.psm1" -Force }
            if (!$LoggingLevel){[int]$LoggingLevel = $GLOBAL:LogLevel} # Defaults to Info Logging
            if ($NoLog) {$LoggingLevel = 8} # Do Not Log
            if ($PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent) {$LoggingLevel = 3} 
            if ($PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent) {$LoggingLevel = 2}  
            if ($Trace) {$LoggingLevel = 1}
	
            #Build Logging Object
            try{
             $log = New-LogFile "Get-DownloadFile" $LogFileName $LoggingLevel
	         $log.debug("Log FileName: $LogFileName") 
            }
            catch{
	           Write-Host "Error Creating PS-Log Object"
    	       Write-Error "$_.Exception.ToString()"
            }
        } else {
            $log = New-Module -AsCustomObject -ScriptBlock {
                     function trace([string]$output){Write-Host "TRACE: $output" -Fore Green}
                     function debug([string]$output){Write-Host "DEBUG: $output" -Fore Blue}
                     function verbose([string]$output) {Write-Host "VERBOSE: $output" -Fore Magenta}
                     function info([string]$output){Write-Host "INFO: $output"}
                     function warn([string]$output){Write-Host "WARN: $output" -Fore Yellow}
                     function error([string]$output){Write-Host "ERROR: $output" -Fore Red}
                     function fatal([string]$output){Write-Host "FATAL: $output" -Fore Red}   
                    } 
        }


     } #Begin
     
     Process
     {
        if(!($local)) { $local = "$(get-location)\$($remote.split("/")[-1])"}
        
        [switch] $success = $false
        if (!(test-path $local -PathType leaf -isValid )){
            $log.Warn("Invalid Local Path Specified")
            $local = "$(get-location)\$($remote.split("/")[-1])"
            $log.Warn("Downloading to: $local")
        }
        
        do {
            $log.Info("Downloading: $remote")
            try{
                $uri = New-Object "System.Uri" "$remote"
                # $request = [System.Net.HttpWebRequest]::Create($uri)
                $request = [System.Net.WebRequest]::Create($uri)
                $request.set_Timeout(300000) #5 Minute Timeout
                $request.proxy = $WebProxy
                
                $response = $request.GetResponse()
                $totalLength = [System.Math]::Floor($response.get_ContentLength()/1024)
                $log.Info("Size: $($TotalLength)K")
                $responseStream = $response.GetResponseStream()
                $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $local, Create
                $buffer = new-object byte[] 10KB
                $count = $responseStream.Read($buffer,0,$buffer.length)
                $downloadedBytes = $count
                
                while ($count -gt 0)
                {
                    $targetStream.Write($buffer, 0, $count)
                    $count = $responseStream.Read($buffer,0,$buffer.length)
                    $downloadedBytes = $downloadedBytes + $count
                    
                    if($progress){Write-Progress -activity "Downloading file '$($url.split('/') | Select -Last 1)'" -status "Downloaded ($([System.Math]::Floor($downloadedBytes/1024))K of $($totalLength)K): " -PercentComplete ((([System.Math]::Floor($downloadedBytes/1024)) / $totalLength)  * 100)}
                }
                if($progress){Write-Progress -activity "Finished downloading file '$($url.split('/') | Select -Last 1)'" -status "Finished"}
                
            }
            catch {
                $log.Error("Error Downloading File: $remote")
                $log.Error("$_")
                $success = $false
            }
            finally {
                $targetStream.Flush()
                $targetStream.Close()
                $targetStream.Dispose()
                $responseStream.Dispose()
                $success = $true
            }
            
            if(($checksum) -and ($success -eq $true)){
                $filechecksum = get-hash -File $local -algorithm $checksumtype
                $log.Info("Verifying Checksum")
                $log.Info("loc: $filechecksum")
                $log.Info("tgt: $checksum")
                if ($filechecksum -ne $checksum){
                    $log.error("Checksum Validation Error")
                    $success = $false
                    if ($(Read-Host "Keep File Y/N") -ne "Y") {
                        $log.info("Removing: $local")
                        remove-item $local
                    } else {
                        $log.info("User chose keep file")
                        $success = $true
                    }
                }  
            }
        
            if ($success -eq $false) {
                if ($(Read-Host "Retry Download Y/N") -ne "Y") {
                    return $null
                }  
            }
        } until ($success -eq $true)
       return $local 
     }
     
}