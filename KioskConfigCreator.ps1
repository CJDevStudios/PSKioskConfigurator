# Windows 10 Kiosk Configration Creator
# Version 1.1
# Curtis Conard
# 3/27/2017
# Changes:
# Version 1.1 - Added proper support for domain users
# Version 1.2 - Removed attempt to delete non-existant folder
#               Added comments

#Prompt for needed information
$KioskUser = Read-Host -Prompt "Kiosk User's Username"
$KioskPass = Read-Host -Prompt "Kiosk User's Password"
$IsUserLocal = Read-Host -Prompt "Local User? (y/n)"
$UserDom = ""
If ($IsUserLocal -eq "n") {
    $UserDom = Read-Host -Prompt "Domain"
}

$ShellApp = Read-Host -Prompt "Kiosk Application Path"
$CloseAction = Read-Host -Prompt "App Close Action (0=Restart App, 1 = Restart, 2 = Shutdown)"
$PackageName = Read-Host -Prompt "Package Name"

Write-Host "Creating Package"
#Check for existing package folder. If it exists, ask to remove it. If no, exit configuration. Otherwise, delete it.
If (Test-Path "$PSScriptRoot\$PackageName\") {
    $Overwrite = Read-Host -Prompt "Package folder exists. OK to overwrite? (y/n)"
    If ($Overwrite -eq "y") {
        Remove-Item -Recurse -Force -Path "$PSScriptRoot\$PackageName\"
    } else {
        exit
    }
}

#If shell application path isn't quoted, add them.
If ($ShellApp.StartsWith("`"") -eq $false) {
    $ShellApp = "`"$ShellApp`""
}

#Create new package folder in script root
New-Item "$PSScriptRoot\$PackageName\" -Type directory

#Build main configuration script. This is what is manually run.
Write-Host "Creating main configuration script"
New-Item "$PSScriptRoot\$PackageName\configure.cmd" -Type file
Add-Content "$PSScriptRoot\$PackageName\configure.cmd" "reg import `"%~dp0KioskAutoLogin.reg`""
Add-Content "$PSScriptRoot\$PackageName\configure.cmd" "Dism /online /Enable-Feature /all /Featurename:Client-EmbeddedShellLauncher"
Add-Content "$PSScriptRoot\$PackageName\configure.cmd" "powershell -ExecutionPolicy ByPass -File `"%~dp0configure.ps1`""

#Build registry file containing the auto-login information
Write-Host "Creating Auto-Login registry file"
New-Item "$PSScriptRoot\$PackageName\KioskAutoLogin.reg" -Type file
Add-Content "$PSScriptRoot\$PackageName\KioskAutoLogin.reg" "Windows Registry Editor Version 5.00"
Add-Content "$PSScriptRoot\$PackageName\KioskAutoLogin.reg" ""
Add-Content "$PSScriptRoot\$PackageName\KioskAutoLogin.reg" "[HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon]"
Add-Content "$PSScriptRoot\$PackageName\KioskAutoLogin.reg" "`"AutoAdminLogon`"=dword:00000001"
Add-Content "$PSScriptRoot\$PackageName\KioskAutoLogin.reg" "`"DefaultUserName`"=`"$KioskUser`""
Add-Content "$PSScriptRoot\$PackageName\KioskAutoLogin.reg" "`"DefaultPassword`"=`"$KioskPass`""
If ($UserDom.Length -gt 0) {
    Add-Content "$PSScriptRoot\$PackageName\KioskAutoLogin.reg" "`"DefaultDomainName`"=`"$UserDom`""
} Else {
    Add-Content "$PSScriptRoot\$PackageName\KioskAutoLogin.reg" "`"DefaultDomainName`"=`"localhost`""
}

#Build script to configure the custom shell. This uses 'template.ps1' as a base, and adds specific code to the end.
Write-Host "Copying shell script template"
Copy-Item "$PSScriptRoot\template.ps1" -Destination "$PSScriptRoot\$PackageName\configure.ps1"
Write-Host "Customizing shell script"

If ($UserDom.Length -gt 0) {
    #This is a domain user, specify user in DOMAIN\USER format
    $UserString = "$UserDom\$KioskUser"
} Else {
    #This is a local user, just use username
    $UserString = $KioskUser
}
#Add line to get user's security identifier
Add-Content "$PSScriptRoot\$PackageName\configure.ps1" "`$KioskUser_SID = Get-UsernameSID(`"$UserString`")"
#Add line to set default shell to explorer. This is what everone except the kiosk user will have
Add-Content "$PSScriptRoot\$PackageName\configure.ps1" "`$ShellLauncherClass.SetDefaultShell(`"explorer.exe`", 0)"
#Add line to remove any previously specified custom shell for the specified kiosk user
Add-Content "$PSScriptRoot\$PackageName\configure.ps1" "`$ShellLauncherClass.RemoveCustomShell(`$KioskUser_SID)"
#Add line to set the new custom shell for the specified kiosk user
Add-Content "$PSScriptRoot\$PackageName\configure.ps1" "`$ShellLauncherClass.SetCustomShell(`$KioskUser_SID, $ShellApp, (`$null), (`$null), $CloseAction)"
#Add line to enable shell launcher
Add-Content "$PSScriptRoot\$PackageName\configure.ps1" "`$ShellLauncherClass.SetEnabled(`$TRUE)"
Write-Host "Package has been created. Run configure.cmd to run the configuration"