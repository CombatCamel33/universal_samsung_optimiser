#Requires -Version 5.1
<#
  Universal Android Optimiser - Windows driver
  ---------------------------------------------------------------
  Debloats and tunes exactly matched Android phones, tablets and watches
  over ADB. Every change is recorded and reversible.

  Usage:  .\run.ps1 [light|balanced|aggressive] [options]
  Help:   .\run.ps1 -Help

  Works on Windows PowerShell 5.1 and PowerShell 7+.
#>

$ErrorActionPreference = 'Continue'
$Version = '1.4.0'
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
$script:ApplySettings = $true
$script:Mode      = 'apply'
$script:RestoreDir = ''
$script:CompareDir = ''
$script:UserList  = @()
$script:Serial    = ''
$script:KeepGroups = $null          # $null = the default groups
$script:KeepDefault = 'teams,samsung-internet,office,gmail,messages,phoning'
$script:KeepValid = @('teams', 'samsung-internet', 'office', 'gmail', 'messages', 'phoning')
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
$script:Manufacturer = ''
$script:MarketName = ''
$script:Build = ''
$script:SecurityPatch = ''
$script:Skin = ''
$script:DeviceProfile = ''
$script:DeviceProfileName = ''
$script:DevicePackageFile = ''
$script:MaxRefreshRate = ''
$script:RuntimeProtected = @{}
$script:RuntimeProtectionReason = @{}

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
Universal Android Optimiser v$Version

  .\run.ps1 <profile> [options]      apply a profile
  .\run.ps1 -Restore [dir]           undo the last run (or a specific backup)
  .\run.ps1 -RestoreAll              reinstall every package in every profile
  .\run.ps1 -Compare [dir]           show the before/after statistics of a run

Profiles
  light         telemetry, diagnostics, ads and factory leftovers
  balanced      + optional OEM/Google background features
  aggressive    + replaceable user-facing apps (defaults/phone kept)

  Galaxy Watch and exact Redmi 10 profiles are detected automatically.
  Run -List to see base, exact-device and watch profiles.

Options
  -Profile <name>   same as passing the profile as the first argument
  -DryRun           show what would happen, change nothing
  -User <id>        only touch this Android user (repeatable)
  -AllUsers         every real user profile (default: all except Secure Folder)
  -Extras           device-specific high-risk removals (read -List first)
  -DisablePreloads  hide /data-installed preloads instead of deleting them
                    (Office, Notes, Samsung Internet... stay on disk, restorable)
  -Keep <groups>    keep these app groups installed (default: all of them)
                    groups: teams, samsung-internet, office, gmail, messages, phoning
                    repeatable or comma-separated; "none" disables keeping
  -NoKeep           disable named keep groups; hard/default-app safety still wins
  -ListKeep         print the keep groups and their packages
  -Trim             clear app caches
  -Dexopt           run a background dexopt job now (slow, optimises app start-up)
  -Reboot           reboot when finished
  -NoSettings       remove/disable packages only; do not change Android settings
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
    "$env:USERPROFILE\Downloads\platform-tools\adb.exe",
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

function Format-Miui {
  param([string]$Value)
  if ($Value -match '^V(\d)(\d)(\d)$') { return "$($Matches[1])$($Matches[2]).$($Matches[3])" }
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

function Resolve-ExactDeviceProfile {
  $script:DeviceProfile = ''
  $script:DeviceProfileName = ''
  $script:DevicePackageFile = ''
  if ($script:DeviceClass -eq 'watch') { return }
  $file = Join-Path $Profiles 'devices.tsv'
  if (-not (Test-Path $file)) { return }
  foreach ($line in (Get-Content -LiteralPath $file)) {
    if (-not $line.Trim() -or $line -match '^\s*#') { continue }
    $f = $line -split "`t"
    if ($f.Count -lt 6) { continue }
    if ($f[1] -ieq $script:Manufacturer -and $f[2] -ieq $script:Device -and $f[3] -ieq $script:Model) {
      $script:DeviceProfile = $f[0]
      $script:DeviceProfileName = $f[4]
      if ($f[5] -and $f[5] -ne '-') { $script:DevicePackageFile = Join-Path $Profiles $f[5] }
      return
    }
  }
}

function Get-MaxRefreshRate {
  $raw = Invoke-Shell 'dumpsys display'
  $max = 0.0
  foreach ($m in [regex]::Matches($raw, '(?:fps|refreshRate)=([0-9]+(?:\.[0-9]+)?)')) {
    $v = 0.0
    if ([double]::TryParse($m.Groups[1].Value, [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture, [ref]$v) -and
        $v -ge 30 -and $v -le 240 -and $v -gt $max) { $max = $v }
  }
  if ($max -le 0) {
    $fallback = Invoke-Shell 'settings get system peak_refresh_rate'
    [double]::TryParse($fallback, [Globalization.NumberStyles]::Float,
      [Globalization.CultureInfo]::InvariantCulture, [ref]$max) | Out-Null
  }
  if ($max -le 0) { return '' }
  if ([Math]::Abs($max - [Math]::Round($max)) -lt 0.01) { return ([int][Math]::Round($max)).ToString() }
  return $max.ToString('0.##', [Globalization.CultureInfo]::InvariantCulture)
}

function Set-DeviceProfile {
  $script:DeviceClass = 'tablet'
  $script:DeviceLabel = 'Android phone / tablet'
  $script:ProfileDir = $Profiles
  $safeSerial = $script:Serial -replace '[^A-Za-z0-9._-]', '_'
  if (-not $safeSerial) { $safeSerial = 'unknown-android' }
  $script:Backups = Join-Path $BackupRoot "device-$safeSerial"

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
  Resolve-ExactDeviceProfile
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
    Say  '  1. Enable Developer options (Settings > About phone/tablet > Software information > tap Build number 7x)'
    Say  '  2. Turn on USB debugging'
    Say  '  3. Reconnect and accept the RSA prompt on the device'
    exit 1
  }
  if (-not $script:Serial) {
    $script:Serial = $ids[0]
    if ($ids.Count -gt 1) { Warn "Multiple devices attached - using $($script:Serial)" }
  }
  $null = Invoke-Adb -Arguments @('wait-for-device') -Quiet
  $script:Model   = Invoke-Shell 'getprop ro.product.model'
  $script:Device  = Invoke-Shell 'getprop ro.product.device'
  $script:Manufacturer = Invoke-Shell 'getprop ro.product.manufacturer'
  $script:MarketName = Invoke-Shell 'getprop ro.product.marketname'
  $script:Release = Invoke-Shell 'getprop ro.build.version.release'
  $script:Build = Invoke-Shell 'getprop ro.build.version.incremental'
  $script:SecurityPatch = Invoke-Shell 'getprop ro.build.version.security_patch'
  $script:Characteristics = Invoke-Shell 'getprop ro.build.characteristics'
  $script:HardwareId = Invoke-Shell 'getprop ro.serialno'
  $script:WatchFeature = ((Invoke-Shell 'pm has-feature android.hardware.type.watch') -eq 'true')
  Set-DeviceProfile
  $oneui = Format-OneUi (Invoke-Shell 'getprop ro.build.version.oneui')
  $miui = Format-Miui (Invoke-Shell 'getprop ro.miui.ui.version.name')
  $script:Skin = if ($oneui) { "One UI $oneui" } elseif ($miui) { "MIUI $miui" } else { '' }
  $script:MaxRefreshRate = Get-MaxRefreshRate
  $name = if ($script:MarketName) { $script:MarketName } elseif ($script:DeviceProfileName) { $script:DeviceProfileName } else { $script:Model }
  $skinSuffix = if ($script:Skin) { " / $($script:Skin)" } else { '' }
  $hzSuffix = if ($script:MaxRefreshRate) { " / max $($script:MaxRefreshRate) Hz" } else { '' }
  Info "Device: $name [$($script:Model)] ($($script:Device)) - Android $($script:Release)$skinSuffix$hzSuffix [$($script:DeviceLabel)]"
  if ($script:DeviceProfile) { Ok "matched device profile: $($script:DeviceProfile)" }
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

# ------------------------------------------------------------------ keep groups
function Get-KeepGroupList {
  if ($null -eq $script:KeepGroups) { return @($script:KeepDefault -split ',') }
  return @($script:KeepGroups)
}

function Add-KeepGroups {
  param([string[]]$Values)
  if ($null -eq $script:KeepGroups) { $script:KeepGroups = @() }
  foreach ($v in $Values) {
    foreach ($g in ($v -split ',')) {
      $g = $g.Trim()
      if ($g -and $g -ne 'none' -and $script:KeepGroups -notcontains $g) { $script:KeepGroups += $g }
    }
  }
}

function Assert-KeepGroups {
  foreach ($g in @(Get-KeepGroupList)) {
    if ($script:KeepValid -notcontains $g) {
      Die "unknown keep group '$g' (use teams, samsung-internet, office, gmail, messages, phoning or none)"
    }
  }
}

function Get-KeepPackages {
  if ($script:DeviceClass -eq 'watch') { return @() }
  $file = Join-Path $Profiles 'keep.tsv'
  if (-not (Test-Path $file)) { return @() }
  $groups = @(Get-KeepGroupList)
  if ($groups.Count -eq 0) { return @() }
  $out = @()
  foreach ($line in (Get-Content -LiteralPath $file)) {
    if ($line -match '^\s*#') { continue }
    $f = $line -split "`t"
    if ($f.Count -lt 3) { continue }
    if ($groups -contains $f[0]) { $out += $f[1] }
  }
  return @($out | Sort-Object -Unique)
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

function Get-PackageRows {
  param([int]$MaxTier)
  $rows = @(Get-ProfileRows -File $script:PackagesFile -MaxTier $MaxTier)
  if ($script:DevicePackageFile -and (Test-Path $script:DevicePackageFile)) {
    $rows += @(Get-ProfileRows -File $script:DevicePackageFile -MaxTier $MaxTier)
  }
  return $rows
}

function Resolve-SettingValue {
  param([string]$Value)
  switch ($Value) {
    '__MAX_REFRESH__' {
      if (-not $script:MaxRefreshRate) { if (-not $script:Manufacturer) { return $Value }; return $null }
      return $script:MaxRefreshRate
    }
    '__BALANCED_MIN_REFRESH__' {
      if (-not $script:MaxRefreshRate) { if (-not $script:Manufacturer) { return $Value }; return $null }
      $max = 0.0
      if (-not [double]::TryParse($script:MaxRefreshRate, [Globalization.NumberStyles]::Float,
          [Globalization.CultureInfo]::InvariantCulture, [ref]$max)) { return $null }
      return ([Math]::Min(60.0, $max)).ToString('0.##', [Globalization.CultureInfo]::InvariantCulture)
    }
    default { return $Value }
  }
}

function Get-SettingRows {
  param([int]$MaxTier, [string]$File = $script:SettingsFile)
  $rows = @()
  foreach ($line in (Get-Content -LiteralPath $File)) {
    if ($line -match '^\s*#') { continue }
    $f = $line -split "`t"
    if ($f.Count -lt 5) { continue }
    if ([int]$f[0] -gt $MaxTier) { continue }
    $scope = if ($f.Count -ge 6) { $f[5].Trim().ToLowerInvariant() } else { 'all' }
    if ($script:Manufacturer -and $scope -and $scope -ne 'all' -and
        $scope -ne $script:Manufacturer.ToLowerInvariant() -and $scope -ne $script:DeviceProfile) { continue }
    $value = Resolve-SettingValue $f[3]
    if ($null -eq $value -or $value -eq '') { continue }
    $f[3] = $value
    $rows += ,$f
  }
  return $rows
}

# ------------------------------------------------------------------ active/default app protection
function Add-RuntimeProtected {
  param([string]$Package, [string]$Reason)
  $Package = ($Package -split '/')[0].Trim()
  if ($Package -match '^[A-Za-z][A-Za-z0-9_.]+$') {
    $script:RuntimeProtected[$Package] = $true
    if (-not $script:RuntimeProtectionReason.ContainsKey($Package)) { $script:RuntimeProtectionReason[$Package] = $Reason }
  }
}

function Initialize-RuntimeProtection {
  param([int[]]$Users)
  $script:RuntimeProtected = @{}
  $script:RuntimeProtectionReason = @{}
  if ($script:DeviceClass -eq 'watch') { return }
  $roles = [ordered]@{
    'android.app.role.HOME' = 'active launcher'; 'android.app.role.SMS' = 'default SMS app'
    'android.app.role.DIALER' = 'default dialer'; 'android.app.role.BROWSER' = 'default browser'
  }
  foreach ($u in $Users) {
    foreach ($role in $roles.Keys) {
      foreach ($line in ((Invoke-Shell "cmd role get-role-holders --user $u $role") -split "`n")) { Add-RuntimeProtected $line $roles[$role] }
    }
    $ime = Invoke-Shell "settings --user $u get secure default_input_method"
    if ($ime -and $ime -ne 'null') { Add-RuntimeProtected $ime 'active keyboard' }
    foreach ($item in @(
      @{ Key = 'enabled_accessibility_services'; Reason = 'enabled accessibility service' },
      @{ Key = 'enabled_notification_listeners'; Reason = 'enabled notification listener' }
    )) {
      $value = Invoke-Shell "settings --user $u get secure $($item.Key)"
      if ($value -and $value -ne 'null') {
        foreach ($component in ($value -split ':')) { Add-RuntimeProtected $component $item.Reason }
      }
    }
  }
  # Secure settings can retain stale components for apps already absent. Only
  # protect and verify packages that exist before this run.
  $installed = @{}
  foreach ($u in $Users) {
    foreach ($line in ((Invoke-Shell "pm list packages --user $u") -split "`n")) {
      if ($line -match '^package:(.+)$') { $installed[$Matches[1].Trim()] = $true }
    }
  }
  foreach ($p in @($script:RuntimeProtected.Keys)) {
    if (-not $installed.ContainsKey($p)) { $script:RuntimeProtected.Remove($p); $script:RuntimeProtectionReason.Remove($p) }
  }
}

function Get-ProtectionReason {
  param([string]$Package)
  if ($script:RuntimeProtectionReason.ContainsKey($Package)) { return $script:RuntimeProtectionReason[$Package] }
  return 'safety blocklist'
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
    'com.samsung.android.mtp','com.google.android.inputmethod.latin','com.google.android.dialer',
    'com.android.updater','com.lbe.security.miui','com.miui.home','com.miui.system',
    'com.miui.core','com.miui.rom','com.miui.securitycenter','com.miui.securitycore',
    'com.miui.securityadd','com.miui.powerkeeper','com.miui.global.packageinstaller',
    'com.miui.notification','com.miui.miwallpaper','com.xiaomi.misettings',
    'com.xiaomi.discover','com.xiaomi.finddevice','com.xiaomi.micloud.sdk',
    'com.xiaomi.account','com.xiaomi.xmsf','com.xiaomi.xmsfkeeper','com.xiaomi.joyose',
    'com.miui.systemui.carriers.overlay','android.miui.home.launcher.res',
    'com.android.phone.overlay.miui','com.android.server.telecom.overlay.miui',
    'com.android.carrierconfig.overlay.miui'
  )
  if (($protected -contains $Package) -or $script:RuntimeProtected.ContainsKey($Package)) { return $true }
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
    $result = Invoke-Adb -Arguments @('shell', "settings delete $Ns $Key")
  } else {
    $result = Invoke-Adb -Arguments @('shell', "settings put $Ns $Key $Value")
  }
  $readback = Invoke-Shell "settings get $Ns $Key"
  $applied = if ($Value -eq '__DELETE__') {
    (-not $readback -or $readback -eq 'null')
  } else {
    $same = ($readback -eq $Value)
    $wantNumber = 0.0; $gotNumber = 0.0
    if (-not $same -and
        [double]::TryParse($Value, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$wantNumber) -and
        [double]::TryParse($readback, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$gotNumber)) {
      $same = ([Math]::Abs($wantNumber - $gotNumber) -lt 0.001)
    }
    $same
  }
  if ($applied) { Ok "$Ns/$Key = $Value  (was $old)" }
  else {
    $detail = if ($result) { " - $result" } else { '' }
    Warn "$Ns/$Key was not applied (readback: $readback)$detail"
  }
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
  $keepInfo = if ($script:DeviceClass -eq 'watch') { 'not-applicable' } else { (Get-KeepGroupList) -join ',' }
  $info = @(
    "Universal Android Optimiser v$Version",
    "date      : $(Get-Date)",
    "profile   : $($script:Profile)",
    "keep      : $keepInfo",
    "extras    : $($script:Extras)",
    "apply-settings : $($script:ApplySettings)",
    "trim      : $($script:Trim)",
    "dexopt    : $($script:Dexopt)",
    "reboot    : $($script:Reboot)",
    "serial    : $($script:Serial)",
    "profile-id: $($script:DeviceProfile)",
    "maker     : $($script:Manufacturer)",
    "model     : $($script:Model)",
    "device    : $($script:Device)",
    "class     : $($script:DeviceClass)",
    "hardware  : $($script:HardwareId)",
    "android   : $($script:Release)",
    "skin      : $($script:Skin)",
    "build     : $($script:Build)",
    "security  : $($script:SecurityPatch)",
    "max-hz    : $($script:MaxRefreshRate)",
    "host      : $([System.Environment]::OSVersion.VersionString)"
  )
  Set-Content -LiteralPath (Join-Path $dir 'info.txt') -Value $info -Encoding ASCII
  $script:LastBackup = $dir
}

function Get-LatestBackup {
  if (-not (Test-Path $BackupRoot)) { return '' }
  $info = Get-ChildItem -LiteralPath $BackupRoot -File -Filter 'info.txt' -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime | Select-Object -Last 1
  if ($info) { return $info.Directory.FullName } else { return '' }
}

# ------------------------------------------------------------------ statistics
function Get-DeviceStats {
  $s = [ordered]@{}
  $s['manufacturer'] = Invoke-Shell 'getprop ro.product.manufacturer'
  $s['model'] = Invoke-Shell 'getprop ro.product.model'
  $s['device'] = Invoke-Shell 'getprop ro.product.device'
  $s['android'] = Invoke-Shell 'getprop ro.build.version.release'
  $s['build'] = Invoke-Shell 'getprop ro.build.version.incremental'
  $s['security_patch'] = Invoke-Shell 'getprop ro.build.version.security_patch'
  $s['display.max_refresh_hz'] = $script:MaxRefreshRate
  $s['setting.window_animation_scale'] = Invoke-Shell 'settings get global window_animation_scale'
  $s['setting.transition_animation_scale'] = Invoke-Shell 'settings get global transition_animation_scale'
  $s['setting.animator_duration_scale'] = Invoke-Shell 'settings get global animator_duration_scale'
  $s['setting.peak_refresh_rate'] = Invoke-Shell 'settings get system peak_refresh_rate'
  $s['setting.min_refresh_rate'] = Invoke-Shell 'settings get system min_refresh_rate'

  $mem = Invoke-Shell 'cat /proc/meminfo'
  foreach ($pair in @(@('mem_total_kb', 'MemTotal'), @('mem_free_kb', 'MemFree'), @('mem_available_kb', 'MemAvailable'))) {
    $m = [regex]::Match($mem, "(?m)^$($pair[1]):\s+(\d+)")
    $s[$pair[0]] = if ($m.Success) { [long]$m.Groups[1].Value } else { 0 }
  }

  $df = Invoke-Shell 'df -k /data'
  $line = ($df -split "`n" | Where-Object { $_ -match '^\S+\s+\d+\s+\d+\s+\d+' } | Select-Object -Last 1)
  $f = @()
  if ($line) { $f = @($line -split '\s+') }
  $s['storage_total_kb'] = if ($f.Count -ge 4) { [long]$f[1] } else { 0 }
  $s['storage_used_kb']  = if ($f.Count -ge 4) { [long]$f[2] } else { 0 }
  $s['storage_free_kb']  = if ($f.Count -ge 4) { [long]$f[3] } else { 0 }

  foreach ($u in @(Resolve-Users)) {
    $installed = @((Invoke-Shell "pm list packages --user $u") -split "`n" | Where-Object { $_ -match '^package:' })
    $disabled  = @((Invoke-Shell "pm list packages -d --user $u") -split "`n" | Where-Object { $_ -match '^package:' })
    $s["packages.user.$u"] = $installed.Count
    $s["disabled.user.$u"] = $disabled.Count
    $installedSet = @{}
    foreach ($pkgLine in $installed) { if ($pkgLine -match '^package:(.+)$') { $installedSet[$Matches[1].Trim()] = $true } }
    $tier = Get-Tier $script:Profile
    $targeted = if ($tier -gt 0) { @(Get-PackageRows -MaxTier $tier) } else { @() }
    if ($script:Extras) { $targeted += @(Get-ProfileRows -File $script:ExtrasFile -MaxTier 9) }
    $targetCount = 0
    foreach ($r in $targeted) { if ($installedSet.ContainsKey($r[1])) { $targetCount++ } }
    $s["targeted.user.$u"] = $targetCount
    $protectedSet = @{}
    foreach ($p in @(Get-KeepPackages)) { $protectedSet[$p] = $true }
    foreach ($p in $script:RuntimeProtected.Keys) { $protectedSet[$p] = $true }
    $protectedCount = 0
    foreach ($p in $protectedSet.Keys) { if ($installedSet.ContainsKey($p)) { $protectedCount++ } }
    $s["protected.user.$u"] = $protectedCount
  }
  return $s
}

function Save-DeviceStats {
  param($Stats, [string]$Path)
  $lines = @("key`tvalue")
  foreach ($k in $Stats.Keys) { $lines += "$k`t$($Stats[$k])" }
  Set-Content -LiteralPath $Path -Value $lines -Encoding ASCII
}

function Import-DeviceStats {
  param([string]$Path)
  $h = [ordered]@{}
  foreach ($line in (Get-Content -LiteralPath $Path)) {
    $f = $line -split "`t"
    if ($f.Count -ge 2 -and $f[0] -ne 'key') { $h[$f[0]] = $f[1] }
  }
  return ,$h
}

function Format-Gb {
  param([double]$Kb)
  return ('{0:N1} GB' -f ($Kb / 1MB))
}

function Get-StatsDiffRows {
  param($BeforeStats, $AfterStats)
  $rows = @()
  foreach ($k in $AfterStats.Keys) {
    if ($k -notmatch '_kb$' -and $k -notmatch '^(packages|disabled|targeted|protected)\.user\.' -and
        $k -notmatch '^setting\.' -and $k -ne 'display.max_refresh_hz') { continue }
    $beforeRaw = if ($BeforeStats.Contains($k)) { [string]$BeforeStats[$k] } else { 'n/a' }
    $afterRaw = [string]$AfterStats[$k]
    $bv = 0.0; $av = 0.0
    $beforeNumeric = [double]::TryParse($beforeRaw, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$bv)
    $afterNumeric = [double]::TryParse($afterRaw, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$av)
    if ($k -match '_kb$' -and $beforeNumeric -and $afterNumeric) {
      $d = $av - $bv; $bs = Format-Gb $bv; $as = Format-Gb $av
      $sign = if ($d -gt 0) { '+' } else { '' }; $cs = '{0}{1:N1} GB' -f $sign, ($d / 1MB)
    } elseif ($k -match '^(packages|disabled|targeted|protected)\.user\.' -and $beforeNumeric -and $afterNumeric) {
      $d = $av - $bv; $bs = '{0}' -f [long]$bv; $as = '{0}' -f [long]$av
      $sign = if ($d -gt 0) { '+' } else { '' }; $cs = '{0}{1}' -f $sign, [long]$d
    } else {
      $bs = $beforeRaw; $as = $afterRaw
      if ($beforeNumeric -and $afterNumeric) {
        $d = $av - $bv; $sign = if ($d -gt 0) { '+' } else { '' }
        $cs = if ([Math]::Abs($d) -lt 0.0001) { 'unchanged' } else { '{0}{1:0.##}' -f $sign, $d }
      } else { $cs = if ($beforeRaw -eq $afterRaw) { 'unchanged' } else { 'changed' } }
    }
    $label = switch -Regex ($k) {
      '^mem_total_kb$' { 'Total RAM'; break }; '^mem_available_kb$' { 'Available RAM'; break }
      '^mem_free_kb$' { 'Free RAM'; break }; '^storage_total_kb$' { 'Storage total'; break }
      '^storage_used_kb$' { 'Storage used'; break }; '^storage_free_kb$' { 'Storage free'; break }
      '^packages\.user\.(.+)$' { "Installed packages (user $($Matches[1]))"; break }
      '^disabled\.user\.(.+)$' { "Disabled packages (user $($Matches[1]))"; break }
      '^targeted\.user\.(.+)$' { "Profile packages present (user $($Matches[1]))"; break }
      '^protected\.user\.(.+)$' { "Protected packages present (user $($Matches[1]))"; break }
      '^display\.max_refresh_hz$' { 'Display maximum'; break }
      '^setting\.window_animation_scale$' { 'Window animation scale'; break }
      '^setting\.transition_animation_scale$' { 'Transition animation scale'; break }
      '^setting\.animator_duration_scale$' { 'Animator duration scale'; break }
      '^setting\.peak_refresh_rate$' { 'Peak refresh-rate setting'; break }
      '^setting\.min_refresh_rate$' { 'Minimum refresh-rate setting'; break }
      default { $k }
    }
    $rows += [pscustomobject]@{ Key=$k; Label=$label; Before=$bs; After=$as; Change=$cs }
  }
  return $rows
}

function Save-BeforeAfterReport {
  param([string]$Before, [string]$After, [string]$Directory)
  if (-not (Test-Path $Before) -or -not (Test-Path $After)) { return }
  $rows = @(Get-StatsDiffRows (Import-DeviceStats $Before) (Import-DeviceStats $After))
  $tsv = @("metric`tbefore`tafter`tchange")
  $md = @('# Before / after', '', '| Metric | Before | After | Change |', '|---|---:|---:|---:|')
  foreach ($r in $rows) {
    $tsv += "$($r.Label)`t$($r.Before)`t$($r.After)`t$($r.Change)"
    $md += "| $($r.Label) | $($r.Before) | $($r.After) | $($r.Change) |"
  }
  Set-Content -LiteralPath (Join-Path $Directory 'before-after.tsv') -Value $tsv -Encoding ASCII
  Set-Content -LiteralPath (Join-Path $Directory 'before-after.md') -Value $md -Encoding UTF8
}

function Show-StatsDiff {
  param([string]$Before, [string]$After)
  if (-not (Test-Path $Before)) { Warn 'no statistics were recorded before this run'; return $false }
  if (-not (Test-Path $After))  { Warn 'no statistics were recorded after this run (was the run interrupted?)'; return $false }

  $b = Import-DeviceStats $Before
  $a = Import-DeviceStats $After
  Say ''
  Say ('  {0,-40} {1,-12} {2,-12} {3}' -f 'Metric', 'Before', 'After', 'Change')
  foreach ($r in @(Get-StatsDiffRows $b $a)) { Say ('  {0,-40} {1,-12} {2,-12} {3}' -f $r.Label, $r.Before, $r.After, $r.Change) }
  Dim '  RAM figures move with what is open - package and storage counts are the reliable ones.'
}

function Show-Compare {
  $dir = $script:CompareDir
  if (-not $dir) { $dir = Get-LatestBackup }
  if (-not $dir) { Die 'no backups found - apply a profile first' }
  if (-not (Test-Path $dir)) { Die "backup not found: $dir" }
  Head1 "Before / after - $(Split-Path -Leaf $dir)"
  $info = Join-Path $dir 'info.txt'
  if (Test-Path $info) {
    Get-Content -LiteralPath $info | ForEach-Object { Say "  $_" }
    Head1 'Statistics'
  }
  $statsBefore = Join-Path $dir 'stats-before.tsv'
  $statsAfter = Join-Path $dir 'stats-after.tsv'
  if ((Test-Path $statsBefore) -and (Test-Path $statsAfter)) {
    Save-BeforeAfterReport $statsBefore $statsAfter $dir
    $null = Show-StatsDiff $statsBefore $statsAfter
    return
  }

  $before = Join-Path $dir 'before.txt'
  $after = Join-Path $dir 'after.txt'
  if ((Test-Path $before) -and (Test-Path $after)) {
    Show-BeforeAfter -BeforePath $before -AfterPath $after
    return
  }
  $null = Show-StatsDiff $statsBefore $statsAfter
}

# ------------------------------------------------------------------ report
function Show-Report {
  Head1 'Device'
  Say "  Name       : $(if ($script:MarketName) {$script:MarketName} else {$script:Model})"
  Say "  Model      : $($script:Model)"
  Say "  Maker      : $($script:Manufacturer)"
  Say "  Target     : $($script:DeviceLabel)"
  Say "  Product    : $(Invoke-Shell 'getprop ro.product.name')"
  Say "  Android    : $(Invoke-Shell 'getprop ro.build.version.release') (SDK $(Invoke-Shell 'getprop ro.build.version.sdk'))"
  Say "  Skin       : $($script:Skin)"
  Say "  Build      : $($script:Build)"
  Say "  Security   : $($script:SecurityPatch)"
  Say "  Profile    : $(if ($script:DeviceProfile) {$script:DeviceProfile} elseif ($script:DeviceClass -eq 'watch') {'watch'} else {'base only'})"
  Say "  CSC        : $(Invoke-Shell 'getprop ro.csc.sales_code')"

  Head1 'Display'
  foreach ($l in ((Invoke-Shell 'wm size') -split "`n")) { Say "  $l" }
  foreach ($l in ((Invoke-Shell 'wm density') -split "`n")) { Say "  $l" }
  Say "  Max mode   : $($script:MaxRefreshRate) Hz"
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
function Show-KeepList {
  $file = Join-Path $Profiles 'keep.tsv'
  if (-not (Test-Path $file)) { Warn 'keep.tsv not found'; return }
  Head1 'Keep groups (never removed by a profile)'
  foreach ($line in (Get-Content -LiteralPath $file)) {
    if ($line -match '^\s*#') { continue }
    $f = $line -split "`t"
    if ($f.Count -ge 4) { Say ("  {0,-20} {1,-52} {2}" -f $f[0], $f[1], $f[3]) }
  }
}

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
  Show-ProfileList -Title 'Android base / Samsung profiles' -Directory $Profiles
  Get-ChildItem -LiteralPath $Profiles -Filter 'packages-*.tsv' -ErrorAction SilentlyContinue | ForEach-Object {
    $rows = @(Get-ProfileRows -File $_.FullName -MaxTier 3)
    Head1 "$($_.BaseName) exact-device additions - $($rows.Count) packages"
    foreach ($r in $rows) { Say ("  [tier {0}] {1,-52} {2}" -f $r[0], $r[1], $r[3]) }
  }
  Show-KeepList
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

function Wait-ForDeviceBoot {
  param([int]$TimeoutSeconds = 240)
  $attempts = [Math]::Max(1, [int]($TimeoutSeconds / 2))
  for ($i = 0; $i -lt $attempts; $i++) {
    if ((Invoke-Adb -Arguments @('get-state') -Quiet).Trim() -eq 'device' -and
        (Invoke-Shell 'getprop sys.boot_completed').Trim() -eq '1') { Start-Sleep -Seconds 5; return $true }
    Start-Sleep -Seconds 2
  }
  return $false
}

function Test-PostApplyHealth {
  param([int[]]$Users, [string]$Path)
  $present = @{}
  foreach ($u in $Users) {
    foreach ($line in ((Invoke-Shell "pm list packages --user $u") -split "`n")) {
      if ($line -match '^package:(.+)$') { $present[$Matches[1].Trim()] = $true }
    }
  }
  $checks = @("check`tresult`tdetail"); $healthy = $true
  foreach ($p in $script:RuntimeProtected.Keys) {
    $ok = $present.ContainsKey($p)
    $checks += "protected:$p`t$(if ($ok) {'ok'} else {'FAIL'})`t$($script:RuntimeProtectionReason[$p])"
    if (-not $ok) { Fail "post-run safety check: protected package missing: $p"; $healthy = $false }
  }
  if ($script:DeviceClass -ne 'watch') {
    foreach ($u in $Users) {
      $homeHolder = (Invoke-Shell "cmd role get-role-holders --user $u android.app.role.HOME").Trim()
      $ok = [bool]($homeHolder -match '^[A-Za-z][A-Za-z0-9_.]+$')
      $checks += "home:user:$u`t$(if ($ok) {'ok'} else {'FAIL'})`t$homeHolder"
      if (-not $ok) { Fail "post-run safety check: user $u has no default launcher"; $healthy = $false }
    }
  }
  Set-Content -LiteralPath $Path -Value $checks -Encoding ASCII
  if ($healthy) { Ok 'post-run safety checks passed' }
  return $healthy
}

# ------------------------------------------------------------------ apply
function Invoke-Apply {
  $tier = Get-Tier $script:Profile
  if ($tier -eq 0) { Die "unknown profile '$($script:Profile)' (use light, balanced or aggressive)" }

  Get-Device
  $users = @(Resolve-Users)
  if ($users.Count -eq 0) { Die 'could not determine any user profile' }
  Initialize-RuntimeProtection -Users $users

  $pkgCount = @(Get-PackageRows -MaxTier $tier).Count
  Head1 'Plan'
  Say "  Target     : $($script:DeviceLabel)"
  Say "  Profile    : $($script:Profile) (tier <= $tier)"
  if ($script:DeviceProfile) { Say "  Device     : $($script:DeviceProfile)" }
  Say "  Packages   : $pkgCount"
  $settingCount = @(Get-SettingRows -MaxTier $tier).Count
  if ($script:ApplySettings) {
    Say "  Settings   : $settingCount"
  } else {
    Say "  Settings   : skipped ($settingCount profile settings left unchanged)"
  }
  Say "  Users      : $($users -join ' ')"
  if ($script:DeviceClass -ne 'watch') {
    $keepGroups = @(Get-KeepGroupList)
    if ($keepGroups.Count -gt 0) {
      Say "  Keep       : $($keepGroups -join ',') ($(@(Get-KeepPackages).Count) packages protected)"
    } else {
      Say '  Keep       : none - every package in the profile can be removed'
    }
    Say "  Active     : $($script:RuntimeProtected.Count) installed defaults/services protected automatically"
  }
  if ($script:Extras) { Warn 'extras enabled - device-critical optional services will be changed' }
  if ($script:DisablePreloads) { Say '  Preloads   : disabled (kept on disk) instead of deleted' }
  else { Warn 'data-installed target apps, if any, will be deleted with their app data (use -DisablePreloads to prevent this)' }
  if ($script:Trim) { Say '  Cache      : trim after package changes' }
  if ($script:Reboot -and $script:DeviceClass -ne 'watch') { Say '  Reboot     : yes; final after snapshot will be captured post-reboot' }
  elseif ($script:Reboot) { Say '  Reboot     : yes, after immediate statistics are captured' }
  if ($script:DryRun) { Warn 'dry run - nothing will change' }

  if (-not $script:DryRun -and -not $script:AssumeYes) {
    $answer = Read-Host '  Continue? [y/N]'
    if ($answer -notmatch '^[yY]') { Say '  cancelled.'; return }
  }

  if (-not $script:DryRun) {
    New-Backup
    Info "Backup written to $($script:LastBackup)"
    $beforeFile = Join-Path $script:LastBackup 'before.txt'
    Save-DeviceStats (Get-DeviceStats) (Join-Path $script:LastBackup 'stats-before.tsv')
    Ok 'baseline statistics captured (before)'
  } else {
    $beforeFile = Join-Path $script:Tmp 'before.txt'
  }
  Save-Snapshot -Path $beforeFile -Users $users
  if ($script:DryRun) { Show-Snapshot -Heading 'Current baseline' -Path $beforeFile }

  $rows = @(Get-PackageRows -MaxTier $tier)
  if ($script:Extras) { $rows += @(Get-ProfileRows -File $script:ExtrasFile -MaxTier 9) }

  $keep = @{}
  foreach ($p in @(Get-KeepPackages)) { $keep[$p] = $true }

  $total = 0
  foreach ($u in $users) {
    Head1 "User $u - $(Get-UserLabel $u)"
    $null = Get-PackageCache -User $u
    Info 'Applying package profile'
    foreach ($r in $rows) {
      if (-not (Test-Installed -User $u -Package $r[1])) { continue }
      if (Test-Protected $r[1]) {
        Write-Host ("    # {0,-48} {1} ({2})" -f $r[1], $r[2], (Get-ProtectionReason $r[1])) -ForegroundColor DarkGray
        continue
      }
      if ($keep.ContainsKey($r[1])) {
        Write-Host ("    = {0,-48} {1} (kept)" -f $r[1], $r[2]) -ForegroundColor DarkGray
        continue
      }
      $action = if ($r.Count -ge 5 -and $r[4]) { $r[4] } else { 'auto' }
      $rc = Invoke-ApplyPackage -User $u -Package $r[1] -Category $r[2] -Action $action
      if ($rc -eq 0) { $total++ }
    }
  }

  Head1 'System settings'
  if ($script:ApplySettings) {
    foreach ($r in @(Get-SettingRows -MaxTier $tier)) {
      Set-Tweak -Ns $r[1] -Key $r[2] -Value $r[3] -Note $r[4]
    }
  } else {
    Dim '  skipped (package-only mode)'
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
    $afterStats = Join-Path $script:LastBackup 'stats-after.tsv'
    $afterFile = Join-Path $script:LastBackup 'after.txt'
    if ($script:Reboot -and $script:DeviceClass -ne 'watch') {
      Save-DeviceStats (Get-DeviceStats) (Join-Path $script:LastBackup 'stats-after-pre-reboot.tsv')
      Save-Snapshot -Path (Join-Path $script:LastBackup 'after-pre-reboot.txt') -Users $users
      Ok 'immediate post-change statistics captured'
      Info 'Rebooting device before the final after snapshot'
      $null = Invoke-Adb -Arguments @('reboot') -Quiet
      if (Wait-ForDeviceBoot) {
        Ok 'device boot completed'
        Save-DeviceStats (Get-DeviceStats) $afterStats
        Save-Snapshot -Path $afterFile -Users $users
        Ok 'statistics captured (after reboot)'
      } else { Warn 'device did not finish booting before the timeout; final after snapshot was not created' }
    } else {
      Save-DeviceStats (Get-DeviceStats) $afterStats
      Save-Snapshot -Path $afterFile -Users $users
      Ok 'statistics captured (after)'
    }
    if (Test-Path $afterStats) {
      $null = Test-PostApplyHealth -Users $users -Path (Join-Path $script:LastBackup 'safety-checks.tsv')
      Save-BeforeAfterReport (Join-Path $script:LastBackup 'stats-before.tsv') $afterStats $script:LastBackup
      Head1 'Before / after'
      $null = Show-StatsDiff (Join-Path $script:LastBackup 'stats-before.tsv') $afterStats
    }
    if (Test-Path $afterFile) { Show-BeforeAfter -BeforePath $beforeFile -AfterPath $afterFile }
    Head1 'Done'
    Say "  $total package actions applied."
    Say "  Backup: $($script:LastBackup)"
    if (Test-Path (Join-Path $script:LastBackup 'before-after.md')) { Say "  Report: $(Join-Path $script:LastBackup 'before-after.md')" }
    Say '  Undo  : .\run.ps1 -Restore'
    if (-not $script:Reboot) { Dim '  A reboot is recommended so every change takes effect.' }
    if ($script:DeviceClass -eq 'watch') { Dim '  Turn off ADB debugging and wireless debugging on the watch when finished.' }
  }

  if ($script:Reboot -and -not $script:DryRun -and $script:DeviceClass -eq 'watch') {
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

  $rows = @(Get-PackageRows -MaxTier 9)
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
      if ($script:Manufacturer -ieq 'Samsung') { $null = Invoke-Shell 'settings put global sem_enhanced_cpu_responsiveness 0' }
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
    '^-Keep(=(.*))?$' {
      $vals = @()
      if ($Matches[2]) { $vals += $Matches[2] }
      else {
        while ($i + 1 -lt $argsList.Count -and $argsList[$i+1] -notmatch '^-' -and $argsList[$i+1] -notmatch '^(light|balanced|aggressive)$') {
          $i++
          $vals += $argsList[$i]
        }
      }
      if ($vals.Count -eq 0) { Fail '-Keep needs a group (teams, samsung-internet, office, gmail, messages, phoning or none)'; exit 2 }
      Add-KeepGroups -Values $vals
    }
    '^-NoKeep$'                     { $script:KeepGroups = @() }
    '^-ListKeep$'                   { $script:Mode = 'list-keep' }
    '^-Trim$'                       { $script:Trim = $true }
    '^-Dexopt$'                     { $script:Dexopt = $true }
    '^-Reboot$'                     { $script:Reboot = $true }
    '^-NoSettings$'                 { $script:ApplySettings = $false }
    '^-AllUsers$'                   { $script:UserList = @() }
    '^-User(=(.*))?$'               { if ($Matches[2]) { $script:UserList += [int]$Matches[2] } else { $i++; $script:UserList += [int]$argsList[$i] } }
    '^-Serial(=(.*))?$'             { if ($Matches[2]) { $script:Serial = $Matches[2] } else { $i++; $script:Serial = $argsList[$i] } }
    '^-RestoreAll$'                 { $script:Mode = 'restore-all' }
    '^-Restore$'                    { $script:Mode = 'restore'; if ($i + 1 -lt $argsList.Count -and $argsList[$i+1] -notmatch '^-') { $i++; $script:RestoreDir = $argsList[$i] } }
    '^-Compare(=(.*))?$'            { $script:Mode = 'compare'; if ($Matches[2]) { $script:CompareDir = $Matches[2] } elseif ($i + 1 -lt $argsList.Count -and $argsList[$i+1] -notmatch '^-') { $i++; $script:CompareDir = $argsList[$i] } }
    '^-List$'                       { $script:Mode = 'list' }
    '^-Report$'                     { $script:Mode = 'report' }
    '^-Help$|^-h$|^-\?$'            { Show-Usage; exit 0 }
    '^-Version$'                    { Say "universal-android-optimiser $Version"; exit 0 }
    default                         { Fail "unknown argument: $a"; Say ''; Show-Usage; exit 2 }
  }
}

Assert-KeepGroups

$null = New-Item -ItemType Directory -Path $script:Tmp -Force

switch ($script:Mode) {
  'list'        { Show-List; exit 0 }
  'list-keep'   { Show-KeepList; exit 0 }
  'compare'     { Show-Compare; exit 0 }
  'report'      { Get-Device; Show-Report; exit 0 }
  'restore'     { Invoke-Restore; exit 0 }
  'restore-all' { Invoke-RestoreAll; exit 0 }
}

# ------------------------------------------------------------------ interactive menu
if (-not $script:Profile) {
  Get-Device
  Head1 "Universal Android Optimiser v$Version"
  Say "  Device: $($script:Model) - Android $($script:Release) ($($script:DeviceLabel))"
  Say ''
  if ($script:DeviceClass -eq 'watch') {
    Say '  1) light       - retail demo, certification and factory test leftovers'
    Say '  2) balanced    - + Bixby, customisation and enterprise provisioning'
    Say '  3) aggressive  - + optional apps; calls, Google Messages and health stay'
  } else {
    Say '  1) light       - telemetry, diagnostics, ads and factory tools'
    Say '  2) balanced    - + optional OEM/Google services and gaming extras'
    Say '  3) aggressive  - + replaceable browser, media and productivity apps'
  }
  Say '  4) restore     - undo the last run'
  Say '  5) report      - show device info without changing anything'
  Say '  6) compare     - before/after statistics of the last run'
  Say '  q) quit'
  $choice = Read-Host '  Choose [1-6/q]'
  switch ($choice) {
    '1' { $script:Profile = 'light' }
    '2' { $script:Profile = 'balanced' }
    '3' { $script:Profile = 'aggressive' }
    '4' { Invoke-Restore; exit 0 }
    '5' { Show-Report; exit 0 }
    '6' { Show-Compare; exit 0 }
    default { Say '  bye.'; exit 0 }
  }
}

Invoke-Apply
exit 0
