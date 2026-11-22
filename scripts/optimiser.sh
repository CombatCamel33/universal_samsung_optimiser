#!/usr/bin/env bash
#
#  Tab S10 FE+ Optimiser - macOS / Linux driver
#  ---------------------------------------------------------------
#  Debloats and tunes a Samsung Galaxy Tab S10 FE+ (or any modern
#  Samsung/Android device) over ADB. Every change is reversible.
#
#  Usage:  ./run.sh [light|balanced|aggressive] [options]
#  Help:   ./run.sh --help
#
#  Written for bash 3.2 (the version macOS ships). No bash 4 features.
#
set -u

VERSION="1.2.0"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILES="$ROOT/profiles"
BACKUPS="$ROOT/backups"
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
MODE="apply"          # apply | restore | restore-all | list | report
RESTORE_DIR=""
USER_LIST=""
SERIAL=""

usage() {
  cat <<EOF
${C_BOLD}Tab S10 FE+ Optimiser${C_RESET} v$VERSION

  ./run.sh <profile> [options]      apply a profile
  ./run.sh --restore [dir]          undo every change (or restore one backup dir)
  ./run.sh --restore-all            reinstall every package in every profile

${C_BOLD}Profiles${C_RESET}
  light         telemetry, diagnostics, AR toys, preloads          (~35 packages)
  balanced      + Bixby, Samsung extras, gaming services, TTS packs (~120 packages)
  aggressive    + browsers, Office, YouTube, Samsung account apps   (~200 packages)

${C_BOLD}Options${C_RESET}
  --profile <name>   same as passing the profile as the first argument
  --dry-run          show what would happen, change nothing
  --user <id>        only touch this Android user (repeatable)
  --all-users        every real user profile (default: all except Secure Folder)
  --extras           also remove Knox / OTA / Samsung account (breaks Secure Folder)
  --disable-preloads hide /data-installed preloads instead of deleting them
                     (Office, Notes, Samsung Internet... stay on disk, restorable)
  --trim             clear app caches (pm trim-caches)
  --dexopt           run a background dexopt job now (slow, optimises app start-up)
  --reboot           reboot when finished
  --yes, -y          do not ask for confirmation
  --list             print the package lists
  --report           print device info, RAM and storage
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

require_device() {
  find_adb || die "adb not found. Install Android platform-tools or set ADB=/path/to/adb"
  local out
  out="$(adb_raw devices | tr -d '\r' | awk 'NR>1 && $2=="device" {print $1}')"
  if [ -z "$out" ]; then
    fail "No authorised device found."
    say  "  1. Enable Developer options (Settings > About tablet > Software information > tap Build number 7x)"
    say  "  2. Turn on USB debugging"
    say  "  3. Reconnect the cable and accept the RSA prompt on the tablet"
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
  RELEASE="$(adbs getprop ro.build.version.release)"
  ONUI="$(oneui_version "$(adbs getprop ro.build.version.oneui)")"
  [ -n "$ONUI" ] && ONUI=" / One UI $ONUI"
  info "Device: ${C_BOLD}${MODEL}${C_RESET} (${DEVICE}) - Android ${RELEASE}${ONUI}"
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

# ------------------------------------------------------------------ safety net
is_protected() {
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
    com.android.vpndialogs|com.android.mtp|com.samsung.android.mtp)
      return 0 ;;
  esac
  return 1
}

# ------------------------------------------------------------------ package state
pkg_installed() { # pkg_installed <user> <package>  (uses cached list)
  grep -qx "package:$2" "$TMP/pkgs-$1" 2>/dev/null
}

pkg_is_system() { # true when the APK lives in the read-only system image
  grep -qx "package:$2" "$TMP/pkgs-sys-$1" 2>/dev/null
}

cache_packages() { # cache_packages <user>
  adbs "pm list packages --user $1" > "$TMP/pkgs-$1"
  adbs "pm list packages -s --user $1" > "$TMP/pkgs-sys-$1"
}

# ------------------------------------------------------------------ apply one package
apply_pkg() { # apply_pkg <user> <package> <category>
  local u="$1" pkg="$2" cat="$3" out action

  if is_protected "$pkg"; then
    fail "refusing to touch protected package: $pkg"
    return 2
  fi
  if ! pkg_installed "$u" "$pkg"; then
    return 3   # not installed for this user - nothing to do
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$DISABLE_PRELOADS" -eq 1 ] && ! pkg_is_system "$u" "$pkg"; then
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
  if [ "$DISABLE_PRELOADS" -eq 0 ] || pkg_is_system "$u" "$pkg"; then
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
  local ns="$1" key="$2" val="$3" note="$4" old
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
  ok "$ns/$key = $val  ${C_DIM}(was $old)${C_RESET}"
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

# ------------------------------------------------------------------ report
do_report() {
  head1 "Device"
  say "  Model      : $(adbs getprop ro.product.model)"
  say "  Product    : $(adbs getprop ro.product.name)"
  say "  Android    : $(adbs getprop ro.build.version.release) (SDK $(adbs getprop ro.build.version.sdk))"
  say "  One UI     : $(oneui_version "$(adbs getprop ro.build.version.oneui)")"
  say "  Build      : $(adbs getprop ro.build.display.id)"
  say "  CSC        : $(adbs getprop ro.csc.sales_code) / $(adbs getprop ro.csc.countryiso_code)"
  say "  ABI        : $(adbs getprop ro.product.cpu.abi)"

  head1 "Display"
  adbs "wm size" | sed 's/^/  /'
  adbs "wm density" | sed 's/^/  /'
  say "  Refresh    : $(adbs 'dumpsys display | grep -o "renderFrameRate [0-9.]*" | head -1')"
  say "  Animations : $(adbs 'settings get global window_animation_scale') / $(adbs 'settings get global transition_animation_scale') / $(adbs 'settings get global animator_duration_scale')"

  head1 "Memory"
  adbs "cat /proc/meminfo | grep -E 'MemTotal|MemFree|MemAvailable'" | sed 's/^/  /'

  head1 "Storage"
  adbs "df -h /data | tail -1" | sed 's/^/  /'

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
do_list() {
  local t label
  for t in 1 2 3; do
    case $t in 1) label=light ;; 2) label=balanced ;; 3) label=aggressive ;; esac
    head1 "$label  (tier <= $t) - $(count_rows "$PROFILES/packages.tsv" "$t") packages"
    ts_filter "$PROFILES/packages.tsv" "$t" | awk -F'\t' '{printf "  %-52s %s\n", $2, $4}'
  done
  head1 "extras (--extras only) - $(ts_filter "$PROFILES/extras.tsv" 9 | wc -l | tr -d ' ') packages"
  ts_filter "$PROFILES/extras.tsv" 9 | awk -F'\t' '{printf "  %-52s %s\n", $2, $4}'
  head1 "settings"
  awk -F'\t' '{sub(/\r$/,"")} !/^[[:space:]]*#/ && NF>=5 {printf "  [tier %s] %s/%s = %s\n", $1, $2, $3, $4}' "$PROFILES/settings.tsv"
}

# ------------------------------------------------------------------ backup
new_backup_dir() {
  local stamp dir
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
  {
    echo "Tab S10 FE+ Optimiser v$VERSION"
    echo "date      : $(date)"
    echo "profile   : $PROFILE"
    echo "extras    : $WANT_EXTRAS"
    echo "serial    : $SERIAL"
    echo "model     : $MODEL"
    echo "device    : $DEVICE"
    echo "android   : $RELEASE"
    echo "oneui     : $ONUI"
    echo "host      : $(uname -s) $(uname -r)"
  } > "$dir/info.txt"
  LAST_BACKUP="$dir"
}

latest_backup() {
  ls -1d "$BACKUPS"/*/ 2>/dev/null | sort | tail -1 | sed 's:/*$::'
}

# ------------------------------------------------------------------ apply
do_apply() {
  local tier users u total=0 rc pkg cat
  tier="$(profile_tier "$PROFILE")" || die "unknown profile '$PROFILE' (use light, balanced or aggressive)"

  require_device
  users="$(resolve_users)"
  [ -z "$users" ] && die "could not determine any user profile"

  head1 "Plan"
  say "  Profile    : ${C_BOLD}$PROFILE${C_RESET} (tier <= $tier)"
  say "  Packages   : $(count_rows "$PROFILES/packages.tsv" "$tier")"
  say "  Settings   : $(awk -F'\t' -v m="$tier" '{sub(/\r$/,"")} !/^[[:space:]]*#/ && NF>=5 && $1+0<=m+0' "$PROFILES/settings.tsv" | wc -l | tr -d ' ')"
  say "  Users      : $(printf '%s' "$users" | tr '\n' ' ')"
  [ "$WANT_EXTRAS" -eq 1 ] && say "  Extras     : ${C_YELLOW}yes - Knox / OTA / Samsung account will be removed${C_RESET}"
  [ "$DISABLE_PRELOADS" -eq 1 ] && say "  Preloads   : disabled (kept on disk) instead of deleted"
  [ "$DRY_RUN" -eq 1 ] && say "  Mode       : ${C_YELLOW}dry run - nothing will change${C_RESET}"

  if [ "$DRY_RUN" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
    printf '\n  Continue? [y/N] '
    read -r answer
    case "$answer" in y|Y|yes|YES) ;; *) say "  cancelled."; exit 0 ;; esac
  fi

  if [ "$DRY_RUN" -eq 0 ]; then
    new_backup_dir
    info "Backup written to $LAST_BACKUP"
  fi

  for u in $users; do
    head1 "User $u - $(user_label "$u")"
    cache_packages "$u"

    info "Removing packages"
    ts_filter "$PROFILES/packages.tsv" "$tier" > "$TMP/list.txt"
    if [ "$WANT_EXTRAS" -eq 1 ]; then
      ts_filter "$PROFILES/extras.tsv" 9 >> "$TMP/list.txt"
    fi
    while IFS='	' read -r _ pkg cat _note; do
      [ -z "${pkg:-}" ] && continue
      apply_pkg "$u" "$pkg" "$cat"
      case $? in 0) total=$((total+1)) ;; esac
    done < "$TMP/list.txt"
  done

  head1 "System settings"
  awk -F'\t' -v m="$tier" '{sub(/\r$/,"")} !/^[[:space:]]*#/ && NF>=5 && $1+0<=m+0' "$PROFILES/settings.tsv" > "$TMP/settings.txt"
  while IFS='	' read -r _ ns key val note; do
    [ -z "${ns:-}" ] && continue
    apply_setting "$ns" "$key" "$val" "$note"
  done < "$TMP/settings.txt"

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

  head1 "Done"
  if [ "$DRY_RUN" -eq 1 ]; then
    say "  Dry run complete - nothing was changed."
  else
    say "  $total package actions applied."
    say "  Backup: $LAST_BACKUP"
    say "  Undo  : ./run.sh --restore"
    dim  "  A reboot is recommended so every change takes effect."
  fi

  if [ "$WANT_REBOOT" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
    info "Rebooting device"
    adb_raw reboot
  fi
}

# ------------------------------------------------------------------ restore
do_restore() {
  local dir u pkg action cat ns key old note n=0 out
  local pkg_src set_src

  require_device

  if [ -n "$RESTORE_DIR" ]; then
    dir="$RESTORE_DIR"
    [ -d "$dir" ] || die "backup not found: $dir"
    [ -f "$dir/packages.tsv" ] || die "not a valid backup (no packages.tsv): $dir"
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
  local u pkg cat n=0 out
  require_device
  head1 "Reinstalling every package from every profile"

  if [ "$ASSUME_YES" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    printf '\n  This reinstalls ~%s packages on all users. Continue? [y/N] ' \
      "$( (ts_filter "$PROFILES/packages.tsv" 9; ts_filter "$PROFILES/extras.tsv" 9) | wc -l | tr -d ' ')"
    read -r answer
    case "$answer" in y|Y|yes|YES) ;; *) say "  cancelled."; exit 0 ;; esac
  fi

  for u in $(resolve_users); do
    head1 "User $u - $(user_label "$u")"
    (ts_filter "$PROFILES/packages.tsv" 9; ts_filter "$PROFILES/extras.tsv" 9) > "$TMP/all.txt"
    while IFS='	' read -r _ pkg cat _note; do
      [ -z "${pkg:-}" ] && continue
      if [ "$DRY_RUN" -eq 1 ]; then say "    would reinstall $pkg"; continue; fi
      out="$(adbs "pm install-existing --user $u '$pkg'")"
      case "$out" in
        *installed*) n=$((n+1)) ;;
        *"not installed"*|*"Unknown package"*) ;;
        *) : ;;
      esac
    done < "$TMP/all.txt"
    adbs "pm enable --user $u 'com.android.chrome'" >/dev/null 2>&1
  done

  head1 "Restoring default settings"
  adbs "settings put global window_animation_scale 1.0" >/dev/null
  adbs "settings put global transition_animation_scale 1.0" >/dev/null
  adbs "settings put global animator_duration_scale 1.0" >/dev/null
  adbs "settings delete global cached_apps_freezer" >/dev/null
  adbs "settings put global sem_enhanced_cpu_responsiveness 0" >/dev/null
  adbs "settings put global wifi_scan_always_enabled 1" >/dev/null
  adbs "settings put global ble_scan_always_enabled 1" >/dev/null
  adbs "settings delete system min_refresh_rate" >/dev/null
  adbs "settings delete system peak_refresh_rate" >/dev/null
  ok "animation scales back to 1.0, refresh-rate overrides cleared"

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
    --trim)      WANT_TRIM=1; shift ;;
    --dexopt)    WANT_DEXOPT=1; shift ;;
    --reboot)    WANT_REBOOT=1; shift ;;
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
    --list)      MODE="list"; shift ;;
    --report)    MODE="report"; shift ;;
    --help|-h)   usage; exit 0 ;;
    --version)   echo "tab-s10-fe-optimiser $VERSION"; exit 0 ;;
    *)           fail "unknown argument: $1"; say ""; usage; exit 2 ;;
  esac
done

# normalise user list
USER_LIST="$(printf '%s\n' $USER_LIST | grep -v '^$' | tr '\n' ' ' | sed 's/ *$//')"

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t tabopt)"
trap 'rm -rf "$TMP"' EXIT INT TERM

case "$MODE" in
  list)        do_list; exit 0 ;;
  report)      require_device; do_report; exit 0 ;;
  restore)     do_restore; exit 0 ;;
  restore-all) do_restore_all; exit 0 ;;
esac

# ------------------------------------------------------------------ no profile? show a menu
if [ -z "$PROFILE" ]; then
  require_device
  head1 "Tab S10 FE+ Optimiser v$VERSION"
  say "  Device: ${C_BOLD}${MODEL}${C_RESET} - Android ${RELEASE}${ONUI}"
  say ""
  say "  ${C_BOLD}1)${C_RESET} light       - telemetry, diagnostics, AR toys, preloads"
  say "  ${C_BOLD}2)${C_RESET} balanced    - + Bixby, Samsung extras, gaming services, TTS packs"
  say "  ${C_BOLD}3)${C_RESET} aggressive  - + browsers, Office, YouTube, Samsung account apps"
  say "  ${C_BOLD}4)${C_RESET} restore     - undo the last run"
  say "  ${C_BOLD}5)${C_RESET} report      - show device info without changing anything"
  say "  ${C_BOLD}q)${C_RESET} quit"
  printf '\n  Choose [1-5/q]: '
  read -r choice
  case "$choice" in
    1) PROFILE=light ;;
    2) PROFILE=balanced ;;
    3) PROFILE=aggressive ;;
    4) do_restore; exit 0 ;;
    5) do_report; exit 0 ;;
    *) say "  bye."; exit 0 ;;
  esac
fi

do_apply
