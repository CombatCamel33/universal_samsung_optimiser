#!/usr/bin/env python3
"""Regenerate docs/TWEAKS.md from profiles/*.tsv.

Usage: python3 tools/generate-docs.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROFILES = ROOT / "profiles"
OUT = ROOT / "docs" / "TWEAKS.md"


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
**disabled** with `pm disable-user --user N` rather than uninstalled, because
uninstalling them would delete the APK for good. Disabled packages are hidden, cannot
run and cannot start at boot - and `pm enable` brings them back instantly.

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
transitions and in-app motion. Samsung shipped this tablet at **1.5x**, which is why
it feels slow next to a Pixel. `0.5` is the sweet spot: visibly faster, still smooth.
`0` makes things feel broken, so the script never uses it.

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


if __name__ == "__main__":
    main()
