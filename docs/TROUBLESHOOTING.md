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
cd path\to\tab-s10-fe-optimiser
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

Some One UI builds reset it when the display mode changes. Re-run the profile, or set
it manually:

```bash
adb shell settings put system min_refresh_rate 90
```

## Multiple devices connected

```bash
adb devices
./run.sh balanced --serial R5GYA1B2C3D
```

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
