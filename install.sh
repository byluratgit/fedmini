#!/bin/bash
# fednirinoc v0.5.0-modified
# Post-install script: Fedora minimal TTY -> niri + Noctalia (Direct Install)
# Removed: Cinnamon Desktop group installation and LGL Tools prompts.
# Run as your regular user with sudo access.

set -euo pipefail

SCRIPT_USER="${USER}"
SCRIPT_HOME="${HOME}"
NIRI_CONFIG_DIR="${SCRIPT_HOME}/.config/niri"
NIRI_CONFIG="${NIRI_CONFIG_DIR}/config.kdl"
ADW_AVAILABLE=false
NOCTALIA_PACKAGE="noctalia-git"

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

info()    { echo "  [INFO] $*"; }
success() { echo "  [ OK ] $*"; }
warn()    { echo "  [WARN] $*"; }
die()     { echo "  [FAIL] $*" >&2; exit 1; }

usage() {
        cat <<'USAGE'
Usage: install.sh [--help]

Post-install script for Fedora minimal -> niri + Noctalia.

Options:
    -h, --help    Show this help and exit
USAGE
}

# Show help and exit
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
fi

require_sudo() {
    if ! sudo -v 2>/dev/null; then
        die "sudo access required. Run as a regular user with sudo."
    fi
}

show_noctalia_notice() {
    echo ""
    echo "  ----------------------------------------------------------------"
    echo "          Noctalia"
    echo "  ----------------------------------------------------------------"
    echo "  Noctalia v5 (noctalia-git) will be installed from the"
    echo "  lionheartp/Hyprland COPR. It is beta software."
    echo "  ----------------------------------------------------------------"
}

# ─────────────────────────────────────────────
# Phase 0: DNF configuration
# ─────────────────────────────────────────────

configure_dnf() {
    echo ""
    echo "  ----------------------------------------------------------------"
    echo "          DNF Configuration"
    echo "  ----------------------------------------------------------------"
    echo "  installonly_limit  — max versions of install-only packages kept"
    echo "                       (e.g. kernel versions retained after upgrades)"
    echo "  max_parallel_downloads — concurrent package downloads"
    echo ""
    echo "  WARNING: Setting these values too high can cause instability."
    echo "  Defaults are 3 and 5. Press Enter to keep defaults."
    echo "  ----------------------------------------------------------------"
    echo ""

    read -rp "  installonly_limit [3]: " dnf_installonly
    read -rp "  max_parallel_downloads [5]: " dnf_parallel

    # Fall back to defaults if empty or non-numeric
    [[ "${dnf_installonly}" =~ ^[0-9]+$ ]] || dnf_installonly=3
    [[ "${dnf_parallel}" =~ ^[0-9]+$ ]]    || dnf_parallel=5

    DNF_CONF="/etc/dnf/dnf.conf"

    if grep -q "^installonly_limit=" "${DNF_CONF}" 2>/dev/null; then
        sudo sed -i "s/^installonly_limit=.*/installonly_limit=${dnf_installonly}/" "${DNF_CONF}"
    else
        echo "installonly_limit=${dnf_installonly}" | sudo tee -a "${DNF_CONF}" > /dev/null
    fi

    if grep -q "^max_parallel_downloads=" "${DNF_CONF}" 2>/dev/null; then
        sudo sed -i "s/^max_parallel_downloads=.*/max_parallel_downloads=${dnf_parallel}/" "${DNF_CONF}"
    else
        echo "max_parallel_downloads=${dnf_parallel}" | sudo tee -a "${DNF_CONF}" > /dev/null
    fi

    success "DNF config updated (installonly_limit=${dnf_installonly}, max_parallel_downloads=${dnf_parallel})"
}

# ─────────────────────────────────────────────
# Preflight checks
# ─────────────────────────────────────────────

preflight() {
    info "Running preflight checks..."

    require_sudo

    # Must not be root
    if [[ "${EUID}" -eq 0 ]]; then
        die "Do not run as root. Run as your regular user."
    fi

    # Internet check
    if ! ping -c1 -W3 8.8.8.8 &>/dev/null; then
        die "No internet connection detected."
    fi

    # Fedora check
    if ! grep -q "Fedora" /etc/os-release 2>/dev/null; then
        die "This script is for Fedora only."
    fi

    # adw-gtk3-theme package name check
    if ! sudo dnf info adw-gtk3-theme &>/dev/null; then
        warn "adw-gtk3-theme not found in repos. GTK theming step will be skipped."
        ADW_AVAILABLE=false
    else
        ADW_AVAILABLE=true
    fi

    success "Preflight passed. User: ${SCRIPT_USER}, Home: ${SCRIPT_HOME}"
}

# ─────────────────────────────────────────────
# Phase 1b: Display manager (Kept for lightdm/greeter)
# ─────────────────────────────────────────────

ensure_display_manager() {
    info "Ensuring lightdm and GTK greeter are installed..."

    sudo dnf install -y lightdm lightdm-gtk-greeter

    sudo systemctl set-default graphical.target
    success "Default target set to graphical.target."

    sudo systemctl enable lightdm
    success "lightdm enabled."
}

# ─────────────────────────────────────────────
# Phase 2: Repos
# ─────────────────────────────────────────────

setup_repos() {
    info "Enabling repos..."

    # niri COPR (avengemedia/danklinux)
    if ! sudo dnf copr list --enabled 2>/dev/null | grep -q "avengemedia/danklinux"; then
        sudo dnf copr enable -y avengemedia/danklinux
        success "Enabled COPR: avengemedia/danklinux"
    else
        info "COPR avengemedia/danklinux already enabled."
    fi

    # Noctalia COPR
    if ! sudo dnf copr list --enabled 2>/dev/null | grep -q "lionheartp/Hyprland"; then
        sudo dnf copr enable -y lionheartp/Hyprland
        success "Enabled COPR: lionheartp/Hyprland"
    else
        info "COPR lionheartp/Hyprland already enabled."
    fi

    sudo dnf makecache -q
    success "Repos configured."
}

# ─────────────────────────────────────────────
# Phase 3: Packages
# ─────────────────────────────────────────────

install_packages() {
    info "Installing packages..."

    PACKAGES=(
        # Core compositor
        niri

        # Noctalia runtime deps
        brightnessctl
        ImageMagick
        python3
        git

        # Portals (Crucial since we don't have full Cinnamon/GNOME stack now)
        xdg-desktop-portal
        xdg-desktop-portal-gtk
        
        # Essential base components previously provided by Cinnamon
        polkit
        gnome-keyring
        gnome-keyring-pam
        gnome-menus
        gtk3
        gtk4
        
        # Qt theming
        qt6ct
        qt5ct

        # XDG user directories
        xdg-user-dirs

        # Terminal
        alacritty

        # Optional but integrated by Noctalia
        cliphist
    )

    if [[ "${ADW_AVAILABLE}" == "true" ]]; then
        PACKAGES+=(adw-gtk3-theme)
    fi

    sudo dnf install -y \
        --exclude=power-profiles-daemon \
        --skip-broken \
        "${PACKAGES[@]}"
    success "Packages installed."

    info "Installing Noctalia v5 beta from lionheartp/Hyprland COPR..."
    NOCTALIA_REPO_ARGS=(
        --exclude=power-profiles-daemon
        --skip-broken
    )

    if rpm -q "${NOCTALIA_PACKAGE}" &>/dev/null; then
        sudo dnf reinstall -y "${NOCTALIA_REPO_ARGS[@]}" "${NOCTALIA_PACKAGE}"
    else
        sudo dnf install -y "${NOCTALIA_REPO_ARGS[@]}" "${NOCTALIA_PACKAGE}"
    fi
    success "Noctalia installed from lionheartp/Hyprland."

    xdg-user-dirs-update
    success "XDG user directories created."
}

# ─────────────────────────────────────────────
# Phase 4: Niri session file
# ─────────────────────────────────────────────

ensure_niri_session_file() {
    info "Checking for niri wayland session file..."

    NIRI_SESSION="/usr/share/wayland-sessions/niri.desktop"

    if [[ -f "${NIRI_SESSION}" ]]; then
        success "niri.desktop already present — lightdm will offer Niri session."
        return
    fi

    warn "niri.desktop not found — writing manually so lightdm can see the session."

    sudo mkdir -p /usr/share/wayland-sessions
    sudo tee "${NIRI_SESSION}" > /dev/null << 'EOF'
[Desktop Entry]
Name=Niri
Comment=A scrollable-tiling Wayland compositor
Exec=niri-session
Type=Application
DesktopNames=niri
EOF

    success "Wrote ${NIRI_SESSION}"
}

# ─────────────────────────────────────────────
# Phase 5: Niri config
# ─────────────────────────────────────────────

configure_niri() {
    info "Configuring niri..."

    mkdir -p "${NIRI_CONFIG_DIR}"

    # Copy default config if none exists
    if [[ ! -f "${NIRI_CONFIG}" ]]; then
        DEFAULT_CONFIG=$(rpm -ql niri 2>/dev/null | grep "default-config.kdl" | head -1)
        if [[ -n "${DEFAULT_CONFIG}" && -f "${DEFAULT_CONFIG}" ]]; then
            cp "${DEFAULT_CONFIG}" "${NIRI_CONFIG}"
            info "Copied default config from ${DEFAULT_CONFIG}"
        else
            # Fallback: create minimal stub
            touch "${NIRI_CONFIG}"
            warn "No default config found in niri package. Created empty config.kdl."
        fi
    else
        info "config.kdl already exists — leaving untouched, appending only."
    fi

    # Comment out spawn-at-startup "waybar" if present
    if grep -q '^spawn-at-startup "waybar"' "${NIRI_CONFIG}"; then
        sed -i 's|^spawn-at-startup "waybar"|// spawn-at-startup "waybar"  // disabled: Noctalia replaces waybar|' "${NIRI_CONFIG}"
        success "Commented out waybar spawn."
    else
        info "No active waybar spawn found."
    fi

    # Append fednirinoc block (idempotent — skip if already present)
    if grep -q "# fednirinoc" "${NIRI_CONFIG}"; then
        info "fednirinoc config block already present — skipping append."
        return
    fi

    cat >> "${NIRI_CONFIG}" << 'EOF'

// ---------------------------------------------
// fednirinoc -- appended by install.sh v0.5.0-modified
// ---------------------------------------------

// Updates the D-Bus and systemd user environment
spawn-at-startup "dbus-update-activation-environment" "--systemd" "--all"

EOF

    cat >> "${NIRI_CONFIG}" << 'EOF'
// Noctalia shell (v5)
spawn-at-startup "noctalia"

EOF

    cat >> "${NIRI_CONFIG}" << 'EOF'
// Uncomment if apps fail to focus when launched via Noctalia
// debug {
//     honor-xdg-activation-with-invalid-serial
// }

// OUTPUT CONFIGURATION
// After first login run: niri msg outputs
// Note your output name and mode, then uncomment and edit below, then:
//   niri msg action quit
//
// output "Virtual-1" {
//     mode "1920x1080@60.000"
//     scale 1.0
//     transform "normal"
// }

// # fednirinoc
EOF

    success "Appended niri config block."
}

# ─────────────────────────────────────────────
# Phase 6: Portal config
# ─────────────────────────────────────────────

configure_portals() {
    info "Writing portal config..."

    PORTAL_CONF="${SCRIPT_HOME}/.config/xdg-desktop-portal/niri-portals.conf"
    mkdir -p "${SCRIPT_HOME}/.config/xdg-desktop-portal"

    if [[ -f "${PORTAL_CONF}" ]]; then
        info "niri-portals.conf already exists — skipping."
        return
    fi

    cat > "${PORTAL_CONF}" << 'EOF'
[preferred]
default=gnome;gtk;
org.freedesktop.impl.portal.Access=gtk;
org.freedesktop.impl.portal.Notification=gtk;
org.freedesktop.impl.portal.Secret=gnome-keyring;
org.freedesktop.impl.portal.FileChooser=gtk;
EOF

    success "Portal config written."
}

# ─────────────────────────────────────────────
# Phase 7: System environment
# ─────────────────────────────────────────────

configure_system_env() {
    info "Writing system environment vars..."

    ENV_FILE="/etc/environment"
    ENV_LINE='QT_QPA_PLATFORMTHEME=qt6ct'

    if grep -q "QT_QPA_PLATFORMTHEME" "${ENV_FILE}" 2>/dev/null; then
        info "QT_QPA_PLATFORMTHEME already set in ${ENV_FILE} — skipping."
    else
        echo "${ENV_LINE}" | sudo tee -a "${ENV_FILE}" > /dev/null
        success "Added ${ENV_LINE} to ${ENV_FILE}"
    fi
}

# ─────────────────────────────────────────────
# Phase 8: GTK theme
# ─────────────────────────────────────────────

configure_gtk_theme() {
    if [[ "${ADW_AVAILABLE}" != "true" ]]; then
        warn "Skipping GTK theme — adw-gtk3-theme not available."
        return
    fi

    info "Applying GTK theme..."

    AUTOSTART_DIR="${SCRIPT_HOME}/.config/autostart"
    AUTOSTART_FILE="${AUTOSTART_DIR}/fednirinoc-gtk-theme.desktop"

    mkdir -p "${AUTOSTART_DIR}"

    cat > "${AUTOSTART_FILE}" << EOF
[Desktop Entry]
Type=Application
Name=fednirinoc GTK theme setup
Exec=bash -c 'gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark && gsettings set org.gnome.desktop.interface color-scheme prefer-dark && rm -f ${AUTOSTART_FILE}'
X-GNOME-Autostart-enabled=true
EOF

    success "GTK theme autostart registered (runs once on first login)."
}

# ─────────────────────────────────────────────
# Phase 10: Post-install banner + reboot prompt
# ─────────────────────────────────────────────

display_banner() {
    echo ""
    echo "================================================================"
    echo "  fednirinoc v0.5.0-modified -- Install Complete"
    echo "================================================================"
    echo ""
    echo "  TO START:"
    echo "    Reboot -> log in via the display manager -> select 'Niri'"
    echo "    from the session menu (gear/cog icon at login screen)."
    echo ""
    echo "  DISPLAY CONFIGURATION (after first login, inside niri):"
    echo "    1. Run: niri msg outputs"
    echo "    2. Note your output name (e.g. eDP-1) und mode"
    echo "       (e.g. 1920x1080@60.000)"
    echo "    3. Edit: ~/.config/niri/config.kdl"
    echo "    4. Find the OUTPUT CONFIGURATION section and uncomment:"
    echo ""
    echo "         output \"YOUR-OUTPUT-NAME\" {"
    echo "             mode \"WIDTHxHEIGHT@REFRESH\""
    echo "             scale 1.0"
    echo "             transform \"normal\""
    echo "         }"
    echo ""
    echo "    5. Restart niri: niri msg action quit"
    echo ""
    echo "  KNOWN ISSUE:"
    echo "    - Noctalia may not appear the first time you run Niri after first boot"
    echo "      Log back out, select Niri again, and it will start correctly."
    echo ""
    echo "================================================================"
    echo ""
    echo "  !! MAKE A NOTE OF THE ABOVE BEFORE REBOOTING !!"
    echo ""
    read -rp "  Reboot now? [y/N] " yn_reboot
    if [[ "${yn_reboot,,}" == "y" ]]; then
        sudo reboot
    else
        echo ""
        echo "  Reboot manually when ready: sudo reboot"
        echo ""
    fi
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

main() {
    echo ""
    echo "  fednirinoc v0.5.0-modified -- Fedora minimal -> niri + Noctalia (Direct)"
    echo "  ------------------------------------------------------------------------"
    echo ""

    show_noctalia_notice
    
    # Directly proceed without asking for Cinnamon
    preflight
    configure_dnf
    ensure_display_manager
    setup_repos
    install_packages
    ensure_niri_session_file
    configure_niri
    configure_portals
    configure_system_env
    configure_gtk_theme
    # LGL tools prompt removed
    display_banner
}

main