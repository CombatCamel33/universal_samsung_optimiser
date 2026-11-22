# Changelog

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
