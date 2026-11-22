# Changelog

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
