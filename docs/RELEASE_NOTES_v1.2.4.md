# v1.2.4 — Universal Samsung Optimiser

First tagged release. Reversible ADB debloat + tuning for the Samsung Galaxy Tab S10 FE+
(SM-X620), written to work on most One UI tablets too.

Tested on: **SM-X620, Android 16 (SDK 36), One UI 8.5**, build `X620XXSBCZI2`, CSC `XSG`.

## Profiles

Every profile is cumulative: `balanced` includes `light`, `aggressive` includes both.

| Profile | Packages | Adds |
|---|---|---|
| `light` | 30 | Telemetry, diagnostics, factory test apps, AR-emoji toys, duplicate CTS shims |
| `balanced` | 80 | Bixby, Samsung Customization/Context services, Device Security (McAfee), Edge panels, Modes & Routines, Digital Wellbeing, Game Optimizing Service, 18 TTS language packs, ARCore, Link to Windows |
| `aggressive` | 159 | Chrome/Samsung Internet, YouTube, Google app, Maps, Gmail, Photos, Messages, Gemini, Microsoft Office suite, Samsung Pass/Cloud, SmartThings, telephony stack |
| `--extras` | +17 | Opt-in Knox / Secure Folder, OTA updater, Samsung account. Breaks Secure Folder and security updates |

Kept on purpose in every profile: launcher, Settings, Play Store, **Galaxy Store**,
**Device Care**, GMS, camera, gallery, My Files, contacts, calendar, keyboard, S Pen,
Quick Share, **face unlock**, **DeX**, **Smart View**, **second-screen mode**,
**Multi Control**, and Secure Folder (user 150 is never touched).

## Measured results

Real SM-X620, after each profile and a reboot:

| Metric | Before | `balanced` | `aggressive` |
|---|---|---|---|
| Installed packages (user 10) | 515 | 409 | **365** |
| Installed packages (user 0) | 443 | 336 | **292** |
| Available RAM (`MemAvailable`) | ~2.4 GB | ~3.2 GB | **~3.8 GB** |
| Storage used / free | 83 GB / 21 GB | 78 GB / 25 GB | **75 GB / 29 GB** |
| Animation scales | 1.5× (stock 1.0×) | 0.5× | **0.5×** |
| Min refresh rate | unset (drops to 30 Hz) | 60 Hz | **90 Hz locked** |
| Background Wi-Fi/BLE scanning | on | off | **off** |

## Quick start

```bash
git clone https://github.com/H33CKER/universal-samsung-optimiser.git
cd universal-samsung-optimiser

./run.sh --report             # look, change nothing
./run.sh balanced --dry-run   # preview every action
./run.sh balanced             # apply
./run.sh --restore            # undo everything
```

Windows: `.\run.ps1 balanced` (PowerShell 5.1+), same arguments.

## Reversibility

- **System-image apps** → `pm uninstall -k --user N`: APK hidden, app data kept,
  `pm install-existing` restores losslessly.
- **`/data`-installed preloads** (Office, Samsung Notes, Samsung Internet, Asphalt demo)
  → `pm uninstall` deletes APK **and** data, because the data would be orphaned. Use
  `--disable-preloads` to hide them instead and keep them restorable.
- Every action is logged to `backups/applied.tsv` and `backups/original-settings.tsv`.
- Full restore was tested end-to-end: 514 of 515 packages and all settings came back.
- Any removed app can also be reinstalled by hand from **Galaxy Store** or **Play Store**,
  both of which stay installed.

## Known limitations

- `com.samsung.android.fmm` (Find My Mobile) is excluded from every profile — Samsung
  blocks both `pm uninstall` and `pm disable-user` on it without root.
- Restoring does not re-download apps you removed yourself from the store.
- `--extras` is opt-in only: it removes Knox and the OTA updater, which breaks Secure
  Folder and stops security updates.

See [CHANGELOG.md](https://github.com/H33CKER/universal-samsung-optimiser/blob/main/CHANGELOG.md)
for the full history.
