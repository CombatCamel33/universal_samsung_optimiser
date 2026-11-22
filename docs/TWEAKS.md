# Every tweak, explained

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

## Tier 1 - light (30 packages)

Safe for anyone. Telemetry, diagnostics, factory test tools, AR toys and preloads.

| Package | Category | What it is / why it can go |
|---|---|---|
| `com.samsung.android.rubin.app` | Samsung | Customization Service - usage analytics, ad personalisation, "recommended content" |
| `com.sec.android.diagmonagent` | Samsung | Diagnostics/telemetry agent that phones home with device health data |
| `com.samsung.android.dqagent` | Samsung | Second Samsung telemetry agent (DQ = data quality), runs at boot |
| `com.samsung.android.knox.analytics.uploader` | Samsung | Uploads Knox analytics events |
| `com.samsung.android.sdm.config` | Samsung | Silently downloads carrier/service configuration bundles |
| `com.samsung.android.svcagent` | Samsung | Remote-support agent for Samsung service centres |
| `com.google.android.feedback` | Google | Google feedback / crash-reporting uploader |
| `com.google.mainline.telemetry` | Google | Mainline (system module) telemetry uploader |
| `com.google.android.gms.location.history` | Google | Location History background service |
| `com.google.android.partnersetup` | Google | Installs preload/partner apps on first boot and after updates |
| `com.google.android.printservice.recommendation` | Google | Suggests printer plugins you never asked for |
| `com.google.android.apps.carrier.carrierwifi` | Google | Carrier Wi-Fi auto-connect (meaningless on a Wi-Fi-only tablet) |
| `com.samsung.android.bbc.bbcagent` | Samsung | Background big-data collector (battery/app usage analytics) |
| `com.samsung.android.aremoji` | Samsung | AR Emoji sticker engine |
| `com.samsung.android.aremojieditor` | Samsung | AR Emoji editor |
| `com.samsung.android.app.dofviewer` | Samsung | AR Doodle viewer |
| `com.samsung.android.app.camera.sticker.facearavatar.preload` | Samsung | Preloaded camera AR-sticker pack |
| `com.sec.android.mimage.avatarstickers` | Samsung | Avatar sticker pack |
| `com.samsung.android.stickercenter` | Samsung | Sticker store for camera/gallery |
| `com.gameloft.android.ANMP.GloftA9HM` | Gaming | Preloaded Asphalt 9 demo (installs itself again after factory reset) |
| `com.hiya.star` | Carrier | Hiya caller-ID / spam service (no SIM in this tablet) |
| `com.android.egg` | AOSP | Android Easter-egg app |
| `com.sec.android.app.hwmoduletest` | Factory | Hidden hardware test app used by service centres |
| `com.sec.android.app.servicemodeapp` | Factory | Hidden service-mode / diagnostics menu |
| `com.sec.factory.camera` | Factory | Factory camera test harness |
| `com.sec.android.app.wlantest` | Factory | Wi-Fi factory test tool |
| `com.android.devicediagnostics` | AOSP | "Device diagnostics" hidden test UI |
| `com.android.traceur` | AOSP | System tracing developer tool |
| `com.android.cts.ctsshim` | AOSP | CTS test shim, only used by certification test suites |
| `com.android.cts.priv.ctsshim` | AOSP | Privileged CTS test shim, only used by certification test suites |

## Tier 2 - balanced (110 packages total)

Adds features that most people never open: Bixby, Samsung context/customisation
services, Edge panels, Modes & Routines, Digital Wellbeing, gaming services,
ARCore, Link-to-Windows and the Samsung TTS language packs (which are large).

| Package | Category | What it is / why it can go |
|---|---|---|
| `com.samsung.android.bixby.agent` | Samsung | Bixby voice assistant |
| `com.samsung.android.bixby.wakeup` | Samsung | Always-listening "Hi Bixby" wake word service |
| `com.samsung.android.bixbyvision.framework` | Samsung | Bixby Vision framework |
| `com.samsung.android.visionintelligence` | Samsung | Bixby Vision / on-device image recognition engine |
| `com.samsung.android.app.vex.scanner` | Samsung | Bixby Vision scanner UI |
| `com.samsung.android.service.airviewdictionary` | Samsung | Bixby Vision dictionary lookup |
| `com.samsung.android.scs` | Samsung | Samsung Context Service - feeds Bixby/ST with usage context |
| `com.samsung.android.mapsagent` | Samsung | Bixby/Places map agent |
| `com.samsung.android.smartsuggestions` | Samsung | Smart suggestions on the home screen |
| `com.samsung.android.app.routines` | Samsung | Modes & Routines automation engine |
| `com.samsung.android.forest` | Samsung | Digital Wellbeing (app timers, screen-time tracking) |
| `com.samsung.android.app.parentalcare` | Samsung | Parental-care helper service |
| `com.samsung.android.appseparation` | Samsung | App-separation service used by Dual Messenger / app cloning |
| `com.samsung.android.messageguardsync` | Samsung | Message-guard sync (telephony companion service) |
| `com.samsung.android.sm.devicesecurity` | Samsung | McAfee-powered "Device security" scanner (~250 MB RAM while running) |
| `com.samsung.android.kgclient` | Samsung | Knox Guard client (carrier/enterprise device locking) |
| `com.samsung.android.mdm` | Samsung | Samsung MDM agent for enterprise management |
| `com.samsung.android.da.daagent` | Samsung | Device-admin agent used by Knox/MDM |
| `com.sec.enterprise.knox.cloudmdm.smdms` | Samsung | Knox cloud MDM enrolment service |
| `com.skms.android.agent` | Samsung | Knox MDM agent stub |
| `com.samsung.android.cidmanager` | Samsung | Carrier-ID manager (rewrites CSC settings on SIM events) |
| `com.samsung.android.app.omcagent` | Samsung | OMC/CSC agent - only needed during first-time carrier setup |
| `com.samsung.android.scpm` | Samsung | Samsung Configuration & Policy Manager (carrier policy pulls) |
| `com.samsung.android.shortcutbackupservice` | Samsung | Backs up home-screen shortcuts to Samsung Cloud |
| `com.samsung.android.brightnessbackupservice` | Samsung | Persists auto-brightness learning data |
| `com.samsung.android.privacydashboard` | Samsung | Privacy dashboard UI (the permission-usage screen) |
| `com.samsung.android.app.sharelive` | Samsung | Private Share (blockchain file sharing) |
| `com.samsung.android.themecenter` | Samsung | Galaxy Themes store |
| `com.samsung.android.wallpaper.live` | Samsung | Live wallpaper engine |
| `com.samsung.android.dynamiclock` | Samsung | Dynamic Lock Screen wallpaper rotation |
| `com.samsung.android.widget.pictureframe` | Samsung | Picture-frame widget |
| `com.samsung.android.app.clipboardedge` | Samsung | Edge panel: clipboard |
| `com.samsung.android.app.taskedge` | Samsung | Edge panel: tasks |
| `com.samsung.android.service.peoplestripe` | Samsung | Edge panel: people |
| `com.samsung.android.app.watchmanagerstub` | Samsung | Galaxy Wearable stub that nags you to install the watch app |
| `com.samsung.android.beaconmanager` | Samsung | SmartThings beacon scanner |
| `com.samsung.android.aware.service` | Samsung | Nearby-device awareness service for SmartThings |
| `com.samsung.android.easysetup` | Samsung | Easy Setup / Quick Share handshake service |
| `com.samsung.android.net.wifi.wifiguider` | Samsung | Wi-Fi "guider" - public Wi-Fi suggestions and captive-portal ads |
| `com.samsung.android.smartswitchassistant` | Samsung | Smart Switch helper service |
| `com.sec.android.easyMover` | Samsung | Smart Switch (phone-to-tablet migration wizard) |
| `com.sec.android.easyMover.Agent` | Samsung | Smart Switch background agent |
| `com.samsung.SMT.lang_de_de_f00` | Samsung | TTS language pack: German |
| `com.samsung.SMT.lang_en_gb_f00` | Samsung | TTS language pack: English (UK) - duplicate voice |
| `com.samsung.SMT.lang_en_gb_l02` | Samsung | TTS language pack: English (UK) - duplicate voice |
| `com.samsung.SMT.lang_en_us_l03` | Samsung | TTS language pack: English (US) - duplicate voice |
| `com.samsung.SMT.lang_es_es_f00` | Samsung | TTS language pack: Spanish (Spain) |
| `com.samsung.SMT.lang_es_mx_f00` | Samsung | TTS language pack: Spanish (Mexico) |
| `com.samsung.SMT.lang_es_us_f00` | Samsung | TTS language pack: Spanish (US) |
| `com.samsung.SMT.lang_fr_fr_f00` | Samsung | TTS language pack: French |
| `com.samsung.SMT.lang_hi_in_f00` | Samsung | TTS language pack: Hindi |
| `com.samsung.SMT.lang_it_it_f00` | Samsung | TTS language pack: Italian |
| `com.samsung.SMT.lang_pl_pl_f00` | Samsung | TTS language pack: Polish |
| `com.samsung.SMT.lang_pt_br_f00` | Samsung | TTS language pack: Portuguese (Brazil) |
| `com.samsung.SMT.lang_ru_ru_f00` | Samsung | TTS language pack: Russian |
| `com.samsung.SMT.lang_th_th_f00` | Samsung | TTS language pack: Thai |
| `com.samsung.SMT.lang_vi_vn_f00` | Samsung | TTS language pack: Vietnamese |
| `com.samsung.SMT.lang_zh_cn_l02` | Samsung | TTS language pack: Chinese (Simplified) |
| `com.samsung.SMT.lang_zh_hk_f00` | Samsung | TTS language pack: Chinese (Hong Kong) |
| `com.samsung.SMT.lang_zh_tw_f00` | Samsung | TTS language pack: Chinese (Traditional) |
| `com.google.ar.core` | Google | ARCore runtime - only needed by AR apps/games |
| `com.google.android.federatedcompute` | Google | Federated-learning job scheduler |
| `com.google.android.ondevicepersonalization.services` | Google | On-device ad/personalisation service |
| `com.google.android.apps.restore` | Google | Restore-from-backup helper used during setup |
| `com.google.android.gms.supervision` | Google | Family Link supervision service |
| `com.google.android.healthconnect.controller` | Google | Health Connect settings UI |
| `com.google.android.health.connect.backuprestore` | Google | Health Connect cloud backup |
| `com.microsoft.appmanager` | Microsoft | "Link to Windows" bridge (useless with a Mac/Linux desktop) |
| `com.android.dreams.basic` | AOSP | Basic screensaver |
| `com.android.dreams.phototable` | AOSP | Photo-table screensaver |
| `com.android.wallpaper.livepicker` | AOSP | Live-wallpaper picker |
| `com.android.bookmarkprovider` | AOSP | Legacy browser bookmark provider |
| `com.android.providers.partnerbookmarks` | AOSP | Preloaded partner bookmarks |
| `com.android.carrierdefaultapp` | AOSP | Carrier redirect app for data-cap errors |
| `com.android.hotspot2.osulogin` | AOSP | Hotspot 2.0 online sign-up |
| `com.android.bluetoothmidiservice` | AOSP | Bluetooth MIDI service |
| `com.google.android.apps.turbo` | Google | Device Health Services - battery/device-health predictions |
| `com.samsung.android.game.gos` | Samsung | Game Optimizing Service - throttles CPU/GPU while gaming |
| `com.samsung.android.game.gametools` | Samsung | Game Launcher / in-game overlay tools |
| `com.samsung.gpuwatchapp` | Samsung | GPU watchdog used by Game Launcher |

## Tier 3 - aggressive (159 packages total)

Adds full apps you can replace with something better, plus the telephony stack
(this tablet has no SIM slot). Read the notes before applying - a few of these
are things people genuinely use.

| Package | Category | What it is / why it can go |
|---|---|---|
| `com.sec.android.app.sbrowser` | Samsung | Samsung Internet browser (Brave is installed) |
| `com.android.chrome` | Google | Chrome (Brave is installed) |
| `com.sec.android.app.chromecustomizations` | Google | Chrome-only customisation overlay (useless once Chrome is gone) |
| `com.google.android.youtube` | Google | YouTube app (ReVanced/Morphe YouTube is installed instead) |
| `com.google.android.apps.photos` | Google | Google Photos |
| `com.google.android.gm` | Google | Gmail |
| `com.google.android.apps.maps` | Google | Google Maps |
| `com.google.android.apps.messaging` | Google | Google Messages (no SIM in this tablet) |
| `com.google.android.apps.tachyon` | Google | Google Meet (Zoom/Teams are installed) |
| `com.google.android.apps.bard` | Google | Google Gemini |
| `com.google.android.googlequicksearchbox` | Google | Google app / Discover feed / "Hey Google" (~330 MB RAM while running) |
| `com.google.android.apps.accessibility.voiceaccess` | Google | Voice Access accessibility service (only if you don't use voice control) |
| `com.android.bips` | AOSP | Built-in print service |
| `com.microsoft.office.outlook` | Microsoft | Outlook |
| `com.microsoft.office.word` | Microsoft | Word |
| `com.microsoft.office.excel` | Microsoft | Excel |
| `com.microsoft.office.powerpoint` | Microsoft | PowerPoint |
| `com.microsoft.office.onenote` | Microsoft | OneNote |
| `com.microsoft.skydrive` | Microsoft | OneDrive |
| `com.microsoft.teams` | Microsoft | Microsoft Teams |
| `com.samsung.android.app.reminder` | Samsung | Samsung Reminder |
| `com.samsung.android.app.notes` | Samsung | Samsung Notes (remove only if you don't use it - it is your heaviest app) |
| `com.samsung.android.kidsinstaller` | Samsung | Samsung Kids |
| `com.samsung.android.scloud` | Samsung | Samsung Cloud sync/backup |
| `com.samsung.android.mobileservice` | Samsung | Samsung account social/backup plumbing |
| `com.samsung.android.samsungpass` | Samsung | Samsung Pass password vault |
| `com.samsung.android.samsungpassautofill` | Samsung | Samsung Pass autofill |
| `com.samsung.android.authfw` | Samsung | Samsung Pass authentication framework |
| `com.samsung.android.photoremasterservice` | Samsung | Galaxy Enhance-X AI photo remaster engine |
| `com.samsung.android.visual.cloudcore` | Samsung | Cloud AI vision backend |
| `com.samsung.android.homemode` | Samsung | SmartThings Home Mode automation |
| `com.samsung.android.service.stplatform` | Samsung | SmartThings platform service |
| `com.samsung.android.service.tagservice` | Samsung | SmartThings tag/location service |
| `com.samsung.android.app.find` | Samsung | SmartThings Find (device tracker) |
| `com.samsung.android.dialer` | Samsung | Phone dialer |
| `com.samsung.android.incallui` | Samsung | In-call UI |
| `com.samsung.android.app.telephonyui` | Samsung | Telephony settings UI fragments |
| `com.samsung.android.callassistant` | Samsung | Call assistant / spam screening |
| `com.samsung.android.callbgprovider` | Samsung | Call background provider |
| `com.samsung.android.smartcallprovider` | Samsung | Smart Call (caller ID database) |
| `com.samsung.android.emergency` | Samsung | Emergency SOS / medical info service |
| `com.sec.android.emergencylauncher` | Samsung | Emergency launcher |
| `com.samsung.android.vtcamerasettings` | Samsung | Video-call camera settings (IMS) |
| `com.sec.imslogger` | Samsung | IMS logging service |
| `com.sec.sve` | Samsung | Samsung VoLTE engine |
| `com.samsung.android.mdecservice` | Samsung | MDE (mobile device experience) call continuity |
| `com.android.calllogbackup` | AOSP | Call-log backup provider |
| `com.android.mms.service` | AOSP | MMS service |
| `com.android.simappdialog` | AOSP | SIM application dialog |

## Extras - `--extras` only (17 packages)

**Not** part of any profile. These break Secure Folder, OTA security updates
and the Samsung account. Only use them if you understand that.

| Package | Category | What it is / why it can go |
|---|---|---|
| `com.samsung.knox.securefolder` | Knox | Secure Folder app itself |
| `com.samsung.android.knox.containercore` | Knox | Knox container engine - Secure Folder and Work Profile depend on it |
| `com.samsung.android.container` | Knox | Knox container support |
| `com.samsung.android.knox.sandbox` | Knox | Knox sandbox runtime |
| `com.samsung.android.knox.er` | Knox | Knox enterprise repository |
| `com.samsung.android.knox.kfbp` | Knox | Knox file-based protection |
| `com.samsung.android.knox.knnr` | Knox | Knox network name resolution |
| `com.samsung.android.knox.kpecore` | Knox | Knox policy engine core |
| `com.samsung.android.knox.pushmanager` | Knox | Knox push notifications |
| `com.samsung.android.knox.zt.framework` | Knox | Knox Zero Trust framework |
| `com.samsung.android.knox.app.networkfilter` | Knox | Knox per-app network filter |
| `com.samsung.android.knox.attestation` | Knox | Knox hardware attestation |
| `com.knox.vpn.proxyhandler` | Knox | Knox VPN proxy handler |
| `com.samsung.android.rampart` | Knox | Auto Blocker (side-loading protection) |
| `com.sec.android.soagent` | Samsung | Software update agent - removing this stops OTA security updates |
| `com.wssyncmldm` | Samsung | Software update download manager - removing this stops OTA updates |
| `com.osp.app.signin` | Samsung | Samsung account sign-in - breaks Galaxy Store, Find My Mobile, Secure Folder |

## System settings

Applied with `settings put <namespace> <key> <value>` and restored from
`backups/original-settings.tsv`.

| Tier | Setting | Value | Why |
|---|---|---|---|
| 1 | `global.window_animation_scale` | `0.5` | Halve the stock 1.0x window-open animation duration |
| 1 | `global.transition_animation_scale` | `0.5` | Halve the stock 1.0x transition animation duration |
| 1 | `global.animator_duration_scale` | `0.5` | Halve the stock 1.0x animator duration - the biggest "feels faster" win |
| 1 | `global.cached_apps_freezer` | `enabled` | Freeze cached background apps instead of keeping them in RAM |
| 1 | `system.peak_refresh_rate` | `90` | Never cap the 90 Hz panel |
| 2 | `global.sem_enhanced_cpu_responsiveness` | `1` | Samsung "Processing speed: High" - keeps the CPU scheduler in performance mode |
| 2 | `global.wifi_scan_always_enabled` | `0` | Stop background Wi-Fi scanning when Wi-Fi is off (battery + fewer wakeups) |
| 2 | `global.ble_scan_always_enabled` | `0` | Stop background Bluetooth LE scanning when Bluetooth is off |
| 2 | `system.min_refresh_rate` | `60` | Never drop below 60 Hz, so scrolling stays smooth (no 30 Hz idle steps) |
| 3 | `system.min_refresh_rate` | `90` | Lock the panel at 90 Hz at all times - smoothest, costs some battery |

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
