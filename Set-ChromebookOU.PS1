<#
.SYNOPSIS
 Moves Chromebooks to propoer OU in GSuite.
.NOTES
 Starting tag is CB201800012001
 Tag number should always be 14 characters in length
#>

[cmdletbinding()]
param (
 [Parameter(Mandatory = $true)]
 [Alias('Server')]
 [string]$SQLServer,
 [Parameter(Mandatory = $true)]
 [Alias('Database')]
 [string]$SQLDatabase,
 [Parameter(Mandatory = $true)]
 [Alias('DBCred')]
 [System.Management.Automation.PSCredential]$SQLCredential,
 <# Specify a custom time for the process to end by.
 Defaults to 5:00pm. Loop interval is set to 15 minutes #>
 [Parameter(Mandatory = $False)]
 [string]$StopTime = '5:00pm',
 [Alias('wi')]
 [SWITCH]$WhatIf
)

function Get-GDevice {
 begin {
  $crosFields = 'annotatedUser,annotatedAssetId,orgUnitPath,deviceId,status'
 }
 process {
  # Write-Verbose ( $MyInvocation.MyCommand.Name, $_ | Out-String )
  $barcode = $_.barcode
  ($gamDev = & $gam print cros query "asset_id: $barcode" fields $crosFields) *>$null
  if (-not$gamDev) { return }
  $formattedDev = $gamDev | ConvertFrom-Csv
  $formattedDev.orgUnitPath = ($formattedDev.orgUnitPath | Out-String).Trim() # Cleanup ourUnitPath
  $obj = [PSCustomObject]@{
   sisData = $_ | ConvertTo-Csv | ConvertFrom-CSV
   dev     = $formattedDev
  }
  Write-Verbose ('{0},sn:[{1}]' -f $MyInvocation.MyCommand.Name, $obj.sisData.sn)
  $obj
 }
}

function Add-TargOU {
 begin {
  $wifiOu = "/Chromebooks/1:1/Student - Unrestricted WiFi Access"
  $stuOU = '/Chromebooks/1:1'
  $staffOU = '/Chromebooks/1:1/Teacher 1:1'
 }
 process {
  $msg = $MyInvocation.MyCommand.Name, $_.sisData.sn

  # Write-Verbose ( $MyInvocation.MyCommand.Name, $_.sisData | Out-String )
  # Write-Verbose ( $MyInvocation.MyCommand.Name, $_.dev | Out-String )

  $userType = $_.sisData.userType

  if ($userType.length -lt 1) { return (Write-Host ('{0},sn:[{1}],No userType detected') -f $msg) }

  $ou = if ($userType -eq 'S') {
   if ($_.dev.orgUnitPath -eq $wifiOu) { $wifiOu } # Keep in wifi OU
   else { $stuOu }
  }
  elseif ($userType -eq 'T') { $staffOU }

  if (-not$ou) { return (Write-Host ('{0},sn:[{1}],No targetOU detected') -f $msg) }

  $_ | Add-Member -MemberType NoteProperty -Name ou -Value $ou
  Write-Verbose ('{0},sn:[{1}],ou:[{2}]' -f $MyInvocation.MyCommand.Name, $_.sisData.sn, $_.ou)
  $_
 }
}

function Set-OU {
 process {
  if ($_.dev.orgUnitPath -eq $_.ou ) { return $_ }
  $msg = $MyInvocation.MyCommand.Name, $_.sisData.userType, $_.sisData.sn, $_.ou
  Write-Host ('{0},userType:[{1}],sn:[{2}],ou:[{3}]' -f $msg) -F Blue
  if (-not$WhatIf) { & $gam update cros $_.dev.deviceId ou $_.ou }
 }
}

function Set-DeviceActive {
 process {
  $msg = $MyInvocation.MyCommand.Name, $_.sisData.sn
  if ( $_.dev.status -eq 'ACTIVE' ) { return }
  Write-Host ('{0},sn:[{1}]' -f $msg) -F Blue
  if (-not$WhatIf) { & $gam update cros $id action reenable }
 }
}

# ============================= main =============================
$gam = '.\bin\gam.exe'

# Imported Functions
. .\lib\Load-Module.ps1
. .\lib\Show-TestRun.ps1

'SQLServer' | Load-Module

$sqlParams = @{
 Server                 = $SQLServer
 Database               = $SQLDatabase
 Credential             = $SQLCredential
 TrustServerCertificate = $true
}
$query = Get-Content .\sql\query-devices.sql -Raw

do {
 Show-TestRun
 $devices = Invoke-SqlCmd @sqlParams -Query $query
 $devices | Get-GDevice | Add-TargOU | Set-OU | Set-DeviceActive
 if (-not$WhatIf) { Start-Sleep (60 * 15) } #60 seconds * 15 minutes
} until ( $WhatIf -or ((Get-Date) -ge (Get-Date $StopTime)) )