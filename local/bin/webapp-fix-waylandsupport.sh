#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# webapp-fix-waylandsupport.sh — Fix Wayland support in existing web app launchers
#
# Updates all web app launchers in ~/.local/bin/ that use a hardcoded
# BROWSER_BIN="brave" (or similar) to instead auto-detect the session type
# at runtime:
#   - Wayland: uses brave-wayland wrapper (ozone/wayland flags)
#   - X11:     uses /usr/bin/brave directly
#
# Safe to run multiple times — skips launchers already updated.
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────

LOCAL_BIN="${HOME}/.local/bin"

# The X11 fallback browser binary embedded in fixed launchers
X11_BROWSER="/usr/bin/brave"

# The Wayland wrapper name (must exist in PATH when launchers are run)
WAYLAND_WRAPPER="brave-wayland"

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────────────────────────────────────────

say()    { printf "%b\n" "$*"; }
ok()     { say "  [OK]     $*"; }
info()   { say "  [skip]   $*"; }
warn()   { say "  [!]      $*"; }
updated(){ say "  [fixed]  $*"; }
err()    { say "  [X]      $*" >&2; }

# ─────────────────────────────────────────────────────────────────────────────
# DETECTION
# ─────────────────────────────────────────────────────────────────────────────

# Returns true if the file looks like a webapp launcher (has APP_URL and BROWSER_BIN)
is_webapp_launcher() {
    local f="$1"
    grep -q 'APP_URL=' "$f" 2>/dev/null && grep -q 'BROWSER_BIN=' "$f" 2>/dev/null
}

# Returns true if the launcher already has Wayland auto-detection
already_fixed() {
    local f="$1"
    grep -q 'WAYLAND_DISPLAY' "$f" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# FIX
# ─────────────────────────────────────────────────────────────────────────────

fix_launcher() {
    local f="$1"

    # Write a Python-free in-place replacement using a temp file
    local tmp
    tmp="$(mktemp)"

    # Read the file and replace the BROWSER_BIN= line with the auto-detect block
    awk -v x11="$X11_BROWSER" -v wl="$WAYLAND_WRAPPER" '
    /^BROWSER_BIN=/ {
        print "# Auto-detect session type at runtime:"
        print "# - Wayland: use " wl " wrapper (ozone/wayland flags)"
        print "# - X11:     use " x11 " directly"
        print "if [[ -n \"${WAYLAND_DISPLAY:-}\" ]] && command -v " wl " >/dev/null 2>&1; then"
        print "    BROWSER_BIN=\"" wl "\""
        print "else"
        print "    BROWSER_BIN=\"" x11 "\""
        print "fi"
        next
    }
    { print }
    ' "$f" > "$tmp"

    # Preserve permissions and replace original
    chmod --reference="$f" "$tmp"
    mv "$tmp" "$f"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────

main() {
    say ""
    say "  ╔══════════════════════════════════════════════════╗"
    say "  ║   WebApp Wayland Fix — NIRUCON Edition           ║"
    say "  ╠══════════════════════════════════════════════════╣"
    say "  ║   Scanning: $LOCAL_BIN"
    say "  ╚══════════════════════════════════════════════════╝"
    say ""

    local fixed=0 skipped=0 total=0

    for f in "$LOCAL_BIN"/*; do
        [[ -f "$f" ]] || continue
        [[ -x "$f" ]] || continue

        if ! is_webapp_launcher "$f"; then
            continue
        fi

        ((total++)) || true

        if already_fixed "$f"; then
            info "$(basename "$f") — already has Wayland support"
            ((skipped++)) || true
            continue
        fi

        fix_launcher "$f"
        updated "$(basename "$f")"
        ((fixed++)) || true
    done

    say ""
    say "  ────────────────────────────────────────────────────"
    ok  "Done — $fixed launcher(s) fixed, $skipped already up to date (${total} total)"
    say ""

    if (( fixed > 0 )); then
        say "  Each launcher now auto-detects at runtime:"
        say "    Wayland  →  $WAYLAND_WRAPPER"
        say "    X11      →  $X11_BROWSER"
        say ""
    fi
}

main "$@"
