#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Linux WebApp Builder — Terminal & dmenu edition
#
# Usage:
#   ./webapp-builder.sh              → auto-detect: dmenu if available, else TUI
#   ./webapp-builder.sh --tui        → force interactive terminal UI
#   ./webapp-builder.sh --dmenu      → force dmenu mode
#   ./webapp-builder.sh --create-manual --name "App" --url "https://..."
#                        [--icon-url URL] [--separate y|n] [--overwrite ask|yes|no]
#   ./webapp-builder.sh --create-category work|ai|other [--overwrite ask|yes|no]
#
# Creates:
#   ~/.local/bin/<app_id>                        → launcher script
#   ~/.local/share/applications/<app_id>.desktop → .desktop entry
#
# Browser:
#   Prefers Chromium-based browsers (Brave, Chrome, Chromium) for --app= mode,
#   which opens the webapp without an address bar in its own window.
#   Wayland is detected automatically at launch time and the correct flags
#   (--ozone-platform=wayland) are added when needed.
#   Falls back to xdg-open (default system browser) if no Chromium-based
#   browser is found — address bar will be visible in that case.
#
# Duplicate handling:
#   When a webapp already exists you are always asked whether to overwrite it.
#   In batch mode (install all) you are asked once before the run starts:
#     - Yes to all   → overwrite every existing app silently
#     - No to all    → skip every existing app silently
#     - Ask per app  → prompt individually for each conflict
# =============================================================================

# ---------- Runtime config ----------
TUI_MODE=0
DMENU_MODE=0
OVERWRITE_POLICY="ask"       # ask | yes | no  (can be overridden per session)
SEPARATE_PROFILE_DEFAULT="n"

# Preferred Chromium-based browsers for --app= / app-mode support
BROWSER_PREF=(brave brave-browser google-chrome-stable chromium chromium-browser)

# ---------- Terminal output helpers ----------
SEP="════════════════════════════════════════════"
say()    { printf "%b\n" "$*"; }
info()   { say "  [*] $*"; }
ok()     { say "  [✓] $*"; }
warn()   { say "  [!] $*"; }
err()    { say "  [✗] $*"; }
header() { printf "\n%s\n  %s\n%s\n" "$SEP" "$*" "$SEP"; }

# ---------- Interrupt / exit handling ----------
trap_exit() {
  printf "\n\n  Exiting WebApp Builder. Bye!\n\n"
  exit 0
}
trap trap_exit INT TERM

# ---------- dmenu wrappers ----------
# dmenu requires an active X11 $DISPLAY — it crashes on pure Wayland terminals
# without Xwayland. Only report dmenu as available when both conditions are met.
have_dmenu() { command -v dmenu >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; }

# dmenu_ask PROMPT [DEFAULT]
# Prints the user's reply to stdout.
dmenu_ask() {
  local prompt="$1" def="${2:-}"
  if ((DMENU_MODE)) && have_dmenu; then
    printf "%s" "$def" | dmenu -p "$prompt"
  else
    local reply
    printf "  %s " "$prompt" >/dev/tty
    [[ -n "$def" ]] && printf "[%s] " "$def" >/dev/tty
    read -r reply </dev/tty || true
    [[ -z "$reply" ]] && reply="$def"
    printf "%s" "$reply"
  fi
}

# dmenu_menu PROMPT ITEM ...
# Displays a numbered menu on /dev/tty (visible even inside $(...) substitution)
# and prints the selected item to stdout.
dmenu_menu() {
  local prompt="$1"; shift
  if ((DMENU_MODE)) && have_dmenu; then
    printf "%s\n" "$@" | dmenu -p "$prompt"
    return
  fi
  # TUI: write menu to /dev/tty so it's visible when called inside $(...)
  local i=1
  printf "\n  %s\n\n" "$prompt" >/dev/tty
  for item in "$@"; do
    printf "    %d)  %s\n" "$i" "$item" >/dev/tty
    ((i++))
  done
  printf "\n  Choice: " >/dev/tty
  local sel
  read -r sel </dev/tty || true
  if [[ "$sel" =~ ^[0-9]+$ ]]; then
    local arr=("$@") idx=$(( sel - 1 ))
    if (( idx >= 0 && idx < ${#arr[@]} )); then
      printf "%s" "${arr[$idx]}"
      return
    fi
  fi
  local lower="${sel,,}"
  for item in "$@"; do
    if [[ "${item,,}" == "$lower"* ]]; then
      printf "%s" "$item"
      return
    fi
  done
  printf ""
}

# ---------- Browser detection ----------
detect_browser() {
  for b in "${BROWSER_PREF[@]}"; do
    command -v "$b" >/dev/null 2>&1 && { printf '%s' "$b"; return; }
  done
  printf ''
}

# ---------- Safe app ID ----------
# Strips everything but lowercase alphanumeric chars; ensures first char is a letter.
make_safe_id() {
  local raw="$1" id
  id="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')"
  [[ -z "$id" ]] && id="webapp"
  [[ "$id" =~ ^[a-z] ]] || id="x${id}"
  printf '%s' "$id"
}

# ---------- Icon handling ----------
# Installs an icon by copying it directly into the XDG hicolor icon theme tree
# at ~/.local/share/icons/hicolor/<size>x<size>/apps/<name>.png
# This approach requires no display (works on X11, Wayland, and headless).
install_icon_size() {
  local size="$1" src="$2" name="$3"
  local dest_dir="$HOME/.local/share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$dest_dir"
  cp -f "$src" "${dest_dir}/${name}.png" || true
}

fetch_and_install_icon() {
  local ICON_URL="$1" ICON_NAME="$2"
  [[ -z "$ICON_URL" ]] && return 0
  command -v curl >/dev/null 2>&1 || { warn "curl not found; skipping icon."; return 0; }

  local TMP_ICON
  TMP_ICON="$(mktemp -t webapp_icon_XXXXXX)"
  if ! curl -fsSL "$ICON_URL" -o "$TMP_ICON"; then
    warn "Failed to download icon: $ICON_URL"
    rm -f "$TMP_ICON"
    return 0
  fi

  local FILETYPE
  FILETYPE="$(file -b --mime-type "$TMP_ICON" 2>/dev/null || true)"

  if [[ "$FILETYPE" == "image/svg+xml" ]] && command -v rsvg-convert >/dev/null 2>&1; then
    # Convert SVG to PNG at each standard size
    for s in 16 32 48 64 128 256 512; do
      local TMP_PNG
      TMP_PNG="$(mktemp -t webapp_icon_XXXXXX).png"
      rsvg-convert -w "$s" -h "$s" -o "$TMP_PNG" "$TMP_ICON"
      install_icon_size "$s" "$TMP_PNG" "$ICON_NAME"
      rm -f "$TMP_PNG"
    done
  elif [[ "$FILETYPE" == "image/png" ]] && command -v convert >/dev/null 2>&1; then
    # Resize PNG to each standard size using ImageMagick
    for s in 16 32 48 64 128 256 512; do
      local TMP_PNG
      TMP_PNG="$(mktemp -t webapp_icon_XXXXXX).png"
      convert "$TMP_ICON" -resize "${s}x${s}" "$TMP_PNG"
      install_icon_size "$s" "$TMP_PNG" "$ICON_NAME"
      rm -f "$TMP_PNG"
    done
  elif [[ "$FILETYPE" == "image/png" ]]; then
    # No ImageMagick: install original PNG at 512 only
    install_icon_size 512 "$TMP_ICON" "$ICON_NAME" || true
  else
    warn "Unsupported icon format ($FILETYPE); skipping icon."
  fi
  rm -f "$TMP_ICON"

  # Notify icon cache to refresh (display-independent, best-effort)
  command -v gtk-update-icon-cache >/dev/null 2>&1 && \
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
}

# =============================================================================
# Core app creation
# =============================================================================

create_webapp_core() {
  local APP_NAME="$1" APP_URL="$2" SEP="${3:-n}" ICON_URL="${4:-}"

  [[ -z "$APP_NAME" || -z "$APP_URL" ]] && { err "Name and URL are required."; return 1; }

  local APP_ID
  APP_ID="$(make_safe_id "$APP_NAME")"
  local BIN_DIR="$HOME/.local/bin"
  local APP_DIR="$HOME/.local/share/applications"
  local WEB_DIR="$HOME/.local/share/webapps"
  local APP_BIN="$BIN_DIR/$APP_ID"
  local DESKTOP="$APP_DIR/$APP_ID.desktop"
  local BROWSER_BIN
  BROWSER_BIN="$(detect_browser)"

  mkdir -p "$BIN_DIR" "$APP_DIR" "$WEB_DIR"

  # ---- Duplicate handling ----
  # Uses the global OVERWRITE_POLICY (ask|yes|no).
  # In batch mode the policy is set once before the loop begins.
  if [[ -e "$APP_BIN" || -e "$DESKTOP" ]]; then
    case "$OVERWRITE_POLICY" in
      yes) : ;;  # overwrite silently
      no)
        info "Already exists, skipping: $APP_NAME"
        return 0
        ;;
      ask)
        local ans
        if ((DMENU_MODE)); then
          ans="$(dmenu_menu "Overwrite ${APP_NAME}?" "Yes" "No")"
          [[ "$ans" == "Yes" ]] || { info "Skipped: $APP_NAME"; return 0; }
        else
          printf "\n  [?] '%s' already exists. Overwrite? (y/N): " "$APP_NAME"
          read -r ans || true
          [[ "${ans,,}" =~ ^y(es)?$ ]] || { info "Skipped: $APP_NAME"; return 0; }
        fi
        ;;
    esac
  fi

  # ---- Optional icon ----
  fetch_and_install_icon "$ICON_URL" "$APP_ID" || true

  # ---- Write launcher script ----
  # Detects Wayland vs X11 at runtime and adds the correct Chromium flags.
  # Falls back to xdg-open if no supported browser is found when launched.
  cat > "$APP_BIN" << LAUNCH
#!/usr/bin/env bash
# WebApp launcher: ${APP_NAME}
# URL:             ${APP_URL}
# Generated by webapp-builder.sh
set -euo pipefail

BROWSER_BIN="${BROWSER_BIN}"
APP_URL="${APP_URL}"
APP_ID="${APP_ID}"
PROFILE_DIR="\$HOME/.local/share/webapps/\${APP_ID}"
CLASS="WebApp-\${APP_ID}"
USE_SEPARATE="${SEP}"

chromium_launch() {
  local args=( --class="\$CLASS" --app="\$APP_URL" )
  # Add native Wayland flags when running under a Wayland compositor.
  # These are ignored gracefully on X11 / XWayland.
  if [[ -n "\${WAYLAND_DISPLAY:-}" ]]; then
    args+=( --ozone-platform=wayland --enable-features=UseOzonePlatform )
  fi
  if [[ "\${USE_SEPARATE,,}" == "y" ]]; then
    mkdir -p "\$PROFILE_DIR"
    args+=( --user-data-dir="\$PROFILE_DIR" --profile-directory=Default )
  fi
  exec "\$BROWSER_BIN" "\${args[@]}" >/dev/null 2>&1
}

xdg_launch() {
  # Fallback: open in the system default browser (address bar will be visible)
  exec xdg-open "\$APP_URL" >/dev/null 2>&1
}

if [[ -n "\$BROWSER_BIN" ]] && command -v "\$BROWSER_BIN" >/dev/null 2>&1; then
  chromium_launch
else
  xdg_launch
fi
LAUNCH
  chmod +x "$APP_BIN"

  # ---- Write .desktop entry ----
  {
    echo "[Desktop Entry]"
    echo "Version=1.1"
    echo "Name=${APP_NAME}"
    echo "Comment=WebApp: ${APP_URL}"
    echo "Exec=${APP_BIN}"
    echo "Terminal=false"
    echo "Type=Application"
    echo "Icon=${APP_ID}"
    echo "Categories=Network;"
    echo "StartupWMClass=WebApp-${APP_ID}"
  } > "$DESKTOP"

  ok "Created: ${APP_NAME}  →  ${APP_URL}"
}

# =============================================================================
# Preset categories
# Format per entry: "Display Name|URL"
# =============================================================================

declare -a CATEGORY_WORK=(
  "Microsoft Teams|https://teams.microsoft.com/"
  "Microsoft OneNote|https://m365.cloud.microsoft/launch/OneNote/"
  "Microsoft SharePoint|https://uddevalla.sharepoint.com/"
  "Microsoft Outlook|https://outlook.office.com/mail"
  "Microsoft Calendar|https://outlook.office.com/calendar/view/workweek"
  "Microsoft Loop|https://loop.cloud.microsoft/"
  "Microsoft OneDrive|https://uddevalla-my.sharepoint.com"
  "Microsoft Planner|https://planner.cloud.microsoft/"
  "Microsoft PowerPoint|https://powerpoint.cloud.microsoft/"
  "Microsoft Word|https://word.cloud.microsoft/"
  "Microsoft Excel|https://excel.cloud.microsoft"
  "Microsoft Lists|https://uddevalla-my.sharepoint.com/personal/nicklas_rudolfsson_uddevalla_se1/_layouts/15/Lists.aspx"
  "Microsoft Power Automate|https://make.powerautomate.com/"
  "Microsoft Stream|https://m365.cloud.microsoft/launch/Stream/"
  "Microsoft Visio|https://m365.cloud.microsoft/launch/Visio/"
  "Microsoft To Do|https://to-do.office.com/"
  "Microsoft Whiteboard|https://whiteboard.cloud.microsoft/"
  "Microsoft Copilot Studio|https://copilotstudio.microsoft.com/"
  "Microsoft Bookings|https://outlook.office.com/bookings/homepage"
  "Microsoft People|https://outlook.office.com/people"
  "Microsoft Insights|https://insights.cloud.microsoft"
  "Microsoft Forms|https://forms.office.com"
  "Inblicken|https://inblicken.uddevalla.se/"
  "Medvind|https://uddevalla.medvind.visma.com/MvWeb/"
  "Raindance|https://raindance.uddevalla.se/raindance/SSO/Saml"
  "Uddevalla.se|https://uddevalla.se"
)

declare -a CATEGORY_AI=(
  "Claude|https://claude.ai/"
  "Microsoft Copilot|https://m365.cloud.microsoft/chat/"
  "ChatGPT|https://chatgpt.com/"
  "Google Gemini|https://gemini.google.com/"
  "DeepSeek|https://chat.deepseek.com/"
  "Grok|https://x.ai/"
  "Perplexity|https://www.perplexity.ai/"
  "Le Chat (Mistral)|https://chat.mistral.ai/"
)

declare -a CATEGORY_OTHER=(
  "Google Gmail|https://mail.google.com/"
  "Google Calendar|https://calendar.google.com/"
  "Google Drive|https://drive.google.com/"
  "Facebook|https://www.facebook.com/"
  "Instagram|https://www.instagram.com/"
  "YouTube|https://www.youtube.com/"
  "Jellyfin|http://100.108.23.65:8096/"
  "GitHub|https://github.com/"
)

# ---------- Batch creation ----------
# Asks once about overwrite policy before processing, then restores the
# previous policy so other operations in the same session are unaffected.
batch_create_category() {
  local label="$1"; shift
  local cat_ref="$1"
  local -n _items="$cat_ref"

  header "Category: ${label}  (${#_items[@]} apps)"

  # Ask once how to handle existing apps (only when global policy is "ask")
  local saved_policy="$OVERWRITE_POLICY"
  if [[ "$OVERWRITE_POLICY" == "ask" ]]; then
    local batch_policy
    batch_policy="$(dmenu_menu \
      "Existing webapps — what to do?" \
      "Ask per app" \
      "Yes to all (overwrite)" \
      "No to all (skip)")"
    case "$batch_policy" in
      "Yes to all"*) OVERWRITE_POLICY="yes" ;;
      "No to all"*)  OVERWRITE_POLICY="no"  ;;
      *)             OVERWRITE_POLICY="ask" ;;  # "Ask per app" or empty
    esac
  fi

  local count=0
  for entry in "${_items[@]}"; do
    local name="${entry%%|*}" url="${entry#*|}"
    create_webapp_core "$name" "$url" "$SEPARATE_PROFILE_DEFAULT" ""
    ((count++)) || true
  done

  OVERWRITE_POLICY="$saved_policy"  # restore for subsequent operations
  ok "Done — ${count} apps processed in '${label}'."
}

# =============================================================================
# Interactive TUI
# =============================================================================

tui_main_menu() {
  while true; do
    header "WebApp Builder"
    local choice
    choice="$(dmenu_menu "Select action:" \
      "1  Create custom webapp" \
      "2  Browse & install from category" \
      "3  Install all: Work" \
      "4  Install all: AI" \
      "5  Install all: Other" \
      "6  Exit")"

    case "$choice" in
      1*) tui_create_custom       ;;
      2*) tui_browse_category     ;;
      3*) batch_create_category "Work"  CATEGORY_WORK  ;;
      4*) batch_create_category "AI"    CATEGORY_AI    ;;
      5*) batch_create_category "Other" CATEGORY_OTHER ;;
      6*|"Exit"|"exit"|"quit"|"q"|"Q")
          printf "\n  Goodbye!\n\n"
          exit 0
          ;;
      "")
          warn "No selection — try again or choose Exit."
          ;;
      *)
          warn "Unknown option: '$choice'"
          ;;
    esac

    printf "\n  Press Enter to continue..."
    read -r || true
  done
}

tui_create_custom() {
  header "Create Custom WebApp"

  local name url icon sep

  printf "  App name: "
  read -r name || true
  [[ -z "$name" ]] && { warn "No name entered. Cancelled."; return 0; }

  printf "  App URL:  "
  read -r url || true
  [[ -z "$url" ]] && { warn "No URL entered. Cancelled."; return 0; }

  printf "  Icon URL  (leave blank to skip): "
  read -r icon || true

  printf "\n  Use separate browser profile? (y/N): "
  read -r sep || true
  [[ "${sep,,}" =~ ^y(es)?$ ]] && sep="y" || sep="n"

  create_webapp_core "$name" "$url" "$sep" "$icon"
}

# Shows a numbered list of all apps in a chosen category.
# The user can install a single app, install all, or go back.
tui_browse_category() {
  header "Browse Category"

  local cat_choice
  cat_choice="$(dmenu_menu "Select category:" \
    "Work" "AI" "Other" "Back")"

  local cat_ref
  case "$cat_choice" in
    "Work")      cat_ref="CATEGORY_WORK"  ;;
    "AI")        cat_ref="CATEGORY_AI"    ;;
    "Other")     cat_ref="CATEGORY_OTHER" ;;
    "Back"|""|*) return 0 ;;
  esac

  # Build parallel name/url arrays from the chosen category
  local -n _cat_items="$cat_ref"
  local names=() urls=()
  for entry in "${_cat_items[@]}"; do
    names+=( "${entry%%|*}" )
    urls+=( "${entry#*|}" )
  done

  while true; do
    header "Category: ${cat_choice}  (${#names[@]} apps)"
    local i=1
    for n in "${names[@]}"; do
      printf "    %2d)  %-35s  %s\n" "$i" "$n" "${urls[$((i-1))]}"
      ((i++))
    done
    printf "\n     a)  Install ALL in this category"
    printf "\n     b)  Back\n"
    printf "\n  Choice (number / 'a' = all / 'b' = back): "

    local sel
    read -r sel || true
    sel="${sel,,}"

    # Back
    [[ "$sel" == "b" || "$sel" == "back" || -z "$sel" ]] && return 0

    # Install all
    if [[ "$sel" == "a" || "$sel" == "all" ]]; then
      batch_create_category "$cat_choice" "$cat_ref"
      return 0
    fi

    # Single app — resolve by number or name prefix
    local idx=-1
    if [[ "$sel" =~ ^[0-9]+$ ]]; then
      idx=$(( sel - 1 ))
    else
      for j in "${!names[@]}"; do
        if [[ "${names[$j],,}" == "$sel"* ]]; then
          idx=$j
          break
        fi
      done
    fi

    if (( idx < 0 || idx >= ${#names[@]} )); then
      warn "Invalid selection: '$sel'"
      printf "\n  Press Enter to try again..."
      read -r || true
      continue
    fi

    local sep
    printf "\n  Use separate browser profile? (y/N): "
    read -r sep || true
    [[ "${sep,,}" =~ ^y(es)?$ ]] && sep="y" || sep="n"

    create_webapp_core "${names[$idx]}" "${urls[$idx]}" "$sep" ""
    printf "\n  Press Enter to continue browsing..."
    read -r || true
  done
}

# =============================================================================
# dmenu flow  (single-pass, no persistent TTY loop)
# =============================================================================

dmenu_flow() {
  local choice
  choice="$(dmenu_menu "WebApp Builder:" \
    "Create custom" \
    "Browse: Work" \
    "Browse: AI" \
    "Browse: Other" \
    "All: Work" \
    "All: AI" \
    "All: Other" \
    "Exit")"

  case "$choice" in
    "Create custom")
      local name url icon sep
      name="$(dmenu_ask "App name:" "")"
      [[ -z "$name" ]] && { warn "No name. Aborted."; return 0; }
      url="$(dmenu_ask "App URL:" "https://")"
      [[ -z "$url" ]] && { warn "No URL. Aborted."; return 0; }
      icon="$(dmenu_ask "Icon URL (optional):" "")"
      sep="$(dmenu_menu "Separate browser profile?" "No" "Yes")"
      [[ "$sep" == "Yes" ]] && sep="y" || sep="n"
      create_webapp_core "$name" "$url" "$sep" "$icon"
      ;;
    "Browse: Work")
      local pick
      pick="$(printf '%s\n' "${CATEGORY_WORK[@]}" | sed 's/|.*$//' | dmenu -p "Work:")"
      [[ -z "$pick" ]] && return 0
      local url; url="$(printf '%s\n' "${CATEGORY_WORK[@]}" | grep "^${pick}|" | cut -d'|' -f2)"
      [[ -z "$url" ]] && { warn "Not found."; return 0; }
      create_webapp_core "$pick" "$url" "n" ""
      ;;
    "Browse: AI")
      local pick
      pick="$(printf '%s\n' "${CATEGORY_AI[@]}" | sed 's/|.*$//' | dmenu -p "AI:")"
      [[ -z "$pick" ]] && return 0
      local url; url="$(printf '%s\n' "${CATEGORY_AI[@]}" | grep "^${pick}|" | cut -d'|' -f2)"
      [[ -z "$url" ]] && { warn "Not found."; return 0; }
      create_webapp_core "$pick" "$url" "n" ""
      ;;
    "Browse: Other")
      local pick
      pick="$(printf '%s\n' "${CATEGORY_OTHER[@]}" | sed 's/|.*$//' | dmenu -p "Other:")"
      [[ -z "$pick" ]] && return 0
      local url; url="$(printf '%s\n' "${CATEGORY_OTHER[@]}" | grep "^${pick}|" | cut -d'|' -f2)"
      [[ -z "$url" ]] && { warn "Not found."; return 0; }
      create_webapp_core "$pick" "$url" "n" ""
      ;;
    "All: Work")  batch_create_category "Work"  CATEGORY_WORK  ;;
    "All: AI")    batch_create_category "AI"    CATEGORY_AI    ;;
    "All: Other") batch_create_category "Other" CATEGORY_OTHER ;;
    *)            : ;;  # Exit or empty — just quit
  esac
}

# =============================================================================
# CLI argument parsing
# =============================================================================

usage() {
  cat << USAGE

  Linux WebApp Builder

  Usage:
    $(basename "$0") [OPTIONS]

  Modes (mutually exclusive):
    (no args)                              Auto: dmenu if available, else TUI
    --tui                                  Force interactive terminal UI
    --dmenu                                Force dmenu mode
    --create-manual                        Create a single webapp non-interactively
      --name  "App Name"                     (required)
      --url   "https://example.com"          (required)
      --icon-url URL                         (optional)
      --separate y|n                         (optional, default: n)
    --create-category work|ai|other        Batch-create all apps in a category

  Options:
    --overwrite ask|yes|no                 How to handle existing webapps (default: ask)
    -h, --help                             Show this help text

USAGE
}

parse_args() {
  local mode="" name="" url="" icon_url="" separate="n" category=""

  # No arguments: auto-select mode
  if (($# == 0)); then
    if have_dmenu; then
      DMENU_MODE=1; dmenu_flow
    else
      TUI_MODE=1; tui_main_menu
    fi
    exit 0
  fi

  while (($#)); do
    case "$1" in
      --tui)             TUI_MODE=1;   mode="tui"      ;;
      --dmenu)           DMENU_MODE=1; mode="dmenu"    ;;
      --create-manual)   mode="manual"                 ;;
      --create-category) mode="category"; category="${2:-}"; shift ;;
      --name)            name="${2:-}";       shift    ;;
      --url)             url="${2:-}";        shift    ;;
      --icon-url)        icon_url="${2:-}";   shift    ;;
      --separate)        separate="${2:-n}";  shift    ;;
      --overwrite)       OVERWRITE_POLICY="${2:-ask}"; shift ;;
      -h|--help)         usage; exit 0 ;;
      *)
        err "Unknown argument: $1"
        usage
        exit 2
        ;;
    esac
    shift || true
  done

  case "$mode" in
    tui)
      tui_main_menu
      ;;
    dmenu)
      dmenu_flow
      ;;
    manual)
      [[ -n "$name" && -n "$url" ]] || {
        err "--name and --url are required for --create-manual"
        exit 2
      }
      create_webapp_core "$name" "$url" "$separate" "$icon_url"
      ;;
    category)
      case "${category,,}" in
        work)  batch_create_category "Work"  CATEGORY_WORK  ;;
        ai)    batch_create_category "AI"    CATEGORY_AI    ;;
        other) batch_create_category "Other" CATEGORY_OTHER ;;
        *)
          err "Unknown category: '$category' — use work|ai|other"
          exit 2
          ;;
      esac
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

# ---------- Entry point ----------
main() {
  parse_args "$@"
}

main "$@"
