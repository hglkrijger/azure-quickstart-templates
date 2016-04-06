# The MIT License (MIT)
#
# Copyright (c) 2015 Microsoft Azure
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

<#
	.SYNOPSIS
		Updates an Elasticsearch cluster to persist AFS credentials.
	.DESCRIPTION
		This script persists AFS credentials.
#>
Param(
    [string]$afsKey,
    [string]$afsAccount,
	[string]$afsShare,
	[string]$username,
	[string]$password
)

# To set the env vars permanently, need to use registry location
Set-Variable regEnvPath -Option Constant -Value 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment'

function Log-Output(){
	$args | Write-Host -ForegroundColor Cyan
}

function Log-Error(){
	$args | Write-Host -ForegroundColor Red
}

Set-Alias -Name lmsg -Value Log-Output -Description "Displays an informational message in green color" 
Set-Alias -Name lerr -Value Log-Error -Description "Displays an error message in red color" 

function ElasticSearch-UpdateService($scriptPath)
{
	$service = Get-WMIObject -class Win32_Service -Filter "name='elasticsearch-service-x64'"
	if ($service -ne $null)
	{
		lmsg 'Configure user account for service logon'
		.\ntrights.exe -u $username +r SeServiceLogonRight

		lmsg 'Update service to logon with user account'
		$service.Change($null,$null,$null,$null,$null,$null,".\$username",$password)

		$elasticService = (get-service | Where-Object {$_.Name -match 'elasticsearch'}).Name
		if($elasticService -ne $null)
		{
			lmsg 'Restarting elasticsearch service...'
			Stop-Service -Name $elasticService | Out-Null
			Start-Service -Name $elasticService | Out-Null
			$svc = Get-Service | Where-Object { $_.Name -Match 'elasticsearch'}
        
			if($svc -ne $null)
			{
				$svc.WaitForStatus('Running', '00:00:10')
			}

			Set-Service $elasticService -StartupType Automatic | Out-Null
		}
	}
}

function Mount-Share
{
	lmsg "mounting share"
	.\psexec.exe -accepteula -u ".\$username" -p "$password" net use * \\$afsAccount.file.core.windows.net\$afsShare /persistent:yes /user:$afsAccount $afsKey
	
	lmsg "adding credentials to store"
	.\psexec.exe -accepteula -u ".\$username" -p "$password" cmdkey /add:$afsAccount.file.core.windows.net /user:$afsAccount /pass:$afsKey
}

function Startup-Output
{
	lmsg 'Update workflow starting with following params:'
    lmsg "AFS credentials: acct:$afsAccount, share:$afsShare, key:$afsKey"
	lmsg "VM credentials: user:$username, pass:$password"
}

function Install-WorkFlow
{
	# Start script
    Startup-Output
	
	# Mount share
    Mount-Share

	# Update service
    ElasticSearch-UpdateService
}

Install-WorkFlow