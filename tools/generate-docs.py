#!/usr/bin/env python3
"""Regenerate docs/TWEAKS.md from profiles/*.tsv.

Usage: python3 tools/generate-docs.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROFILES = ROOT / "profiles"
OUT = ROOT / "docs" / "TWEAKS.md"
WATCH_OUT = ROOT / "docs" / "WATCH.md"


def rows(path):
    for line in path.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        f = line.split("\t")
        if len(f) >= 4:
            yield f


def table(items):
    out = ["| Package | Category | What it is / why it can go |", "|---|---|---|"]
    for tier, pkg, cat, note in items:
        out.append(f"| `{pkg}` | {cat} | {note} |")
    return "\n".join(out)


def watch_table(items):
    out = [
        "| Package | Action | Category | What it is / why it can go |",
        "|---|---|---|---|",
    ]
    for row in items:
        _tier, pkg, cat, note, *rest = row
        action = rest[0] if rest else "uninstall"
        out.append(f"| `{pkg}` | `{action}` | {cat} | {note} |")
    return "\n".join(out)


def main():
    pkgs = list(rows(PROFILES / "packages.tsv"))
    extras = list(rows(PROFILES / "extras.tsv"))
    settings = list(rows(PROFILES / "settings.tsv"))

    tiers = {1: [], 2: [], 3: []}
    for r in pkgs:
        tiers[int(r[0])].append(r)

    doc = f"""# Every tweak, explained

This file is generated from `profiles/*.tsv` by `tools/generate-docs.py`.

* **light** = tier 1
* **balanced** = tiers 1-2
* **aggressive** = tiers 1-3

Packages that live in the read-only system image are removed per user profile with
`pm uninstall -k --user N` (app data is kept) and come back with
`pm install-existing --user N`.

A handful of preloads are installed into `/data` instead of the system image
(Microsoft Office, Samsung Notes, Samsung Internet, the Asphalt demo...). Those are
removed completely - `pm uninstall` deletes the APK and the app data, since the data
would be orphaned otherwise. Because the APK is not in the system image they cannot be
restored with `pm install-existing` - they have to be downloaded again from the store.
Pass `--disable-preloads` to hide them instead and keep them restorable with `pm enable`.

Nothing here needs root.

> A package is only touched if it is actually installed on your device, so the real
> number of changes is usually lower than the table below.

## Tier 1 - light ({len(tiers[1])} packages)

Safe for anyone. Telemetry, diagnostics, factory test tools, AR toys and preloads.

{table(tiers[1])}

## Tier 2 - balanced ({len(tiers[1]) + len(tiers[2])} packages total)

Adds features that most people never open: Bixby, Samsung context/customisation
services, Edge panels, Modes & Routines, Digital Wellbeing, gaming services,
ARCore, Link-to-Windows and the Samsung TTS language packs (which are large).

{table(tiers[2])}

## Tier 3 - aggressive ({len(pkgs)} packages total)

Adds full apps you can replace with something better, plus the telephony stack
(this tablet has no SIM slot). Read the notes before applying - a few of these
are things people genuinely use.

{table(tiers[3])}

## Extras - `--extras` only ({len(extras)} packages)

**Not** part of any profile. These break Secure Folder, OTA security updates
and the Samsung account. Only use them if you understand that.

{table(extras)}

## System settings

Applied with `settings put <namespace> <key> <value>` and restored from
`backups/original-settings.tsv`.

| Tier | Setting | Value | Why |
|---|---|---|---|
""" + "\n".join(
        f"| {t} | `{ns}.{key}` | `{val}` | {note} |" for t, ns, key, val, note in settings
    ) + """

### What each one does

**Animation scales (tier 1)** - `window_animation_scale`, `transition_animation_scale`
and `animator_duration_scale` control how long Android spends animating windows,
transitions and in-app motion. The stock One UI value is **1.0x**; `0.5` is the sweet
spot - visibly faster, still smooth. `0` makes things feel broken, so the script never
uses it. (This particular tablet had been set to 1.5x before the optimiser ran, which is
why the before/after table shows 1.5x.)

**`cached_apps_freezer` (tier 1)** - Android keeps recently used apps in a "cached"
state in RAM. With the freezer enabled, they are frozen (CPU and wakelocks stopped)
instead of being allowed to run in the background. Better idle battery, no downside
for normal use.

**`peak_refresh_rate` / `min_refresh_rate`** - the S10 FE+ panel supports 30, 48, 60
and 90 Hz. By default it drops to 30 Hz aggressively, which makes scrolling look
choppy. `peak=90` stops any cap; `min=60` keeps it at 60 Hz or above; `min=90` locks
it at 90 Hz (smoothest, costs battery).

**`sem_enhanced_cpu_responsiveness` (tier 2)** - the value behind
Settings → Battery → Processing speed. `0` = optimised, `1` = high, `2` = maximum.
`1` keeps the scheduler in its performance profile without the heat of `2`.

**`wifi_scan_always_enabled` / `ble_scan_always_enabled` (tier 2)** - Android scans
for Wi-Fi and Bluetooth LE networks even when those radios are "off", for location
accuracy. Turning that off removes a constant source of wakeups. Downside: slightly
worse location accuracy when Wi-Fi is off.

## Appendix - other useful ADB commands

These are **not** run by the script, but they are handy on this tablet:

```bash
# Free app caches (the --trim option does this)
adb shell cmd package trim-caches 64G

# Optimise every app's bytecode for faster cold starts (slow, run once)
adb shell cmd package bg-dexopt-job

# Show which apps are currently holding wakelocks
adb shell dumpsys power | grep -A20 'Wake Locks'

# Show battery drain per app since last charge
adb shell dumpsys batterystats --charged | head -80

# Disable the Google app completely (it is the single biggest RAM user)
adb shell pm uninstall -k --user 0 com.google.android.googlequicksearchbox

# Put an app to sleep (battery optimisation, reversible)
adb shell cmd appops set <package> RUN_IN_BACKGROUND ignore

# Undo that
adb shell cmd appops set <package> RUN_IN_BACKGROUND allow

# See every package that is currently disabled
adb shell pm list packages -d

# Reinstall something you removed
adb shell pm install-existing --user 0 <package>
```
"""

    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(doc)
    print(f"wrote {OUT.relative_to(ROOT)} ({len(pkgs)} packages, {len(extras)} extras, {len(settings)} settings)")

    watch_dir = PROFILES / "watch"
    watch_pkgs = list(rows(watch_dir / "packages.tsv"))
    watch_extras = list(rows(watch_dir / "extras.tsv"))
    watch_settings = list(rows(watch_dir / "settings.tsv"))
    watch_tiers = {1: [], 2: [], 3: []}
    for row in watch_pkgs:
        watch_tiers[int(row[0])].append(row)

    watch_doc = f"""# Galaxy Watch / Wear OS support

This file is generated from `profiles/watch/*.tsv` by `tools/generate-docs.py`.
The optimiser detects `android.hardware.type.watch` / the `watch` build characteristic
and selects these profiles automatically. The tablet package and display settings are
never applied to a watch.

Tested on a **Galaxy Watch6 Bluetooth 40 mm** (`SM-R930`, `fresh6bs`) running
**Android 16 / Wear OS 6 / One UI Watch 8.0**.

The full aggressive profile was applied on-device: all 44 targets were absent after
reboot, while calls, Google Messages, health, safety, NFC, both stores, connectivity and
the watch UI remained installed and enabled.

## Safety model

The watch profiles are cumulative:

* **light** = tier 1 ({len(watch_tiers[1])} package actions)
* **balanced** = tiers 1-2 ({len(watch_tiers[1]) + len(watch_tiers[2])} package actions)
* **aggressive** = tiers 1-3 ({len(watch_pkgs)} package actions)

Every normal-profile target is uninstalled. System-image packages use
`pm uninstall -k --user 0`: only the owner-user registration is removed, while the
read-only APK and app data remain available to `pm install-existing`. For `/data` apps,
uninstalling the only user removes the APK and app data; reinstall those from Galaxy Store
or Play Store. Pass `--disable-preloads` if you want `/data` targets disabled and preserved
instead.

Every tier deliberately keeps:

* Samsung Health, Google Health Services, Samsung Health Monitor, sensors and sleep tracking
* the dialer, in-call UI, contacts, call continuity and IMS services
* Google Messages (aggressive may remove only the duplicate Samsung Messages companion)
* emergency/SOS, Find My Watch and location services
* NFC infrastructure, OTA updates, phone pairing and notification transport
* Google Play Store and Galaxy Store (`com.sec.android.app.samsungapps`), both hard-protected
* System UI, Wear Services, tiles, complications, keyboards and all core stock watch faces

Balanced removes Samsung Pay while retaining Google Wallet. Aggressive removes both wallet
clients but keeps NFC itself. Aggressive also uninstalls the promotional Samsung Global
Goals face companions listed in tier 3; the watch-face runtime and Samsung's normal face
packages are hard-protected.

`com.sec.android.diagmonagent` is also retained. Some Samsung firmware repeatedly tries to
restart it after removal, which can cause a crash loop and *increase* battery drain.

## Tier 1 - light ({len(watch_tiers[1])} actions)

Retail-demo, certification and factory-only components, plus Device Quality Agent telemetry.

{watch_table(watch_tiers[1])}

## Tier 2 - balanced ({len(watch_tiers[1]) + len(watch_tiers[2])} actions total)

Adds Bixby, Samsung Pay, Samsung Customization Service, self-diagnostics and enterprise provisioning.
Do not use this tier on an organisation-managed watch.

{watch_table(watch_tiers[2])}

## Tier 3 - aggressive ({len(watch_pkgs)} actions total)

Adds Google Assistant/Gemini, Google Wallet, optional user-facing apps and duplicate
Samsung apps. Calling, Google Messages and all health features remain intact. Read each
row and use `--dry-run` before applying it.

{watch_table(watch_tiers[3])}

## Extras - `--extras` only ({len(watch_extras)} actions)

These stop OTA update checks/downloads and are intentionally outside every normal profile.

{watch_table(watch_extras)}

## Watch-safe settings

The 90 Hz refresh-rate and Samsung CPU-performance settings used on the tablet are not valid
for the Watch6's fixed 60 Hz panel and are never loaded. Only these settings are applied:

| Tier | Setting | Value | Why |
|---|---|---|---|
""" + "\n".join(
        f"| {tier} | `{ns}.{key}` | `{value}` | {note} |"
        for tier, ns, key, value, note in watch_settings
    ) + """

## Wireless ADB

1. On the watch, enable Developer options by tapping **Settings → About watch → Software
   information → Software version** seven times.
2. Enable **ADB debugging** and **Wireless debugging**.
3. Open **Wireless debugging → Pair new device** and keep that screen open.
4. Pair using the temporary pairing port and six-digit code:

   ```bash
   adb pair WATCH_IP:PAIRING_PORT PAIRING_CODE
   ```

5. If `adb devices` does not discover it automatically, use the separate IP/port shown on
   the main Wireless debugging screen: `adb connect WATCH_IP:DEBUG_PORT`.
6. Preview and apply normally:

   ```bash
   ./run.sh aggressive --dry-run
   ./run.sh aggressive
   ```

Turn off ADB debugging and Wireless debugging afterward; leaving them enabled costs battery.

## Before / after snapshots

A real run writes `before.txt` and `after.txt` beside its package/settings manifests and
prints installed/enabled package counts, available RAM, free `/data` space and battery level.
RAM immediately after package changes is only indicative; reboot before taking a stable
comparison.
"""

    WATCH_OUT.write_text(watch_doc)
    print(
        f"wrote {WATCH_OUT.relative_to(ROOT)} "
        f"({len(watch_pkgs)} packages, {len(watch_extras)} extras, {len(watch_settings)} settings)"
    )


if __name__ == "__main__":
    main()
