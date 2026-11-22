# Galaxy Tab S10 FE+ Optimiser

One-command, **fully reversible** ADB optimiser for the Samsung Galaxy Tab S10 FE+ (and most modern Samsung tablets).

Removes background bloat, kills Samsung's sluggish animation scaling and tunes the system for smoother UI and lower RAM usage. Works on **macOS, Windows and Linux**. No root, no custom ROM, no warranty voiding.

```bash
./run.sh balanced      # macOS / Linux
.\run.ps1 balanced     # Windows
```

---

## Tested on

| | |
|---|---|
| Device | Samsung Galaxy Tab S10 FE+ Wi-Fi (`SM-X620` / `gts10fepwifi`) |
| OS | Android 16, One UI 8.5 |
| Build | `X620XXSBCZI2` (CSC `XSG`) |
| RAM | 8 GB |
| Display | 1800 × 2880, 90 Hz |
| Users | 2 real profiles + Secure Folder |

The script is generic: it only touches packages that actually exist on your device, so it also works on the S10 FE, S9 FE, Tab S9/S10 series and most Galaxy phones.

## Results on the test tablet

Measured on a real SM-X620 after each profile and a reboot:

| Metric | Before | `balanced` | `aggressive` |
|---|---|---|---|
| Installed packages (user 10) | 515 | 409 | **359** |
| Installed packages (user 0) | 443 | 336 | **290** |
| Packages removed | - | 105 | **156** |
| Available RAM (`MemAvailable`) | ~2.4 GB | ~3.2 GB | **~3.8 GB** |
| Storage used / free | 83 GB / 21 GB | 78 GB / 25 GB | **75 GB / 29 GB** |
| Animation scales | 1.5× / 1.5× / 1.5× (stock 1.0×) | 0.5× | **0.5×** |
| Min refresh rate | unset (drops to 30 Hz) | 60 Hz | **90 Hz (locked)** |
| Processing speed | Optimised | High | **High** |
| Background Wi-Fi/BLE scanning | on | off | **off** |
| Samsung telemetry agents | 5 running | 0 | **0** |

`aggressive` additionally deletes the `/data` preloads outright, which is where most of
the extra storage comes from (Office, Teams, Samsung Notes, Samsung Internet...).

RAM numbers move around with what you have open — the point is that ~155 packages no
longer start at boot. Galaxy Store, Device Care, face unlock, DeX, Smart View and
second-screen mode are kept on purpose, which is why aggressive removes ~156 rather than 175. After the aggressive run the only things left in the top RAM list
were the launcher, System UI, Play Services and the keyboard.

## Requirements

1. **Android platform-tools** (the `adb` binary)
   - macOS: `brew install android-platform-tools`
   - Windows: [download platform-tools](https://developer.android.com/tools/releases/platform-tools) and unzip it
   - Linux: `sudo apt install android-tools-adb` (or your distro's package)
2. **USB debugging** on the tablet:
   - Settings → About tablet → Software information → tap **Build number** 7 times
   - Settings → Developer options → enable **USB debugging**
   - Connect the cable and accept the RSA prompt on the tablet
3. A USB **data** cable (many charging cables are power-only)

The scripts find `adb` automatically in the usual SDK / Homebrew / `Downloads/platform-tools` locations. If yours is somewhere else:

```bash
ADB=/path/to/adb ./run.sh balanced          # macOS / Linux
$env:ADB="C:\path\adb.exe"; .\run.ps1 balanced   # Windows
```

## Quick start

```bash
git clone https://github.com/<you>/tab-s10-fe-optimiser.git
cd tab-s10-fe-optimiser

./run.sh                 # interactive menu
./run.sh --report        # look first, change nothing
./run.sh balanced --dry-run   # preview every action
./run.sh balanced        # apply
```

On Windows use `.\run.ps1` with the same arguments. If PowerShell blocks the script:

```powershell
powershell -ExecutionPolicy Bypass -File .\run.ps1 balanced
```

## Profiles

Every profile is cumulative: `balanced` includes `light`, `aggressive` includes both.

| Profile | Packages | What it adds |
|---|---|---|
| `light` | 30 | Pure telemetry, diagnostics, factory test apps, AR-emoji toys, the preloaded Asphalt demo, duplicate CTS shims |
| `balanced` | 110 | + Bixby, Samsung Customization/Context services, Device Security (McAfee), Edge panels, Modes & Routines, Digital Wellbeing, Game Optimizing Service, 18 Samsung TTS language packs, ARCore, Link-to-Windows |
| `aggressive` | 163 | + Chrome/Samsung Internet, YouTube, Google app, Maps, Gmail, Photos, Messages, Meet, Gemini, the whole Microsoft Office suite, Samsung Pass/Cloud, SmartThings, telephony stack (Wi-Fi-only tablet) |
| `--extras` | +17 | Knox/Secure Folder, OTA updater, Samsung account. **Opt-in only** — breaks Secure Folder and security updates |
| `--disable-preloads` | flag | Hides `/data`-installed preloads instead of deleting them, so they stay restorable |

`light` is safe for anyone. `balanced` is what I run daily. `aggressive` is for a tablet used as a browser + media device.

Full per-package explanation: **[docs/TWEAKS.md](docs/TWEAKS.md)**.

## What `aggressive` removes - and what stops working

`aggressive` is meant for a tablet used as a browser + media device. It removes whole
apps, not just background services, so read this before running it.

**Removed app groups**

| Group | Apps |
|---|---|
| Browsers | Chrome, Samsung Internet (keep Brave/Firefox/whatever you installed) |
| Google | YouTube, YouTube Music, Drive, Docs, Google app (Search/Discover/Assistant), Maps, Gmail, Photos, Messages, Meet, Gemini, Voice Access, print spooler |
| Microsoft | Word, Excel, PowerPoint, OneNote, Outlook, Teams, OneDrive - **APK and data** |
| Samsung | Notes, Reminder, Studio video editor, Samsung Pass + autofill, Samsung Cloud, Samsung Kids, SmartThings, Find, Photo Remaster |
| Telephony | Dialer, in-call UI, telephony UI, call assistant, smart call, Emergency SOS, IMS/VoLTE, MMS, SIM dialogs |

**What stops working**

- No built-in browser, YouTube, YouTube Music, Drive, Docs, Gmail, Maps, Photos or
  Google Assistant/Discover (Morphe/ReVanced YouTube and YouTube Music keep working if
  you have them installed).
- No Studio video editor.
- **Samsung Notes is deleted together with its local notes** - back it up first.
- No Samsung Pass autofill.
- No dialer or Emergency SOS (the Wi-Fi-only tablet has no SIM anyway).

Every app listed above can be reinstalled by hand from **Galaxy Store** or **Play Store**
whenever you want it back - see [Reinstalling an app you actually want](#reinstalling-an-app-you-actually-want).

**What keeps working**

Camera, Gallery, My Files, Clock, Calculator, Contacts, Calendar, Settings, Samsung
keyboard, the launcher, Play Store, **Galaxy Store**, **Device Care**, Google Play
Services, S Pen / Air Command, Quick Share, Good Lock, **face unlock**,
**Smart View / casting**, **DeX**, **second-screen mode** and **Multi Control**, and
**Secure Folder** (user 150 is never touched).

Samsung's whole continuity stack (`mdx`, `mcf*`, `secondscreen`, `hwresourceshare`,
`smartmirroring`) is deliberately left alone - it is what makes DeX, Smart View and
second-screen mode work.

Everything above is restorable with `./run.sh --restore` **except** the `/data`-installed
preloads (Office, Samsung Notes, Samsung Internet, Reminder, YouTube Music, Drive, Docs),
whose APK and data are deleted by design - reinstall those from the Play Store or Galaxy
Store. Studio, YouTube and everything else in the list are system apps, so `--restore`
brings them back untouched.

One package is not in any profile on purpose: `com.samsung.android.fmm` (Find My Mobile).
Samsung blocks both `pm uninstall` and `pm disable-user` on it, so it can only be removed
with root. It is left installed and idle.

## Reinstalling an app you actually want

You do **not** have to restore everything to get one app back. Any removed app can be
installed again by hand, at any time, after any profile:

| App type | Where to get it |
|---|---|
| Samsung apps (Notes, Reminder, SmartThings, Samsung Internet, Samsung Kids...) | **Galaxy Store** - still installed, so search the app name and tap Install |
| Google apps (Chrome, YouTube, Gmail, Maps, Photos, Messages, Gemini...) | **Play Store** - search the app name |
| Microsoft apps (Word, Excel, PowerPoint, OneNote, Outlook, Teams, OneDrive) | **Play Store** - search the app name |
| Everything else | Play Store, or the vendor's own site |

Both stores are left installed in every profile, so this always works without ADB.

Notes:

- A store reinstall gives you the **latest version**, not the preloaded build. That is
  normally what you want anyway.
- **Samsung Notes**: if you had local notes, they were deleted with the app on
  `aggressive` - check Samsung Cloud / Smart Switch backup before reinstalling.
- **Samsung Internet / Samsung Pass**: reinstallable from Galaxy Store, but Samsung Pass
  autofill only works again if `com.samsung.android.samsungpass` and
  `com.samsung.android.authfw` are restored too (`./run.sh --restore`), because a store
  install cannot re-register the Knox-backed system service.
- **System apps** (Chrome, YouTube, Gmail, Maps...) are better brought back with
  `./run.sh --restore`: it re-enables the copy already on the device, keeps your data and
  needs no download.

## Maintenance tasks

```bash
./run.sh balanced --trim      # clear app caches (pm trim-caches 64G)
./run.sh balanced --dexopt    # optimise every app's bytecode (slow, run once)
./run.sh --reboot             # reboot when the run finishes
./run.sh --report             # RAM, storage, top consumers, versions
```

`--trim` usually frees a few GB on a tablet that has been used for a while.
`--dexopt` can take 5-15 minutes; it improves cold-start times until the next OTA.

## The system tweaks (all profiles)

| Tweak | Why |
|---|---|
| `window_animation_scale` → `0.5` | Halves the stock 1.0× duration. Every window feels instant instead of sluggish. |
| `transition_animation_scale` → `0.5` | Same for app-switch transitions. |
| `animator_duration_scale` → `0.5` | Same for in-app animations. |
| `cached_apps_freezer` → `enabled` | Freezes cached background apps instead of keeping them resident. |
| `peak_refresh_rate` → `90` | Never caps the 90 Hz panel. |
| `sem_enhanced_cpu_responsiveness` → `1` *(balanced)* | Samsung's "Processing speed: High" scheduler mode. |
| `min_refresh_rate` → `60` *(balanced)* | Stops the panel dropping to 30 Hz and making scrolling judder. |
| `wifi_scan_always_enabled` / `ble_scan_always_enabled` → `0` *(balanced)* | Stops background radio scanning when the radios are off. |
| `min_refresh_rate` → `90` *(aggressive)* | Locks the panel at 90 Hz at all times. |

## Reversibility

System apps are never deleted. They are removed **per user profile** with
`pm uninstall -k --user N`, which keeps all app data, and every action is written to
`backups/` before it happens.

Data-installed preloads (Microsoft Office, Samsung Notes, Samsung Internet, the Asphalt
demo...) are removed completely: `pm uninstall` deletes the APK **and** their app data,
since that data would just be orphaned once the APK is gone. Because their APK is not in
the read-only system image they cannot be restored with `pm install-existing` - they
have to be downloaded again from the store.

If you want to keep that option, add `--disable-preloads`: those apps are then hidden
and stopped but stay on disk, and `pm enable` brings them back instantly.

```
backups/
├── applied.tsv              every package action ever taken (user, package, action)
├── original-settings.tsv    the original value of every setting touched
└── 20261122-102849/         one folder per run (info.txt + that run's changes)
```

Undo everything:

```bash
./run.sh --restore          # reinstalls every package + restores original settings
./run.sh --restore backups/20261122-102849   # or undo just one run
./run.sh --restore-all      # brute force: reinstall every package in every profile
```

On Windows: `.\run.ps1 -Restore`, `.\run.ps1 -RestoreAll`.

Restoring puts the system apps back exactly as they were (same user, data intact).
Reboot afterwards.

What a restore cannot bring back are **data-installed preloads** (Office, Samsung
Notes, Samsung Internet, the Asphalt demo, some TTS voices) - their APK is not in the
system image, so they have to be re-downloaded. On the test tablet that was two items:
the preloaded Asphalt 9 demo and a duplicate English (UK) TTS voice. Everything else
came back in a full restore test (514 of 515 packages, all settings).

Use `--disable-preloads` if you want those to stay restorable.

## Other options

```bash
--dry-run        show every action without changing anything
--user 10        only touch one Android user (repeatable)
--all-users      every real user profile (default)
--trim           clear app caches (pm trim-caches)
--dexopt         run a background dexopt job now (slow, speeds up app start-up)
--reboot         reboot when finished
--yes, -y        skip the confirmation prompt
--list           print every package in every profile
--report         device info, RAM, storage, top RAM consumers
--serial <id>    pick a device when several are connected
```

Multi-user tablets: by default every real user profile is debloated, but **Secure Folder (user 150) is always skipped**. Use `--user 10` to limit it to one profile.

## Safety

- **No root.** Everything uses the normal ADB shell API.
- **Keeps app data for system apps.** Every system-image app is removed with `-k`, so its
  data survives and a restore is lossless. Only `/data`-installed preloads lose their data,
  because the APK is deleted anyway.
- **Protected-package blocklist** in both scripts refuses to touch `systemui`, `settings`, `gms`, `vending`, the launcher, the keyboard, permission controllers, etc.
- **Idempotent.** Running a profile twice does nothing the second time.
- **No OTA or Knox changes** unless you pass `--extras`.
- The worst realistic outcome is an app you wanted disappearing from the launcher — `--restore` brings it back in seconds.

## Repo layout

```
.
├── run.sh / run.ps1          entry points
├── scripts/
│   ├── optimiser.sh          macOS + Linux driver
│   └── optimiser.ps1         Windows driver
├── profiles/
│   ├── packages.tsv          tier, package, category, explanation
│   ├── settings.tsv          tier, namespace, key, value, explanation
│   └── extras.tsv            opt-in Knox / OTA / Samsung account
├── docs/
│   ├── TWEAKS.md             every package explained
│   ├── RESTORE.md            undo guide
│   └── TROUBLESHOOTING.md    when adb misbehaves
└── backups/                  generated at run time (git-ignored)
```

Want to add or drop a package? Edit `profiles/packages.tsv` — the scripts and the docs are generated from that one file.

## Contributing

Pull requests welcome. If a package is missing from a newer One UI build, add it with a tier and a one-line explanation. Test with `--dry-run` first.

## License

MIT — see [LICENSE](LICENSE). Use at your own risk; you are modifying your own device over ADB.
