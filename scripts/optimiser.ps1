#Requires -Version 5.1
<#
  Tab S10 FE+ Optimiser - Windows driver
  ---------------------------------------------------------------
  Debloats and tunes a Samsung Galaxy Tab S10 FE+ (or any modern
  Samsung/Android device) over ADB. Every change is reversible.

  Usage:  .\run.ps1 [light|balanced|aggressive] [options]
  Help:   .\run.ps1 -Help

  Works on Windows PowerShell 5.1 and PowerShell 7+.
#>

$ErrorActionPreference = 'Continue'
$Version = '1.1.0'
$Root    = Split-Path -Parent $PSScriptRoot
$Profiles = Join-Path $Root 'profiles'
$Backups  = Join-Path $Root 'backups'

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
$script:Tmp       = Join-Path ([System.IO.Path]::GetTempPath()) ("tabopt-" + [guid]::NewGuid().ToString('N').Substring(0,8))
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
Tab S10 FE+ Optimiser v$Version

  .\run.ps1 <profile> [options]      apply a profile
  .\run.ps1 -Restore [dir]           undo the last run (or a specific backup)
  .\run.ps1 -RestoreAll              reinstall every package in every profile

Profiles
  light         telemetry, diagnostics, AR toys, preloads
  balanced      + Bixby, Samsung extras, gaming services, TTS packs
  aggressive    + browsers, Office, YouTube, Samsung account apps

Options
  -Profile <name>   same as passing the profile as the first argument
  -DryRun           show what would happen, change nothing
  -User <id>        only touch this Android user (repeatable)
  -AllUsers         every real user profile (default: all except Secure Folder)
  -Extras           also remove Knox / OTA / Samsung account (breaks Secure Folder)
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
  $oneui          = Invoke-Shell 'getprop ro.build.version.oneui'
  $suffix = if ($oneui) { " / One UI $oneui" } else { '' }
  Info "Device: $($script:Model) ($($script:Device)) - Android $($script:Release)$suffix"
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
  param([int]$MaxTier)
  $file = Join-Path $Profiles 'settings.tsv'
  $rows = @()
  foreach ($line in (Get-Content -LiteralPath $file)) {
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
  return ($protected -contains $Package)
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

# ------------------------------------------------------------------ apply
function Invoke-ApplyPackage {
  param([int]$User, [string]$Package, [string]$Category)
  if (Test-Protected $Package) { Fail "refusing to touch protected package: $Package"; return 2 }
  if (-not (Test-Installed -User $User -Package $Package)) { return 3 }

  if ($script:DryRun) {
    $isSystem = Test-SystemPackage -User $User -Package $Package
    if (-not $isSystem -and $script:DisablePreloads) {
      Write-Host ("    {0,-48} {1} (preload: would disable)" -f $Package, $Category) -ForegroundColor DarkGray
    } elseif (-not $isSystem) {
      Write-Host ("    {0,-48} {1} (preload: would delete)" -f $Package, $Category) -ForegroundColor DarkGray
    } else {
      Write-Host ("    {0,-48} {1}" -f $Package, $Category) -ForegroundColor DarkGray
    }
    return 0
  }

  # Data-installed preloads are deleted like everything else. Pass
  # -DisablePreloads to hide them instead and keep them restorable.
  if (-not $script:DisablePreloads -or (Test-SystemPackage -User $User -Package $Package)) {
    $out = Invoke-Shell "pm uninstall -k --user $User '$Package'"
    if ($out -match 'Success') {
      Add-Content -LiteralPath $script:Manifest -Value ("{0}`t{1}`tuninstalled`t{2}" -f $User, $Package, $Category) -Encoding ASCII
      Add-Content -LiteralPath (Join-Path $Backups 'applied.tsv') -Value ("{0}`t{1}`tuninstalled`t{2}" -f $User, $Package, $Category) -Encoding ASCII
      Write-Host ("    - {0,-48} {1}" -f $Package, $Category) -ForegroundColor DarkGray
      return 0
    }
  }

  $out = Invoke-Shell "pm disable-user --user $User '$Package'"
  if ($out -match 'disabled|Success') {
    Add-Content -LiteralPath $script:Manifest -Value ("{0}`t{1}`tdisabled`t{2}" -f $User, $Package, $Category) -Encoding ASCII
    Add-Content -LiteralPath (Join-Path $Backups 'applied.tsv') -Value ("{0}`t{1}`tdisabled`t{2}" -f $User, $Package, $Category) -Encoding ASCII
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
  Add-Content -LiteralPath (Join-Path $Backups 'original-settings.tsv') -Value ("{0}`t{1}`t{2}`t{3}" -f $Ns, $Key, $old, $Note) -Encoding ASCII

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
  $dir = Join-Path $Backups $stamp
  $null = New-Item -ItemType Directory -Path $dir -Force
  $script:Manifest = Join-Path $dir 'packages.tsv'
  $script:SettingsManifest = Join-Path $dir 'settings.tsv'
  Set-Content -LiteralPath $script:Manifest -Value '' -Encoding ASCII
  Set-Content -LiteralPath $script:SettingsManifest -Value '' -Encoding ASCII
  $info = @(
    "Tab S10 FE+ Optimiser v$Version",
    "date      : $(Get-Date)",
    "profile   : $($script:Profile)",
    "extras    : $($script:Extras)",
    "serial    : $($script:Serial)",
    "model     : $($script:Model)",
    "device    : $($script:Device)",
    "android   : $($script:Release)",
    "host      : $([System.Environment]::OSVersion.VersionString)"
  )
  Set-Content -LiteralPath (Join-Path $dir 'info.txt') -Value $info -Encoding ASCII
  $script:LastBackup = $dir
}

function Get-LatestBackup {
  if (-not (Test-Path $Backups)) { return '' }
  $d = Get-ChildItem -LiteralPath $Backups -Directory | Sort-Object Name | Select-Object -Last 1
  if ($d) { return $d.FullName } else { return '' }
}

# ------------------------------------------------------------------ report
function Show-Report {
  Head1 'Device'
  Say "  Model      : $(Invoke-Shell 'getprop ro.product.model')"
  Say "  Product    : $(Invoke-Shell 'getprop ro.product.name')"
  Say "  Android    : $(Invoke-Shell 'getprop ro.build.version.release') (SDK $(Invoke-Shell 'getprop ro.build.version.sdk'))"
  Say "  One UI     : $(Invoke-Shell 'getprop ro.build.version.oneui')"
  Say "  Build      : $(Invoke-Shell 'getprop ro.build.display.id')"
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
function Show-List {
  foreach ($t in 1, 2, 3) {
    $label = @('light', 'balanced', 'aggressive')[$t - 1]
    $rows = @(Get-ProfileRows -File (Join-Path $Profiles 'packages.tsv') -MaxTier $t)
    Head1 "$label (tier <= $t) - $($rows.Count) packages"
    foreach ($r in $rows) { Say ("  {0,-52} {1}" -f $r[1], $r[3]) }
  }
  $ex = @(Get-ProfileRows -File (Join-Path $Profiles 'extras.tsv') -MaxTier 9)
  Head1 "extras (--extras only) - $($ex.Count) packages"
  foreach ($r in $ex) { Say ("  {0,-52} {1}" -f $r[1], $r[3]) }
  Head1 'settings'
  foreach ($r in @(Get-SettingRows -MaxTier 3)) {
    Say ("  [tier {0}] {1}/{2} = {3}" -f $r[0], $r[1], $r[2], $r[3])
  }
}

# ------------------------------------------------------------------ apply
function Invoke-Apply {
  $tier = Get-Tier $script:Profile
  if ($tier -eq 0) { Die "unknown profile '$($script:Profile)' (use light, balanced or aggressive)" }

  Get-Device
  $users = @(Resolve-Users)
  if ($users.Count -eq 0) { Die 'could not determine any user profile' }

  $pkgCount = (Get-ProfileRows -File (Join-Path $Profiles 'packages.tsv') -MaxTier $tier).Count
  Head1 'Plan'
  Say "  Profile    : $($script:Profile) (tier <= $tier)"
  Say "  Packages   : $pkgCount"
  Say "  Settings   : $(@(Get-SettingRows -MaxTier $tier).Count)"
  Say "  Users      : $($users -join ' ')"
  if ($script:Extras) { Warn 'extras enabled - Knox / OTA / Samsung account will be removed' }
  if ($script:DisablePreloads) { Say '  Preloads   : disabled (kept on disk) instead of deleted' }
  if ($script:DryRun) { Warn 'dry run - nothing will change' }

  if (-not $script:DryRun -and -not $script:AssumeYes) {
    $answer = Read-Host '  Continue? [y/N]'
    if ($answer -notmatch '^[yY]') { Say '  cancelled.'; return }
  }

  if (-not $script:DryRun) {
    New-Backup
    Info "Backup written to $($script:LastBackup)"
  }

  $rows = @(Get-ProfileRows -File (Join-Path $Profiles 'packages.tsv') -MaxTier $tier)
  if ($script:Extras) { $rows += @(Get-ProfileRows -File (Join-Path $Profiles 'extras.tsv') -MaxTier 9) }

  $total = 0
  foreach ($u in $users) {
    Head1 "User $u - $(Get-UserLabel $u)"
    $null = Get-PackageCache -User $u
    Info 'Removing packages'
    foreach ($r in $rows) {
      $rc = Invoke-ApplyPackage -User $u -Package $r[1] -Category $r[2]
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

  Head1 'Done'
  if ($script:DryRun) {
    Say '  Dry run complete - nothing was changed.'
  } else {
    Say "  $total package actions applied."
    Say "  Backup: $($script:LastBackup)"
    Say '  Undo  : .\run.ps1 -Restore'
    Dim '  A reboot is recommended so every change takes effect.'
  }

  if ($script:Reboot -and -not $script:DryRun) {
    Info 'Rebooting device'
    $null = Invoke-Adb -Arguments @('reboot') -Quiet
  }
}

# ------------------------------------------------------------------ restore
function Invoke-Restore {
  Get-Device
  $pkgSrc = ''
  $setSrc = ''

  if ($script:RestoreDir) {
    $dir = $script:RestoreDir
    if (-not (Test-Path $dir)) { Die "backup not found: $dir" }
    $pkgSrc = Join-Path $dir 'packages.tsv'
    if (-not (Test-Path $pkgSrc)) { Die "not a valid backup (no packages.tsv): $dir" }
    $setSrc = Join-Path $dir 'settings.tsv'
    Head1 "Restoring a single run from $dir"
    $infoFile = Join-Path $dir 'info.txt'
    if (Test-Path $infoFile) { Get-Content $infoFile | ForEach-Object { Say "  $_" } }
  } else {
    $pkgSrc = Join-Path $Backups 'applied.tsv'
    $setSrc = Join-Path $Backups 'original-settings.tsv'
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

  $rows = @(Get-ProfileRows -File (Join-Path $Profiles 'packages.tsv') -MaxTier 9)
  $rows += @(Get-ProfileRows -File (Join-Path $Profiles 'extras.tsv') -MaxTier 9)
  $n = 0

  foreach ($u in (Resolve-Users)) {
    Head1 "User $u - $(Get-UserLabel $u)"
    foreach ($r in $rows) {
      if ($script:DryRun) { Say "    would reinstall $($r[1])"; continue }
      $out = Invoke-Shell "pm install-existing --user $u '$($r[1])'"
      if ($out -match 'installed') { $n++ }
    }
  }

  Head1 'Restoring default settings'
  $null = Invoke-Shell 'settings put global window_animation_scale 1.0'
  $null = Invoke-Shell 'settings put global transition_animation_scale 1.0'
  $null = Invoke-Shell 'settings put global animator_duration_scale 1.0'
  $null = Invoke-Shell 'settings delete global cached_apps_freezer'
  $null = Invoke-Shell 'settings put global sem_enhanced_cpu_responsiveness 0'
  $null = Invoke-Shell 'settings put global wifi_scan_always_enabled 1'
  $null = Invoke-Shell 'settings put global ble_scan_always_enabled 1'
  $null = Invoke-Shell 'settings delete system min_refresh_rate'
  $null = Invoke-Shell 'settings delete system peak_refresh_rate'
  Ok 'animation scales back to 1.0, refresh-rate overrides cleared'

  Head1 'Done'
  Say "  $n packages reinstalled. Reboot recommended."
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
    '^-Version$'                    { Say "tab-s10-fe-optimiser $Version"; exit 0 }
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
  Head1 "Tab S10 FE+ Optimiser v$Version"
  Say "  Device: $($script:Model) - Android $($script:Release)"
  Say ''
  Say '  1) light       - telemetry, diagnostics, AR toys, preloads'
  Say '  2) balanced    - + Bixby, Samsung extras, gaming services, TTS packs'
  Say '  3) aggressive  - + browsers, Office, YouTube, Samsung account apps'
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
