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

function Complete-Processing {
 process {
  Write-Verbose ('{0},[{1}]' -f $MyInvocation.MyCommand.Name, $_.barcode)
  # Read-Host Arrrrrrrggggggg
 }
}

function Add-TargOU {
 begin {
  $wifiOu = "/Chromebooks/1:1/Student - Unrestricted WiFi Access"
  $stuOU = '/Chromebooks/1:1'
  $staffOU = '/Chromebooks/1:1/Teacher 1:1'
 }
 process {
  $msg = $MyInvocation.MyCommand.Name, $_.barCode
  if ($_.userType.length -lt 1) { return (Write-Host ('{0},[{1}],No userType detected' -f $msg)) }

  $targOu = if ($_.userType -eq 'S') {
   if ($_.devOu -eq $wifiOu) { $wifiOu } # Keep in wifi OU
   else { $stuOu }
  }
  elseif ($_.userType -eq 'T') { $staffOU }

  if (-not$targOu) { return (Write-Host ('{0},[{1}],No targetOU detected') -f $msg) }

  $_.targOu = $targOu
  Write-Verbose ('{0},[{1}],[{2}]' -f $MyInvocation.MyCommand.Name, $_.barCode, $_.targOu)
  $_
 }
}

function Format-Obj {
 process {
  [PSCustomObject]@{
   barcode   = $_.barCode
   userType  = $_.userType
   sn        = $_.sn
   targOu    = $null
   devId     = $null
   devOu     = $null
   devuser   = $null
   devStatus = $null
  }
 }
}

function Get-GDevice {
 begin {
  $crosFields = 'annotatedUser,annotatedAssetId,orgUnitPath,deviceId,status'
 }
 process {
  # Write-Verbose ( $MyInvocation.MyCommand.Name, $_ | Out-String )
  Write-Verbose "& $gam print cros query `"asset_id: $($_.barcode)`" fields $crosFields"
  ($gamDev = & $gam print cros query "asset_id: $($_.barcode)" fields $crosFields) *>$null
  if (-not$gamDev) { return (Write-Verbose Fuck) }
  $devObj = $gamDev | ConvertFrom-Csv
  Write-Verbose ('{0},[{1}]' -f $MyInvocation.MyCommand.Name, $_.barcode)
  $_.devId = $devObj.deviceId
  $_.devOu = $devObj.orgUnitPath.Trim()
  $_.devUser = $devObj.annotatedUser
  $_.devStatus = $devObj.status
  $_
 }
}

function Update-OU {
 process {
  Write-Verbose ( $MyInvocation.MyCommand.Name, $_ | Out-String )
  if ($_.devOu -eq $_.targOu ) { return $_ }
  $msg = $MyInvocation.MyCommand.Name, $_.userType, $_.barCode, $_.devOu, $_.targOu
  Write-Host ('{0},[{1}],[{2}],[{3}] -> [{4}]' -f $msg) -F Blue
  Write-Host "& $gam update cros $($_.devId) ou `"$($_.targOu)`"" -F Blue
  # GAM and quotes can be tricky
  if (-not$WhatIf) { (& $gam update cros $_.devId ou "$($_.targOu)") *>$null }
  $_
 }
}

function Set-DeviceActive {
 process {
  $msg = $MyInvocation.MyCommand.Name, $_.barCode, $_.devId
  Write-Verbose ('{0},[{1}],[{2}]' -f $msg)
  if ( $_.devStatus -eq 'ACTIVE' ) { return $_ }
  Write-Host ('{0},[{1}],[{2}]' -f $msg) -F Blue
  Write-Host ("& $gam update cros $($_.devId) action reenable") -F Blue
  if (-not$WhatIf) { (& $gam update cros $_.devId action reenable) *>$null }
  $_
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
 $devices | Format-Obj | Get-GDevice | Add-TargOU |
 Update-OU | Set-DeviceActive | Complete-Processing
 'Next run at {0}' -f ((Get-Date).AddMinutes(15))
 if (-not$WhatIf) { Start-Sleep (60 * 15) } #60 seconds * 15 minutes
} until ( $WhatIf -or ((Get-Date) -ge (Get-Date $StopTime)) )