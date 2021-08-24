#Requires -Version 5.0
<#
.SYNOPSIS
 Moves Chromebooks to propoer OU in GSuite.
.DESCRIPTION
.EXAMPLE
.INPUTS
.OUTPUTS
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
 [SWITCH]$WhatIf
)

# Variable
$ENV:GAM_DEVICE_MAX_RESULTS = 100
$gam = '.\lib\gam-64\gam.exe'

# Imported Functions
. '.\lib\Add-Log.ps1'
. '.\lib\Invoke-SQLCommand.ps1' # Useful function for querying SQL and returning results

# Functions

$query = Get-Content .\sql\query-devices.sql -Raw
$crosFields = 'annotatedUser,annotatedAssetId,orgUnitPath,deviceId,status'

# Processing
Add-Log script "Begin Processing. Running Until $(Get-Date $StopTime)." -WhatIf:$WhatIf
do {
 # Begin Do Loop
 $allCros = $null
 # $allCros = Import-Csv .\all-cros.csv
 $results = Invoke-SQLCommand -Server $SQLServer -Database $SQLDatabase -Credential $SQLCredential -Query $query
 $deviceCountThreshold = 100 # 67 is the optimal number as determined by benchmarking.
 if ($results.count -gt $deviceCountThreshold) {
  # Compares result count to threshold value
  Write-Verbose "Aeries results ($($results.count)) are over threshold ($deviceCountThreshold)."
  Write-Verbose 'Querying all Devices in GSuite'
  ($allCrosRaw = .$gam print cros fields $crosFields) *>$null
  $allCros = $allCrosRaw | ConvertFrom-Csv
 }
 foreach ($dev in $results) {
  $barcode = $dev.barcode
  Write-Debug "Process $barcode ?"
  # Search allCROS for matching barcode(asset_id)
  if ($allCros) { $gamDevice = $allCros.where( { $_.annotatedAssetId -eq $barcode }) }
  else {
   ($gamDeviceRaw = .$gam print cros query "asset_id: $barcode" fields $crosFields) *>$null
   $gamDevice = $gamDeviceRaw | ConvertFrom-Csv
  }
  if ($gamDevice) {
   # Begin Device Check
   $id = $gamDevice.deviceId
   $userType = $dev.userType

   # Begin Set orgUnitPath and annotatedUser fields in GSuite ====================================

   # Determine if (S)tudent or (T)eacher for OU placement.
   if ($userType -eq 'S') {
    if (($null -eq $dev.userGrade) -or ('' -eq $dev.userGrade)) {
     Add-Log warning ('{0}, userGrade not detected. {1} OU unchanged' -f $barcode, $gamDevice.orgUnitPath)
     $targOU = $gamDevice.orgUnitPath
    }
    elseif ($dev.userGrade -lt 2) { $targOU = '/Chromebooks/Clever Badge' }
    else { $targOU = '/Chromebooks/1:1' }
    Write-Verbose ( 'Grade: {0}. OU: {1}' -f $dev.userGrade, $targOU )
   }
   elseif ($userType -eq 'T') { $targOU = '/Chromebooks/1:1/Teacher 1:1' }
   else {
    Add-Log error ( " for CB: {1}. Should be 'S' or 'T'" -f $barcode )
    Write-Error 'userType not detected' -TargetObject $userType
   }

   $ouGsuite = ($gamDevice.orgUnitPath | Out-String).Trim() # Fix orgUnitPath string output from gam.exe
   
   if ($targOU -ne $ouGsuite) {
    # Check for non-matching orUnitPaths
    Write-Verbose "OrgUnitPAth = '$ouGsuite' - Should = '$targOU'"
    Add-Log update ( 'Barcode: {0},Grade: {1},OU: {2}' -f $barcode, $dev.userGrade , $targOU ) -WhatIf:$WhatIf
    if (!$WhatIf) { (.$gam update cros $id ou $targOU) *>$null }
    # End Set orgUnitPath and annotatedUser fields in GSuite ========================================
    # Begin Set device status (action disable/reenable) =======================================
    # Check if GSuite status for device is already correct
    if ( $gamDevice.status -eq 'ACTIVE' ) { continue }
    Add-Log update "$barcode,ACTIVE" -WhatIf:$WhatIf
    if (!$WhatIf) { [void] (.$gam update cros $id action reenable) }
    # End Set device status (action disable/reenable) =========================================
   }
   else { Write-Verbose "OrgUnitPath '$targOU' correct for $barcode" }
  }
  else {
   Add-Log warning "$barcode,GSuite asset_id/deviceId not found."
  }  # End Device Check
 }

 if (!$WhatIf) {
  # $waitTime = 15*60 # Seconds
  $waitTime = 5
  Write-Verbose "Next run at $((Get-Date).AddSeconds($waitTime))."
  Start-Sleep -Seconds $waitTime
 }
 
} until ( $WhatIf -or ((Get-Date) -ge (Get-Date $StopTime)) )
# End Do Loop