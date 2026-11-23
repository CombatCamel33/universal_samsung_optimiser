#Requires -Version 5.1
<#
  Universal Samsung Optimiser - Windows driver
  ---------------------------------------------------------------
  Debloats and tunes supported Samsung Galaxy tablets and watches
  over ADB. Every change is reversible.

  Usage:  .\run.ps1 [light|balanced|aggressive] [options]
  Help:   .\run.ps1 -Help

  Works on Windows PowerShell 5.1 and PowerShell 7+.
#>

$ErrorActionPreference = 'Continue'
$Version = '1.3.0'
$Root    = Split-Path -Parent $PSScriptRoot
$Profiles = Join-Path $Root 'profiles'
$BackupRoot = Join-Path $Root 'backups'

# ------------------------------------------------------------------ state
$script:Profile   = ''
$script:DryRun    = $false
$script:AssumeYes = $false
$script:Extras    = $false
$script:DisablePreloads = $false
$script:Trim      = $false
$script:Dexopt    = $false
$script:Reboot    = $false
$script:Mode      = 'apply'
$script:RestoreDir = ''
$script:UserList  = @()
$script:Serial    = ''
$script:Adb       = $env:ADB
$script:DeviceClass = 'tablet'
$script:DeviceLabel = 'Galaxy tablet / Android'
$script:Characteristics = ''
$script:HardwareId = ''
$script:WatchFeature = $false
$script:ProfileDir = $Profiles
$script:PackagesFile = Join-Path $script:ProfileDir 'packages.tsv'
$script:SettingsFile = Join-Path $script:ProfileDir 'settings.tsv'
$script:ExtrasFile = Join-Path $script:ProfileDir 'extras.tsv'
$script:Backups = $BackupRoot
$script:Tmp       = Join-Path ([System.IO.Path]::GetTempPath()) ("samsungopt-" + [guid]::NewGuid().ToString('N').Substring(0,8))
$script:Manifest  = ''
$script:SettingsManifest = ''
$script:LastBackup = ''

# ------------------------------------------------------------------ output
function Say    { param([string]$Text = '') Write-Host $Text }
function Info   { param([string]$Text) Write-Host ":: " -ForegroundColor Cyan -NoNewline; Write-Host $Text }
function Ok     { param([string]$Text) Write-Host "  ok " -ForegroundColor Green -NoNewline; Write-Host $Text }
function Warn   { param([string]$Text) Write-Host "  !! " -ForegroundColor Yellow -NoNewline; Write-Host $Text }
function Fail   { param([string]$Text) Write-Host "  xx " -ForegroundColor Red -NoNewline; Write-Host $Text }
function Head1  { param([string]$Text) Write-Host ''; Write-Host $Text -ForegroundColor White }
function Dim    { param([string]$Text) Write-Host $Text -ForegroundColor DarkGray }
function Die    { param([string]$Text) Fail $Text; exit 1 }

function Show-Usage {
  @"
Universal Samsung Optimiser v$Version

  .\run.ps1 <profile> [options]      apply a profile
  .\run.ps1 -Restore [dir]           undo the last run (or a specific backup)
  .\run.ps1 -RestoreAll              reinstall every package in every profile

Profiles
  light         safest telemetry, diagnostics and factory leftovers
  balanced      + optional Samsung/Google background features
  aggressive    + replaceable user-facing apps

  A Galaxy Watch is detected automatically and uses its own conservative,
  device-tested package list. Run -List to see both device families.

Options
  -Profile <name>   same as passing the profile as the first argument
  -DryRun           show what would happen, change nothing
  -User <id>        only touch this Android user (repeatable)
  -AllUsers         every real user profile (default: all except Secure Folder)
  -Extras           device-specific high-risk removals (read -List first)
  -DisablePreloads  hide /data-installed preloads instead of deleting them
                    (Office, Notes, Samsung Internet... stay on disk, restorable)
  -Trim             clear app caches
  -Dexopt           run a background dexopt job now (slow, optimises app start-up)
  -Reboot           reboot when finished
  -Yes              do not ask for confirmation
  -List             print the package lists
  -Report           print device info, RAM and storage
  -Serial <id>      target a specific device when several are attached
  -Help             this text
  -Version          print version

Environment
  ADB=C:\path\to\adb.exe   use a specific adb binary
"@
}

# ------------------------------------------------------------------ adb discovery
function Find-Adb {
  if ($script:Adb -and (Test-Path $script:Adb)) { return $true }
  $cmd = Get-Command adb -ErrorAction SilentlyContinue
  if ($cmd) { $script:Adb = $cmd.Source; return $true }
  $candidates = @(
    "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    "$env:USERPROFILE\AppData\Local\Android\Sdk\platform-tools\adb.exe",
    "$env:ANDROID_HOME\platform-tools\adb.exe",
    "$env:ANDROID_SDK_ROOT\platform-tools\adb.exe",
    "C:\platform-tools\adb.exe",
    "C:\adb\adb.exe",
    "C:\Program Files\Android\platform-tools\adb.exe"
  )
  foreach ($c in $candidates) {
    if ($c -and (Test-Path $c)) { $script:Adb = $c; return $true }
  }
  return $false
}

function Format-OneUi {
  param([string]$Value)
  if ($Value -match '^\d{3,}$') {
    $minor = [int]$Value.Substring(1, 2)
    return "$($Value.Substring(0,1)).$minor"
  }
  return $Value
}

function Invoke-Adb {
  param([string[]]$Arguments, [switch]$Quiet)
  $a = @()
  if ($script:Serial) { $a += @('-s', $script:Serial) }
  $a += $Arguments
  if ($Quiet) {
    $out = & $script:Adb @a 2>$null
  } else {
    $out = & $script:Adb @a 2>&1
  }
  return ($out | Out-String).Replace("`r", "").TrimEnd()
}

function Invoke-Shell { param([string]$Command) Invoke-Adb -Arguments @('shell', $Command) -Quiet }

function Set-DeviceProfile {
  $script:DeviceClass = 'tablet'
  $script:DeviceLabel = 'Galaxy tablet / Android'
  $script:ProfileDir = $Profiles
  $script:Backups = $BackupRoot

  if ((($script:Characteristics -split ',') -contains 'watch') -or $script:WatchFeature) {
    $script:DeviceClass = 'watch'
    $script:DeviceLabel = 'Galaxy Watch / Wear OS'
    $script:ProfileDir = Join-Path $Profiles 'watch'
    $safeId = ("{0}-{1}" -f $script:Model, $script:HardwareId) -replace '[^A-Za-z0-9._-]', '_'
    if (-not $safeId) { $safeId = 'unknown-watch' }
    $script:Backups = Join-Path $BackupRoot "watch-$safeId"
  }

  $script:PackagesFile = Join-Path $script:ProfileDir 'packages.tsv'
  $script:SettingsFile = Join-Path $script:ProfileDir 'settings.tsv'
  $script:ExtrasFile = Join-Path $script:ProfileDir 'extras.tsv'
}

function Get-Device {
  if (-not (Find-Adb)) { Die 'adb not found. Install Android platform-tools or set ADB=C:\path\to\adb.exe' }
  $raw = Invoke-Adb -Arguments @('devices')
  $ids = @()
  foreach ($line in ($raw -split "`n")) {
    $parts = $line -split '\s+'
    if ($parts.Count -ge 2 -and $parts[1] -eq 'device') { $ids += $parts[0] }
  }
  if ($ids.Count -eq 0) {
    Fail 'No authorised device found.'
    Say  '  1. Enable Developer options (Settings > About tablet > Software information > tap Build number 7x)'
    Say  '  2. Turn on USB debugging'
    Say  '  3. Reconnect the cable and accept the RSA prompt on the tablet'
    exit 1
  }
  if (-not $script:Serial) {
    $script:Serial = $ids[0]
    if ($ids.Count -gt 1) { Warn "Multiple devices attached - using $($script:Serial)" }
  }
  $null = Invoke-Adb -Arguments @('wait-for-device') -Quiet
  $script:Model   = Invoke-Shell 'getprop ro.product.model'
  $script:Device  = Invoke-Shell 'getprop ro.product.device'
  $script:Release = Invoke-Shell 'getprop ro.build.version.release'
  $script:Characteristics = Invoke-Shell 'getprop ro.build.characteristics'
  $script:HardwareId = Invoke-Shell 'getprop ro.serialno'
  $script:WatchFeature = ((Invoke-Shell 'pm has-feature android.hardware.type.watch') -eq 'true')
  Set-DeviceProfile
  $oneui          = Format-OneUi (Invoke-Shell 'getprop ro.build.version.oneui')
  $suffix = if ($oneui) { " / One UI $oneui" } else { '' }
  Info "Device: $($script:Model) ($($script:Device)) - Android $($script:Release)$suffix [$($script:DeviceLabel)]"
}

# ------------------------------------------------------------------ users
function Get-RealUsers {
  $raw = Invoke-Shell 'pm list users'
  $users = @()
  foreach ($line in ($raw -split "`n")) {
    if ($line -match 'UserInfo\{(\d+):([^:]*):') {
      $id = [int]$Matches[1]; $name = $Matches[2]
      if ($name -notmatch 'Secure') { $users += [pscustomobject]@{ Id = $id; Name = $name } }
    }
  }
  return $users
}

function Resolve-Users {
  if ($script:UserList.Count -gt 0) { return $script:UserList }
  return (Get-RealUsers | ForEach-Object { $_.Id })
}

function Get-UserLabel {
  param([int]$Id)
  $u = Get-RealUsers | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
  if ($u) { return $u.Name } else { return '' }
}

# ------------------------------------------------------------------ profiles
function Get-Tier {
  param([string]$Name)
  switch ($Name) {
    'light'      { return 1 }
    'balanced'   { return 2 }
    'aggressive' { return 3 }
    default      { return 0 }
  }
}

function Get-ProfileRows {
  param([string]$File, [int]$MaxTier)
  if (-not (Test-Path $File)) { return @() }
  $rows = @()
  foreach ($line in (Get-Content -LiteralPath $File)) {
    if ($line -match '^\s*#') { continue }
    $f = $line -split "`t"
    if ($f.Count -lt 4) { continue }
    if ($f[0] -eq 'extras') { $rows += ,$f; continue }
    if ([int]$f[0] -le $MaxTier) { $rows += ,$f }
  }
  return $rows
}

function Get-SettingRows {
  param([int]$MaxTier, [string]$File = $script:SettingsFile)
  $rows = @()
  foreach ($line in (Get-Content -LiteralPath $File)) {
    if ($line -match '^\s*#') { continue }
    $f = $line -split "`t"
    if ($f.Count -lt 5) { continue }
    if ([int]$f[0] -le $MaxTier) { $rows += ,$f }
  }
  return $rows
}

# ------------------------------------------------------------------ safety net
function Test-Protected {
  param([string]$Package)
  $protected = @(
    'android','com.android.systemui','com.android.settings','com.android.shell',
    'com.android.phone','com.android.server.telecom','com.android.providers.settings',
    'com.android.providers.media','com.android.providers.downloads',
    'com.android.providers.contacts','com.android.providers.telephony',
    'com.android.providers.calendar','com.android.packageinstaller',
    'com.google.android.packageinstaller','com.google.android.permissioncontroller',
    'com.google.android.webview','com.google.android.gms','com.google.android.gsf',
    'com.android.vending','com.google.android.networkstack',
    'com.google.android.networkstack.tethering','com.android.networkstack',
    'com.android.networkstack.tethering','com.android.bluetooth',
    'com.android.wifi.resources','com.android.keychain','com.android.certinstaller',
    'com.android.settings.intelligence','com.sec.android.app.launcher',
    'com.samsung.android.honeyboard','com.samsung.android.biometrics.app.setting',
    'com.samsung.android.location','com.android.externalstorage',
    'com.android.intentresolver','com.android.vpndialogs','com.android.mtp',
    'com.samsung.android.mtp'
  )
  if ($protected -contains $Package) { return $true }
  if ($script:DeviceClass -eq 'watch') {
    $watchProtected = @(
      'com.samsung.android.wearable.sysui','com.google.android.apps.wearable.systemui',
      'com.google.wear.services','com.google.android.wearable.app',
      'com.google.android.wearable.protolayout.renderer','com.google.android.gsmediator',
      'com.samsung.android.clientconnection','com.samsung.android.secondconnection',
      'com.samsung.android.wcs.extension','com.samsung.android.mcfds',
      'com.samsung.android.service.health','com.google.android.wearable.healthservices',
      'com.samsung.android.wear.shealth','com.samsung.android.shealthmonitor',
      'com.samsung.android.hardware.sensormanager.permission',
      'com.samsung.android.watch.safety_assistance','com.samsung.android.watch.findmywatch',
      'com.samsung.android.watch.stf','com.samsung.android.app.find','com.google.android.apps.adm',
      'com.android.nfc','com.samsung.android.dialer',
      'com.samsung.android.incallui','com.samsung.android.app.telephonyui',
      'com.samsung.advancedcallservice','com.samsung.android.mdecservice',
      'com.samsung.android.wear.blockednumber','com.samsung.android.providers.contacts',
      'com.samsung.android.app.contacts','com.samsung.wear.contacts.sync','com.sec.imsservice',
      'com.samsung.advp.imssettings','com.google.android.apps.messaging',
      'com.samsung.android.wearable.samsungaccount','com.samsung.android.scloud',
      'com.sec.android.app.samsungapps','com.samsung.android.wearable.setupwizard',
      'com.samsung.android.wearable.setupwizard.fota','com.sec.android.easyMover',
      'com.samsung.android.wear.smartswitchassistant','com.samsung.wear.watchface.runtime'
    )
    if (($watchProtected -contains $Package) -or $Package.StartsWith('com.samsung.android.watch.watchface.')) { return $true }
  }
  return $false
}

# ------------------------------------------------------------------ package state
function Get-PackageCache {
  param([int]$User)
  $path = Join-Path $script:Tmp "pkgs-$User.txt"
  if (-not (Test-Path $path)) {
    $out = Invoke-Shell "pm list packages --user $User"
    Set-Content -LiteralPath $path -Value $out -Encoding ASCII
    $sys = Invoke-Shell "pm list packages -s --user $User"
    Set-Content -LiteralPath (Join-Path $script:Tmp "pkgs-sys-$User.txt") -Value $sys -Encoding ASCII
    $disabled = Invoke-Shell "pm list packages -d --user $User"
    Set-Content -LiteralPath (Join-Path $script:Tmp "pkgs-disabled-$User.txt") -Value $disabled -Encoding ASCII
  }
  return $path
}

function Test-SystemPackage {
  param([int]$User, [string]$Package)
  $path = Join-Path $script:Tmp "pkgs-sys-$User.txt"
  if (-not (Test-Path $path)) { return $false }
  $needle = "package:$Package"
  foreach ($l in (Get-Content -LiteralPath $path)) {
    if ($l.Trim() -eq $needle) { return $true }
  }
  return $false
}

function Test-Installed {
  param([int]$User, [string]$Package)
  $path = Get-PackageCache -User $User
  if (-not (Test-Path $path)) { return $false }
  $needle = "package:$Package"
  foreach ($l in (Get-Content -LiteralPath $path)) {
    if ($l.Trim() -eq $needle) { return $true }
  }
  return $false
}

function Test-Disabled {
  param([int]$User, [string]$Package)
  $path = Join-Path $script:Tmp "pkgs-disabled-$User.txt"
  if (-not (Test-Path $path)) { return $false }
  $needle = "package:$Package"
  foreach ($l in (Get-Content -LiteralPath $path)) {
    if ($l.Trim() -eq $needle) { return $true }
  }
  return $false
}

# ------------------------------------------------------------------ apply
function Invoke-ApplyPackage {
  param([int]$User, [string]$Package, [string]$Category, [string]$Action = 'auto')
  if (-not $Action) { $Action = 'auto' }
  if ($Action -notin @('auto', 'uninstall', 'disable')) { Fail "$Package - invalid profile action '$Action'"; return 2 }
  if (Test-Protected $Package) { Fail "refusing to touch protected package: $Package"; return 2 }
  if (-not (Test-Installed -User $User -Package $Package)) { return 3 }
  if ((Test-Disabled -User $User -Package $Package) -and $Action -ne 'uninstall') { return 3 }

  if ($script:DryRun) {
    $isSystem = Test-SystemPackage -User $User -Package $Package
    if ($Action -eq 'disable') {
      Write-Host ("    {0,-48} {1} (would disable; APK + data kept)" -f $Package, $Category) -ForegroundColor DarkGray
    } elseif ($Action -eq 'uninstall' -and $isSystem) {
      Write-Host ("    {0,-48} {1} (would uninstall for user {2}; data kept)" -f $Package, $Category, $User) -ForegroundColor DarkGray
    } elseif (-not $isSystem -and $script:DisablePreloads) {
      Write-Host ("    {0,-48} {1} (preload: would disable)" -f $Package, $Category) -ForegroundColor DarkGray
    } elseif (-not $isSystem) {
      Write-Host ("    {0,-48} {1} (preload: would delete APK + data)" -f $Package, $Category) -ForegroundColor DarkGray
    } else {
      Write-Host ("    {0,-48} {1}" -f $Package, $Category) -ForegroundColor DarkGray
    }
    return 0
  }

  # System-image apps keep their data (-k) so a restore is lossless.
  # Data-installed preloads are removed completely - APK *and* data - because
  # their data would just be orphaned once the APK is gone.
  # Pass -DisablePreloads to hide them instead.
  $isSystemPkg = Test-SystemPackage -User $User -Package $Package
  if ($Action -ne 'disable' -and (-not $script:DisablePreloads -or $isSystemPkg)) {
    if ($isSystemPkg) {
      $out = Invoke-Shell "pm uninstall -k --user $User '$Package'"
    } else {
      $out = Invoke-Shell "pm uninstall --user $User '$Package'"
    }
    if ($out -match 'Success') {
      Add-Content -LiteralPath $script:Manifest -Value ("{0}`t{1}`tuninstalled`t{2}" -f $User, $Package, $Category) -Encoding ASCII
      Add-Content -LiteralPath (Join-Path $script:Backups 'applied.tsv') -Value ("{0}`t{1}`tuninstalled`t{2}" -f $User, $Package, $Category) -Encoding ASCII
      Write-Host ("    - {0,-48} {1}" -f $Package, $Category) -ForegroundColor DarkGray
      return 0
    }
  }

  $out = Invoke-Shell "pm disable-user --user $User '$Package'"
  if ($out -match 'disabled|Success') {
    Add-Content -LiteralPath $script:Manifest -Value ("{0}`t{1}`tdisabled`t{2}" -f $User, $Package, $Category) -Encoding ASCII
    Add-Content -LiteralPath (Join-Path $script:Backups 'applied.tsv') -Value ("{0}`t{1}`tdisabled`t{2}" -f $User, $Package, $Category) -Encoding ASCII
    Write-Host ("    x {0,-48} {1} (disabled)" -f $Package, $Category) -ForegroundColor DarkGray
    return 0
  }

  Fail "$Package - $out"
  return 1
}

function Set-Tweak {
  param([string]$Ns, [string]$Key, [string]$Value, [string]$Note)
  $old = Invoke-Shell "settings get $Ns $Key"
  if (-not $old) { $old = 'null' }

  if ($script:DryRun) {
    Write-Host ("    {0,-34} {1,-34} -> {2}" -f "$Ns/$Key", $old, $Value) -ForegroundColor DarkGray
    return
  }

  Add-Content -LiteralPath $script:SettingsManifest -Value ("{0}`t{1}`t{2}`t{3}" -f $Ns, $Key, $old, $Note) -Encoding ASCII
  Add-Content -LiteralPath (Join-Path $script:Backups 'original-settings.tsv') -Value ("{0}`t{1}`t{2}`t{3}" -f $Ns, $Key, $old, $Note) -Encoding ASCII

  if ($Value -eq '__DELETE__') {
    $null = Invoke-Shell "settings delete $Ns $Key"
  } else {
    $null = Invoke-Shell "settings put $Ns $Key $Value"
  }
  Ok "$Ns/$Key = $Value  (was $old)"
}

function Restore-Tweak {
  param([string]$Ns, [string]$Key, [string]$Old)
  if (-not $Old -or $Old -eq 'null' -or $Old -eq '__NULL__') {
    $null = Invoke-Shell "settings delete $Ns $Key"
    Ok "$Ns/$Key cleared"
  } else {
    $null = Invoke-Shell "settings put $Ns $Key $Old"
    Ok "$Ns/$Key = $Old"
  }
}

# ------------------------------------------------------------------ backup
function New-Backup {
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $dir = Join-Path $script:Backups $stamp
  $null = New-Item -ItemType Directory -Path $dir -Force
  $script:Manifest = Join-Path $dir 'packages.tsv'
  $script:SettingsManifest = Join-Path $dir 'settings.tsv'
  Set-Content -LiteralPath $script:Manifest -Value '' -Encoding ASCII
  Set-Content -LiteralPath $script:SettingsManifest -Value '' -Encoding ASCII
  $info = @(
    "Universal Samsung Optimiser v$Version",
    "date      : $(Get-Date)",
    "profile   : $($script:Profile)",
    "extras    : $($script:Extras)",
    "serial    : $($script:Serial)",
    "model     : $($script:Model)",
    "device    : $($script:Device)",
    "class     : $($script:DeviceClass)",
    "hardware  : $($script:HardwareId)",
    "android   : $($script:Release)",
    "host      : $([System.Environment]::OSVersion.VersionString)"
  )
  Set-Content -LiteralPath (Join-Path $dir 'info.txt') -Value $info -Encoding ASCII
  $script:LastBackup = $dir
}

function Get-LatestBackup {
  if (-not (Test-Path $script:Backups)) { return '' }
  $d = Get-ChildItem -LiteralPath $script:Backups -Directory | Sort-Object Name | Select-Object -Last 1
  if ($d) { return $d.FullName } else { return '' }
}

# ------------------------------------------------------------------ report
function Show-Report {
  Head1 'Device'
  Say "  Model      : $(Invoke-Shell 'getprop ro.product.model')"
  Say "  Target     : $($script:DeviceLabel)"
  Say "  Product    : $(Invoke-Shell 'getprop ro.product.name')"
  Say "  Android    : $(Invoke-Shell 'getprop ro.build.version.release') (SDK $(Invoke-Shell 'getprop ro.build.version.sdk'))"
  Say "  One UI     : $(Format-OneUi (Invoke-Shell 'getprop ro.build.version.oneui'))"
  Say "  Build      : $(Invoke-Shell 'getprop ro.build.display.id')"
  Say "  Security   : $(Invoke-Shell 'getprop ro.build.version.security_patch')"
  Say "  CSC        : $(Invoke-Shell 'getprop ro.csc.sales_code')"

  Head1 'Display'
  foreach ($l in ((Invoke-Shell 'wm size') -split "`n")) { Say "  $l" }
  foreach ($l in ((Invoke-Shell 'wm density') -split "`n")) { Say "  $l" }
  Say ("  Animations : " + (Invoke-Shell 'settings get global window_animation_scale') + ' / ' +
       (Invoke-Shell 'settings get global transition_animation_scale') + ' / ' +
       (Invoke-Shell 'settings get global animator_duration_scale'))

  Head1 'Memory'
  foreach ($l in ((Invoke-Shell 'cat /proc/meminfo') -split "`n" | Select-Object -First 4)) { Say "  $l" }

  Head1 'Storage'
  Say ("  " + (Invoke-Shell 'df -h /data | tail -1'))

  if ($script:DeviceClass -eq 'watch') {
    Head1 'Battery'
    foreach ($line in ((Invoke-Shell 'dumpsys battery') -split "`n")) {
      if ($line -match '^\s*(level|status|health|temperature):') { Say "  $line" }
    }
  }

  Head1 'Users'
  foreach ($u in (Get-RealUsers)) { Say "  $($u.Id)  $($u.Name)" }

  Head1 'Top 10 RAM consumers'
  $mem = Invoke-Shell 'dumpsys meminfo'
  $lines = $mem -split "`n"
  $start = -1
  for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match 'Total RSS by process') { $start = $i; break } }
  if ($start -ge 0) {
    $lines[($start + 2)..([Math]::Min($start + 11, $lines.Count - 1))] | ForEach-Object { Say "  $_" }
  }

  Head1 'Package counts'
  foreach ($u in (Resolve-Users)) {
    $n = (Invoke-Shell "pm list packages --user $u") -split "`n"
    Say "  user $u : $($n.Count) installed"
  }
}

# ------------------------------------------------------------------ list
function Show-ProfileList {
  param([string]$Title, [string]$Directory)
  Head1 $Title
  foreach ($t in 1, 2, 3) {
    $label = @('light', 'balanced', 'aggressive')[$t - 1]
    $rows = @(Get-ProfileRows -File (Join-Path $Directory 'packages.tsv') -MaxTier $t)
    Head1 "$label (tier <= $t) - $($rows.Count) packages"
    foreach ($r in $rows) {
      $action = if ($r.Count -ge 5 -and $r[4]) { " [$($r[4])]" } else { '' }
      Say ("  {0,-52} {1}{2}" -f $r[1], $r[3], $action)
    }
  }
  $ex = @(Get-ProfileRows -File (Join-Path $Directory 'extras.tsv') -MaxTier 9)
  Head1 "extras (--extras only) - $($ex.Count) packages"
  foreach ($r in $ex) {
    $action = if ($r.Count -ge 5 -and $r[4]) { " [$($r[4])]" } else { '' }
    Say ("  {0,-52} {1}{2}" -f $r[1], $r[3], $action)
  }
  Head1 'settings'
  foreach ($r in @(Get-SettingRows -MaxTier 3 -File (Join-Path $Directory 'settings.tsv'))) {
    Say ("  [tier {0}] {1}/{2} = {3}" -f $r[0], $r[1], $r[2], $r[3])
  }
}

function Show-List {
  Show-ProfileList -Title 'Galaxy tablet / Android profiles' -Directory $Profiles
  Show-ProfileList -Title 'Galaxy Watch / Wear OS profiles' -Directory (Join-Path $Profiles 'watch')
}

# ------------------------------------------------------------------ before / after snapshots
function Save-Snapshot {
  param([string]$Path, [object[]]$Users)
  $installed = 0
  $enabled = 0
  foreach ($u in $Users) {
    $installed += @((Invoke-Shell "pm list packages --user $u") -split "`n" | Where-Object { $_.Trim() }).Count
    $enabled += @((Invoke-Shell "pm list packages -e --user $u") -split "`n" | Where-Object { $_.Trim() }).Count
  }

  $memKb = 0
  $memText = Invoke-Shell 'cat /proc/meminfo'
  if ($memText -match '(?m)^MemAvailable:\s+(\d+)') { $memKb = [long]$Matches[1] }

  $dataFreeKb = 0
  $dfLines = @((Invoke-Shell 'df -k /data') -split "`n" | Where-Object { $_.Trim() })
  if ($dfLines.Count -gt 0) {
    $parts = @($dfLines[-1].Trim() -split '\s+')
    if ($parts.Count -ge 4 -and $parts[3] -match '^\d+$') { $dataFreeKb = [long]$parts[3] }
  }

  $battery = 0
  $batteryText = Invoke-Shell 'dumpsys battery'
  if ($batteryText -match '(?m)^\s*level:\s*(\d+)') { $battery = [int]$Matches[1] }

  $lines = @(
    "captured_at`t$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "installed_packages`t$installed",
    "enabled_packages`t$enabled",
    "mem_available_kb`t$memKb",
    "data_free_kb`t$dataFreeKb",
    "battery_percent`t$battery"
  )
  Set-Content -LiteralPath $Path -Value $lines -Encoding ASCII
}

function Get-SnapshotValue {
  param([string]$Path, [string]$Key)
  foreach ($line in (Get-Content -LiteralPath $Path)) {
    $parts = $line -split "`t", 2
    if ($parts.Count -eq 2 -and $parts[0] -eq $Key) { return $parts[1] }
  }
  return '0'
}

function Format-MiB { param([double]$Kb) return ("{0:F1} MiB" -f ($Kb / 1024)) }
function Format-GiB { param([double]$Kb) return ("{0:F2} GiB" -f ($Kb / 1048576)) }
function Format-NumberDelta { param([double]$Before, [double]$After) return ("{0:+0;-0;0}" -f ($After - $Before)) }
function Format-MemoryDelta { param([double]$Before, [double]$After) return ("{0:+0.0;-0.0;0.0} MiB" -f (($After - $Before) / 1024)) }
function Format-StorageDelta { param([double]$Before, [double]$After) return ("{0:+0.00;-0.00;0.00} GiB" -f (($After - $Before) / 1048576)) }

function Show-Snapshot {
  param([string]$Heading, [string]$Path)
  $installed = Get-SnapshotValue $Path 'installed_packages'
  $enabled = Get-SnapshotValue $Path 'enabled_packages'
  $mem = [double](Get-SnapshotValue $Path 'mem_available_kb')
  $free = [double](Get-SnapshotValue $Path 'data_free_kb')
  $battery = Get-SnapshotValue $Path 'battery_percent'
  Head1 $Heading
  Say "  Installed packages : $installed"
  Say "  Enabled packages   : $enabled"
  Say "  Available RAM      : $(Format-MiB $mem)"
  Say "  Free /data         : $(Format-GiB $free)"
  Say "  Battery            : $battery%"
}

function Show-BeforeAfter {
  param([string]$BeforePath, [string]$AfterPath)
  $bi = [double](Get-SnapshotValue $BeforePath 'installed_packages'); $ai = [double](Get-SnapshotValue $AfterPath 'installed_packages')
  $be = [double](Get-SnapshotValue $BeforePath 'enabled_packages');   $ae = [double](Get-SnapshotValue $AfterPath 'enabled_packages')
  $bm = [double](Get-SnapshotValue $BeforePath 'mem_available_kb');   $am = [double](Get-SnapshotValue $AfterPath 'mem_available_kb')
  $bf = [double](Get-SnapshotValue $BeforePath 'data_free_kb');       $af = [double](Get-SnapshotValue $AfterPath 'data_free_kb')
  $bb = [double](Get-SnapshotValue $BeforePath 'battery_percent');    $ab = [double](Get-SnapshotValue $AfterPath 'battery_percent')
  Head1 'Before -> after (immediate)'
  Say ("  {0,-21} {1,14} {2,14} {3,14}" -f 'Metric', 'Before', 'After', 'Change')
  Say ("  {0,-21} {1,14} {2,14} {3,14}" -f 'Installed packages', $bi, $ai, (Format-NumberDelta $bi $ai))
  Say ("  {0,-21} {1,14} {2,14} {3,14}" -f 'Enabled packages', $be, $ae, (Format-NumberDelta $be $ae))
  Say ("  {0,-21} {1,14} {2,14} {3,14}" -f 'Available RAM', (Format-MiB $bm), (Format-MiB $am), (Format-MemoryDelta $bm $am))
  Say ("  {0,-21} {1,14} {2,14} {3,14}" -f 'Free /data', (Format-GiB $bf), (Format-GiB $af), (Format-StorageDelta $bf $af))
  Say ("  {0,-21} {1,13}% {2,13}% {3,13}%" -f 'Battery', $bb, $ab, (Format-NumberDelta $bb $ab))
  Dim '  RAM is an immediate reading; compare again after reboot for a stable result.'
}

# ------------------------------------------------------------------ apply
function Invoke-Apply {
  $tier = Get-Tier $script:Profile
  if ($tier -eq 0) { Die "unknown profile '$($script:Profile)' (use light, balanced or aggressive)" }

  Get-Device
  $users = @(Resolve-Users)
  if ($users.Count -eq 0) { Die 'could not determine any user profile' }

  $pkgCount = (Get-ProfileRows -File $script:PackagesFile -MaxTier $tier).Count
  Head1 'Plan'
  Say "  Target     : $($script:DeviceLabel)"
  Say "  Profile    : $($script:Profile) (tier <= $tier)"
  Say "  Packages   : $pkgCount"
  Say "  Settings   : $(@(Get-SettingRows -MaxTier $tier).Count)"
  Say "  Users      : $($users -join ' ')"
  if ($script:Extras) { Warn 'extras enabled - device-critical optional services will be changed' }
  if ($script:DisablePreloads) { Say '  Preloads   : disabled (kept on disk) instead of deleted' }
  if ($script:DryRun) { Warn 'dry run - nothing will change' }

  if (-not $script:DryRun -and -not $script:AssumeYes) {
    $answer = Read-Host '  Continue? [y/N]'
    if ($answer -notmatch '^[yY]') { Say '  cancelled.'; return }
  }

  if (-not $script:DryRun) {
    New-Backup
    Info "Backup written to $($script:LastBackup)"
    $beforeFile = Join-Path $script:LastBackup 'before.txt'
  } else {
    $beforeFile = Join-Path $script:Tmp 'before.txt'
  }
  Save-Snapshot -Path $beforeFile -Users $users
  if ($script:DryRun) { Show-Snapshot -Heading 'Current baseline' -Path $beforeFile }

  $rows = @(Get-ProfileRows -File $script:PackagesFile -MaxTier $tier)
  if ($script:Extras) { $rows += @(Get-ProfileRows -File $script:ExtrasFile -MaxTier 9) }

  $total = 0
  foreach ($u in $users) {
    Head1 "User $u - $(Get-UserLabel $u)"
    $null = Get-PackageCache -User $u
    Info 'Applying package profile'
    foreach ($r in $rows) {
      $action = if ($r.Count -ge 5 -and $r[4]) { $r[4] } else { 'auto' }
      $rc = Invoke-ApplyPackage -User $u -Package $r[1] -Category $r[2] -Action $action
      if ($rc -eq 0) { $total++ }
    }
  }

  Head1 'System settings'
  foreach ($r in @(Get-SettingRows -MaxTier $tier)) {
    Set-Tweak -Ns $r[1] -Key $r[2] -Value $r[3] -Note $r[4]
  }

  if ($script:Trim -and -not $script:DryRun) {
    Head1 'Clearing app caches'
    $null = Invoke-Shell 'cmd package trim-caches 64G'
    Ok 'caches trimmed'
  }

  if ($script:Dexopt -and -not $script:DryRun) {
    Head1 'Background dexopt'
    Dim '  this can take several minutes...'
    $null = Invoke-Shell 'cmd package bg-dexopt-job'
    Ok 'dexopt job finished'
  }

  if ($script:DryRun) {
    Head1 'Done'
    Say '  Dry run complete - nothing was changed.'
  } else {
    $afterFile = Join-Path $script:LastBackup 'after.txt'
    Save-Snapshot -Path $afterFile -Users $users
    Show-BeforeAfter -BeforePath $beforeFile -AfterPath $afterFile
    Head1 'Done'
    Say "  $total package actions applied."
    Say "  Backup: $($script:LastBackup)"
    Say '  Undo  : .\run.ps1 -Restore'
    Dim '  A reboot is recommended so every change takes effect.'
    if ($script:DeviceClass -eq 'watch') { Dim '  Turn off ADB debugging and wireless debugging on the watch when finished.' }
  }

  if ($script:Reboot -and -not $script:DryRun) {
    Info 'Rebooting device'
    $null = Invoke-Adb -Arguments @('reboot') -Quiet
  }
}

# ------------------------------------------------------------------ restore
function Assert-BackupTarget {
  param([string]$Directory)
  $infoFile = Join-Path $Directory 'info.txt'
  if (-not (Test-Path $infoFile)) { Warn 'backup has no device metadata; target cannot be verified'; return }
  $backupDevice = ''
  $backupClass = ''
  foreach ($line in (Get-Content -LiteralPath $infoFile)) {
    if ($line -match '^device\s*:\s*(.*)$') { $backupDevice = $Matches[1].Trim() }
    if ($line -match '^class\s*:\s*(.*)$') { $backupClass = $Matches[1].Trim() }
  }
  if ($backupDevice -and $backupDevice -ne $script:Device) {
    Die "backup is for device '$backupDevice', but the connected device is '$($script:Device)'"
  }
  if ($backupClass -and $backupClass -ne $script:DeviceClass) {
    Die "backup is for class '$backupClass', but the connected device is '$($script:DeviceClass)'"
  }
}

function Invoke-Restore {
  Get-Device
  $pkgSrc = ''
  $setSrc = ''

  if ($script:RestoreDir) {
    $dir = $script:RestoreDir
    if (-not (Test-Path $dir)) { Die "backup not found: $dir" }
    $pkgSrc = Join-Path $dir 'packages.tsv'
    if (-not (Test-Path $pkgSrc)) { Die "not a valid backup (no packages.tsv): $dir" }
    Assert-BackupTarget -Directory $dir
    $setSrc = Join-Path $dir 'settings.tsv'
    Head1 "Restoring a single run from $dir"
    $infoFile = Join-Path $dir 'info.txt'
    if (Test-Path $infoFile) { Get-Content $infoFile | ForEach-Object { Say "  $_" } }
  } else {
    $pkgSrc = Join-Path $script:Backups 'applied.tsv'
    $setSrc = Join-Path $script:Backups 'original-settings.tsv'
    if (-not (Test-Path $pkgSrc)) { Die 'nothing to restore - no changes have been applied yet' }
    Head1 'Restoring every change this tool has ever made'
    $pkgLines = @(Get-Content -LiteralPath $pkgSrc | Where-Object { $_.Trim() } | Sort-Object -Unique)
    $setKeys = @{}
    if (Test-Path $setSrc) {
      foreach ($line in (Get-Content -LiteralPath $setSrc)) {
        $f = $line -split "`t"
        if ($f.Count -ge 3) { $setKeys["$($f[0].Trim())|$($f[1].Trim())"] = $true }
      }
    }
    Say "  packages: $($pkgLines.Count) rows"
    Say "  settings: $($setKeys.Count) keys"
  }

  if (-not $script:AssumeYes -and -not $script:DryRun) {
    $answer = Read-Host '  Continue? [y/N]'
    if ($answer -notmatch '^[yY]') { Say '  cancelled.'; return }
  }

  Head1 'Reinstalling packages'
  $n = 0
  $pkgLines = @(Get-Content -LiteralPath $pkgSrc | Where-Object { $_.Trim() } | Sort-Object -Unique)
  foreach ($line in $pkgLines) {
    $f = $line -split "`t"
    if ($f.Count -lt 3) { continue }
    $u = $f[0].Trim(); $pkg = $f[1].Trim(); $action = $f[2].Trim()
    if ($script:DryRun) { Say "    would restore $pkg (user $u)"; continue }
    if ($action -eq 'uninstalled') {
      $out = Invoke-Shell "pm install-existing --user $u '$pkg'"
      if ($out -match 'installed') { Ok "$pkg (user $u)"; $n++ }
      elseif ($out -match "doesn't exist|Unknown package|not installed") { Warn "$pkg (user $u) is no longer on the device - reinstall it from the Galaxy/Play Store" }
      else { Fail "$pkg (user $u): $out" }
    } elseif ($action -eq 'disabled') {
      $out = Invoke-Shell "pm enable --user $u '$pkg'"
      if ($out -match 'enabled') { Ok "$pkg (user $u) enabled"; $n++ } else { Fail "$pkg (user $u): $out" }
    }
  }

  Head1 'Restoring settings'
  if (Test-Path $setSrc) {
    $seen = @{}
    foreach ($line in (Get-Content -LiteralPath $setSrc)) {
      $f = $line -split "`t"
      if ($f.Count -lt 3) { continue }
      $ns = $f[0].Trim(); $k = $f[1].Trim(); $v = $f[2].Trim()
      $id = "$ns|$k"
      if ($seen.ContainsKey($id)) { continue }   # keep the oldest = the real original
      $seen[$id] = $true
      if ($script:DryRun) { Say "    would restore $ns/$k = $v" }
      else { Restore-Tweak -Ns $ns -Key $k -Old $v }
    }
  }

  Head1 'Done'
  if ($script:DryRun) {
    Say '  Dry run complete - nothing was restored.'
  } else {
    Say "  $n packages restored. Reboot recommended."
    if ($script:Reboot) { $null = Invoke-Adb -Arguments @('reboot') -Quiet }
  }
}

# ------------------------------------------------------------------ restore all
function Invoke-RestoreAll {
  Get-Device
  Head1 'Reinstalling every package from every profile'
  if (-not $script:AssumeYes -and -not $script:DryRun) {
    $answer = Read-Host '  This reinstalls every package in every profile on all users. Continue? [y/N]'
    if ($answer -notmatch '^[yY]') { Say '  cancelled.'; return }
  }

  $rows = @(Get-ProfileRows -File $script:PackagesFile -MaxTier 9)
  $rows += @(Get-ProfileRows -File $script:ExtrasFile -MaxTier 9)
  $n = 0

  foreach ($u in (Resolve-Users)) {
    Head1 "User $u - $(Get-UserLabel $u)"
    foreach ($r in $rows) {
      $action = if ($r.Count -ge 5 -and $r[4]) { $r[4] } else { 'auto' }
      if ($script:DryRun) {
        if ($action -eq 'disable') { Say "    would enable $($r[1])" } else { Say "    would reinstall $($r[1])" }
        continue
      }
      if ($action -eq 'disable') {
        $out = Invoke-Shell "pm enable --user $u '$($r[1])'"
        if ($out -match 'enabled') { $n++ }
      } else {
        $out = Invoke-Shell "pm install-existing --user $u '$($r[1])'"
        if ($out -match 'installed') { $n++ }
      }
    }
    if ($script:DeviceClass -ne 'watch' -and -not $script:DryRun) { $null = Invoke-Shell "pm enable --user $u 'com.android.chrome'" }
  }

  Head1 'Restoring default settings'
  if ($script:DryRun) {
    Say '    would restore animation scales and clear the cached-app freezer override'
    if ($script:DeviceClass -ne 'watch') { Say '    would restore tablet CPU, radio-scan and refresh-rate defaults' }
  } else {
    $null = Invoke-Shell 'settings put global window_animation_scale 1.0'
    $null = Invoke-Shell 'settings put global transition_animation_scale 1.0'
    $null = Invoke-Shell 'settings put global animator_duration_scale 1.0'
    $null = Invoke-Shell 'settings delete global cached_apps_freezer'
    if ($script:DeviceClass -ne 'watch') {
      $null = Invoke-Shell 'settings put global sem_enhanced_cpu_responsiveness 0'
      $null = Invoke-Shell 'settings put global wifi_scan_always_enabled 1'
      $null = Invoke-Shell 'settings put global ble_scan_always_enabled 1'
      $null = Invoke-Shell 'settings delete system min_refresh_rate'
      $null = Invoke-Shell 'settings delete system peak_refresh_rate'
    }
    Ok "default settings restored for $($script:DeviceLabel)"
  }

  Head1 'Done'
  if ($script:DryRun) { Say '  Dry run complete - nothing was changed.' }
  else { Say "  $n package actions restored. Reboot recommended." }
  if ($script:Reboot -and -not $script:DryRun) { $null = Invoke-Adb -Arguments @('reboot') -Quiet }
}

# ------------------------------------------------------------------ arguments
$argsList = @($args)
for ($i = 0; $i -lt $argsList.Count; $i++) {
  $a = $argsList[$i]
  switch -Regex ($a) {
    '^(light|balanced|aggressive)$' { $script:Profile = $a }
    '^-Profile(=(.*))?$'            { if ($Matches[2]) { $script:Profile = $Matches[2] } else { $i++; $script:Profile = $argsList[$i] } }
    '^-DryRun$'                     { $script:DryRun = $true }
    '^-Yes$|^-y$'                   { $script:AssumeYes = $true }
    '^-Extras$'                     { $script:Extras = $true }
    '^-DisablePreloads$'            { $script:DisablePreloads = $true }
    '^-Trim$'                       { $script:Trim = $true }
    '^-Dexopt$'                     { $script:Dexopt = $true }
    '^-Reboot$'                     { $script:Reboot = $true }
    '^-AllUsers$'                   { $script:UserList = @() }
    '^-User(=(.*))?$'               { if ($Matches[2]) { $script:UserList += [int]$Matches[2] } else { $i++; $script:UserList += [int]$argsList[$i] } }
    '^-Serial(=(.*))?$'             { if ($Matches[2]) { $script:Serial = $Matches[2] } else { $i++; $script:Serial = $argsList[$i] } }
    '^-RestoreAll$'                 { $script:Mode = 'restore-all' }
    '^-Restore$'                    { $script:Mode = 'restore'; if ($i + 1 -lt $argsList.Count -and $argsList[$i+1] -notmatch '^-') { $i++; $script:RestoreDir = $argsList[$i] } }
    '^-List$'                       { $script:Mode = 'list' }
    '^-Report$'                     { $script:Mode = 'report' }
    '^-Help$|^-h$|^-\?$'            { Show-Usage; exit 0 }
    '^-Version$'                    { Say "universal-samsung-optimiser $Version"; exit 0 }
    default                         { Fail "unknown argument: $a"; Say ''; Show-Usage; exit 2 }
  }
}

$null = New-Item -ItemType Directory -Path $script:Tmp -Force

switch ($script:Mode) {
  'list'        { Show-List; exit 0 }
  'report'      { Get-Device; Show-Report; exit 0 }
  'restore'     { Invoke-Restore; exit 0 }
  'restore-all' { Invoke-RestoreAll; exit 0 }
}

# ------------------------------------------------------------------ interactive menu
if (-not $script:Profile) {
  Get-Device
  Head1 "Universal Samsung Optimiser v$Version"
  Say "  Device: $($script:Model) - Android $($script:Release) ($($script:DeviceLabel))"
  Say ''
  if ($script:DeviceClass -eq 'watch') {
    Say '  1) light       - retail demo, certification and factory test leftovers'
    Say '  2) balanced    - + Bixby, customisation and enterprise provisioning'
    Say '  3) aggressive  - + optional apps; calls, Google Messages and health stay'
  } else {
    Say '  1) light       - telemetry, diagnostics, AR toys, preloads'
    Say '  2) balanced    - + Bixby, Samsung extras, gaming services, TTS packs'
    Say '  3) aggressive  - + browsers, Office, YouTube, Samsung account apps'
  }
  Say '  4) restore     - undo the last run'
  Say '  5) report      - show device info without changing anything'
  Say '  q) quit'
  $choice = Read-Host '  Choose [1-5/q]'
  switch ($choice) {
    '1' { $script:Profile = 'light' }
    '2' { $script:Profile = 'balanced' }
    '3' { $script:Profile = 'aggressive' }
    '4' { Invoke-Restore; exit 0 }
    '5' { Show-Report; exit 0 }
    default { Say '  bye.'; exit 0 }
  }
}

Invoke-Apply
