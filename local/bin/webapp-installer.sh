#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# webapp-installer.sh — Linux WebApp Installer (NIRUCON Edition)
#
# Creates browser-based web app launchers for both X11 (dwm) and Wayland (niri).
# Each generated launcher auto-detects the session type at runtime:
#   - Wayland: uses brave-wayland wrapper (ozone/wayland flags)
#   - X11:     uses /usr/bin/brave directly
#
# Creates:
#   ~/.local/bin/<app_id>                          — executable launcher
#   ~/.local/share/applications/<app_id>.desktop   — desktop entry for wofi/rofi
#
# Usage:
#   ./webapp-installer.sh                          — interactive terminal menu
#   ./webapp-installer.sh --create-manual \
#       --name "App" --url "https://example.com"   — non-interactive single app
#   ./webapp-installer.sh --create-category work   — batch create work apps
#   ./webapp-installer.sh --create-category private
#   ./webapp-installer.sh --overwrite yes ...      — skip overwrite prompt
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────

OVERWRITE_POLICY="ask"        # ask | yes | no
SEPARATE_PROFILE_DEFAULT="n"  # default isolated profile for batch creation

# Absolute paths searched for the system browser (X11 fallback in launchers)
BROWSER_PREF=(/usr/bin/brave /usr/bin/brave-browser /usr/bin/google-chrome-stable /usr/bin/chromium)

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────────────────────────────────────────

say()  { printf "%b\n" "$*"; }
info() { say "  [*] $*"; }
ok()   { say "  [OK] $*"; }
warn() { say "  [!] $*"; }
err()  { say "  [X] $*" >&2; }

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────

# Returns absolute path of the system browser binary for X11 fallback.
detect_browser_bin() {
    for b in "${BROWSER_PREF[@]}"; do
        [[ -x "$b" ]] && printf '%s' "$b" && return
    done
    printf ''
}

# Convert a display name to a safe lowercase alphanumeric identifier.
make_safe_id() {
    local raw="$1"
    local id
    id="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')"
    [[ -z "$id" ]] && id="webapp"
    [[ "$id" =~ ^[a-z] ]] || id="x${id}"
    printf '%s' "$id"
}

# ─────────────────────────────────────────────────────────────────────────────
# ICON INSTALLATION (optional)
# ─────────────────────────────────────────────────────────────────────────────

install_icon_size() {
    local size="$1" src="$2" name="$3"
    xdg-icon-resource install --context apps --size "$size" "$src" "$name" >/dev/null 2>&1 || true
}

fetch_and_install_icon() {
    local icon_url="$1" icon_name="$2"
    [[ -z "$icon_url" ]] && return 0

    command -v curl >/dev/null 2>&1 || { warn "curl not found — skipping icon"; return 0; }

    local tmp
    tmp="$(mktemp -t webapp_icon_XXXXXX)"
    if ! curl -fsSL "$icon_url" -o "$tmp"; then
        warn "Failed to download icon: $icon_url"
        rm -f "$tmp"
        return 0
    fi

    local filetype
    filetype="$(file -b --mime-type "$tmp" 2>/dev/null || true)"

    if [[ "$filetype" == "image/svg+xml" ]] && command -v rsvg-convert >/dev/null 2>&1; then
        for s in 16 24 32 48 64 96 128 256 512; do
            local resized
            resized="$(mktemp -t webapp_icon_${s}_XXXXXX).png"
            rsvg-convert -w "$s" -h "$s" -o "$resized" "$tmp"
            install_icon_size "$s" "$resized" "$icon_name"
            rm -f "$resized"
        done
    elif [[ "$filetype" == "image/png" ]] && command -v convert >/dev/null 2>&1; then
        for s in 16 24 32 48 64 96 128 256 512; do
            local resized
            resized="$(mktemp -t webapp_icon_${s}_XXXXXX).png"
            convert "$tmp" -resize "${s}x${s}" "$resized"
            install_icon_size "$s" "$resized" "$icon_name"
            rm -f "$resized"
        done
    else
        install_icon_size 512 "$tmp" "$icon_name" || true
    fi

    rm -f "$tmp"
    ok "Icon installed: $icon_name"
}

# ─────────────────────────────────────────────────────────────────────────────
# CORE CREATION
# ─────────────────────────────────────────────────────────────────────────────

create_webapp_core() {
    local app_name="$1" app_url="$2" sep="${3:-n}" icon_url="${4:-}"

    [[ -z "$app_name" || -z "$app_url" ]] && { err "Name and URL are required"; return 1; }

    local app_id
    app_id="$(make_safe_id "$app_name")"

    local local_bin="$HOME/.local/bin"
    local apps_dir="$HOME/.local/share/applications"
    local app_bin="$local_bin/${app_id}"
    local desktop_file="$apps_dir/${app_id}.desktop"
    local browser_bin
    browser_bin="$(detect_browser_bin)"

    [[ -z "$browser_bin" ]] && { err "No supported browser found — aborting"; return 1; }

    mkdir -p "$local_bin" "$apps_dir" "$HOME/.local/share/webapps"

    # ── Duplicate handling ────────────────────────────────────────────────────
    if [[ -e "$app_bin" || -e "$desktop_file" ]]; then
        case "$OVERWRITE_POLICY" in
            yes) : ;;
            no)
                info "Already exists, skipping: $app_name"
                return 0
                ;;
            ask)
                local ans
                read -r -p "  Overwrite '$app_name'? (y/n): " ans || true
                [[ "${ans,,}" =~ ^(y|yes)$ ]] || { info "Skipped: $app_name"; return 0; }
                ;;
        esac
    fi

    # ── Optional icon ─────────────────────────────────────────────────────────
    fetch_and_install_icon "$icon_url" "$app_id" || true

    # ── Launcher script ───────────────────────────────────────────────────────
    # The launcher detects at runtime whether we are in Wayland or X11 and
    # picks the appropriate browser binary accordingly.
    cat > "$app_bin" <<LAUNCHER
#!/usr/bin/env bash
set -euo pipefail
# WebApp launcher — generated by webapp-installer.sh
# Auto-detects Wayland vs X11 at runtime.

APP_URL="${app_url}"
APP_ID="${app_id}"
PROFILE_DIR="\$HOME/.local/share/webapps/\${APP_ID}"
CLASS="WebApp-\${APP_ID}"

# Use brave-wayland wrapper in Wayland sessions, system brave in X11
if [[ -n "\${WAYLAND_DISPLAY:-}" ]] && command -v brave-wayland >/dev/null 2>&1; then
    BROWSER_BIN="brave-wayland"
else
    BROWSER_BIN="${browser_bin}"
fi

ARGS=( --class="\$CLASS" --app="\$APP_URL" )
if [[ "${sep,,}" == "y" ]]; then
    mkdir -p "\$PROFILE_DIR"
    ARGS+=( --user-data-dir="\$PROFILE_DIR" --profile-directory=Default )
fi

exec "\$BROWSER_BIN" "\${ARGS[@]}" >/dev/null 2>&1 &
LAUNCHER
    chmod +x "$app_bin"

    # ── Desktop entry ─────────────────────────────────────────────────────────
    cat > "$desktop_file" <<DESKTOP
[Desktop Entry]
Name=${app_name}
Comment=WebApp — ${app_url}
Exec=${app_bin}
Terminal=false
Type=Application
Icon=${app_id}
Categories=Network;
StartupWMClass=WebApp-${app_id}
DESKTOP

    ok "Created: $app_name  →  $app_bin"
}

# ─────────────────────────────────────────────────────────────────────────────
# PRESET CATEGORIES
# ─────────────────────────────────────────────────────────────────────────────

declare -a CATEGORY_WORK=(
    "Microsoft Teams|https://teams.microsoft.com/"
    "Microsoft OneNote|https://m365.cloud.microsoft/launch/OneNote/"
    "Microsoft SharePoint|https://uddevalla.sharepoint.com/"
    "Microsoft Outlook|https://outlook.office.com/mail"
    "Microsoft Calendar|https://outlook.office.com/calendar/view/workweek"
    "Microsoft Loop|https://loop.cloud.microsoft/"
    "Microsoft OneDrive|https://uddevalla-my.sharepoint.com"
    "Microsoft Planner|https://planner.cloud.microsoft/"
    "Microsoft Copilot (AI)|https://m365.cloud.microsoft/chat/"
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

declare -a CATEGORY_PRIVATE=(
    "ChatGPT (AI)|https://chatgpt.com/"
    "GrokAI (AI)|https://x.ai/"
    "Google Gemini (AI)|https://gemini.google.com/"
    "Google Gmail|https://mail.google.com/"
    "Google Calendar|https://calendar.google.com/"
    "Google Drive|https://drive.google.com/"
    "Facebook|https://www.facebook.com/"
    "Instagram|https://www.instagram.com/"
    "Claude (AI)|https://claude.ai/"
    "Jellyfin|http://100.108.23.65:8096/"
    "DeepSeek (AI)|https://chat.deepseek.com/"
)

batch_create_category() {
    local category_name="$1"
    local -n _items="$2"
    local count=0

    say ""
    say "  Creating category: $category_name (${#_items[@]} apps)"
    say "  ────────────────────────────────────────"

    for entry in "${_items[@]}"; do
        local name="${entry%%|*}"
        local url="${entry#*|}"
        create_webapp_core "$name" "$url" "$SEPARATE_PROFILE_DEFAULT" ""
        ((count++)) || true
    done

    say ""
    ok "Category '$category_name': $count apps processed."
}

# ─────────────────────────────────────────────────────────────────────────────
# INTERACTIVE TERMINAL MENU
# ─────────────────────────────────────────────────────────────────────────────

interactive_flow() {
    say ""
    say "  ╔══════════════════════════════════════════╗"
    say "  ║     WebApp Installer — NIRUCON Edition   ║"
    say "  ╠══════════════════════════════════════════╣"
    say "  ║  1)  Create single app (manual)          ║"
    say "  ║  2)  Create all Work apps                ║"
    say "  ║  3)  Create all Private apps             ║"
    say "  ║  4)  Exit                                ║"
    say "  ╚══════════════════════════════════════════╝"
    say ""
    read -r -p "  Your choice [1-4]: " choice

    case "$choice" in
        1)
            say ""
            local name url icon sep
            read -r -p "  App name: " name
            [[ -z "$name" ]] && { warn "No name given — aborting"; return 0; }
            read -r -p "  App URL:  " url
            [[ -z "$url" ]]  && { warn "No URL given — aborting"; return 0; }
            read -r -p "  Icon URL (optional, Enter to skip): " icon || true
            read -r -p "  Separate browser profile? (y/n) [n]: " sep || true
            sep="${sep:-n}"
            say ""
            create_webapp_core "$name" "$url" "$sep" "${icon:-}"
            ;;
        2)
            batch_create_category "Work" CATEGORY_WORK
            ;;
        3)
            batch_create_category "Private" CATEGORY_PRIVATE
            ;;
        4|"")
            info "Exiting."
            ;;
        *)
            err "Invalid choice: $choice"
            exit 1
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# USAGE
# ─────────────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF

Usage:
  $(basename "$0")                                        Interactive menu
  $(basename "$0") --create-manual --name "X" --url "Y"  Create single app
  $(basename "$0") --create-category work                 Batch create Work apps
  $(basename "$0") --create-category private              Batch create Private apps

Options:
  --name        App display name
  --url         App URL
  --icon-url    Optional icon URL (png or svg)
  --separate    Isolated browser profile: y|n  (default: n)
  --overwrite   Overwrite policy: ask|yes|no   (default: ask)
  -h|--help     Show this help

EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# ARGUMENT PARSING
# ─────────────────────────────────────────────────────────────────────────────

parse_args() {
    if (($# == 0)); then
        interactive_flow
        exit 0
    fi

    local mode="" name="" url="" icon_url="" separate="n" category=""

    while (($#)); do
        case "$1" in
            --create-manual)   mode="manual" ;;
            --create-category) mode="category"; category="${2:-}"; shift ;;
            --name)            name="${2:-}"; shift ;;
            --url)             url="${2:-}"; shift ;;
            --icon-url)        icon_url="${2:-}"; shift ;;
            --separate)        separate="${2:-n}"; shift ;;
            --overwrite)       OVERWRITE_POLICY="${2:-ask}"; shift ;;
            -h|--help)         usage; exit 0 ;;
            *)                 err "Unknown argument: $1"; usage; exit 2 ;;
        esac
        shift || true
    done

    case "$mode" in
        manual)
            [[ -n "$name" && -n "$url" ]] || { err "--create-manual requires --name and --url"; exit 2; }
            create_webapp_core "$name" "$url" "$separate" "$icon_url"
            ;;
        category)
            case "${category,,}" in
                work)    batch_create_category "Work"    CATEGORY_WORK ;;
                private) batch_create_category "Private" CATEGORY_PRIVATE ;;
                *)       err "Unknown category: $category (use work|private)"; exit 2 ;;
            esac
            ;;
        *)
            err "No valid mode specified"
            usage
            exit 2
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

main() {
    parse_args "$@"
}

main "$@"
