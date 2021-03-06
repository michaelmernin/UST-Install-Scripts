param([String]$py="3",
    [Switch]$cleanpy=$false)


if ($py -eq "2"){
    $pythonVersion = "2"
} else {$pythonVersion = "3"}


$ErrorActionPreference = "Stop"

# Array for collecting warnings to display at end of install
$warnings = New-Object System.Collections.Generic.List[System.Object]

# URL's Combined for convenience here
$7ZipURL = "https://www.7-zip.org/a/7z1801-x64.exe"
$7zURL = 'http://www.7-zip.org/a/7za920.zip'
$USTPython2URL = "https://github.com/adobe-apiplatform/user-sync.py/releases/download/v2.2.2/user-sync-v2.2.2-windows-py2714.tar.gz"
$USTPython3URL = "https://github.com/adobe-apiplatform/user-sync.py/releases/download/v2.2.2/user-sync-v2.2.2-windows-py363.tar.gz"
$USTExamplesURL = "https://github.com/adobe-apiplatform/user-sync.py/releases/download/v2.2.1/example-configurations.tar.gz"
$openSSLBinURL = "https://indy.fulgan.com/SSL/openssl-1.0.2l-x64_86-win64.zip"
$adobeIOCertScriptURL = "https://raw.githubusercontent.com/janssenda-adobe/UST-Install-Scripts/master/UST_io_certgen.ps1"
#"https://raw.githubusercontent.com/bhunut-adobe/user-sync-quick-install/master/adobe_io_certgen.ps1"
$Python2URL = "https://www.python.org/ftp/python/2.7.14/python-2.7.14.amd64.msi"
$Python3URL = "https://www.python.org/ftp/python/3.6.4/python-3.6.4-amd64.exe"
$notepadURL = "https://notepad-plus-plus.org/repository/7.x/7.5.5/npp.7.5.5.Installer.x64.exe"

# Set global parameters
# TLS 1.2 protocol enable - required to download from GitHub, does NOT work on Powershell < 3
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Temporary download location
$DownloadFolder = "$env:TEMP\USTDownload"

function printColor ($msg, $color) {
    Write-Host $msg -ForegroundColor $color
}

function banner {
    Param(
        [String]$message,
        [String]$type="Info",
        [String]$color="Green"
    )

    $message = If ($message) {$message} Else {$type}

    if ($color -eq "Green"){
        switch ($type) {
            "Warning" { $color = "Yellow"; break }
            "Error" { $color = "Red"; break }
        }
    }

    $msgChar = "="
    $charLen = 20

    $messageTop = ("`n" + $msgChar*$charLen + " ${message} " + $msgChar*$charLen)
    $messageBottom = $msgChar*($messageTop.length-1)

    printColor $messageTop $color
}

function Expand-Archive() {
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [ValidateScript({Test-Path -path $_})]
        $Path,
        $OutPut,
        $ArchiveType
    )

    $7zpath = "C:\7-Zip\7z.exe"

    try
    {
        if ($ArchiveType -eq "tar") {
            Start-Process cmd.exe -ArgumentList ("/c ${7zpath} x $Path -so | ${7zpath} x -y -si -aoa -ttar -o`"$OutPut`"") -Wait
        }
        else {
            Start-Process cmd.exe -ArgumentList ("/c ${7zpath} x $Path -y -tzip -aoa -o`"$OutPut`"") -Wait
        }
    } catch {

        printColor "Error while extracting $path..." red
        printColor ("- " + $PSItem.ToString()) red
        $warnings.Add("- " + $PSItem.ToString())

    }
}

function install($displayName, $key, $fileURL, $argList){

    banner "Installing $displayName" -type Info
    # Subkeys from registry for managing installed software state
    $UninstallKey = "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall"
    $reg = [microsoft.win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine',$env:computername)
    $UninstallerSubkeys = $reg.OpenSubkey($UninstallKey).GetSubkeyNames()

    foreach ($k in $UninstallerSubkeys)  {
        $thisKey = $reg.OpenSubKey("${UninstallKey}\\${k}")
        if ($thisKey.GetValue("DisplayName") | Select-String -pattern "($key).+" -Quiet)   {
            Write-Host "- $displayName already installed, skipping... "
            $installLocation = $thisKey.GetValue("InstallLocation");
            return $installLocation
        }
    }

    $filename = $fileURL.Split('/')[-1]
    $installer = "$DownloadFolder\$filename"

    #Download file
    Write-Host "- Downloading $filename from $fileURL"

    (New-Object net.webclient).DownloadFile($fileURL, $installer)

    if (Test-Path $installer){
        Write-Host "- Begin $displayName Installation"
        $installProcess = Start-Process $installer -ArgumentList @($argList) -Wait -PassThru
        if ($installProcess.ExitCode -eq 0)        {
            Write-Host "- $displayName Installation - Completed"
            return
        }
        else        {
            $errmsg =  "-$displayName Installation - Error with ExitCode: $( $installProcess.ExitCode )"
            printColor $errmsg red
            $warnings.Add($errmsg)
        }
    }

    return
}



function Get7Zip () {
    install "7-Zip" "7-Zip" $7ZipURL '/S' > $null

    # Needed to run 7z via command line during extraction (spaces cannot be present)
    Write-Host "- Creating 7-zip temp folder..."
    Copy-Item -Path "C:\Program Files\7-Zip" -Destination "C:\" -Force -Recurse
}


function GetNotepadPP(){
   install "Notepad++" "Notepad\+" $notepadURL '/S'

}

function pyUninstaller(){
    banner "Uninstalling Python" -type Info
    $errors = $false

    # Subkeys from registry for managing installed software state
    $UninstallKey = "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall"
    $reg = [microsoft.win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine',$env:computername)
    $UninstallerSubkeys = $reg.OpenSubkey($UninstallKey).GetSubkeyNames()

    foreach ($k in $UninstallerSubkeys){
        $thisKey = $reg.OpenSubKey("${UninstallKey}\\${k}")
        if ($thisKey.GetValue("DisplayName") | Select-String -pattern "(Python)" -Quiet)    {
            $matches = $true
            $id = ([String] $thisKey).Split('\')[-1]
            $rmKey = "HKLM:\\" + $UninstallKey + "\\$id"
            $app = $thisKey.GetValue("DisplayName")

            Write-Host "- Removing" $app

            $instCode = (Start-Process msiexec.exe -ArgumentList("/x $id /q /norestart") -Wait -PassThru).ExitCode

            if ($instCode -eq 0 -or $instCode -eq 1603)  {
                if (Test-Path $rmKey) {
                    Remove-Item -Path $rmKey
                }
            } else {
                $errors = $true
                $errmsg =  "- There was a problem removing ($app)`n- Please remove it manually!"
                printColor $errmsg red
                printColor ("- " + $PSItem.ToString()) red
                $warnings.Add($PSItem.ToString())

            }

        }
    }

    $systemPaths = @("C:\Python27","C:\Program Files\Python36","C:\Program Files (x86)\Python36")

    foreach ($p in $systemPaths){
        if (Test-Path $p){
            Write-Host "- Removing $p"
            Remove-Item -path $p -Force -confirm:$false -recurse
        }
    }

    if (-not ($matches)){
        Write-Host "- Nothing to uninstall!"
    } elseif ($errors){
        printColor "`n- Uninstallation completed with some errors..." Yellow
    } else {
        printColor "`n- Uninstall completed succesfully!" Green
    }
}

function SetDirectory(){

    $USTInstallDir = "$PWD\UST_Install"
    Write-Host "- Creating directory $USTInstallDir... "
    New-Item -ItemType Directory -Force -Path $USTInstallDir | Out-Null

    return $USTInstallDir

}

function GetUSTFiles ($USTFolder) {
    banner -message "Download UST Files"
    if ($pythonVersion -eq 2){
        $URL = $USTPython2URL
    } else {
        $URL = $USTPython3URL
    }

    #Download UST 2.2.2 and Extract
    $USTdownloadList = @()
    $USTdownloadList += $URL
    $USTdownloadList += $USTExamplesURL

    foreach($download in $USTdownloadList){
        $filename = $download.Split('/')[-1]
        $downloadfile = "$DownloadFolder\$filename"

        #Download file
        Write-Host "- Downloading $filename from $download"

        $wc = New-Object net.webclient
        $wc.DownloadFile($download,$downloadfile)

        if(Test-Path $downloadfile){
            #Extract downloaded file to UST Folder
            Write-Host "- Extracting $downloadfile to $USTFolder"
            Expand-Archive -Path $downloadfile -OutPut $USTFolder -ArchiveType tar
        }
    }


    #Make example config files readable in windows and Copy "config files - basic" to root
    $configExamplePath = "$USTFolder\examples"
    if(Test-Path -Path $configExamplePath){
        Get-ChildItem -Path $configExamplePath -Recurse -Filter '*.yml' | % { ( $_ |  Get-Content ) | Set-Content $_.pspath -Force }
        #Copy config files
        $configBasicPath = "$configExamplePath\config files - basic"
        Copy-Item -Path "$configBasicPath\3 connector-ldap.yml" -Destination $USTFolder\connector-ldap.yml -Force
        Copy-Item -Path "$configBasicPath\2 connector-umapi.yml" -Destination $USTFolder\connector-umapi.yml -Force
        Copy-Item -Path "$configBasicPath\1 user-sync-config.yml" -Destination $USTFolder\user-sync-config.yml -Force

    }
}


function GetOpenSSL ($USTFolder) {

    #Download OpenSSL 1.0.2l binary for Windows and extract to utils folder
    $openSSLBinFileName = $openSSLBinURL.Split('/')[-1]
    $openSSLOutputPath = "$DownloadFolder\$openSSLBinFileName"
    $openSSLUSTFolder = "$USTFolder\Utils\openSSL"
    Write-Host "- Downloading OpenSSL Win32 Binary from $openSSLBinURL"


    $wc = New-Object net.webclient
    $wc.DownloadFile($openSSLBinURL,$openSSLOutputPath)

    if(Test-Path $openSSLOutputPath){
        #- Extracting downloaded file to UST folder.
        Write-Host "- Extracting $openSSLBinFileName to $openSSLUSTFolder"
        try{
            New-Item -Path $openSSLUSTFolder -ItemType Directory -Force | Out-Null
            Expand-Archive -Path $openSSLOutputPath -OutPut $openSSLUSTFolder -ArchiveType zip
            Write-Host "- Completed extracting $openSSLBinFileName to $openSSLUSTFolder"
        }catch{
            Write-Error "Unable to extract openSSL"
        }
    }

    #Download Default Openssl.cfg configuration file
    $openSSLConfigURL = 'http://web.mit.edu/crypto/openssl.cnf'
    $openSSLConfigFileName = $openSSLConfigURL.Split('/')[-1]
    $openSSLConfigOutputPath = "$USTFolder\Utils\openSSL\$openSSLConfigFileName"
    Write-Host "- Downloading default openssl.cnf config file from $openSSLConfigURL"
    #Invoke-WebRequest -Uri $openSSLConfigURL -OutFile $openSSLConfigOutputPath

    $wc = New-Object net.webclient
    $wc.DownloadFile($openSSLConfigURL,$openSSLConfigOutputPath)

    return $openSSLUSTFolder

}

function FinalizeInstallation ($USTFolder, $openSSLUSTFolder) {

    #Download Adobe.IO Cert generation Script and put it into utils\openSSL folder
    $adobeIOCertScript = $adobeIOCertScriptURL.Split('/')[-1]
    $adobeIOCertScriptOutputPath = "$USTFolder\Utils\openSSL\$adobeIOCertScript"
    Write-Host "- Downloading Adobe.IO Cert Generation Script from $adobeIOCertScriptURL"

    $wc = New-Object net.webclient
    $wc.DownloadFile($adobeIOCertScriptURL,$adobeIOCertScriptOutputPath)

    #echo $adobeIOCertScriptOutputPath

    if(Test-Path $adobeIOCertScriptOutputPath){

        $batchfile = '@"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -InputFormat None -ExecutionPolicy Bypass -file ' + $adobeIOCertScriptOutputPath
        $batchfile | Out-File "$openSSLUSTFolder\Adobe_IO_Cert_Generation.bat" -Force -Encoding ascii

    }


    if ($py -eq 2){
        $pycmd = "C:\Python27\python.exe"
    }
    else {
        $pycmd = "C:\Program Files\python36\python.exe"
    }

    #Create Test-Mode and Live-Mode UST Batch file
    if(Test-Path $USTFolder){
        $test_mode_batchfile = @"
REM "Running UST in TEST-MODE"
cd "$USTFolder"
python user-sync.pex --process-groups --users mapped -t
pause
"@
        $test_mode_batchfile | Out-File "$USTFolder\Run_UST_Test_Mode.bat" -Force -Encoding ascii

        $live_mode_batchfile = @"
REM "Running UST"
cd "$USTFolder"
python user-sync.pex --process-groups --users mapped
"@
        $live_mode_batchfile | Out-File "$USTFolder\Run_UST_Live.bat" -Force -Encoding ascii
    }

}



function GetPython ($USTFolder) {
    banner -message "Install Python $pythonVersion"
    $install = $FALSE
    $UST_version = 3
    $inst_version = $pythonVersion

    # Subkeys from registry for managing installed software state
    $UninstallKey = "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall"
    $reg = [microsoft.win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine',$env:computername)
    $UninstallerSubkeys = $reg.OpenSubkey($UninstallKey).GetSubkeyNames()

    foreach ($k in $UninstallerSubkeys){
        $thisKey = $reg.OpenSubKey("${UninstallKey}\\${k}")
        if ($thisKey.GetValue("DisplayName") | Select-String -pattern "(Python).+(\(64-Bit\))" -Quiet)    {
            $thisKey.GetValue("DisplayVersion") | Select-String -pattern "((3.6)|(2.7))(.)" | foreach-object {
                switch ($_.Matches[0].Groups[1].Value) {
                    "2.7" {$p2_installed = $true; break}
                    "3.6" {$p3_installed = $true; break}
                }
            }
        }
    }

    if ($pythonVersion -eq "3" -and -not $p3_installed) { $install = $true }
    elseif ($pythonVersion -eq "2" -and -not $p2_installed) { $install = $true }
    else {
        Write-Host "- Python version $pythonVersion is already installed...".
    }

    if ($install){
        Write-Host "- Python $inst_version will be updated/installed...".
        if ($inst_version -eq 2){
            $pythonURL = $Python2URL
            $UST_version = 2
        } else {
            $pythonURL = $Python3URL
            $UST_version = 3
        }

        $pythonInstaller = $pythonURL.Split('/')[-1]
        $pythonInstallerOutput = "$DownloadFolder\$pythonInstaller"

        Write-Host "- Downloading Python from $pythonURL"


        $wc = New-Object net.webclient
        $wc.DownloadFile($pythonURL,$pythonInstallerOutput)

        if(Test-Path $pythonInstallerOutput){

            #Passive Install of Python. This will show progressbar and error.
            Write-Host "- Begin Python Installation"
            $pythonProcess = Start-Process $pythonInstallerOutput -ArgumentList @('/passive', 'InstallAllUsers=1', 'PrependPath=1') -Wait -PassThru
            if($pythonProcess.ExitCode -eq 0){

                if ($inst_version -eq 2){
                    Write-Host "- Add C:\Python27 to path..."
                    [Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\Python27\", [EnvironmentVariableTarget]::Machine)
                }

                Write-Host "- Python Installation - Completed"
            }else{
                if ($inst_version -eq 3){
                    printColor "- Error: Python may have failed to install Windows updates for this version of Windows.`n- Update Windows manually or try installing Python 2 instead..." red
                }

                $errmsg = "- Python Installation - Error with ExitCode: $($pythonProcess.ExitCode)"
                printColor $errmsg red
                $warnings.Add($errmsg)
                $install = $false
            }
        }
    }

    #Set Environment Variable
    Write-Host "- Set PEX_ROOT System Environment Variable"
    [Environment]::SetEnvironmentVariable("PEX_ROOT", "$env:SystemDrive\PEX", "Machine")



}

function Cleanup() {

    try{
        #Delete Temp DownloadFolder for UST, Python and Config files
        Remove-Item -Path $DownloadFolder -Recurse -Confirm:$false -Force
    } catch {}

    try {
        #Delete 7-zip temp folder
        Remove-Item -Path "C:\7-zip" -Recurse -Confirm:$false -Force
    } catch {}
}

# Main
if ((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){

    $introbanner = "`n
  _   _                 ___
 | | | |___ ___ _ _    / __|_  _ _ _  __
 | |_| (_-</ -_) '_|   \__ \ || | ' \/ _|
  \___//__/\___|_|     |___/\_, |_||_\__|
                            |__/
    "

    printColor $introbanner Cyan
    banner -message "User Sync Tool Quick Install" -color Cyan
    Write-Host ""

    printColor "*** Parameter List ***`n" Green
    Write-Host "- Python Version: " $py
    Write-Host "- Clean Py Install: " $cleanpy

    if ($cleanpy) {
        try {
            pyUninstaller
        } catch {
            $errmsg = "- Failed to completely remove python... "
            printColor $errmsg red
            $warnings.Add($errmsg)
        }
    }

    banner -message "- Creating UST directory"
    $USTFolder = SetDirectory

    #Create Temp download folder
    New-Item -Path $DownloadFolder -ItemType "Directory" -Force | Out-Null

    # Install Process
    try    {
        Get7Zip
    } catch {
        printColor ("- " + $PSItem.ToString()) yellow
        throw "Error downloading 7zip, installation cannot continue... "
    }

    try    {
        GetPython $USTFolder
    } catch {
        banner -type Error
        Write-Host "- Failed to install Python with error:"
        Write-Host ("- " + $PSItem.ToString())
        $warnings.Add("- " + $PSItem.ToString())
    }

    try    {
        GetNotepadPP
    } catch {
        banner -type Error
        Write-Host "- Failed to install Notepad++ with error:"
        Write-Host ("- " + $PSItem.ToString())
        $warnings.Add("- " + $PSItem.ToString())
    }

    try    {
        GetUSTFiles $USTFolder $pythonVersion
    } catch {
        banner -type Error
        Write-Host "- Failed to download UST resources with error:"
        Write-Host ("- " + $PSItem.ToString())
        $warnings.Add("- " + $PSItem.ToString())
    }

    # Try loop as connection occasionally fails the first time
    banner -message "Download OpenSSL"
    $i = 0
    while ($true)  {
        $i++
        try {
            $openSSLUSTFolder = GetOpenSSL $USTFolder
            break
        }
        catch {
            printColor "- Connection failed... retrying... ctrl-c to abort..." Yellow
        }
        if ($i -eq 5) {
            banner -type Warning
            $errmsg = "- Open SSL failed to download... retry or download manually..."
            printColor $errmsg red
            $warnings.Add($errmsg)

            break
        }
    }

    try  {
        FinalizeInstallation $USTFolder $openSSLUSTFolder
    } catch {
        banner -type Error
        Write-Host "- Failed to create batch files with error:"
        Write-Host ("- " + $PSItem.ToString())
        $warnings.Add("- " + $PSItem.ToString())
    }

    Cleanup

    banner -message "Install Finish" -color Blue

    if ($warnings.Count -gt 0){
        printColor "- Install completed with some warnings: " yellow

        foreach($w in $warnings){
            printColor "$w" red
        }

        Write-Host ""

    }

    Write-Host "- Completed - You can begin to edit configuration files in:`n"
    printColor "- $USTFolder" Green
    Write-Host ""

}else{
    Write-host "Not elevated. Re-run the script with elevated permission"
}


