# Changelog

## 1.4.0

- Expanded the project to **Universal Android Optimiser** while preserving the dedicated
  Galaxy Watch profiles introduced in 1.3.
- Added an exact Xiaomi Redmi 10 profile for `21061119DG` / `eos`, validated against a
  connected MIUI 14.0.7 Global phone. Xiaomi telemetry, MSA ads, factory tools and
  optional apps are tiered in `profiles/packages-redmi-10.tsv`.
- Added `profiles/devices.tsv`; OEM additions require an exact manufacturer, codename
  and model match rather than being guessed from a brand.
- Refresh values are detected from advertised display modes. Samsung's CPU-performance
  setting is now scoped to Samsung and is never written to Xiaomi devices.
- The selected launcher, dialer, SMS app, browser, keyboard, installed accessibility
  services and notification listeners are protected dynamically.
- Settings writes are read back and reported as rejected when an OEM (notably MIUI
  without USB debugging security permission) does not accept them.
- Before/after capture now includes setting readbacks and target/protected package counts,
  writes Markdown/TSV reports, and captures a post-reboot final snapshot on phones/tablets.
- Phone/tablet cumulative histories are isolated by ADB serial, extending the existing
  per-watch isolation and preventing cross-device restores.
- Verified Redmi aggressive with preload preservation: 451 -> 407 installed packages,
  all 29 present protected packages retained, and available RAM measured 1.1 -> 2.3 GB
  after reboot. MIUI settings remained unchanged and were reported honestly.

## 1.3.1

- **Phone keep list.** New `profiles/keep.tsv` with six groups - `teams`,
  `samsung-internet`, `office`, `gmail`, `messages` and `phoning` - all enabled by
  default on tablets and phones. Packages in those groups are skipped by every profile,
  so a connected phone keeps Teams, Samsung Internet, Office, Gmail, Google Messages,
  the dialer, IMS/VoLTE/Wi-Fi calling, RCS and Emergency SOS working.
- `messages` protects Google Messages and MMS but deliberately **not** Samsung Messages,
  which `aggressive` targets. Confirm Google Messages holds the SMS role first.
- `phoning` also protects the AOSP phone/telecom stack, carrier configuration, eSIM and
  virtual-SIM support, Hiya and the Samsung IMS services - packages a tablet-only list
  would otherwise strip from a phone.
- New `--keep <groups>` (Windows `-Keep`), `--no-keep` (`-NoKeep`) and `--list-keep`
  (`-ListKeep`) options. Kept rows are printed as `(kept)` and skipped before any
  `pm uninstall` / `pm disable-user` call.
- New `--no-settings` (Windows `-NoSettings`) applies package changes only and leaves
  animation scales, refresh rate and every other Android setting alone.
- New `--compare [dir]` (Windows `-Compare`) reprints the before/after statistics of a
  run, including tablet and phone runs; the interactive menu has a `6) compare` entry.
- Verified on a Galaxy M23 5G (`SM-M236B`): 495 -> 400 installed packages, 11.1 GB of
  storage freed, and all 43 protected packages plus all 13 Knox/OTA components still
  present after the reboot. README has the full before/after table.
- `profiles/packages.tsv` and `docs/TWEAKS.md` explain which rows are kept by default;
  `tools/generate-docs.py` regenerates the keep section.

## 1.3.0

- Renamed the project and CLI to **Universal Samsung Optimiser**.
- Added device-aware Galaxy Watch / Wear OS support with dedicated cumulative `light`,
  `balanced`, and `aggressive` profiles.
- Tested profile detection, dry runs, and the full 44-action aggressive profile on
  Galaxy Watch6 Bluetooth 40 mm (`SM-R930`, Android 16 / Wear OS 6 / One UI Watch 8.0).
- Watch aggressive preserves calls, Google Messages, health/sleep tracking, safety,
  connectivity, stores, tiles, keyboards, and core stock watch faces.
- Added explicit per-package `uninstall` / `disable` actions. Normal watch profiles
  uninstall every target; `--disable-preloads` preserves `/data` APKs and data when wanted.
- Added automatic before/after snapshots for package counts, available RAM, storage,
  and battery level.
- Watch backup histories are isolated per device, and explicit restores reject backups
  recorded for a different device class/codename.
- Added wireless ADB instructions and generated `docs/WATCH.md` reference documentation.

## 1.2.5

- `aggressive` now also removes **YouTube Music**, **Google Drive**, **Google Docs** and
  the Samsung **Studio** video editor.
- Aggressive is now 163 packages (30 / 80 / 163).
- README results table refreshed (359 / 290 packages, 156 removals per user).

## 1.2.4

- README: new "Reinstalling an app you actually want" section - Galaxy Store / Play Store
  both stay installed, so any removed app can be added back by hand after any profile.
- `docs/RESTORE.md`: same guidance for single-app recovery, including the caveat that a
  store install starts with fresh app data.

## 1.2.3

- `aggressive` keeps **Device Care** (`com.samsung.android.lool`).
- Aggressive is now 159 packages (30 / 80 / 159), 150 removals per user.
- README results table refreshed with the final aggressive numbers after the
  Galaxy Store / continuity / Device Care restores.

## 1.2.2

- `aggressive` no longer touches Galaxy Store, face unlock, Smart View / audio mirroring,
  second-screen mode, DeX/MDX, Multi Control or hardware resource sharing.
- `com.samsung.android.app.updatecenter` (Galaxy Store's update component) is kept too.
- Aggressive is now 160 packages (30 / 110 / 160).
- README corrected: DeX, Smart View, second screen, face unlock and Galaxy Store all keep
  working; continuity stack is explicitly left installed.

## 1.2.1

- Removed `com.samsung.android.fmm` (Find My Mobile) from tier 3 - Samsung blocks both
  `pm uninstall` and `pm disable-user` on it, so it can only be removed with root.
  Aggressive is now 177 packages.
- README: added a before / `balanced` / `aggressive` results table and a section on
  what aggressive removes and what stops working.

## 1.2.0

- **Preloads now lose their app data too.** `/data`-installed preloads are removed with
  `pm uninstall` (no `-k`), so the APK *and* its data are gone. System-image apps still
  use `-k`, so a restore stays lossless.
- `--dry-run` marks those rows as `(preload: would delete APK + data)`.
- Report and banner now print the One UI version in human form (`80500` -> `8.5`).
- Docs corrected to One UI 8.5 (the test tablet runs Android 16 / One UI 8.5).

## 1.1.0

- **Data-installed preloads are now deleted by default** (Office, Samsung Notes,
  Samsung Internet, the Asphalt demo, extra TTS voices). They are removed with
  `pm uninstall -k`, which deletes the APK and keeps app data.
- New `--disable-preloads` / `-DisablePreloads` flag: hides those preloads instead of
  deleting them, so they stay restorable with `pm enable`.
- `--dry-run` now marks preloads as `(preload: would delete)` or
  `(preload: would disable)`.
- Restore reports deleted preloads as "no longer on the device" instead of a hard error.
- Corrected the animation-scale wording: stock One UI is 1.0x, not 1.5x. The 1.5x in the
  before/after table was a pre-existing non-default value on the test tablet.

## 1.0.0

- Initial release: `light` / `balanced` / `aggressive` profiles, `--extras`,
  cumulative backups, `--restore` / `--restore-all`, `--report`, `--list`, `--trim`,
  `--dexopt`.
- macOS/Linux bash driver and Windows PowerShell driver.
