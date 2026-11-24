# Universal Samsung Optimiser

One-command, **fully reversible**, device-aware ADB optimiser for the Samsung Galaxy
Tab S10 FE+, Galaxy phones and Galaxy Watch6.

It detects tablets versus Wear OS watches before loading a profile, removes background
bloat, shortens sluggish animations, and tunes each device with settings that are valid
for its hardware. Works on **macOS, Windows and Linux**. No root or custom ROM.

Teams, Samsung Internet, the Microsoft Office apps, Gmail, Messages and the
phone/telephony services are **kept on every tablet or phone by default** - a connected phone
stays a phone
(see [Keeping apps on a phone](#keeping-apps-on-a-phone-teams-samsung-internet-office-gmail-messages-phone)).

```bash
./run.sh balanced      # macOS / Linux
.\run.ps1 balanced     # Windows
```

---

## Galaxy Watch6 aggressive results

Measured on the SM-R930 immediately before applying the 44-action profile and again
after rebooting on the same build:

| Metric | Before | `aggressive` | Change |
|---|---:|---:|---:|
| Installed packages | 249 | **205** | **-44** |
| Enabled packages | 247 | **203** | **-44** |
| Available RAM | 657.0 MiB | **790.4 MiB** | **+133.4 MiB** |
| Free `/data` storage | 5.70 GiB | **6.04 GiB** | **+355.4 MiB** |
| Animation scales | 1.0× / 1.0× / 1.0× | **0.5× / 0.5× / 0.5×** | Halved |
| Reduce transparency and blur | off | **on (profile-enforced)** | Enabled and retained after reboot |

All 44 targets were confirmed absent after reboot. Calls, Google Messages, Samsung
Health, Health Services, Health Monitor, emergency/SOS, NFC, Play Store, Galaxy Store,
phone connectivity, System UI, tiles and core watch faces were confirmed installed.
RAM varies with running apps; the post-reboot figure is a point-in-time comparison.

---

## Tested on

### Galaxy Tab S10 FE+

| | |
|---|---|
| Device | Samsung Galaxy Tab S10 FE+ Wi-Fi (`SM-X620` / `gts10fepwifi`) |
| OS | Android 16, One UI 8.5 |
| Build | `X620XXSBCZI2` (CSC `XSG`) |
| RAM | 8 GB |
| Display | 1800 × 2880, 90 Hz |
| Users | 2 real profiles + Secure Folder |

### Galaxy Watch6

| | |
|---|---|
| Device | Galaxy Watch6 Bluetooth 40 mm (`SM-R930` / `fresh6bs`) |
| OS | Android 16, Wear OS 6, One UI Watch 8.0 |
| Build | `BP2A.250325.020.R930XXS2CZF5` (CSC `BTU`) |
| Security patch | 5 July 2026 |
| RAM / storage | 2 GB / 8 GB |
| Display | 432 × 432, fixed 60 Hz |
| Connection | Wireless ADB pairing and automatic mDNS discovery |

Watch detection, inventory, reporting, protected-package checks, all three dry-run plans,
and the full aggressive profile were validated on this device. The watch has a separate
package/settings profile; the tablet's 90 Hz and CPU-performance overrides can never be
selected for it.

The tablet/phone profile still only touches packages that exist on the target, so it also
works on the S10 FE, S9 FE, and Tab S9/S10 series. Its full aggressive list contains the
telephony stack, but the default `phoning` keep group protects it on a phone; only
`--no-keep` opts back into removing those packages.

## Results on the test tablet

Measured on a real SM-X620 after each profile and a reboot. The aggressive column is the
original list (`aggressive --no-keep` today); the default keep list protects Teams, Office,
Samsung Internet, Gmail, Messages and the phone, so a default aggressive run removes
roughly 30 fewer packages and keeps a little more of the storage/RAM in use.

| Metric | Before | `balanced` | `aggressive --no-keep` |
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

`aggressive --no-keep` additionally deletes the `/data` preloads outright, which is where
most of the extra storage comes from (Office, Teams, Samsung Notes, Samsung Internet...).
With the default keep list those preloads stay installed.

RAM numbers move around with what you have open — the point is that ~155 packages no
longer start at boot. Galaxy Store, Device Care, face unlock, DeX, Smart View and
second-screen mode are kept on purpose, which is why `--no-keep` removes ~156 rather than
175. After the aggressive run the only things left in the top RAM list were the launcher,
System UI, Play Services and the keyboard.

## Results on a Galaxy M23 5G (real run)

Applied on 23 Nov 2026 to `SM-M236B` (Android 14, One UI 6.1, 4 GB RAM), user 0 only:

```bash
./run.sh aggressive --keep teams,samsung-internet,office,gmail,messages,phoning \
  --user 0 --disable-preloads --trim --no-settings --reboot
```

`--no-settings` was used deliberately: the generic profile targets a 90 Hz tablet panel and
0.5x animations, while this phone was already on 120 Hz adaptive and 0x animations, so
leaving Android settings alone preserved both. `--disable-preloads` keeps Drive, Photos and
Samsung Notes recoverable, and `--user 0` leaves Secure Folder (user 150) untouched.

| Metric | Before | After | Change |
|---|---|---|---|
| Installed packages (user 0) | 495 | 400 | **-95** |
| Disabled packages (user 0) | 33 | 35 | +2 |
| Available RAM (`MemAvailable`) | 0.5 GB | 0.8 GB | +0.2 GB |
| Free RAM | 0.2 GB | 0.2 GB | 0.0 GB |
| Storage used / free | 79.6 GB / 28.5 GB | 68.5 GB / 39.6 GB | **-11.1 GB / +11.1 GB** |
| Refresh rate | 120 Hz adaptive | 120 Hz adaptive | unchanged |

Samsung Messages was removed only after Google Messages was confirmed as the default SMS
app. Gmail, Google Messages/MMS, Teams, Samsung Internet, Word/Outlook/OneDrive, the
dialer, in-call UI, IMS/VoLTE, SIM UI and Emergency SOS all remained installed and enabled.
Knox, Secure Folder, the OTA updater and the Samsung account were untouched (no
`--extras`), and all 43 protected packages that existed before the run were still present
after the reboot. Figures come from
`backups/20261123-131937/stats-before.tsv` and `stats-after.tsv`.

## Requirements

1. **Android platform-tools** (the `adb` binary)
   - macOS: `brew install android-platform-tools`
   - Windows: [download platform-tools](https://developer.android.com/tools/releases/platform-tools) and unzip it
   - Linux: `sudo apt install android-tools-adb` (or your distro's package)
2. A debugging connection:
   - **Tablet (USB):**
     - Settings → About tablet → Software information → tap **Build number** 7 times
     - Settings → Developer options → enable **USB debugging**
     - Connect a USB **data** cable and accept the RSA prompt
   - **Galaxy Watch (wireless):**
     - Settings → About watch → Software information → tap **Software version** 7 times
     - Developer options → enable **ADB debugging** and **Wireless debugging**
     - Follow [Wireless ADB for Galaxy Watch](docs/WATCH.md#wireless-adb)

The scripts find `adb` automatically in the usual SDK / Homebrew / `Downloads/platform-tools` locations. If yours is somewhere else:

```bash
ADB=/path/to/adb ./run.sh balanced          # macOS / Linux
$env:ADB="C:\path\adb.exe"; .\run.ps1 balanced   # Windows
```

## Quick start

```bash
git clone https://github.com/H33CKER/universal-samsung-optimiser.git
cd universal-samsung-optimiser

./run.sh                 # interactive menu
./run.sh --report        # look first, change nothing
./run.sh balanced --dry-run   # preview every action
./run.sh balanced        # apply
```

For a watch, pair first. The pairing port/code and normal debugging port are different:

```bash
adb pair WATCH_IP:PAIRING_PORT PAIRING_CODE
adb connect WATCH_IP:DEBUG_PORT       # only if mDNS did not connect automatically
./run.sh aggressive --dry-run         # automatically selects the watch profile
```

On Windows use `.\run.ps1` with the same arguments. If PowerShell blocks the script:

```powershell
powershell -ExecutionPolicy Bypass -File .\run.ps1 balanced
```

## Profiles

Every profile is cumulative: `balanced` includes `light`, `aggressive` includes both.

### Tablet profiles

| Profile | Packages | What it adds |
|---|---|---|
| `light` | 30 | Pure telemetry, diagnostics, factory test apps, AR-emoji toys, the preloaded Asphalt demo, duplicate CTS shims |
| `balanced` | 110 | + Bixby, Samsung Customization/Context services, Device Security (McAfee), Edge panels, Modes & Routines, Digital Wellbeing, Game Optimizing Service, 18 Samsung TTS language packs, ARCore, Link-to-Windows |
| `aggressive` | 164 | + Chrome/Samsung Internet, YouTube, Google app, Maps, Gmail, Photos, Messages, Meet, Gemini, the whole Microsoft Office suite, Samsung Pass/Cloud, SmartThings, telephony stack. **Teams, Samsung Internet, Office, Gmail, Messages and phone services are kept by default** |
| `--extras` | +17 | Knox/Secure Folder, OTA updater, Samsung account. **Opt-in only** — breaks Secure Folder and security updates |
| `--disable-preloads` | flag | Hides `/data`-installed preloads instead of deleting them, so they stay restorable |

`light` is safe for anyone. `balanced` is what I run daily. `aggressive` is for a tablet or phone used as a browser + media device. The 164 count is the full `--no-keep` list; with the default keep list about 30 of those packages are reported as `(kept)` and skipped.

### Galaxy Watch profiles

| Profile | Actions | What it adds |
|---|---:|---|
| `light` | 14 | Retail demo, CTS certification shims, factory/service test tools, Device Quality Agent telemetry |
| `balanced` | 23 | + Bixby, Samsung Pay, Customization Service, self-diagnostics, partner and enterprise provisioning; Google Wallet stays |
| `aggressive` | 44 | + Google Assistant/Gemini, Google Wallet, Global Goals, Outlook, Samsung Internet, SmartThings, optional media/tools and Samsung Messages |
| `--extras` | +2 | OTA update agents. **Opt-in only** — stops normal watch updates |

The watch aggressive tier still keeps **all calling components, Google Messages, Samsung
Health, Health Services, Health Monitor, sleep tracking, sensors, emergency/SOS, Find My
Watch, phone connectivity, tiles, keyboards and all core stock watch faces**. Only the
promotional Global Goals face companions are part of aggressive. Every watch target is
uninstalled; system apps remain restorable, while `/data` apps require a store reinstall.
Use `--disable-preloads` to preserve `/data` APKs and data instead.
Google Play Store and Galaxy Store are hard-protected in every watch tier.

Full explanations: **[tablet tweaks](docs/TWEAKS.md)** · **[Galaxy Watch profiles](docs/WATCH.md)**.

## Keeping apps on a phone (Teams, Samsung Internet, Office, Gmail, Messages, phone)

The repo was written for a Wi-Fi-only tablet, but it is safe on a phone because a
**keep list** in [`profiles/keep.tsv`](profiles/keep.tsv) always wins. These groups are
kept by default on whichever tablet or phone is connected:

| Group | Keeps |
|---|---|
| `teams` | Microsoft Teams |
| `samsung-internet` | Samsung Internet browser |
| `office` | Word, Excel, PowerPoint, OneNote, Outlook, the unified Microsoft 365 app and OneDrive |
| `gmail` | Gmail |
| `messages` | Google Messages, MMS and Message Guard (Samsung Messages is removed by `aggressive`) |
| `phoning` | Dialer, in-call UI, telephony settings, call assistant, Smart Call, Emergency SOS, IMS/VoLTE/Wi-Fi calling, RCS/Carrier Services, call continuity, call-log backup, SIM and carrier configuration |

Before using `aggressive` on a phone, confirm Google Messages is installed and selected as
the default SMS app. Samsung Messages is intentionally not in the keep list.

Kept packages are reported as `(kept)` in the run output and are never uninstalled or
disabled. Because they are not touched, the phone keeps calling, texting, Teams, Office,
Gmail and Samsung Internet working after any profile.

Choose only some groups, add groups, or opt out completely:

```bash
./run.sh aggressive --keep phoning,messages,teams   # keep just these
./run.sh aggressive --keep office                  # one group (repeatable)
./run.sh aggressive --no-keep                      # old behaviour: remove everything
./run.sh --list-keep                               # show every group + package
```

On Windows use `-Keep phoning,messages,teams`, `-NoKeep`, `-ListKeep` and `-NoSettings`.
Watch profiles use their own safety rules and ignore the tablet/phone keep list.

Packages that are already removed stay removed - run `--restore` first, then re-apply the
profile. A package that does not exist on your model is ignored, and you can add other
package names to `profiles/keep.tsv` if your build uses a different one.

## What tablet `aggressive` removes - and what stops working

`aggressive` is meant for a tablet or phone used as a browser + media device. It removes
whole apps, not just background services, so read this before running it. The
[keep list](#keeping-apps-on-a-phone-teams-samsung-internet-office-gmail-messages-phone) means
the Teams / Samsung Internet / Office / Gmail / Messages / phone rows below are **not** removed
unless you pass `--no-keep`.

**Removed app groups**

| Group | Apps |
|---|---|
| Browsers | Chrome, Samsung Internet *(kept by default)* |
| Google | YouTube, YouTube Music, Drive, Docs, Google app (Search/Discover/Assistant), Maps, Photos, Meet, Gemini, Voice Access, print spooler. **Gmail and Google Messages are kept by default** |
| Microsoft | Word, Excel, PowerPoint, OneNote, Outlook, Teams, OneDrive - all **kept by default**; `--no-keep` deletes APK and data |
| Samsung | Samsung Messages, Notes, Reminder, Studio video editor, Samsung Pass + autofill, Samsung Cloud, Samsung Kids, SmartThings, Find, Photo Remaster |
| Telephony | Dialer, in-call UI, telephony UI, call assistant, smart call, Emergency SOS, IMS/VoLTE, MMS, SIM dialogs and carrier configuration - **kept by default** |

**What stops working**

- No Chrome, YouTube, YouTube Music, Drive, Docs, Maps, Photos or
  Google Assistant/Discover (Morphe/ReVanced YouTube and YouTube Music keep working if
  you have them installed). Samsung Internet and Gmail stay installed by default.
- No Studio video editor.
- **Samsung Notes is deleted together with its local notes** - back it up first.
- No Samsung Pass autofill.
- Nothing telephony-related: with the default keep list the dialer, messages, IMS/VoLTE
  and Emergency SOS stay installed. Passing `--no-keep` removes them, which is only
  sensible on a Wi-Fi-only tablet.

Every app listed above can be reinstalled by hand from **Galaxy Store** or **Play Store**
whenever you want it back - see [Reinstalling an app you actually want](#reinstalling-an-app-you-actually-want).

**What keeps working**

Camera, Gallery, My Files, Clock, Calculator, Contacts, Calendar, Settings, Samsung
keyboard, the launcher, Play Store, **Galaxy Store**, **Device Care**, Google Play
Services, S Pen / Air Command, Quick Share, Good Lock, **face unlock**,
**Smart View / casting**, **DeX**, **second-screen mode** and **Multi Control**,
**Secure Folder** (user 150 is never touched), plus **Teams, Samsung Internet, Office,
Gmail, Messages and the phone app** through the default keep list.

Samsung's whole continuity stack (`mdx`, `mcf*`, `secondscreen`, `hwresourceshare`,
`smartmirroring`) is deliberately left alone - it is what makes DeX, Smart View and
second-screen mode work.

Everything that is actually removed is restorable with `./run.sh --restore` **except**
the `/data`-installed preloads (Office, Samsung Notes, Samsung Internet, Reminder, YouTube
Music, Drive, Docs), whose APK and data are deleted by design when they are not kept -
reinstall those from the Play Store or Galaxy Store. Studio, YouTube and everything else
in the list are system apps, so `--restore` brings them back untouched. Office and Samsung
Internet keep their data by default because they are never removed.

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

### Automatic before / after

Every real profile run captures a baseline before making changes and a second snapshot
afterward. The terminal and backup show installed/enabled package counts, available RAM,
free `/data` storage, and battery level. The immediate RAM number is indicative only;
reboot before making a stable comparison.

Dry runs capture and print only the current baseline—nothing is written to `backups/`.

The numbers are saved as `stats-before.tsv` and `stats-after.tsv` in the run's backup
folder, so they can be reprinted at any time - no device needed:

```bash
./run.sh --compare                              # most recent run
./run.sh --compare backups/20261123-104500      # a specific run
```

On Windows: `.\run.ps1 -Compare` or `.\run.ps1 -Compare backups\20261123-104500`.

The same capture runs on phones and tablets, for every real user profile. RAM changes with
what is open at the moment, so package counts and storage are the reliable numbers.

## System tweaks

The animation/freezer settings apply to both device families. Reduce transparency and
blur is **watch-only**; the remaining performance, scan and refresh-rate settings are
**tablet-only**. The Watch6 has a fixed 60 Hz panel and never receives tablet display or
Samsung CPU-performance overrides.

| Tweak | Why |
|---|---|
| `window_animation_scale` → `0.5` | Halves the stock 1.0× duration. Every window feels instant instead of sluggish. |
| `transition_animation_scale` → `0.5` | Same for app-switch transitions. |
| `animator_duration_scale` → `0.5` | Same for in-app animations. |
| `cached_apps_freezer` → `enabled` | Freezes cached background apps instead of keeping them resident. |
| `accessibility_reduce_transparency` → `1` *(watch)* | Enables Accessibility → Visibility enhancements → Reduce transparency and blur, reducing compositing overhead. |
| `peak_refresh_rate` → `90` | Never caps the 90 Hz panel. |
| `sem_enhanced_cpu_responsiveness` → `1` *(balanced)* | Samsung's "Processing speed: High" scheduler mode. |
| `min_refresh_rate` → `60` *(balanced)* | Stops the panel dropping to 30 Hz and making scrolling judder. |
| `wifi_scan_always_enabled` / `ble_scan_always_enabled` → `0` *(balanced)* | Stops background radio scanning when the radios are off. |
| `min_refresh_rate` → `90` *(aggressive)* | Locks the panel at 90 Hz at all times. |

## Reversibility

System apps are never deleted. They are removed **per user profile** with
`pm uninstall -k --user N`, which keeps all app data, and every action is written to
`backups/` before it happens.

On the tablet, data-installed preloads (Microsoft Office, Samsung Notes, Samsung
Internet, the Asphalt demo...) are removed completely: `pm uninstall` deletes the APK
**and** their app data, since that data would just be orphaned once the APK is gone.
Because their APK is not in the read-only system image they cannot be restored with
`pm install-existing` - they have to be downloaded again from the store.

If you want to keep that option, add `--disable-preloads`: those apps are then hidden
and stopped but stay on disk, and `pm enable` brings them back instantly.

The watch profile uninstalls every target. System-image watch apps use reversible per-user
uninstall. Watch apps whose APK lives only in `/data` are deleted with their app data and
must be downloaded again; use `--disable-preloads` to disable and preserve them instead.

```
backups/
├── applied.tsv              every package action ever taken (user, package, action)
├── original-settings.tsv    the original value of every setting touched
├── 20261122-102849/         one folder per tablet/phone run:
│   ├── info.txt             device, profile, keep groups
│   ├── packages.tsv         that run's package changes
│   ├── settings.tsv         that run's setting changes
│   ├── stats-before.tsv     device statistics before the run
│   └── stats-after.tsv      device statistics after the run
└── watch-SM-R930-…/         isolated per-watch history
    ├── applied.tsv
    ├── original-settings.tsv
    └── 20261123-120000/     watch run: manifests + before.txt / after.txt
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

Watch and tablet histories are isolated, and an explicitly selected backup is rejected
if its recorded device codename/class does not match the connected target.

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
--keep <groups>  keep app groups (default: teams,samsung-internet,office,gmail,messages,phoning)
--no-keep        remove every listed package, including the default keep groups
--list-keep      print the keep groups and their packages
--no-settings    remove/disable packages only; leave Android settings untouched
--trim           clear app caches (pm trim-caches)
--dexopt         run a background dexopt job now (slow, speeds up app start-up)
--reboot         reboot when finished
--yes, -y        skip the confirmation prompt
--list           print every package in every profile
--report         device info, RAM, storage, top RAM consumers
--compare [dir]  before/after statistics for a run (default: the latest)
--serial <id>    pick a device when several are connected
```

On Windows the equivalents are `-Keep`, `-NoKeep`, `-ListKeep`, `-NoSettings`, `-Compare`,
`-List`, `-Report`, `-User`, `-Serial`, `-Trim`, `-Dexopt`, `-Reboot` and `-Yes`.

Multi-user tablets: by default every real user profile is debloated, but **Secure Folder (user 150) is always skipped**. Use `--user 10` to limit it to one profile.

## Safety

- **No root.** Everything uses the normal ADB shell API.
- **Keeps app data for system apps.** Every system-image app is removed with `-k`, so its
  data survives and a restore is lossless. Only `/data`-installed preloads lose their data,
  because the APK is deleted anyway.
- **Protected-package blocklist** refuses to touch core Android packages. On watches it
  additionally protects both System UIs, Wear Services, phone pairing/transport, tiles,
  health services, calls, safety/SOS, Find My Watch, NFC, stores and the Samsung account.
- **Keep list on by default** - Teams, Samsung Internet, Office, Gmail, Messages and the phone/telephony stack are never removed unless you explicitly pass `--no-keep`.
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
│   ├── keep.tsv              app groups that are never removed (default: all)
│   ├── extras.tsv            opt-in Knox / OTA / Samsung account
│   └── watch/                device-specific packages, settings and extras
├── docs/
│   ├── TWEAKS.md             every package explained
│   ├── WATCH.md              Watch6 profiles + wireless ADB guide
│   ├── RESTORE.md            undo guide
│   └── TROUBLESHOOTING.md    when adb misbehaves
└── backups/                  generated at run time (git-ignored)
```

Want to add or drop a package? Edit `profiles/packages.tsv` for tablets and phones or
`profiles/watch/packages.tsv` for watches, then run `python3 tools/generate-docs.py`.
Want an app to survive every profile? Add it to a group in `profiles/keep.tsv`.

## Contributing

Pull requests welcome. If a package is missing from a newer One UI build, add it with a tier and a one-line explanation. Test with `--dry-run` first.

## License

MIT — see [LICENSE](LICENSE). Use at your own risk; you are modifying your own device over ADB.
