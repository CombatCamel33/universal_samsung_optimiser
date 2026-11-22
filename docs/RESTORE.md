# Restoring everything

Nothing this tool does is permanent. There are three levels of undo, from gentlest to
most thorough.

## 1. Undo everything (normal case)

```bash
./run.sh --restore          # macOS / Linux
.\run.ps1 -Restore          # Windows
```

That reads:

* `backups/applied.tsv` - every package the tool ever removed, with the user profile it was removed from
* `backups/original-settings.tsv` - the **original** value of every setting it touched

and then runs `pm install-existing --user <id> <package>` for each one plus restores
the settings. App data was never deleted (`-k`), so everything comes back logged in
with your data intact.

Reboot afterwards:

```bash
adb reboot
```

## 2. Undo one specific run

Each run also writes its own folder:

```bash
ls backups/
# 20261122-102743  20261122-102828  20261122-102849
./run.sh --restore backups/20261122-102849
```

## 3. Brute force reinstall

If `applied.tsv` is missing (for example you deleted `backups/`), reinstall every
package that appears in any profile:

```bash
./run.sh --restore-all
```

This also resets the animation scales to Android's defaults and removes the refresh
rate overrides. Packages that were never installed are ignored.

## Restoring a single app by hand

```bash
# find it first
./run.sh --list | grep -i notes

# put it back for the current user
adb shell pm install-existing --user 10 com.samsung.android.app.notes

# if it was disabled instead of uninstalled
adb shell pm enable --user 10 com.samsung.android.app.notes
```

`pm install-existing` works for system apps without root. If it prints
`Package ... not installed`, the package was not removed for that user - check the
right user id with `adb shell pm list users`.

## Restoring settings by hand

```bash
# the original values are in backups/original-settings.tsv
cat backups/original-settings.tsv

adb shell settings put global window_animation_scale 1.0
adb shell settings put global transition_animation_scale 1.0
adb shell settings put global animator_duration_scale 1.0
adb shell settings delete global cached_apps_freezer
adb shell settings put global sem_enhanced_cpu_responsiveness 0
adb shell settings put global wifi_scan_always_enabled 1
adb shell settings put global ble_scan_always_enabled 1
adb shell settings delete system min_refresh_rate
adb shell settings delete system peak_refresh_rate
```

## Nuclear option

If the tablet will not boot properly after an aggressive run (this has not happened
in testing):

1. Hold **Power + Volume Down** for ~10 seconds to force a restart.
2. If it still will not boot, hold **Power + Volume Up** while connecting USB to reach
   Recovery, then **Wipe cache partition**. This does not delete your data.
3. Last resort: Recovery → **Factory data reset**. Everything is in Samsung Cloud /
   Google backup if you enabled it.

Because every removal is per-user and keeps data, a factory reset is almost never
needed - but it is the guaranteed clean slate.

## Data-installed preloads (disabled, not removed)

Android has two kinds of "preinstalled" app:

1. **System image apps** - the APK sits in a read-only partition (`/system`, `/product`,
   `/system_ext`, `/vendor`). `pm uninstall --user 0` only marks it uninstalled for that
   user; the APK stays, so `pm install-existing` always works.
2. **Data-installed preloads** - Samsung shipped the app, but its APK lives in
   `/data/app`. Uninstalling the last user deletes the APK, so the app is gone until you
   download it again. The scripts remove these completely (APK **and** app data) by
   default, unless you pass `--disable-preloads`.

Real examples from a Galaxy Tab S10 FE+ (Android 16):

| Package | APK location | Default | With `--disable-preloads` |
|---|---|---|---|
| `com.microsoft.office.word` | `/data/app/~~duG82SZdq1_3U6G_f7mn7w==/.../base.apk` | APK + data deleted | disabled |
| `com.microsoft.office.excel` | `/data/app/~~VyE9HeGSP9YgrE7L-9ZRiA==/.../base.apk` | APK + data deleted | disabled |
| `com.microsoft.teams` | `/data/app/~~ZvIH_3AsYNshnhSQ2fSLvg==/.../base.apk` | APK + data deleted | disabled |
| `com.samsung.android.app.notes` | `/data/app/~~YGHjeOYI23jGAPqDKhLaAA==/.../base.apk` | APK + data deleted | disabled |
| `com.samsung.android.app.reminder` | `/data/app/~~ZSRowudJRoapTgWUpt2gDw==/.../base.apk` | APK + data deleted | disabled |
| `com.sec.android.app.sbrowser` | `/data/app/~~TlWrT3SXNB-W8ZzlGzgnuA==/.../base.apk` | APK + data deleted | disabled |
| `com.gameloft.android.ANMP.GloftA9HM` | `/data/app/...` (Asphalt 9 demo) | APK + data deleted | disabled |
| `com.samsung.SMT.lang_en_gb_l02` | `/data/app/...` (TTS voice) | APK + data deleted | disabled |

A system app that has been **updated from the store** also shows a `/data/app` path,
but it is still restorable because the original APK is in the system image:

```
$ adb shell pm path com.google.android.youtube
package:/data/app/~~fvxM1dtJEnLdT-1-BlDWpQ==/com.google.android.youtube-.../base.apk

$ adb shell pm list packages -s | grep youtube
package:com.google.android.youtube        <- still a system package, so it comes back
```

That is why the scripts do not test the path. They test the system-image membership:

```bash
adb shell pm list packages -s --user 0 | grep -x package:com.example.app
```

* **in the list** -> `pm uninstall -k --user N` (restorable)
* **not in the list** -> deleted by default, or disabled with `--disable-preloads`

To keep preloads restorable, run the profile like this:

```bash
./run.sh balanced --disable-preloads      # macOS / Linux
.\run.ps1 balanced -DisablePreloads      # Windows
```

Check what is currently disabled, or bring one back:

```bash
adb shell pm list packages -d --user 10
adb shell pm enable --user 10 com.microsoft.office.word
```

`--restore` handles both cases automatically (`install-existing` for uninstalled
packages, `pm enable` for disabled ones).

## Notes

* Restoring does **not** re-download apps you uninstalled from the Play Store yourself.
* Samsung apps come back in their preloaded state; updates arrive through Galaxy Store
  or Play Store again.
* Secure Folder (user 150) is never touched by default, and `--restore` skips it too.
