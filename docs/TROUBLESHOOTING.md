# Troubleshooting

## `adb not found`

Install platform-tools, or point the script at your copy:

```bash
# macOS / Linux
ADB=~/Downloads/platform-tools/adb ./run.sh --report

# Windows PowerShell
$env:ADB="C:\platform-tools\adb.exe"; .\run.ps1 -Report
```

Common locations the script already checks:

* macOS: `~/Library/Android/sdk/platform-tools/adb`, `/opt/homebrew/bin/adb`, `/usr/local/bin/adb`
* Linux: `~/Android/Sdk/platform-tools/adb`, `/usr/bin/adb`
* Windows: `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`, `C:\platform-tools\adb.exe`

## `No authorised device found`

```bash
adb devices
```

| Output | Meaning | Fix |
|---|---|---|
| empty list | cable / driver problem | try another **data** cable and USB port |
| `unauthorized` | RSA prompt not accepted | unplug, replug, tap **Allow** on the tablet |
| `offline` | adb daemon out of sync | `adb kill-server && adb start-server` |
| `device` | fine | you are good to go |

If the prompt never appears: Settings → Developer options → **Revoke USB debugging
authorisations**, then replug.

### Galaxy Watch wireless ADB

The **Pair new device** screen shows a temporary pairing port and six-digit code. Pair
while that screen remains open:

```bash
adb pair WATCH_IP:PAIRING_PORT PAIRING_CODE
```

The main **Wireless debugging** screen shows a different normal debugging port. Modern
ADB usually discovers it through mDNS; if `adb devices -l` remains empty, connect it:

```bash
adb connect WATCH_IP:DEBUG_PORT
adb devices -l
```

Both ports can change. The computer and watch must be on the same Wi-Fi network. Turn
off ADB debugging and Wireless debugging when finished because they consume watch battery.

## Windows: "running scripts is disabled on this system"

```powershell
powershell -ExecutionPolicy Bypass -File .\run.ps1 balanced
```

Or permanently for your user:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## Windows: `adb` opens and closes instantly

You are probably running `adb.exe` by double-clicking. Always run the script from a
PowerShell window in the repo folder:

```powershell
cd path\to\universal-samsung-optimiser
.\run.ps1 --report
```

## `Error: java.lang.SecurityException: Shell does not have permission to access user 150`

Harmless. User 150 is **Secure Folder**, which is protected by Knox. The scripts skip
it on purpose. You will only see this if you run `pm list packages` without `--user`.

## A package refuses to uninstall

The script automatically falls back to `pm disable-user`, which hides the package and
stops it running. Both are reversible.

Some packages are hard-protected by Samsung (Knox, the launcher, the keyboard). The
scripts have a blocklist and will refuse to touch them.

## I removed something I need

```bash
./run.sh --restore
```

or for one app:

```bash
adb shell pm install-existing --user 10 <package>
```

## The tablet feels the same

1. Reboot. Package changes only fully settle after a restart.
2. Run `./run.sh --report` and look at **Top 10 RAM consumers**. If a third-party app
   (browser, game, social app) is at the top, that is your bottleneck - not the system.
3. Animations are the most noticeable change. Check them:
   ```bash
   adb shell settings get global window_animation_scale
   ```
4. Battery optimisation can undo some of it: Settings → Battery → Background usage
   limits → make sure your main apps are not "Deep sleeping".

## `min_refresh_rate` does not stick

This section is tablet-only. The Watch6 panel is fixed at 60 Hz and the watch profile
never writes a refresh-rate override.

Some OEM builds reset it when display mode or battery saver changes. Re-run the profile,
which detects the panel maximum, or inspect the current values:

```bash
adb shell settings get system peak_refresh_rate
adb shell settings get system min_refresh_rate
```

Do not copy a 90/120/144 Hz value from another model.

## MIUI says a setting was not applied

Some Xiaomi builds permit package operations but reject `settings put`. The optimiser
reads each value back and reports **not applied** instead of claiming success. To permit
ADB settings, enable Xiaomi's separate **USB debugging (Security settings)** developer
option, reconnect/reauthorise, and rerun. Package changes/restores do not need that toggle.

## Multiple devices connected

```bash
adb devices
./run.sh balanced --serial R5GYA1B2C3D
```

Wireless devices may appear as an mDNS service name rather than `IP:port`; copy the
identifier exactly from the first column of `adb devices -l`.

## The script asks about users

Android supports multiple user profiles. By default the tool debloats all real users
and skips Secure Folder. To target one:

```bash
./run.sh balanced --user 10
```

Find your user id:

```bash
adb shell pm list users
```

## Still stuck?

Open an issue with the output of:

```bash
./run.sh --report
adb devices -l
adb shell getprop ro.build.display.id
```
