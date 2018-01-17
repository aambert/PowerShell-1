﻿<#
	.SYNOPSIS
		BIOS Update
	
	.DESCRIPTION
		This is intended for Dell systems. The script will query if the system is a laptop, is it docked if specified, is it BitLockered, and is the BIOS password set. These steps are taken as a cautious measure so end-users do not brick their laptops out of impatience. If it is bitlockered, the script will suspend Bitlocker. If a BIOS password is set, the system will use the password for flashing. If all tests pass, the script will execute the BIOS patch and then exit with a return code of 3010. If any of those parameters are not met, the script will exit with a return code of 1 or 2, thereby killing the task sequence.
	
	.PARAMETER BIOSLocation
		UNC path to BIOS update files
	
	.PARAMETER BIOSPassword
		BIOS Password
	
	.PARAMETER RequireDocking
		Specifies if docking is required for laptop in order to apply the BIOS update
	
	.NOTES
		===========================================================================
		Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2017 v5.4.143
		Created on:   	1/9/2018 1:46 PM
		Created by:   	Mick Pletcher
		Filename:		DellBIOSUpdater.ps1
		===========================================================================
		
		Exitcode 0 : Success
		Exitcode 1 : Laptop not docked
		Exitcode 2 : Bitlocker failed to pause
		Exitcode 3 : BIOS file is missing
		Exitcode 4 : BIOS file does not match model
#>
[CmdletBinding()]
param
(
	[ValidateNotNullOrEmpty()][string]$BIOSLocation = '\\drfs1\DesktopApplications\ProductionApplications\Dell\BIOS',
	[string]$BIOSPassword = $null,
	[switch]$RequireDocking
)

function Confirm-Bitlocker {
<#
	.SYNOPSIS
		Is system bitlockered
	
	.DESCRIPTION
		A detailed description of the Confirm-Bitlocker function.
	
	.EXAMPLE
		PS C:\> Confirm-Bitlocker
	
	.NOTES
		Additional information about the function.
#>
	
	[CmdletBinding()][OutputType([boolean])]
	param ()
	
	$BDEStatus = manage-bde -status
	if ((($BDEStatus) -like "*Protection On*") -and ($BDEStatus -like "*" + $Env:HOMEDRIVE + "*")) {
		Return $true
	} else {
		Return $false
	}
}

function Confirm-Docked {
<#
	.SYNOPSIS
		Is laptop docked
	
	.DESCRIPTION
		A detailed description of the Confirm-Docked function.
	
	.EXAMPLE
				PS C:\> Confirm-Docked
	
	.NOTES
		Additional information about the function.
#>
	
	[CmdletBinding()][OutputType([boolean])]
	param ()
	
	#Check if laptop is docked
	if (((Get-ItemProperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\IDConfigDB\CurrentDockInfo").DockingState) -eq 1) {
		Return $true
	} else {
		Return $false
	}
}

function Confirm-Laptop {
<#
	.SYNOPSIS
		Test for Battery
	
	.DESCRIPTION
		A detailed description of the Confirm-Laptop function.
	
	.EXAMPLE
		PS C:\> Confirm-Laptop
	
	.NOTES
		Additional information about the function.
#>
	
	[CmdletBinding()][OutputType([boolean])]
	param ()
	
	#Test if system is a laptop
	#$Battery = Get-WmiObject Win32_Battery
	if ((Get-WmiObject Win32_Battery) -ne $null) {
		Return $true
	} else {
		Return $false
	}
}

function Disable-Bitlocker {
<#
	.SYNOPSIS
		Disable Bitlocker
	
	.DESCRIPTION
		Pause bitlocker
	
	.EXAMPLE
				PS C:\> Disable-Bitlocker
	
	.NOTES
		Additional information about the function.
#>
	
	[CmdletBinding()]
	param ()
	
	$BDEStatus = manage-bde -protectors -disable $env:HOMEDRIVE
	$Bitlockered = Confirm-Bitlocker
	If ($Bitlockered -eq $false) {
		Return $false
	} else {
		Return $true
	}
	
}

function Enable-Bitlocker {
<#
	.SYNOPSIS
		Enable Bitlocker
	
	.DESCRIPTION
		Enable bitlocker
	
	.EXAMPLE
		PS C:\> Enable-Bitlocker
	
	.NOTES
		Additional information about the function.
#>
	
	[CmdletBinding()][OutputType([boolean])]
	param ()
	
	$BDEStatus = manage-bde -protectors -enable $env:HOMEDRIVE
	$Bitlockered = Confirm-Bitlocker
	If ($Bitlockered -eq $false) {
		Return $true
	} else {
		Return $false
	}
}

function Get-Architecture {
<#
	.SYNOPSIS
		Get-Architecture
	
	.DESCRIPTION
		Returns whether the system architecture is 32-bit or 64-bit
	
	.EXAMPLE
		Get-Architecture
	
	.NOTES
		Additional information about the function.
#>
	
	[CmdletBinding()][OutputType([string])]
	param ()
	
	$OSArchitecture = (Get-WmiObject -Class Win32_OperatingSystem | Select-Object OSArchitecture).OSArchitecture
	Return $OSArchitecture
	#Returns 32-bit or 64-bit
}

function Get-BIOSPasswordStatus {
<#
	.SYNOPSIS
		Check BIOS Password Status
	
	.DESCRIPTION
		Check if the BIOS password is set
	
	.EXAMPLE
		PS C:\> Get-BIOSPasswordStatus
	
	.NOTES
		Additional information about the function.
#>
	
	[CmdletBinding()][OutputType([boolean])]
	param ()
	
	$Architecture = Get-Architecture
	#Find Dell CCTK
	If ($Architecture -eq "32-Bit") {
		$File = Get-ChildItem ${Env:ProgramFiles(x86)}"\Dell\" -Filter cctk.exe -Recurse | Where-Object { $_.Directory -notlike "*x86_64*" }
	} else {
		$File = Get-ChildItem ${Env:ProgramFiles(x86)}"\Dell\" -Filter cctk.exe -Recurse | Where-Object { $_.Directory -like "*x86_64*" }
	}
	$cmd = [char]38 + [char]32 + [char]34 + $file.FullName + [char]34 + [char]32 + "--setuppwd=" + $BIOSPassword
	$Output = Invoke-Expression $cmd
	#BIOS Password is set
	If ($Output -like "*The old password must be provided to set a new password using*") {
		Return $true
	}
	#BIOS Password was not set, so remove newly set password and return $false
	If ($Output -like "*Password is set successfully*") {
		$cmd = [char]38 + [char]32 + [char]34 + $file.FullName + [char]34 + [char]32 + "--setuppwd=" + [char]32 + "--valsetuppwd=" + $BIOSPassword
		$Output = Invoke-Expression $cmd
		Return $false
	}
}

function Install-BIOSUpdate {
<#
	.SYNOPSIS
		Install BIOS Update
	
	.DESCRIPTION
		A detailed description of the Install-BIOSUpdate function.
	
	.EXAMPLE
				PS C:\> Install-BIOSUpdate
	
	.NOTES
		Additional information about the function.
#>
	
	[CmdletBinding()]
	param ()
	
	$Model = ((Get-WmiObject Win32_ComputerSystem).Model).split(" ")[1]
	$File = Get-ChildItem -Path $BIOSLocation | Where-Object { $_.Name -eq $Model } | Get-ChildItem -Filter *.exe
	#If the BIOS file does not exist, then exit program with error code 3
	If ($File -ne $null) {
		#Backup test to make sure BIOS file matches system model
		If ($File -like "*"+$Model+"*") {
			#Determine if BIOS password is set
			$BIOSPasswordSet = Get-BIOSPasswordStatus
			If ($BIOSPasswordSet -eq $false) {
				$Arguments = "/f /s /l=" + $env:windir + "\waller\Logs\ApplicationLogs\BIOS.log"
			} else {
				$Arguments = "/f /s /p=" + $BIOSPassword + [char]32 + "/l=" + $env:windir + "\waller\Logs\ApplicationLogs\BIOS.log"
			}
			$ErrCode = (Start-Process -FilePath $File.FullName -ArgumentList $Arguments -Wait -PassThru).ExitCode
			If (($ErrCode -eq 0) -or ($ErrCode -eq 2)) {
				Exit 3010
			}
		} else {
			Exit 4
		}
	} else {
		Exit 3
	}
}

Enable-Bitlocker
#Test if system is a laptop, docking required, and is docked, otherwise exit with errcode 1
If (((Confirm-Laptop) -eq $true) -and ($RequireDocking.IsPresent) -and ((Confirm-Docked) -eq $false)) {
	Exit 1
}
#Pause Bitlocker if enabled
$Bitlockered = Confirm-Bitlocker
If ($Bitlockered -eq $true) {
	$Bitlockered = Disable-Bitlocker
	If ($Bitlockered -eq $true) {
		Exit 2
	}
}
Install-BIOSUpdate
