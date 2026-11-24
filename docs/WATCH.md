# Galaxy Watch / Wear OS support

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

* **light** = tier 1 (14 package actions)
* **balanced** = tiers 1-2 (23 package actions)
* **aggressive** = tiers 1-3 (44 package actions)

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

## Tier 1 - light (14 actions)

Retail-demo, certification and factory-only components, plus Device Quality Agent telemetry.

| Package | Action | Category | What it is / why it can go |
|---|---|---|---|
| `com.google.android.apps.wearable.retailattractloop` | `uninstall` | Wear OS | Retail-store demo loop; has no purpose on a personally owned watch |
| `com.android.cts.ctsshim` | `uninstall` | AOSP | Compatibility Test Suite shim used only during device certification |
| `com.android.cts.priv.ctsshim` | `uninstall` | AOSP | Privileged Compatibility Test Suite shim used only during certification |
| `com.sec.android.app.hwmoduletest` | `uninstall` | Factory | Hidden Samsung hardware-module test interface |
| `com.sec.android.app.servicemodeapp` | `uninstall` | Factory | Hidden service-mode application used by repair technicians |
| `com.sec.android.app.wlantest` | `uninstall` | Factory | Factory Wi-Fi test harness |
| `com.sem.factoryapp` | `uninstall` | Factory | Samsung manufacturing test application |
| `com.sec.android.app.factorykeystring` | `uninstall` | Factory | Factory key-code and engineering-menu handler |
| `com.sec.facatfunction` | `uninstall` | Factory | Factory AT-command handler; not needed during normal use |
| `com.sec.hiddenmenu` | `uninstall` | Factory | Hidden factory/engineering menu |
| `com.sec.android.app.felicatest` | `uninstall` | Factory | Factory FeliCa/NFC test application |
| `com.sec.nfc.felicalocktest` | `uninstall` | Factory | Factory FeliCa lock test application |
| `com.samsung.android.aircommandmanager` | `uninstall` | Factory | Factory Air Command stub; Galaxy Watches have no S Pen |
| `com.samsung.android.dqagent` | `uninstall` | Samsung | Device Quality Agent telemetry and diagnostic upload jobs |

## Tier 2 - balanced (23 actions total)

Adds Bixby, Samsung Pay, Samsung Customization Service, self-diagnostics and enterprise provisioning.
Do not use this tier on an organisation-managed watch.

| Package | Action | Category | What it is / why it can go |
|---|---|---|---|
| `com.samsung.android.bixby.agent` | `uninstall` | Samsung | Bixby assistant; Google Assistant remains installed |
| `com.samsung.android.bixby.wakeup` | `uninstall` | Samsung | Bixby wake-word and hardware-key listener |
| `com.samsung.android.intellivoiceservice` | `uninstall` | Samsung | Samsung/Bixby intelligent voice service |
| `com.samsung.android.samsungpay.gear` | `uninstall` | Samsung | Samsung Pay watch client; balanced keeps Google Wallet as the only wallet |
| `com.samsung.android.watch.runestone.app` | `uninstall` | Samsung | Customization Service; collects usage context for personalised recommendations |
| `com.samsung.android.watch.selfdiagnostics` | `uninstall` | Samsung | User-facing Samsung Members self-diagnostics tool |
| `com.google.android.partnersetup` | `uninstall` | Google | Partner preload provisioning used during initial setup |
| `com.android.managedprovisioning` | `uninstall` | AOSP | Work/enterprise device provisioning; keep it if this watch is organisation-managed |
| `com.sds.emm.cloud.knox.samsung` | `uninstall` | Knox | Knox Manage enterprise enrolment client; keep it on a managed work watch |

## Tier 3 - aggressive (44 actions total)

Adds Google Assistant/Gemini, Google Wallet, optional user-facing apps and duplicate
Samsung apps. Calling, Google Messages and all health features remain intact. Read each
row and use `--dry-run` before applying it.

| Package | Action | Category | What it is / why it can go |
|---|---|---|---|
| `com.google.android.wearable.assistant` | `uninstall` | Google | Google Assistant / Gemini for Wear OS |
| `com.google.android.apps.walletnfcrel` | `uninstall` | Google | Google Wallet; NFC infrastructure remains installed |
| `com.samsung.sree` | `uninstall` | Samsung | Samsung Global Goals application |
| `com.samsung.sree.spin` | `uninstall` | Samsung | Samsung Global Goals Spin watch face companion |
| `com.samsung.sree.digital` | `uninstall` | Samsung | Samsung Global Goals Digital watch face companion |
| `com.samsung.sree.classic` | `uninstall` | Samsung | Samsung Global Goals Classic watch face companion |
| `com.samsung.sree.countdown` | `uninstall` | Samsung | Samsung Global Goals Countdown watch face companion |
| `com.microsoft.office.outlook` | `uninstall` | Microsoft | Outlook watch client; remove only if you do not use Outlook notifications/mail |
| `com.sec.android.app.sbrowser` | `uninstall` | Samsung | Samsung Internet browser for Wear OS |
| `com.samsung.android.oneconnect` | `uninstall` | Samsung | SmartThings watch application and device controls |
| `com.samsung.android.watch.budscontroller` | `uninstall` | Samsung | Galaxy Buds controller; keep it if you control Buds from the watch |
| `com.samsung.android.app.reminder` | `uninstall` | Samsung | Samsung Reminder watch application |
| `com.samsung.android.wear.voicerecorder` | `uninstall` | Samsung | Voice Recorder watch application |
| `com.samsung.android.wearable.music` | `uninstall` | Samsung | Samsung Music player on the watch |
| `com.samsung.android.wear.musictransfer` | `uninstall` | Samsung | Phone-to-watch music transfer service |
| `com.samsung.android.video.wearable` | `uninstall` | Samsung | Samsung wearable video player |
| `com.samsung.android.gallery.watch` | `uninstall` | Samsung | Gallery viewer on the watch |
| `com.samsung.android.watch.cameracontroller` | `uninstall` | Samsung | Remote camera viewfinder/controller for Galaxy phones |
| `com.samsung.android.watch.worldclock` | `uninstall` | Samsung | World Clock watch application |
| `com.samsung.android.watch.compass` | `uninstall` | Samsung | Compass watch application |
| `com.samsung.android.messaging` | `uninstall` | Samsung | Samsung Messages companion; Google Messages remains installed |

## Extras - `--extras` only (2 actions)

These stop OTA update checks/downloads and are intentionally outside every normal profile.

| Package | Action | Category | What it is / why it can go |
|---|---|---|---|
| `com.sec.android.soagent` | `disable` | Samsung | Software-update metadata agent; disabling it stops normal OTA update checks |
| `com.wssyncmldm` | `disable` | Samsung | Software-update download/install manager; disabling it stops normal OTA updates |

## Watch-safe settings

Phone/tablet refresh-rate and Samsung CPU-performance settings are not loaded on the
Watch6's fixed 60 Hz panel. Only these watch settings are applied:

| Tier | Setting | Value | Why |
|---|---|---|---|
| 1 | `global.window_animation_scale` | `0.5` | Halve window-open animation duration without disabling animations completely |
| 1 | `global.transition_animation_scale` | `0.5` | Halve screen and app transition animation duration |
| 1 | `global.animator_duration_scale` | `0.5` | Halve in-app animator duration for a more responsive interface |
| 1 | `global.cached_apps_freezer` | `enabled` | Freeze cached background apps so they cannot consume CPU while idle |
| 1 | `system.accessibility_reduce_transparency` | `1` | Enable Reduce transparency and blur to lower UI compositing overhead |

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
