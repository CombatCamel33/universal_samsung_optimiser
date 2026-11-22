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

Measured after applying `balanced` and rebooting:

| Metric | Before | After |
|---|---|---|
| Installed packages (user 10) | 515 | **409** |
| Installed packages (user 0) | 443 | **336** |
| Available RAM (`MemAvailable`) | ~2.4 GB | **~3.2 GB** |
| Animation scales | 1.5× / 1.5× / 1.5× (stock is 1.0×) | **0.5×** |
| Always-on background scanners | Wi-Fi + BLE + location history | **off** |
| Samsung telemetry agents | 5 running | **0** |

RAM numbers move around with what you have open — the point is that roughly 100 background services no longer start at boot.

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
| `balanced` | 111 | + Bixby, Samsung Customization/Context services, Device Security (McAfee), Edge panels, Modes & Routines, Digital Wellbeing, Game Optimizing Service, 18 Samsung TTS language packs, ARCore, Link-to-Windows |
| `aggressive` | 178 | + Chrome/Samsung Internet, YouTube, Google app, Maps, Gmail, Photos, Messages, Meet, Gemini, the whole Microsoft Office suite, Galaxy Store, Samsung Pass/Cloud, SmartThings, casting/second-screen stack, telephony stack (Wi-Fi-only tablet) |
| `--extras` | +17 | Knox/Secure Folder, OTA updater, Samsung account. **Opt-in only** — breaks Secure Folder and security updates |
| `--disable-preloads` | flag | Hides `/data`-installed preloads instead of deleting them, so they stay restorable |

`light` is safe for anyone. `balanced` is what I run daily. `aggressive` is for a tablet used as a browser + media device.

Full per-package explanation: **[docs/TWEAKS.md](docs/TWEAKS.md)**.

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

Nothing is deleted. Packages are removed **per user profile** with `pm uninstall -k --user N`, which keeps all app data, and every action is written to `backups/` before it happens.

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

Restoring puts the packages back exactly as they were (same user, data intact). Reboot afterwards.

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
