#!/usr/bin/env bash
#
#  Universal Android Optimiser - macOS / Linux driver
#  ---------------------------------------------------------------
#  Debloats and tunes exactly matched Android phones, tablets and watches
#  over ADB. Every change is recorded and reversible.
#
#  Usage:  ./run.sh [light|balanced|aggressive] [options]
#  Help:   ./run.sh --help
#
#  Written for bash 3.2 (the version macOS ships). No bash 4 features.
#
set -u

VERSION="1.4.0"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILES="$ROOT/profiles"
BACKUP_ROOT="$ROOT/backups"
BACKUPS="$BACKUP_ROOT"
PROFILE_DIR="$PROFILES"
PACKAGES_FILE="$PROFILE_DIR/packages.tsv"
SETTINGS_FILE="$PROFILE_DIR/settings.tsv"
EXTRAS_FILE="$PROFILE_DIR/extras.tsv"
ADB="${ADB:-}"

# ------------------------------------------------------------------ output helpers
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET="$(printf '\033[0m')"; C_BOLD="$(printf '\033[1m')"
  C_DIM="$(printf '\033[2m')";   C_RED="$(printf '\033[31m')"
  C_GREEN="$(printf '\033[32m')"; C_YELLOW="$(printf '\033[33m')"
  C_BLUE="$(printf '\033[34m')";  C_CYAN="$(printf '\033[36m')"
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

say()  { printf '%s\n' "$*"; }
info() { printf '%s\n' "${C_CYAN}::${C_RESET} $*"; }
ok()   { printf '%s\n' "${C_GREEN}  ok${C_RESET} $*"; }
warn() { printf '%s\n' "${C_YELLOW}  !!${C_RESET} $*"; }
fail() { printf '%s\n' "${C_RED}  xx${C_RESET} $*"; }
head1(){ printf '\n%s\n' "${C_BOLD}$*${C_RESET}"; }
dim()  { printf '%s\n' "${C_DIM}$*${C_RESET}"; }

die() { fail "$*"; exit 1; }

# ------------------------------------------------------------------ CLI state
PROFILE=""
DRY_RUN=0
ASSUME_YES=0
WANT_EXTRAS=0
DISABLE_PRELOADS=0
WANT_TRIM=0
WANT_DEXOPT=0
WANT_REBOOT=0
APPLY_SETTINGS=1
MODE="apply"          # apply | restore | restore-all | list | report | compare
RESTORE_DIR=""
COMPARE_DIR=""
USER_LIST=""
SERIAL=""
DEVICE_CLASS="tablet"
DEVICE_LABEL="Galaxy tablet / Android"
CHARACTERISTICS=""
HARDWARE_ID=""
WATCH_FEATURE="false"
MANUFACTURER=""
MARKET_NAME=""
BUILD=""
SECURITY_PATCH=""
SKIN=""
DEVICE_PROFILE=""
DEVICE_PROFILE_NAME=""
DEVICE_PACKAGE_FILE=""
MAX_REFRESH_RATE=""

# App groups that are never removed. Works on tablets and phones alike.
KEEP_DEFAULT="teams,samsung-internet,office,gmail,messages,phoning"
KEEP_GROUPS="$KEEP_DEFAULT"
KEEP_EXPLICIT=0

usage() {
  cat <<EOF
${C_BOLD}Universal Android Optimiser${C_RESET} v$VERSION

  ./run.sh <profile> [options]      apply a profile
  ./run.sh --restore [dir]          undo every change (or restore one backup dir)
  ./run.sh --restore-all            reinstall every package in every profile
  ./run.sh --compare [dir]          show the before/after statistics of a run

${C_BOLD}Profiles${C_RESET}
  light         telemetry, diagnostics, ads and factory leftovers
  balanced      + optional OEM/Google background features
  aggressive    + replaceable user-facing apps (defaults/phone kept)

  Galaxy Watch and exact Redmi 10 profiles are detected automatically.
  Run --list to see base, exact-device and watch profiles.

${C_BOLD}Options${C_RESET}
  --profile <name>   same as passing the profile as the first argument
  --dry-run          show what would happen, change nothing
  --user <id>        only touch this Android user (repeatable)
  --all-users        every real user profile (default: all except Secure Folder)
  --extras           device-specific high-risk removals (read --list first)
  --disable-preloads hide /data-installed preloads instead of deleting them
                     (Office, Notes, Samsung Internet... stay on disk, restorable)
  --keep <groups>    keep these app groups installed (default: all of them)
                     groups: teams, samsung-internet, office, gmail, messages, phoning
                     repeatable, or comma-separated; "none" disables keeping
  --no-keep          disable named keep groups; hard/default-app safety still wins
  --list-keep        print the keep groups and their packages
  --trim             clear app caches (pm trim-caches)
  --dexopt           run a background dexopt job now (slow, optimises app start-up)
  --reboot           reboot when finished
  --no-settings      remove/disable packages only; do not change Android settings
  --yes, -y          do not ask for confirmation
  --list             print the package lists
  --report           print device info, RAM and storage
  --serial <id>      target a specific device when several are attached
  --compare [dir]    compare the statistics captured before/after a run
                     (default: the most recent backup)
  --help, -h         this text
  --version          print version

${C_BOLD}Environment${C_RESET}
  ADB=/path/to/adb   use a specific adb binary
EOF
}

# ------------------------------------------------------------------ adb discovery
find_adb() {
  if [ -n "$ADB" ] && [ -x "$ADB" ]; then return 0; fi
  if command -v adb >/dev/null 2>&1; then ADB="$(command -v adb)"; return 0; fi
  for c in \
    "${ANDROID_HOME:-}/platform-tools/adb" \
    "${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
    "$HOME/Library/Android/sdk/platform-tools/adb" \
    "$HOME/Android/Sdk/platform-tools/adb" \
    "$HOME/android-sdk/platform-tools/adb" \
    "$HOME/Downloads/platform-tools/adb" \
    /opt/homebrew/bin/adb \
    /usr/local/bin/adb \
    /usr/bin/adb
  do
    [ -n "$c" ] && [ -x "$c" ] && { ADB="$c"; return 0; }
  done
  return 1
}

oneui_version() { # 80500 -> 8.5, 60100 -> 6.1, 70000 -> 7.0
  local v="$1"
  case "$v" in
    ''|*[!0-9]*) printf '%s' "$v"; return ;;
  esac
  if [ "${#v}" -ge 3 ]; then
    printf '%s.%d' "$(printf '%s' "$v" | cut -c1)" "$(printf '%s' "$v" | cut -c2-3 | sed 's/^0*//; s/^$/0/')"
  else
    printf '%s' "$v"
  fi
}

miui_version() {
  case "$1" in V[0-9][0-9][0-9]) printf '%s.%s' "$(printf '%s' "$1" | cut -c2-3)" "$(printf '%s' "$1" | cut -c4)" ;; *) printf '%s' "$1" ;; esac
}

adbs() { # adbs <shell args...>  -> runs adb shell, strips CR
  if [ -n "$SERIAL" ]; then
    "$ADB" -s "$SERIAL" shell "$@" </dev/null 2>/dev/null | tr -d '\r'
  else
    "$ADB" shell "$@" </dev/null 2>/dev/null | tr -d '\r'
  fi
}

adb_raw() {
  if [ -n "$SERIAL" ]; then "$ADB" -s "$SERIAL" "$@" </dev/null; else "$ADB" "$@" </dev/null; fi
}

resolve_exact_device_profile() {
  local file="$PROFILES/devices.tsv" id maker device model name pkg
  DEVICE_PROFILE=""; DEVICE_PROFILE_NAME=""; DEVICE_PACKAGE_FILE=""
  [ "$DEVICE_CLASS" = "watch" ] && return 0
  [ -f "$file" ] || return 0
  while IFS='	' read -r id maker device model name pkg; do
    case "$id" in ''|'#'*) continue ;; esac
    if [ "$(printf '%s' "$maker" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$MANUFACTURER" | tr '[:upper:]' '[:lower:]')" ] &&
       [ "$(printf '%s' "$device" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$DEVICE" | tr '[:upper:]' '[:lower:]')" ] &&
       [ "$(printf '%s' "$model" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$MODEL" | tr '[:upper:]' '[:lower:]')" ]; then
      DEVICE_PROFILE="$id"; DEVICE_PROFILE_NAME="$name"
      [ -n "$pkg" ] && [ "$pkg" != "-" ] && DEVICE_PACKAGE_FILE="$PROFILES/$pkg"
      return 0
    fi
  done < "$file"
}

detect_max_refresh_rate() {
  local max fallback
  max="$(adbs "dumpsys display" | grep -Eo '(fps|refreshRate)=[0-9]+([.][0-9]+)?' | cut -d= -f2 |
    awk '$1 >= 30 && $1 <= 240 && $1 > max {max=$1} END {if(max>0) printf "%g",max}')"
  if [ -z "$max" ]; then fallback="$(adbs "settings get system peak_refresh_rate")"; case "$fallback" in ''|null|*[!0-9.]*) ;; *) max="$fallback" ;; esac; fi
  printf '%s' "$max"
}

configure_device_profile() {
  local safe_id
  DEVICE_CLASS="tablet"
  DEVICE_LABEL="Android phone / tablet"
  PROFILE_DIR="$PROFILES"
  safe_id="$(printf '%s' "$SERIAL" | tr -c 'A-Za-z0-9._-' '_')"
  [ -z "$safe_id" ] && safe_id="unknown-android"
  BACKUPS="$BACKUP_ROOT/device-$safe_id"

  case ",$CHARACTERISTICS,$WATCH_FEATURE," in
    *,watch,*|*,true,*)
      DEVICE_CLASS="watch"
      DEVICE_LABEL="Galaxy Watch / Wear OS"
      PROFILE_DIR="$PROFILES/watch"
      safe_id="$(printf '%s-%s' "$MODEL" "$HARDWARE_ID" | tr -c 'A-Za-z0-9._-' '_')"
      [ -z "$safe_id" ] && safe_id="unknown-watch"
      BACKUPS="$BACKUP_ROOT/watch-$safe_id"
      ;;
  esac

  PACKAGES_FILE="$PROFILE_DIR/packages.tsv"
  SETTINGS_FILE="$PROFILE_DIR/settings.tsv"
  EXTRAS_FILE="$PROFILE_DIR/extras.tsv"
  resolve_exact_device_profile
}

require_device() {
  find_adb || die "adb not found. Install Android platform-tools or set ADB=/path/to/adb"
  local out
  out="$(adb_raw devices | tr -d '\r' | awk 'NR>1 && $2=="device" {print $1}')"
  if [ -z "$out" ]; then
    fail "No authorised device found."
    say  "  1. Enable Developer options (Settings > About phone/tablet > Software information > tap Build number 7x)"
    say  "  2. Turn on USB debugging"
    say  "  3. Reconnect and accept the RSA prompt on the device"
    exit 1
  fi
  if [ -z "$SERIAL" ]; then
    SERIAL="$(printf '%s\n' "$out" | head -1)"
    if [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -gt 1 ]; then
      warn "Multiple devices attached - using $SERIAL (override with --serial)"
    fi
  fi
  adb_raw wait-for-device >/dev/null 2>&1
  MODEL="$(adbs getprop ro.product.model)"
  DEVICE="$(adbs getprop ro.product.device)"
  MANUFACTURER="$(adbs getprop ro.product.manufacturer)"
  MARKET_NAME="$(adbs getprop ro.product.marketname)"
  RELEASE="$(adbs getprop ro.build.version.release)"
  BUILD="$(adbs getprop ro.build.version.incremental)"
  SECURITY_PATCH="$(adbs getprop ro.build.version.security_patch)"
  CHARACTERISTICS="$(adbs getprop ro.build.characteristics)"
  HARDWARE_ID="$(adbs getprop ro.serialno)"
  WATCH_FEATURE="$(adbs "pm has-feature android.hardware.type.watch")"
  configure_device_profile
  ONUI="$(oneui_version "$(adbs getprop ro.build.version.oneui)")"
  MIUI="$(miui_version "$(adbs getprop ro.miui.ui.version.name)")"
  if [ -n "$ONUI" ]; then SKIN="One UI $ONUI"; elif [ -n "$MIUI" ]; then SKIN="MIUI $MIUI"; else SKIN=""; fi
  MAX_REFRESH_RATE="$(detect_max_refresh_rate)"
  local name skin_suffix hz_suffix
  name="${MARKET_NAME:-${DEVICE_PROFILE_NAME:-$MODEL}}"; skin_suffix=""; hz_suffix=""
  [ -n "$SKIN" ] && skin_suffix=" / $SKIN"; [ -n "$MAX_REFRESH_RATE" ] && hz_suffix=" / max $MAX_REFRESH_RATE Hz"
  info "Device: ${C_BOLD}${name}${C_RESET} [$MODEL] ($DEVICE) - Android ${RELEASE}${skin_suffix}${hz_suffix} [$DEVICE_LABEL]"
  [ -n "$DEVICE_PROFILE" ] && ok "matched device profile: $DEVICE_PROFILE"
}

# ------------------------------------------------------------------ users
list_real_users() { # prints "id<TAB>name"
  adbs "pm list users" | sed -n 's/.*UserInfo{\([0-9][0-9]*\):\([^:]*\):.*/\1	\2/p'
}

resolve_users() {
  if [ -n "$USER_LIST" ]; then
    printf '%s\n' "$USER_LIST"
    return
  fi
  list_real_users | while IFS='	' read -r id name; do
    case "$name" in
      *Secure*Folder*) continue ;;
    esac
    printf '%s\n' "$id"
  done
}

user_label() {
  local want="$1" id name
  list_real_users | while IFS='	' read -r id name; do
    if [ "$id" = "$want" ]; then printf '%s' "$name"; return; fi
  done
}

# ------------------------------------------------------------------ profiles
profile_tier() {
  case "$1" in
    light)      echo 1 ;;
    balanced)   echo 2 ;;
    aggressive) echo 3 ;;
    *)          return 1 ;;
  esac
}

# ------------------------------------------------------------------ keep groups
keep_group_names() {
  printf '%s\n' teams samsung-internet office gmail messages phoning
}

is_keep_group() {
  case "$1" in
    teams|samsung-internet|office|gmail|messages|phoning) return 0 ;;
  esac
  return 1
}

keep_words() { # normalise KEEP_GROUPS to a space-separated list
  printf '%s\n' "$KEEP_GROUPS" | tr ',' ' ' | tr -s ' ' '\n' | sed '/^$/d'
}

# keep_packages -> package names for every enabled group (from profiles/keep.tsv)
keep_packages() {
  local file="$PROFILES/keep.tsv" g
  [ -f "$file" ] || return 0
  for g in $(keep_words); do
    awk -F'\t' -v g="$g" '
      { sub(/\r$/, "") }
      /^[[:space:]]*#/ { next }
      NF >= 3 && $1 == g { print $2 }
    ' "$file"
  done | sort -u
}

# add_keep_arg <groups> - first explicit --keep replaces the defaults, later ones add
add_keep_arg() {
  local list tok
  if [ "$KEEP_EXPLICIT" -eq 0 ]; then
    KEEP_GROUPS=""
    KEEP_EXPLICIT=1
  fi
  list="$(printf '%s' "$1" | tr ',' ' ')"
  for tok in $list; do
    [ "$tok" = "none" ] && continue
    KEEP_GROUPS="${KEEP_GROUPS:+$KEEP_GROUPS,}$tok"
  done
}

validate_keep_groups() {
  local g
  for g in $(keep_words); do
    is_keep_group "$g" || die "unknown keep group '$g' (use teams, samsung-internet, office, gmail, messages, phoning or none)"
  done
}

# ts_filter <file> <max_tier>  -> prints rows with tier <= max (or all extras rows)
ts_filter() {
  local file="$1" max="$2"
  [ -f "$file" ] || return 0
  awk -F'\t' -v max="$max" '
    { sub(/\r$/, "") }
    /^[[:space:]]*#/ { next }
    NF < 4          { next }
    $1 == "extras"  { print; next }
    $1 + 0 <= max + 0 { print }
  ' "$file"
}

count_rows() { # count_rows <file> <max>
  ts_filter "$1" "$2" | wc -l | tr -d ' '
}

package_rows() {
  ts_filter "$PACKAGES_FILE" "$1"
  if [ -n "$DEVICE_PACKAGE_FILE" ] && [ -f "$DEVICE_PACKAGE_FILE" ]; then ts_filter "$DEVICE_PACKAGE_FILE" "$1"; fi
}

count_package_rows() { package_rows "$1" | wc -l | tr -d ' '; }

setting_rows() {
  local max="$1" tier ns key val note scope scope_l maker_l resolved
  maker_l="$(printf '%s' "$MANUFACTURER" | tr '[:upper:]' '[:lower:]')"
  while IFS='	' read -r tier ns key val note scope; do
    case "$tier" in ''|'#'*) continue ;; esac
    [ "$tier" -le "$max" ] 2>/dev/null || continue
    scope="${scope:-all}"; scope_l="$(printf '%s' "$scope" | tr '[:upper:]' '[:lower:]')"
    if [ -n "$MANUFACTURER" ] && [ "$scope_l" != "all" ] && [ "$scope_l" != "$maker_l" ] && [ "$scope_l" != "$DEVICE_PROFILE" ]; then continue; fi
    resolved="$val"
    case "$val" in
      __MAX_REFRESH__) [ -n "$MAX_REFRESH_RATE" ] || continue; resolved="$MAX_REFRESH_RATE" ;;
      __BALANCED_MIN_REFRESH__) [ -n "$MAX_REFRESH_RATE" ] || continue; resolved="$(awk -v max="$MAX_REFRESH_RATE" 'BEGIN{if(max<60)printf "%g",max;else print 60}')" ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\n' "$tier" "$ns" "$key" "$resolved" "$note"
  done < "$SETTINGS_FILE"
}

# ------------------------------------------------------------------ active/default app protection
add_runtime_protected() {
  local pkg reason="$2"; pkg="${1%%/*}"
  case "$pkg" in [A-Za-z]*.*) printf '%s\t%s\n' "$pkg" "$reason" >> "$TMP/runtime-protected.tsv" ;; esac
}

build_runtime_protection() {
  local users="$1" u role reason line value component
  : > "$TMP/runtime-protected.tsv"
  [ "$DEVICE_CLASS" = "watch" ] && return 0
  for u in $users; do
    for role in android.app.role.HOME android.app.role.SMS android.app.role.DIALER android.app.role.BROWSER; do
      case "$role" in *.HOME) reason="active launcher";; *.SMS) reason="default SMS app";; *.DIALER) reason="default dialer";; *) reason="default browser";; esac
      adbs "cmd role get-role-holders --user $u $role" | while IFS= read -r line; do add_runtime_protected "$line" "$reason"; done
    done
    value="$(adbs "settings --user $u get secure default_input_method")"; [ -n "$value" ] && [ "$value" != "null" ] && add_runtime_protected "$value" "active keyboard"
    for line in enabled_accessibility_services enabled_notification_listeners; do
      value="$(adbs "settings --user $u get secure $line")"; [ -n "$value" ] && [ "$value" != "null" ] || continue
      reason="enabled notification listener"; [ "$line" = "enabled_accessibility_services" ] && reason="enabled accessibility service"
      printf '%s\n' "$value" | tr ':' '\n' | while IFS= read -r component; do add_runtime_protected "$component" "$reason"; done
    done
  done
  sort -u "$TMP/runtime-protected.tsv" -o "$TMP/runtime-protected.tsv"
  : > "$TMP/runtime-installed.txt"
  for u in $users; do adbs "pm list packages --user $u" | sed -n 's/^package://p' >> "$TMP/runtime-installed.txt"; done
  sort -u "$TMP/runtime-installed.txt" -o "$TMP/runtime-installed.txt"
  awk -F'\t' 'NR==FNR{present[$1]=1;next}present[$1]' "$TMP/runtime-installed.txt" "$TMP/runtime-protected.tsv" > "$TMP/runtime-protected.filtered.tsv"
  mv "$TMP/runtime-protected.filtered.tsv" "$TMP/runtime-protected.tsv"
}

runtime_protected() { awk -F'\t' -v p="$1" '$1==p{found=1}END{exit !found}' "$TMP/runtime-protected.tsv" 2>/dev/null; }
protection_reason() { awk -F'\t' -v p="$1" '$1==p{print $2;exit}' "$TMP/runtime-protected.tsv" 2>/dev/null; }

# ------------------------------------------------------------------ safety net
is_protected() {
  runtime_protected "$1" && return 0
  case "$1" in
    android|com.android.systemui|com.android.settings|com.android.shell|\
    com.android.phone|com.android.server.telecom|com.android.providers.settings|\
    com.android.providers.media|com.android.providers.downloads|com.android.providers.contacts|\
    com.android.providers.telephony|com.android.providers.calendar|\
    com.android.packageinstaller|com.google.android.packageinstaller|\
    com.google.android.permissioncontroller|com.google.android.webview|\
    com.google.android.gms|com.google.android.gsf|com.android.vending|\
    com.google.android.networkstack|com.google.android.networkstack.tethering|\
    com.android.networkstack|com.android.networkstack.tethering|\
    com.android.bluetooth|com.android.wifi.resources|com.android.keychain|\
    com.android.certinstaller|com.android.settings.intelligence|\
    com.sec.android.app.launcher|com.samsung.android.honeyboard|\
    com.samsung.android.biometrics.app.setting|com.samsung.android.location|\
    com.android.externalstorage|com.android.intentresolver|\
    com.android.vpndialogs|com.android.mtp|com.samsung.android.mtp|\
    com.google.android.inputmethod.latin|com.google.android.dialer|com.android.updater|\
    com.lbe.security.miui|com.miui.home|com.miui.system|com.miui.core|com.miui.rom|\
    com.miui.securitycenter|com.miui.securitycore|com.miui.securityadd|com.miui.powerkeeper|\
    com.miui.global.packageinstaller|com.miui.notification|com.miui.miwallpaper|\
    com.xiaomi.misettings|com.xiaomi.discover|com.xiaomi.finddevice|com.xiaomi.micloud.sdk|\
    com.xiaomi.account|com.xiaomi.xmsf|com.xiaomi.xmsfkeeper|com.xiaomi.joyose|\
    com.miui.systemui.carriers.overlay|android.miui.home.launcher.res|\
    com.android.phone.overlay.miui|com.android.server.telecom.overlay.miui|\
    com.android.carrierconfig.overlay.miui)
      return 0 ;;
  esac
  if [ "$DEVICE_CLASS" = "watch" ]; then
    case "$1" in
      com.samsung.android.wearable.sysui|com.google.android.apps.wearable.systemui|\
      com.google.wear.services|com.google.android.wearable.app|\
      com.google.android.wearable.protolayout.renderer|com.google.android.gsmediator|\
      com.samsung.android.clientconnection|com.samsung.android.secondconnection|\
      com.samsung.android.wcs.extension|com.samsung.android.mcfds|\
      com.samsung.android.service.health|com.google.android.wearable.healthservices|\
      com.samsung.android.wear.shealth|com.samsung.android.shealthmonitor|\
      com.samsung.android.hardware.sensormanager.permission|\
      com.samsung.android.watch.safety_assistance|com.samsung.android.watch.findmywatch|\
      com.samsung.android.watch.stf|com.samsung.android.app.find|com.google.android.apps.adm|\
      com.android.nfc|\
      com.samsung.android.dialer|com.samsung.android.incallui|\
      com.samsung.android.app.telephonyui|com.samsung.advancedcallservice|\
      com.samsung.android.mdecservice|com.samsung.android.wear.blockednumber|\
      com.samsung.android.providers.contacts|com.samsung.android.app.contacts|\
      com.samsung.wear.contacts.sync|com.sec.imsservice|com.samsung.advp.imssettings|\
      com.google.android.apps.messaging|com.samsung.android.wearable.samsungaccount|\
      com.samsung.android.scloud|com.sec.android.app.samsungapps|\
      com.samsung.android.wearable.setupwizard|com.samsung.android.wearable.setupwizard.fota|\
      com.sec.android.easyMover|com.samsung.android.wear.smartswitchassistant|\
      com.samsung.wear.watchface.runtime|com.samsung.android.watch.watchface.*)
        return 0 ;;
    esac
  fi
  return 1
}

# ------------------------------------------------------------------ package state
pkg_installed() { # pkg_installed <user> <package>  (uses cached list)
  grep -qx "package:$2" "$TMP/pkgs-$1" 2>/dev/null
}

pkg_is_system() { # true when the APK lives in the read-only system image
  grep -qx "package:$2" "$TMP/pkgs-sys-$1" 2>/dev/null
}

pkg_is_disabled() {
  grep -qx "package:$2" "$TMP/pkgs-disabled-$1" 2>/dev/null
}

cache_packages() { # cache_packages <user>
  adbs "pm list packages --user $1" > "$TMP/pkgs-$1"
  adbs "pm list packages -s --user $1" > "$TMP/pkgs-sys-$1"
  adbs "pm list packages -d --user $1" > "$TMP/pkgs-disabled-$1"
}

# ------------------------------------------------------------------ apply one package
apply_pkg() { # apply_pkg <user> <package> <category> [auto|uninstall|disable]
  local u="$1" pkg="$2" cat="$3" requested="${4:-auto}" out

  case "$requested" in
    ''|auto|uninstall|disable) ;;
    *) fail "$pkg - invalid profile action '$requested'"; return 2 ;;
  esac

  if is_protected "$pkg"; then
    fail "refusing to touch protected package: $pkg"
    return 2
  fi
  if ! pkg_installed "$u" "$pkg"; then
    return 3   # not installed for this user - nothing to do
  fi
  if pkg_is_disabled "$u" "$pkg" && [ "$requested" != "uninstall" ]; then
    return 3   # already in the requested disabled state
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$requested" = "disable" ]; then
      printf '    %s%-46s%s %s (would disable; APK + data kept)\n' "$C_DIM" "$pkg" "$C_RESET" "$cat"
    elif [ "$requested" = "uninstall" ] && pkg_is_system "$u" "$pkg"; then
      printf '    %s%-46s%s %s (would uninstall for user %s; data kept)\n' "$C_DIM" "$pkg" "$C_RESET" "$cat" "$u"
    elif [ "$DISABLE_PRELOADS" -eq 1 ] && ! pkg_is_system "$u" "$pkg"; then
      printf '    %s%-46s%s %s (preload: would disable)\n' "$C_DIM" "$pkg" "$C_RESET" "$cat"
    elif ! pkg_is_system "$u" "$pkg"; then
      printf '    %s%-46s%s %s (preload: would delete APK + data)\n' "$C_DIM" "$pkg" "$C_RESET" "$cat"
    else
      printf '    %s%-46s%s %s\n' "$C_DIM" "$pkg" "$C_RESET" "$cat"
    fi
    return 0
  fi

  # System-image apps keep their data (-k) so a restore is lossless.
  # Data-installed preloads (Office, Samsung Notes, Samsung Internet, ...) are
  # removed completely - APK *and* app data - because their data would just be
  # orphaned once the APK is gone. Use --disable-preloads to hide them instead.
  if [ "$requested" != "disable" ] && { [ "$DISABLE_PRELOADS" -eq 0 ] || pkg_is_system "$u" "$pkg"; }; then
    if pkg_is_system "$u" "$pkg"; then
      out="$(adbs "pm uninstall -k --user $u '$pkg'")"
    else
      out="$(adbs "pm uninstall --user $u '$pkg'")"
    fi
    case "$out" in
      *Success*)
        printf '%s\t%s\t%s\t%s\n' "$u" "$pkg" "uninstalled" "$cat" >> "$MANIFEST"
        printf '%s\t%s\t%s\t%s\n' "$u" "$pkg" "uninstalled" "$cat" >> "$CUMULATIVE_PKG"
        printf '    %s- %-46s%s %s\n' "$C_DIM" "$pkg" "$C_RESET" "$cat"
        return 0 ;;
    esac
  fi

  out="$(adbs "pm disable-user --user $u '$pkg'")"
  case "$out" in
    *"disabled-user"*|*Success*)
      printf '%s\t%s\t%s\t%s\n' "$u" "$pkg" "disabled" "$cat" >> "$MANIFEST"
      printf '%s\t%s\t%s\t%s\n' "$u" "$pkg" "disabled" "$cat" >> "$CUMULATIVE_PKG"
      printf '    %sx %-46s%s %s (disabled)\n' "$C_DIM" "$pkg" "$C_RESET" "$cat"
      return 0 ;;
  esac

  fail "$pkg - $out"
  return 1
}

# ------------------------------------------------------------------ settings
apply_setting() { # apply_setting <ns> <key> <value> <note>
  local ns="$1" key="$2" val="$3" note="$4" old readback applied=0
  old="$(adbs "settings get $ns $key")"
  [ -z "$old" ] && old="null"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '    %s%-34s %-34s -> %s%s\n' "$C_DIM" "$ns/$key" "$old" "$val" "$C_RESET"
    return 0
  fi

  printf '%s\t%s\t%s\t%s\n' "$ns" "$key" "$old" "$note" >> "$SETTINGS_MANIFEST"
  printf '%s\t%s\t%s\t%s\n' "$ns" "$key" "$old" "$note" >> "$CUMULATIVE_SET"

  if [ "$val" = "__DELETE__" ]; then
    adbs "settings delete $ns $key" >/dev/null
  else
    adbs "settings put $ns $key $val" >/dev/null
  fi
  readback="$(adbs "settings get $ns $key")"
  if [ "$val" = "__DELETE__" ]; then
    if [ -z "$readback" ] || [ "$readback" = "null" ]; then applied=1; fi
  elif [ "$readback" = "$val" ]; then applied=1
  elif awk -v want="$val" -v got="$readback" 'BEGIN{if(want!~/^[-+]?[0-9]+([.][0-9]+)?$/||got!~/^[-+]?[0-9]+([.][0-9]+)?$/)exit 1;d=want-got;if(d<0)d=-d;exit !(d<0.001)}'; then applied=1
  fi
  if [ "$applied" -eq 1 ]; then ok "$ns/$key = $val  ${C_DIM}(was $old)${C_RESET}"; else warn "$ns/$key was not applied (readback: $readback)"; fi
}

restore_setting() { # restore_setting <ns> <key> <old>
  local ns="$1" key="$2" old="$3"
  if [ "$old" = "null" ] || [ "$old" = "__NULL__" ] || [ -z "$old" ]; then
    adbs "settings delete $ns $key" >/dev/null
    ok "$ns/$key cleared"
  else
    adbs "settings put $ns $key $old" >/dev/null
    ok "$ns/$key = $old"
  fi
}

# ------------------------------------------------------------------ statistics
snapshot_stats() { # snapshot_stats <path>  -> key/value TSV for before/after comparisons
  local out="$1" u line total used free installed tier target_count protected_count
  tier="$(profile_tier "$PROFILE" 2>/dev/null || printf '0')"
  : > "$TMP/stats-targets.txt"
  if [ "$tier" -gt 0 ] 2>/dev/null; then package_rows "$tier" | cut -f2 >> "$TMP/stats-targets.txt"; fi
  if [ "$WANT_EXTRAS" -eq 1 ]; then ts_filter "$EXTRAS_FILE" 9 | cut -f2 >> "$TMP/stats-targets.txt"; fi
  { keep_packages; cut -f1 "$TMP/runtime-protected.tsv" 2>/dev/null; } | sort -u > "$TMP/stats-protected.txt"
  {
    printf 'key\tvalue\n'
    printf 'manufacturer\t%s\n' "${MANUFACTURER:-unknown}"
    printf 'model\t%s\n' "${MODEL:-unknown}"
    printf 'device\t%s\n' "${DEVICE:-unknown}"
    printf 'android\t%s\n' "${RELEASE:-unknown}"
    printf 'build\t%s\n' "${BUILD:-unknown}"
    printf 'security_patch\t%s\n' "${SECURITY_PATCH:-unknown}"
    printf 'display.max_refresh_hz\t%s\n' "${MAX_REFRESH_RATE:-unknown}"
    printf 'setting.window_animation_scale\t%s\n' "$(adbs "settings get global window_animation_scale")"
    printf 'setting.transition_animation_scale\t%s\n' "$(adbs "settings get global transition_animation_scale")"
    printf 'setting.animator_duration_scale\t%s\n' "$(adbs "settings get global animator_duration_scale")"
    printf 'setting.peak_refresh_rate\t%s\n' "$(adbs "settings get system peak_refresh_rate")"
    printf 'setting.min_refresh_rate\t%s\n' "$(adbs "settings get system min_refresh_rate")"
    printf 'mem_total_kb\t%s\n' "$(adbs "cat /proc/meminfo" | awk '/^MemTotal:/{print $2; exit}')"
    printf 'mem_free_kb\t%s\n' "$(adbs "cat /proc/meminfo" | awk '/^MemFree:/{print $2; exit}')"
    printf 'mem_available_kb\t%s\n' "$(adbs "cat /proc/meminfo" | awk '/^MemAvailable:/{print $2; exit}')"
    line="$(adbs "df -k /data" | tail -1)"
    total="$(printf '%s\n' "$line" | awk '{print $2}')"
    used="$(printf '%s\n' "$line" | awk '{print $3}')"
    free="$(printf '%s\n' "$line" | awk '{print $4}')"
    printf 'storage_total_kb\t%s\n' "${total:-0}"
    printf 'storage_used_kb\t%s\n' "${used:-0}"
    printf 'storage_free_kb\t%s\n' "${free:-0}"
    for u in $(resolve_users); do
      installed="$(adbs "pm list packages --user $u" | grep '^package:')"
      printf 'packages.user.%s\t%s\n' "$u" "$(printf '%s\n' "$installed" | grep -c '^package:')"
      printf 'disabled.user.%s\t%s\n' "$u" "$(adbs "pm list packages -d --user $u" | grep -c '^package:')"
      target_count="$(printf '%s\n' "$installed" | sed 's/^package://' | grep -Fxf "$TMP/stats-targets.txt" 2>/dev/null | wc -l | tr -d ' ')"
      protected_count="$(printf '%s\n' "$installed" | sed 's/^package://' | grep -Fxf "$TMP/stats-protected.txt" 2>/dev/null | wc -l | tr -d ' ')"
      printf 'targeted.user.%s\t%s\n' "$u" "${target_count:-0}"
      printf 'protected.user.%s\t%s\n' "$u" "${protected_count:-0}"
    done
  } > "$out"
}

show_stats_diff() { # show_stats_diff <before.tsv> <after.tsv>
  local before="$1" after="$2"
  if [ ! -f "$before" ]; then
    warn "no statistics were recorded before this run"
    return 1
  fi
  if [ ! -f "$after" ]; then
    warn "no statistics were recorded after this run (was the run interrupted?)"
    return 1
  fi

  printf '  %-40s %-12s %-12s %s\n' 'Metric' 'Before' 'After' 'Change'
  awk -F'\t' '
    function gb(kb) { return sprintf("%.1f GB", kb / 1048576) }
    function is_kb(k) { return k ~ /_kb$/ }
    function is_count(k) { return k ~ /^(packages|disabled|targeted|protected)\.user\./ }
    function is_num(v) { return v ~ /^[-+]?[0-9]+([.][0-9]+)?$/ }
    function interesting(k) { return is_kb(k) || is_count(k) || k ~ /^setting\./ || k == "display.max_refresh_hz" }
    FNR == 1 { next }
    FNR == NR { b[$1] = $2; next }
    {
      a[$1] = $2
      if (interesting($1) && !($1 in seen)) { seen[$1] = 1; order[++n] = $1 }
    }
    END {
      for (i = 1; i <= n; i++) {
        key = order[i]
        ar = a[key]; br = (key in b) ? b[key] : "n/a"
        av = ar + 0; bv = br + 0; d = av - bv
        if (is_kb(key) && is_num(ar) && is_num(br)) {
          bs = gb(bv); as = gb(av)
          cs = (d > 0 ? "+" : "") sprintf("%.1f GB", d / 1048576)
        } else if (is_count(key) && is_num(ar) && is_num(br)) {
          bs = bv ""; as = av ""
          cs = (d > 0 ? "+" : "") d ""
        } else {
          bs = br; as = ar
          if (is_num(ar) && is_num(br)) cs = (d == 0 ? "unchanged" : (d > 0 ? "+" : "") sprintf("%.2f", d))
          else cs = (ar == br ? "unchanged" : "changed")
        }
        label = key
        if (key == "mem_total_kb") label = "Total RAM"
        else if (key == "mem_available_kb") label = "Available RAM"
        else if (key == "mem_free_kb") label = "Free RAM"
        else if (key == "storage_total_kb") label = "Storage total"
        else if (key == "storage_used_kb") label = "Storage used"
        else if (key == "storage_free_kb") label = "Storage free"
        else if (key ~ /^packages\.user\./) {
          id = key; sub(/^packages\.user\./, "", id)
          label = "Installed packages (user " id ")"
        } else if (key ~ /^disabled\.user\./) {
          id = key; sub(/^disabled\.user\./, "", id)
          label = "Disabled packages (user " id ")"
        } else if (key ~ /^targeted\.user\./) {
          id = key; sub(/^targeted\.user\./, "", id)
          label = "Profile packages present (user " id ")"
        } else if (key ~ /^protected\.user\./) {
          id = key; sub(/^protected\.user\./, "", id)
          label = "Protected packages present (user " id ")"
        } else if (key == "display.max_refresh_hz") label = "Display maximum"
        else if (key == "setting.window_animation_scale") label = "Window animation scale"
        else if (key == "setting.transition_animation_scale") label = "Transition animation scale"
        else if (key == "setting.animator_duration_scale") label = "Animator duration scale"
        else if (key == "setting.peak_refresh_rate") label = "Peak refresh-rate setting"
        else if (key == "setting.min_refresh_rate") label = "Minimum refresh-rate setting"
        printf "  %-40s %-12s %-12s %s\n", label, bs, as, cs
      }
    }
  ' "$before" "$after"
  dim "  RAM figures move with what is open - package and storage counts are the reliable ones."
}

save_before_after_report() { # before after directory
  local before="$1" after="$2" dir="$3"
  [ -f "$before" ] && [ -f "$after" ] || return 0
  awk -F'\t' '
    function gb(kb) { return sprintf("%.1f GB", kb / 1048576) }
    function is_kb(k) { return k ~ /_kb$/ }
    function is_count(k) { return k ~ /^(packages|disabled|targeted|protected)\.user\./ }
    function is_num(v) { return v ~ /^[-+]?[0-9]+([.][0-9]+)?$/ }
    function interesting(k) { return is_kb(k) || is_count(k) || k ~ /^setting\./ || k == "display.max_refresh_hz" }
    function label_for(key, id) {
      if (key == "mem_total_kb") return "Total RAM"
      if (key == "mem_available_kb") return "Available RAM"
      if (key == "mem_free_kb") return "Free RAM"
      if (key == "storage_total_kb") return "Storage total"
      if (key == "storage_used_kb") return "Storage used"
      if (key == "storage_free_kb") return "Storage free"
      if (key ~ /^packages\.user\./) { id=key; sub(/^packages\.user\./,"",id); return "Installed packages (user " id ")" }
      if (key ~ /^disabled\.user\./) { id=key; sub(/^disabled\.user\./,"",id); return "Disabled packages (user " id ")" }
      if (key ~ /^targeted\.user\./) { id=key; sub(/^targeted\.user\./,"",id); return "Profile packages present (user " id ")" }
      if (key ~ /^protected\.user\./) { id=key; sub(/^protected\.user\./,"",id); return "Protected packages present (user " id ")" }
      if (key == "display.max_refresh_hz") return "Display maximum"
      if (key == "setting.window_animation_scale") return "Window animation scale"
      if (key == "setting.transition_animation_scale") return "Transition animation scale"
      if (key == "setting.animator_duration_scale") return "Animator duration scale"
      if (key == "setting.peak_refresh_rate") return "Peak refresh-rate setting"
      if (key == "setting.min_refresh_rate") return "Minimum refresh-rate setting"
      return key
    }
    BEGIN { print "metric\tbefore\tafter\tchange" }
    FNR == 1 { next }
    FNR == NR { b[$1]=$2; next }
    interesting($1) { a[$1]=$2; order[++n]=$1 }
    END {
      for (i=1;i<=n;i++) {
        k=order[i]; ar=a[k]; br=(k in b)?b[k]:"n/a"; d=(ar+0)-(br+0)
        if (is_kb(k) && is_num(ar) && is_num(br)) { bs=gb(br); as=gb(ar); cs=(d>0?"+":"") sprintf("%.1f GB",d/1048576) }
        else if (is_count(k) && is_num(ar) && is_num(br)) { bs=br; as=ar; cs=(d>0?"+":"") d }
        else { bs=br; as=ar; cs=(is_num(ar)&&is_num(br))?(d==0?"unchanged":(d>0?"+":"") sprintf("%.2f",d)):(ar==br?"unchanged":"changed") }
        print label_for(k) "\t" bs "\t" as "\t" cs
      }
    }
  ' "$before" "$after" > "$dir/before-after.tsv"
  awk -F'\t' 'BEGIN { print "# Before / after\n\n| Metric | Before | After | Change |\n|---|---:|---:|---:|" } NR>1 { printf "| %s | %s | %s | %s |\n",$1,$2,$3,$4 }' \
    "$dir/before-after.tsv" > "$dir/before-after.md"
}

do_compare() {
  local dir="$COMPARE_DIR" stats_before stats_after
  if [ -z "$dir" ]; then dir="$(latest_backup)"; fi
  [ -n "$dir" ] || die "no backups found - apply a profile first"
  [ -d "$dir" ] || die "backup not found: $dir"
  head1 "Before / after - $(basename "$dir")"
  if [ -f "$dir/info.txt" ]; then sed 's/^/  /' "$dir/info.txt"; head1 "Statistics"; fi
  stats_before="$dir/stats-before.tsv"
  stats_after="$dir/stats-after.tsv"
  if [ -f "$stats_before" ] && [ -f "$stats_after" ]; then
    save_before_after_report "$stats_before" "$stats_after" "$dir"
    show_stats_diff "$stats_before" "$stats_after"
  elif [ -f "$dir/before.txt" ] && [ -f "$dir/after.txt" ]; then
    show_before_after "$dir/before.txt" "$dir/after.txt"
  else
    show_stats_diff "$stats_before" "$stats_after"
  fi
}

# ------------------------------------------------------------------ report
do_report() {
  head1 "Device"
  say "  Name       : ${MARKET_NAME:-$MODEL}"
  say "  Model      : $MODEL"
  say "  Maker      : $MANUFACTURER"
  say "  Target     : $DEVICE_LABEL"
  say "  Product    : $(adbs getprop ro.product.name)"
  say "  Android    : $(adbs getprop ro.build.version.release) (SDK $(adbs getprop ro.build.version.sdk))"
  say "  Skin       : $SKIN"
  say "  Build      : $BUILD"
  say "  Security   : $SECURITY_PATCH"
  say "  Profile    : ${DEVICE_PROFILE:-${DEVICE_CLASS}}"
  say "  CSC        : $(adbs getprop ro.csc.sales_code) / $(adbs getprop ro.csc.countryiso_code)"
  say "  ABI        : $(adbs getprop ro.product.cpu.abi)"

  head1 "Display"
  adbs "wm size" | sed 's/^/  /'
  adbs "wm density" | sed 's/^/  /'
  say "  Max mode   : $MAX_REFRESH_RATE Hz"
  say "  Refresh    : $(adbs 'dumpsys display | grep -o "renderFrameRate [0-9.]*" | head -1')"
  say "  Animations : $(adbs 'settings get global window_animation_scale') / $(adbs 'settings get global transition_animation_scale') / $(adbs 'settings get global animator_duration_scale')"

  head1 "Memory"
  adbs "cat /proc/meminfo | grep -E 'MemTotal|MemFree|MemAvailable'" | sed 's/^/  /'

  head1 "Storage"
  adbs "df -h /data | tail -1" | sed 's/^/  /'

  if [ "$DEVICE_CLASS" = "watch" ]; then
    head1 "Battery"
    adbs "dumpsys battery | grep -E 'level:|status:|health:|temperature:'" | sed 's/^/  /'
  fi

  head1 "Users"
  list_real_users | while IFS='	' read -r id name; do
    say "  $id  $name"
  done

  head1 "Top 10 RAM consumers"
  adbs "dumpsys meminfo" | sed -n '/Total RSS by process/,/^$/p' | sed -n '3,13p' | sed 's/^/  /'

  head1 "Package counts"
  local u
  for u in $(resolve_users); do
    say "  user $u: $(adbs "pm list packages --user $u" | wc -l | tr -d ' ') installed"
  done
}

# ------------------------------------------------------------------ list
do_list_keep() {
  local g
  [ -f "$PROFILES/keep.tsv" ] || { warn "keep.tsv not found in $PROFILES"; return 1; }
  for g in $(keep_group_names); do
    head1 "$g"
    awk -F'\t' -v g="$g" '
      { sub(/\r$/, "") }
      /^[[:space:]]*#/ { next }
      NF >= 4 && $1 == g { printf "  %-52s %s\n", $2, $4 }
    ' "$PROFILES/keep.tsv"
  done
}

list_profile_set() {
  local title="$1" dir="$2" t label
  head1 "$title"
  for t in 1 2 3; do
    case $t in 1) label=light ;; 2) label=balanced ;; 3) label=aggressive ;; esac
    head1 "$label  (tier <= $t) - $(count_rows "$dir/packages.tsv" "$t") packages"
    ts_filter "$dir/packages.tsv" "$t" | awk -F'\t' '{printf "  %-52s %s%s\n", $2, $4, ($5 != "" ? " [" $5 "]" : "")}'
  done
  head1 "extras (--extras only) - $(ts_filter "$dir/extras.tsv" 9 | wc -l | tr -d ' ') packages"
  ts_filter "$dir/extras.tsv" 9 | awk -F'\t' '{printf "  %-52s %s%s\n", $2, $4, ($5 != "" ? " [" $5 "]" : "")}'
  head1 "settings"
  awk -F'\t' '{sub(/\r$/,"")} !/^[[:space:]]*#/ && NF>=5 {printf "  [tier %s] %s/%s = %s\n", $1, $2, $3, $4}' "$dir/settings.tsv"
}

do_list() {
  list_profile_set "Android base / Samsung profiles" "$PROFILES"
  for file in "$PROFILES"/packages-*.tsv; do
    [ -f "$file" ] || continue
    head1 "$(basename "$file" .tsv) exact-device additions - $(count_rows "$file" 3) packages"
    ts_filter "$file" 3 | awk -F'\t' '{printf "  [tier %s] %-52s %s\n",$1,$2,$4}'
  done
  head1 "keep groups (never removed by a tablet or phone profile)"
  awk -F'\t' '{sub(/\r$/,"")} !/^[[:space:]]*#/ && NF>=4 {printf "  %-20s %-52s %s\n", $1, $2, $4}' "$PROFILES/keep.tsv"
  list_profile_set "Galaxy Watch / Wear OS profiles" "$PROFILES/watch"
}

# ------------------------------------------------------------------ backup
new_backup_dir() {
  local stamp dir keep_info
  stamp="$(date +%Y%m%d-%H%M%S)"
  dir="$BACKUPS/$stamp"
  mkdir -p "$dir"
  MANIFEST="$dir/packages.tsv"
  SETTINGS_MANIFEST="$dir/settings.tsv"
  CUMULATIVE_PKG="$BACKUPS/applied.tsv"
  CUMULATIVE_SET="$BACKUPS/original-settings.tsv"
  : >> "$CUMULATIVE_PKG"
  : >> "$CUMULATIVE_SET"
  : > "$MANIFEST"
  : > "$SETTINGS_MANIFEST"
  if [ "$DEVICE_CLASS" = "watch" ]; then
    keep_info="not-applicable"
  else
    keep_info="$(keep_words | tr '\n' ',' | sed 's/,$//')"
  fi
  {
    echo "Universal Android Optimiser v$VERSION"
    echo "date      : $(date)"
    echo "profile   : $PROFILE"
    echo "keep      : $keep_info"
    echo "extras    : $WANT_EXTRAS"
    echo "apply-settings : $APPLY_SETTINGS"
    echo "trim      : $WANT_TRIM"
    echo "dexopt    : $WANT_DEXOPT"
    echo "reboot    : $WANT_REBOOT"
    echo "serial    : $SERIAL"
    echo "profile-id: $DEVICE_PROFILE"
    echo "maker     : $MANUFACTURER"
    echo "model     : $MODEL"
    echo "device    : $DEVICE"
    echo "class     : $DEVICE_CLASS"
    echo "hardware  : $HARDWARE_ID"
    echo "android   : $RELEASE"
    echo "skin      : $SKIN"
    echo "build     : $BUILD"
    echo "security  : $SECURITY_PATCH"
    echo "max-hz    : $MAX_REFRESH_RATE"
    echo "host      : $(uname -s) $(uname -r)"
  } > "$dir/info.txt"
  LAST_BACKUP="$dir"
}

latest_backup() {
  local info dir
  find "$BACKUP_ROOT" -type f -name info.txt 2>/dev/null | while IFS= read -r info; do
    dir="${info%/info.txt}"
    printf '%s\t%s\n' "${dir##*/}" "$dir"
  done | sort | tail -1 | cut -f2-
}

# ------------------------------------------------------------------ before / after snapshots
capture_snapshot() { # capture_snapshot <file> <space/newline-separated users>
  local file="$1" users="$2" u n installed=0 enabled=0 mem_kb data_free_kb battery
  for u in $users; do
    n="$(adbs "pm list packages --user $u" | wc -l | tr -d ' ')"
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    installed=$((installed+n))
    n="$(adbs "pm list packages -e --user $u" | wc -l | tr -d ' ')"
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    enabled=$((enabled+n))
  done
  mem_kb="$(adbs "cat /proc/meminfo" | awk '$1=="MemAvailable:" {print $2; exit}')"
  data_free_kb="$(adbs "df -k /data" | awk 'END {print $4}')"
  battery="$(adbs "dumpsys battery" | sed -n 's/^[[:space:]]*level:[[:space:]]*//p' | head -1)"
  printf 'captured_at\t%s\ninstalled_packages\t%s\nenabled_packages\t%s\nmem_available_kb\t%s\ndata_free_kb\t%s\nbattery_percent\t%s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$installed" "$enabled" "${mem_kb:-0}" "${data_free_kb:-0}" "${battery:-0}" > "$file"
}

snapshot_value() { # snapshot_value <file> <key>
  awk -F'\t' -v key="$2" '$1==key {print $2; exit}' "$1"
}

format_mib() {
  awk -v kb="${1:-0}" 'BEGIN {printf "%.1f MiB", kb / 1024}'
}

format_gib() {
  awk -v kb="${1:-0}" 'BEGIN {printf "%.2f GiB", kb / 1048576}'
}

number_delta() {
  awk -v before="${1:-0}" -v after="${2:-0}" 'BEGIN {d=after-before; printf "%+.0f", d}'
}

memory_delta() {
  awk -v before="${1:-0}" -v after="${2:-0}" 'BEGIN {d=(after-before)/1024; printf "%+.1f MiB", d}'
}

storage_delta() {
  awk -v before="${1:-0}" -v after="${2:-0}" 'BEGIN {d=(after-before)/1048576; printf "%+.2f GiB", d}'
}

show_snapshot() { # show_snapshot <heading> <file>
  local heading="$1" file="$2" installed enabled mem free battery
  installed="$(snapshot_value "$file" installed_packages)"
  enabled="$(snapshot_value "$file" enabled_packages)"
  mem="$(snapshot_value "$file" mem_available_kb)"
  free="$(snapshot_value "$file" data_free_kb)"
  battery="$(snapshot_value "$file" battery_percent)"
  head1 "$heading"
  say "  Installed packages : $installed"
  say "  Enabled packages   : $enabled"
  say "  Available RAM      : $(format_mib "$mem")"
  say "  Free /data         : $(format_gib "$free")"
  say "  Battery            : ${battery}%"
}

show_before_after() { # show_before_after <before-file> <after-file>
  local before="$1" after="$2" bi ai be ae bm am bf af bb ab
  bi="$(snapshot_value "$before" installed_packages)"; ai="$(snapshot_value "$after" installed_packages)"
  be="$(snapshot_value "$before" enabled_packages)";   ae="$(snapshot_value "$after" enabled_packages)"
  bm="$(snapshot_value "$before" mem_available_kb)";   am="$(snapshot_value "$after" mem_available_kb)"
  bf="$(snapshot_value "$before" data_free_kb)";       af="$(snapshot_value "$after" data_free_kb)"
  bb="$(snapshot_value "$before" battery_percent)";   ab="$(snapshot_value "$after" battery_percent)"
  head1 "Before -> after (immediate)"
  printf '  %-21s %14s %14s %14s\n' "Metric" "Before" "After" "Change"
  printf '  %-21s %14s %14s %14s\n' "Installed packages" "$bi" "$ai" "$(number_delta "$bi" "$ai")"
  printf '  %-21s %14s %14s %14s\n' "Enabled packages" "$be" "$ae" "$(number_delta "$be" "$ae")"
  printf '  %-21s %14s %14s %14s\n' "Available RAM" "$(format_mib "$bm")" "$(format_mib "$am")" "$(memory_delta "$bm" "$am")"
  printf '  %-21s %14s %14s %14s\n' "Free /data" "$(format_gib "$bf")" "$(format_gib "$af")" "$(storage_delta "$bf" "$af")"
  printf '  %-21s %13s%% %13s%% %13s%%\n' "Battery" "$bb" "$ab" "$(number_delta "$bb" "$ab")"
  dim "  RAM is an immediate reading; compare again after reboot for a stable result."
}

wait_for_device_boot() {
  local timeout="${1:-240}" attempts i state booted
  attempts=$((timeout/2)); [ "$attempts" -gt 0 ] || attempts=1; i=0
  while [ "$i" -lt "$attempts" ]; do
    state="$(adb_raw get-state 2>/dev/null || true)"
    if [ "$state" = "device" ]; then booted="$(adbs "getprop sys.boot_completed")"; [ "$booted" = "1" ] && { sleep 5; return 0; }; fi
    sleep 2; i=$((i+1))
  done
  return 1
}

post_apply_health() {
  local users="$1" out="$2" u pkg reason home_holder healthy=1
  : > "$TMP/health-packages.txt"
  for u in $users; do adbs "pm list packages --user $u" | sed 's/^package://' >> "$TMP/health-packages.txt"; done
  sort -u "$TMP/health-packages.txt" -o "$TMP/health-packages.txt"
  printf 'check\tresult\tdetail\n' > "$out"
  while IFS='	' read -r pkg reason; do
    [ -n "${pkg:-}" ] || continue
    if grep -qxF "$pkg" "$TMP/health-packages.txt"; then printf 'protected:%s\tok\t%s\n' "$pkg" "$reason" >> "$out"
    else printf 'protected:%s\tFAIL\t%s\n' "$pkg" "$reason" >> "$out"; fail "post-run safety check: protected package missing: $pkg"; healthy=0; fi
  done < "$TMP/runtime-protected.tsv"
  if [ "$DEVICE_CLASS" != "watch" ]; then
    for u in $users; do
      home_holder="$(adbs "cmd role get-role-holders --user $u android.app.role.HOME" | head -1)"
      if [ -n "$home_holder" ]; then printf 'home:user:%s\tok\t%s\n' "$u" "$home_holder" >> "$out"
      else printf 'home:user:%s\tFAIL\t\n' "$u" >> "$out"; fail "post-run safety check: user $u has no default launcher"; healthy=0; fi
    done
  fi
  [ "$healthy" -eq 1 ] && { ok "post-run safety checks passed"; return 0; }
  return 1
}

# ------------------------------------------------------------------ apply
do_apply() {
  local tier users u total=0 rc pkg cat action before_file after_file keep_file settings_count reason after_stats
  tier="$(profile_tier "$PROFILE")" || die "unknown profile '$PROFILE' (use light, balanced or aggressive)"

  require_device
  users="$(resolve_users)"
  [ -z "$users" ] && die "could not determine any user profile"
  build_runtime_protection "$users"

  head1 "Plan"
  say "  Target     : $DEVICE_LABEL"
  say "  Profile    : ${C_BOLD}$PROFILE${C_RESET} (tier <= $tier)"
  [ -n "$DEVICE_PROFILE" ] && say "  Device     : $DEVICE_PROFILE"
  say "  Packages   : $(count_package_rows "$tier")"
  settings_count="$(setting_rows "$tier" | wc -l | tr -d ' ')"
  if [ "$APPLY_SETTINGS" -eq 1 ]; then
    say "  Settings   : $settings_count"
  else
    say "  Settings   : skipped ($settings_count profile settings left unchanged)"
  fi
  say "  Users      : $(printf '%s' "$users" | tr '\n' ' ')"
  if [ "$DEVICE_CLASS" != "watch" ]; then
    if [ -n "$KEEP_GROUPS" ]; then
      say "  Keep       : $(keep_words | tr '\n' ',' | sed 's/,$//') ($(keep_packages | wc -l | tr -d ' ') packages protected)"
    else
      say "  Keep       : ${C_YELLOW}none - every package in the profile can be removed${C_RESET}"
    fi
    say "  Active     : $(cut -f1 "$TMP/runtime-protected.tsv" | sort -u | wc -l | tr -d ' ') installed defaults/services protected automatically"
  fi
  [ "$WANT_EXTRAS" -eq 1 ] && say "  Extras     : ${C_YELLOW}yes - device-critical optional services will be changed${C_RESET}"
  [ "$DISABLE_PRELOADS" -eq 1 ] && say "  Preloads   : disabled (kept on disk) instead of deleted"
  [ "$DISABLE_PRELOADS" -eq 1 ] || warn "data-installed target apps, if any, will be deleted with their app data (use --disable-preloads to prevent this)"
  [ "$WANT_TRIM" -eq 1 ] && say "  Cache      : trim after package changes"
  if [ "$WANT_REBOOT" -eq 1 ] && [ "$DEVICE_CLASS" != "watch" ]; then say "  Reboot     : yes; final after snapshot will be captured post-reboot"
  elif [ "$WANT_REBOOT" -eq 1 ]; then say "  Reboot     : yes, after immediate statistics are captured"; fi
  [ "$DRY_RUN" -eq 1 ] && say "  Mode       : ${C_YELLOW}dry run - nothing will change${C_RESET}"

  if [ "$DRY_RUN" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
    printf '\n  Continue? [y/N] '
    read -r answer
    case "$answer" in y|Y|yes|YES) ;; *) say "  cancelled."; exit 0 ;; esac
  fi

  if [ "$DRY_RUN" -eq 0 ]; then
    new_backup_dir
    info "Backup written to $LAST_BACKUP"
    before_file="$LAST_BACKUP/before.txt"
    snapshot_stats "$LAST_BACKUP/stats-before.tsv"
    ok "baseline statistics captured (before)"
  else
    before_file="$TMP/before.txt"
  fi
  capture_snapshot "$before_file" "$users"
  [ "$DRY_RUN" -eq 1 ] && show_snapshot "Current baseline" "$before_file"

  if [ "$DEVICE_CLASS" != "watch" ]; then
    keep_packages > "$TMP/keep-packages.txt"
  else
    : > "$TMP/keep-packages.txt"
  fi
  keep_file="$TMP/keep-packages.txt"

  for u in $users; do
    head1 "User $u - $(user_label "$u")"
    cache_packages "$u"

    info "Applying package profile"
    package_rows "$tier" > "$TMP/list.txt"
    if [ "$WANT_EXTRAS" -eq 1 ]; then
      ts_filter "$EXTRAS_FILE" 9 >> "$TMP/list.txt"
    fi
    while IFS='	' read -r _ pkg cat _note action; do
      [ -z "${pkg:-}" ] && continue
      pkg_installed "$u" "$pkg" || continue
      if is_protected "$pkg"; then
        reason="$(protection_reason "$pkg")"; [ -n "$reason" ] || reason="safety blocklist"
        printf '    %s# %-46s%s %s (%s)\n' "$C_DIM" "$pkg" "$C_RESET" "$cat" "$reason"
        continue
      fi
      if [ -s "$keep_file" ] && grep -qxF "$pkg" "$keep_file"; then
        printf '    %s= %-46s%s %s (kept)\n' "$C_DIM" "$pkg" "$C_RESET" "$cat"
        continue
      fi
      apply_pkg "$u" "$pkg" "$cat" "${action:-auto}"
      case $? in 0) total=$((total+1)) ;; esac
    done < "$TMP/list.txt"
  done

  head1 "System settings"
  if [ "$APPLY_SETTINGS" -eq 1 ]; then
    setting_rows "$tier" > "$TMP/settings.txt"
    while IFS='	' read -r _ ns key val note; do
      [ -z "${ns:-}" ] && continue
      apply_setting "$ns" "$key" "$val" "$note"
    done < "$TMP/settings.txt"
  else
    dim "  skipped (package-only mode)"
  fi

  if [ "$WANT_TRIM" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
    head1 "Clearing app caches"
    adbs "cmd package trim-caches 64G" >/dev/null
    ok "caches trimmed"
  fi

  if [ "$WANT_DEXOPT" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
    head1 "Background dexopt"
    dim "  this can take several minutes..."
    adbs "cmd package bg-dexopt-job" >/dev/null
    ok "dexopt job finished"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    head1 "Done"
    say "  Dry run complete - nothing was changed."
  else
    after_stats="$LAST_BACKUP/stats-after.tsv"
    after_file="$LAST_BACKUP/after.txt"
    if [ "$WANT_REBOOT" -eq 1 ] && [ "$DEVICE_CLASS" != "watch" ]; then
      snapshot_stats "$LAST_BACKUP/stats-after-pre-reboot.tsv"
      capture_snapshot "$LAST_BACKUP/after-pre-reboot.txt" "$users"
      ok "immediate post-change statistics captured"
      info "Rebooting device before the final after snapshot"
      adb_raw reboot >/dev/null
      if wait_for_device_boot 240; then
        ok "device boot completed"
        snapshot_stats "$after_stats"; capture_snapshot "$after_file" "$users"
        ok "statistics captured (after reboot)"
      else warn "device did not finish booting before the timeout; final after snapshot was not created"; fi
    else
      snapshot_stats "$after_stats"; capture_snapshot "$after_file" "$users"; ok "statistics captured (after)"
    fi
    if [ -f "$after_stats" ]; then
      post_apply_health "$users" "$LAST_BACKUP/safety-checks.tsv" || true
      save_before_after_report "$LAST_BACKUP/stats-before.tsv" "$after_stats" "$LAST_BACKUP"
      head1 "Before / after"; show_stats_diff "$LAST_BACKUP/stats-before.tsv" "$after_stats"
    fi
    [ -f "$after_file" ] && show_before_after "$before_file" "$after_file"
    head1 "Done"
    say "  $total package actions applied."
    say "  Backup: $LAST_BACKUP"
    [ -f "$LAST_BACKUP/before-after.md" ] && say "  Report: $LAST_BACKUP/before-after.md"
    say "  Undo  : ./run.sh --restore"
    [ "$WANT_REBOOT" -eq 1 ] || dim "  A reboot is recommended so every change takes effect."
    [ "$DEVICE_CLASS" = "watch" ] && dim "  Turn off ADB debugging and wireless debugging on the watch when finished."
  fi

  if [ "$WANT_REBOOT" -eq 1 ] && [ "$DRY_RUN" -eq 0 ] && [ "$DEVICE_CLASS" = "watch" ]; then
    info "Rebooting device"
    adb_raw reboot
  fi
}

# ------------------------------------------------------------------ restore
validate_backup_target() { # validate_backup_target <backup-dir>
  local dir="$1" backup_device backup_class
  [ -f "$dir/info.txt" ] || { warn "backup has no device metadata; target cannot be verified"; return 0; }
  backup_device="$(sed -n 's/^device[[:space:]]*:[[:space:]]*//p' "$dir/info.txt" | head -1)"
  backup_class="$(sed -n 's/^class[[:space:]]*:[[:space:]]*//p' "$dir/info.txt" | head -1)"
  if [ -n "$backup_device" ] && [ "$backup_device" != "$DEVICE" ]; then
    die "backup is for device '$backup_device', but the connected device is '$DEVICE'"
  fi
  if [ -n "$backup_class" ] && [ "$backup_class" != "$DEVICE_CLASS" ]; then
    die "backup is for class '$backup_class', but the connected device is '$DEVICE_CLASS'"
  fi
}

do_restore() {
  local dir u pkg action cat ns key old note n=0 out
  local pkg_src set_src

  require_device

  if [ -n "$RESTORE_DIR" ]; then
    dir="$RESTORE_DIR"
    [ -d "$dir" ] || die "backup not found: $dir"
    [ -f "$dir/packages.tsv" ] || die "not a valid backup (no packages.tsv): $dir"
    validate_backup_target "$dir"
    pkg_src="$dir/packages.tsv"
    set_src="$dir/settings.tsv"
    head1 "Restoring a single run from $dir"
    if [ -f "$dir/info.txt" ]; then sed 's/^/  /' "$dir/info.txt"; fi
  else
    [ -f "$BACKUPS/applied.tsv" ] || die "nothing to restore - no changes have been applied yet"
    pkg_src="$BACKUPS/applied.tsv"
    set_src="$BACKUPS/original-settings.tsv"
    head1 "Restoring every change this tool has ever made"
    say "  packages: $(sort -u "$pkg_src" | wc -l | tr -d ' ') rows"
    say "  settings: $(awk -F'\t' '!seen[$1 FS $2]++' "$set_src" | wc -l | tr -d ' ') keys"
  fi

  if [ "$ASSUME_YES" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    printf '\n  Continue? [y/N] '
    read -r answer
    case "$answer" in y|Y|yes|YES) ;; *) say "  cancelled."; exit 0 ;; esac
  fi

  head1 "Reinstalling packages"
  sed 's/\r$//' "$pkg_src" | sort -u > "$TMP/restore-packages.txt"
  while IFS='	' read -r u pkg action cat; do
    [ -z "${pkg:-}" ] && continue
    case "$action" in
      uninstalled)
        if [ "$DRY_RUN" -eq 1 ]; then say "    would reinstall $pkg (user $u)"; continue; fi
        out="$(adbs "pm install-existing --user $u '$pkg'")"
        case "$out" in
          *installed*) ok "$pkg (user $u)"; n=$((n+1)) ;;
          *"doesn't exist"*|*"Unknown package"*|*"not installed"*)
            warn "$pkg (user $u) is no longer on the device - reinstall it from the Galaxy/Play Store" ;;
          *) fail "$pkg (user $u): $out" ;;
        esac ;;
      disabled)
        if [ "$DRY_RUN" -eq 1 ]; then say "    would enable $pkg (user $u)"; continue; fi
        out="$(adbs "pm enable --user $u '$pkg'")"
        case "$out" in
          *enabled*) ok "$pkg (user $u) enabled"; n=$((n+1)) ;;
          *)         fail "$pkg (user $u): $out" ;;
        esac ;;
    esac
  done < "$TMP/restore-packages.txt"

  head1 "Restoring settings"
  if [ -f "$set_src" ]; then
    # keep the oldest recorded value per key = the real original
    sed 's/\r$//' "$set_src" | awk -F'\t' 'NF>=3 && !seen[$1 FS $2]++' > "$TMP/restore-settings.txt"
    while IFS='	' read -r ns key old note; do
      [ -z "${key:-}" ] && continue
      if [ "$DRY_RUN" -eq 1 ]; then
        say "    would restore $ns/$key = $old"
      else
        restore_setting "$ns" "$key" "$old"
      fi
    done < "$TMP/restore-settings.txt"
  fi

  head1 "Done"
  if [ "$DRY_RUN" -eq 1 ]; then
    say "  Dry run complete - nothing was restored."
  else
    say "  $n packages restored. Reboot recommended."
    if [ "$WANT_REBOOT" -eq 1 ]; then adb_raw reboot; fi
  fi
}

# ------------------------------------------------------------------ restore-all
do_restore_all() {
  local u pkg cat action n=0 out
  require_device
  head1 "Reinstalling every package from every profile"

  if [ "$ASSUME_YES" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    printf '\n  This reinstalls ~%s packages on all users. Continue? [y/N] ' \
      "$( (package_rows 9; ts_filter "$EXTRAS_FILE" 9) | wc -l | tr -d ' ')"
    read -r answer
    case "$answer" in y|Y|yes|YES) ;; *) say "  cancelled."; exit 0 ;; esac
  fi

  for u in $(resolve_users); do
    head1 "User $u - $(user_label "$u")"
    (package_rows 9; ts_filter "$EXTRAS_FILE" 9) > "$TMP/all.txt"
    while IFS='	' read -r _ pkg cat _note action; do
      [ -z "${pkg:-}" ] && continue
      if [ "$DRY_RUN" -eq 1 ]; then
        if [ "${action:-auto}" = "disable" ]; then say "    would enable $pkg"; else say "    would reinstall $pkg"; fi
        continue
      fi
      if [ "${action:-auto}" = "disable" ]; then
        out="$(adbs "pm enable --user $u '$pkg'")"
        case "$out" in *enabled*) n=$((n+1)) ;; esac
      else
        out="$(adbs "pm install-existing --user $u '$pkg'")"
        case "$out" in
          *installed*) n=$((n+1)) ;;
          *"not installed"*|*"Unknown package"*) ;;
          *) : ;;
        esac
      fi
    done < "$TMP/all.txt"
    [ "$DEVICE_CLASS" != "watch" ] && [ "$DRY_RUN" -eq 0 ] && adbs "pm enable --user $u 'com.android.chrome'" >/dev/null 2>&1
  done

  head1 "Restoring default settings"
  if [ "$DRY_RUN" -eq 1 ]; then
    say "    would restore animation scales and clear the cached-app freezer override"
    [ "$DEVICE_CLASS" != "watch" ] && say "    would restore tablet CPU, radio-scan and refresh-rate defaults"
  else
    adbs "settings put global window_animation_scale 1.0" >/dev/null
    adbs "settings put global transition_animation_scale 1.0" >/dev/null
    adbs "settings put global animator_duration_scale 1.0" >/dev/null
    adbs "settings delete global cached_apps_freezer" >/dev/null
    if [ "$DEVICE_CLASS" != "watch" ]; then
      if [ "$(printf '%s' "$MANUFACTURER" | tr '[:upper:]' '[:lower:]')" = "samsung" ]; then adbs "settings put global sem_enhanced_cpu_responsiveness 0" >/dev/null; fi
      adbs "settings put global wifi_scan_always_enabled 1" >/dev/null
      adbs "settings put global ble_scan_always_enabled 1" >/dev/null
      adbs "settings delete system min_refresh_rate" >/dev/null
      adbs "settings delete system peak_refresh_rate" >/dev/null
    fi
    ok "default settings restored for $DEVICE_LABEL"
  fi

  head1 "Done"
  if [ "$DRY_RUN" -eq 1 ]; then
    say "  Dry run complete - nothing was changed."
  else
    say "  $n packages reinstalled. Reboot recommended."
    if [ "$WANT_REBOOT" -eq 1 ]; then adb_raw reboot; fi
  fi
}

# ------------------------------------------------------------------ argument parsing
while [ $# -gt 0 ]; do
  case "$1" in
    light|balanced|aggressive) PROFILE="$1"; shift ;;
    --profile)   PROFILE="${2:-}"; shift 2 ;;
    --profile=*) PROFILE="${1#*=}"; shift ;;
    --dry-run)   DRY_RUN=1; shift ;;
    --yes|-y)    ASSUME_YES=1; shift ;;
    --extras)    WANT_EXTRAS=1; shift ;;
    --disable-preloads) DISABLE_PRELOADS=1; shift ;;
    --keep)
      shift
      [ $# -gt 0 ] || die "--keep needs a group (teams, samsung-internet, office, gmail, messages, phoning or none)"
      while [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; do
        case "$1" in light|balanced|aggressive) break ;; esac
        add_keep_arg "$1"; shift
      done ;;
    --keep=*)    add_keep_arg "${1#*=}"; shift ;;
    --no-keep)   KEEP_GROUPS=""; KEEP_EXPLICIT=1; shift ;;
    --list-keep) MODE="list-keep"; shift ;;
    --trim)      WANT_TRIM=1; shift ;;
    --dexopt)    WANT_DEXOPT=1; shift ;;
    --reboot)    WANT_REBOOT=1; shift ;;
    --no-settings) APPLY_SETTINGS=0; shift ;;
    --user)      USER_LIST="$USER_LIST ${2:-}"; shift 2 ;;
    --user=*)    USER_LIST="$USER_LIST ${1#*=}"; shift ;;
    --all-users) USER_LIST=""; shift ;;
    --serial)    SERIAL="${2:-}"; shift 2 ;;
    --serial=*)  SERIAL="${1#*=}"; shift ;;
    --restore)
      MODE="restore"
      if [ $# -gt 1 ] && [ "${2#-}" = "$2" ]; then RESTORE_DIR="$2"; shift; fi
      shift ;;
    --restore-all) MODE="restore-all"; shift ;;
    --compare)
      MODE="compare"
      if [ $# -gt 1 ] && [ "${2#-}" = "$2" ]; then COMPARE_DIR="$2"; shift; fi
      shift ;;
    --compare=*) MODE="compare"; COMPARE_DIR="${1#*=}"; shift ;;
    --list)      MODE="list"; shift ;;
    --report)    MODE="report"; shift ;;
    --help|-h)   usage; exit 0 ;;
    --version)   echo "universal-android-optimiser $VERSION"; exit 0 ;;
    *)           fail "unknown argument: $1"; say ""; usage; exit 2 ;;
  esac
done

# normalise user list
USER_LIST="$(printf '%s\n' $USER_LIST | grep -v '^$' | tr '\n' ' ' | sed 's/ *$//')"

validate_keep_groups

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t samsungopt)"
trap 'rm -rf "$TMP"' EXIT INT TERM

case "$MODE" in
  list)        do_list; exit 0 ;;
  list-keep)   do_list_keep; exit 0 ;;
  compare)     do_compare; exit 0 ;;
  report)      require_device; do_report; exit 0 ;;
  restore)     do_restore; exit 0 ;;
  restore-all) do_restore_all; exit 0 ;;
esac

# ------------------------------------------------------------------ no profile? show a menu
if [ -z "$PROFILE" ]; then
  require_device
  head1 "Universal Android Optimiser v$VERSION"
  say "  Device: ${C_BOLD}${MARKET_NAME:-$MODEL}${C_RESET} - Android ${RELEASE}${SKIN:+ / $SKIN} ($DEVICE_LABEL)"
  say ""
  if [ "$DEVICE_CLASS" = "watch" ]; then
    say "  ${C_BOLD}1)${C_RESET} light       - retail demo, certification and factory test leftovers"
    say "  ${C_BOLD}2)${C_RESET} balanced    - + Bixby, customisation and enterprise provisioning"
    say "  ${C_BOLD}3)${C_RESET} aggressive  - + optional apps; calls, messages and health stay"
  else
    say "  ${C_BOLD}1)${C_RESET} light       - telemetry, diagnostics, ads and factory tools"
    say "  ${C_BOLD}2)${C_RESET} balanced    - + optional OEM/Google services and gaming extras"
    say "  ${C_BOLD}3)${C_RESET} aggressive  - + replaceable browser, media and productivity apps"
  fi
  say "  ${C_BOLD}4)${C_RESET} restore     - undo the last run"
  say "  ${C_BOLD}5)${C_RESET} report      - show device info without changing anything"
  say "  ${C_BOLD}6)${C_RESET} compare     - before/after statistics of the last run"
  say "  ${C_BOLD}q)${C_RESET} quit"
  printf '\n  Choose [1-6/q]: '
  read -r choice
  case "$choice" in
    1) PROFILE=light ;;
    2) PROFILE=balanced ;;
    3) PROFILE=aggressive ;;
    4) do_restore; exit 0 ;;
    5) do_report; exit 0 ;;
    6) do_compare; exit 0 ;;
    *) say "  bye."; exit 0 ;;
  esac
fi

do_apply
