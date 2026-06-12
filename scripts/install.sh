#!/usr/bin/env bash
#
# PSP Crypto Platform installer.
#
#   bash <(curl -sSL https://raw.githubusercontent.com/crypto-chiefs/psp-install/main/scripts/install.sh)
#
# Supported: Linux (Debian/Ubuntu, RHEL/Fedora, openSUSE, Arch, Alpine),
# WSL2, macOS, Windows (run inside Git Bash). Linux installs need root.
#
# Environment overrides:
#   WL_LICENSE_KEY    installation key (skips the prompt)
#   WL_MODE           server | local (skips the prompt)
#   WL_DIR            install directory (default: /opt/psp-crypto,
#                     ~/psp-crypto on macOS/Windows)
#   WL_CHANNEL        release branch (default: stable)
#   WL_REPO           source repository slug
#   WL_LICENSE_API    license server URL

set -euo pipefail

WL_REPO="${WL_REPO:-crypto-chiefs/cryptochief-whitelabel}"
WL_CHANNEL="${WL_CHANNEL:-stable}"
WL_LICENSE_KEY="${WL_LICENSE_KEY:-}"
WL_MODE="${WL_MODE:-}"
WL_LICENSE_API="${WL_LICENSE_API:-https://license.crypto-chief.com}"

if [ -t 1 ]; then
    C_INFO=$'\033[1;36m'; C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; C_OFF=$'\033[0m'
else
    C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""; C_OFF=""
fi
say()  { printf '%s==>%s %s\n' "$C_INFO" "$C_OFF" "$*"; }
ok()   { printf '%s ✓%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn() { printf '%s !%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Reads input from the terminal even when stdin is a pipe (curl | bash).
# $1 = variable name, $2 = prompt, $3 = "silent" for secrets.
ask() {
    _flags="-r"
    [ "${3:-}" = "silent" ] && _flags="-rs"
    if [ -r /dev/tty ]; then
        # shellcheck disable=SC2229
        read $_flags -p "$2" "$1" </dev/tty || true
        { [ "${3:-}" = "silent" ] && printf '\n' >/dev/tty; } || true
    else
        # shellcheck disable=SC2229
        read $_flags -p "$2" "$1" || true
        { [ "${3:-}" = "silent" ] && printf '\n'; } || true
    fi
}

rand_hex() { # $1 = bytes
    if have openssl; then
        openssl rand -hex "$1"
    else
        head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'
    fi
}

json_field() { # $1 = json, $2 = field name; flat string fields only
    printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

# --- platform detection ------------------------------------------------------

PLATFORM=""
case "$(uname -s)" in
    Linux*)
        if grep -qi microsoft /proc/version 2>/dev/null; then PLATFORM="wsl"; else PLATFORM="linux"; fi ;;
    Darwin*) PLATFORM="mac" ;;
    MINGW*|MSYS*|CYGWIN*) PLATFORM="windows" ;;
    *) die "Unsupported OS: $(uname -s). Supported: Linux, macOS, Windows (Git Bash), WSL." ;;
esac

case "$PLATFORM" in
    linux|wsl) WL_DIR="${WL_DIR:-/opt/psp-crypto}" ;;
    *)         WL_DIR="${WL_DIR:-$HOME/psp-crypto}" ;;
esac

# Root is only required where the script installs packages and writes to /opt.
if [ "$PLATFORM" = "linux" ] || [ "$PLATFORM" = "wsl" ]; then
    [ "$(id -u)" -eq 0 ] || die "Please run as root (e.g. 'sudo -i', then re-run the command)."
fi

printf '\n%s' "$C_INFO"
cat <<'BANNER'
 ____  ____  ____     ____                  _
|  _ \/ ___||  _ \   / ___|_ __ _   _ _ __ | |_ ___
| |_) \___ \| |_) | | |   | '__| | | | '_ \| __/ _ \
|  __/ ___) |  __/  | |___| |  | |_| | |_) | || (_) |
|_|   |____/|_|      \____|_|   \__, | .__/ \__\___/
                                |___/|_|
BANNER
printf '%s        P l a t f o r m\n\n' "$C_OFF"
say "Platform: $PLATFORM"
printf '\n'

# --- install mode ------------------------------------------------------------

if [ -z "$WL_MODE" ]; then
    default_mode="local"
    [ "$PLATFORM" = "linux" ] && default_mode="server"
    echo "Where are you installing?"
    echo "  1) Public server / VPS (production, HTTPS link out of the box)"
    echo "  2) Local computer      (demo mode for evaluation)"
    choice=""
    ask choice "Choose 1 or 2 [default: $([ "$default_mode" = server ] && echo 1 || echo 2)]: "
    case "$choice" in
        1) WL_MODE="server" ;;
        2) WL_MODE="local" ;;
        "") WL_MODE="$default_mode" ;;
        *) die "Invalid choice '$choice', expected 1 or 2." ;;
    esac
fi
case "$WL_MODE" in server|local) : ;; *) die "WL_MODE must be 'server' or 'local'." ;; esac
ok "Mode: $WL_MODE"

# --- installation key --------------------------------------------------------

if [ -z "$WL_LICENSE_KEY" ]; then
    echo
    echo "An installation key is required to download the platform."
    echo "Don't have one? Contact https://crypto-chief.com/contact/ or admin@crypto-chief.com"
    ask WL_LICENSE_KEY "Installation key: " silent
fi
[ -n "$WL_LICENSE_KEY" ] || die "No installation key provided."
case "$WL_LICENSE_KEY" in
    PSP-*) : ;;
    *) die "That does not look like an installation key (expected PSP-XXXXX-XXXXX-XXXXX-XXXXX). Contact https://crypto-chief.com/contact/ for a valid key." ;;
esac

# --- dependencies ------------------------------------------------------------

wait_docker() { # $1 = attempts (2s each)
    for _ in $(seq 1 "$1"); do
        docker info >/dev/null 2>&1 && return 0
        sleep 2
    done
    return 1
}

ensure_deps_linux() {
    PKG=""
    for pm in apt-get dnf yum zypper pacman apk; do
        if have "$pm"; then PKG="$pm"; break; fi
    done
    [ -n "$PKG" ] || die "Unsupported distribution: no apt/dnf/yum/zypper/pacman/apk found."

    APT_UPDATED=0
    pkg_install() {
        case "$PKG" in
            apt-get)
                if [ "$APT_UPDATED" -eq 0 ]; then
                    DEBIAN_FRONTEND=noninteractive apt-get update -qq
                    APT_UPDATED=1
                fi
                DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" ;;
            dnf)    dnf install -y -q "$@" ;;
            yum)    yum install -y -q "$@" ;;
            zypper) zypper --non-interactive install -y "$@" ;;
            pacman) pacman -Sy --noconfirm --needed "$@" ;;
            apk)    apk add --no-cache "$@" ;;
        esac
    }

    say "Checking base dependencies (curl, git)..."
    have curl || pkg_install curl
    have git  || pkg_install git
    pkg_install ca-certificates >/dev/null 2>&1 || true
    ok "git $(git --version | awk '{print $3}') and curl are ready"

    if have docker; then
        ok "Docker already installed: $(docker --version)"
    else
        say "Installing Docker..."
        case "$PKG" in
            pacman) pkg_install docker docker-compose docker-buildx ;;
            apk)    pkg_install docker docker-cli-compose docker-cli-buildx ;;
            zypper) pkg_install docker docker-compose ;;
            *)
                # Official convenience script: Debian/Ubuntu/Raspbian,
                # RHEL/CentOS/Fedora and derivatives.
                curl -fsSL https://get.docker.com | sh || die "Docker installation failed. Install Docker manually and re-run."
                ;;
        esac
    fi

    # Start the daemon: systemd, then OpenRC, then plain service (WSL without
    # systemd). With Docker Desktop WSL integration the daemon is already up.
    if ! docker info >/dev/null 2>&1; then
        if have systemctl && [ -d /run/systemd/system ]; then
            systemctl enable --now docker >/dev/null 2>&1 || systemctl start docker || true
        elif have rc-update; then
            rc-update add docker default >/dev/null 2>&1 || true
            rc-service docker start >/dev/null 2>&1 || service docker start || true
        elif have service; then
            service docker start || true
        fi
    fi
    if ! wait_docker 30; then
        if [ "$PLATFORM" = "wsl" ]; then
            die "Docker daemon is not running. Enable Docker Desktop WSL integration (Settings -> Resources -> WSL) or start the native daemon, then re-run."
        fi
        die "Docker daemon did not start. Check: journalctl -u docker"
    fi
    ok "Docker daemon is running"

    if ! docker compose version >/dev/null 2>&1; then
        say "Installing Docker Compose plugin..."
        case "$PKG" in
            apt-get|dnf|yum) pkg_install docker-compose-plugin || true ;;
            zypper|pacman)   pkg_install docker-compose || true ;;
            apk)             pkg_install docker-cli-compose || true ;;
        esac
        if ! docker compose version >/dev/null 2>&1; then
            # Fallback: plugin binary from GitHub releases.
            arch="$(uname -m)"
            mkdir -p /usr/local/lib/docker/cli-plugins
            curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${arch}" \
                -o /usr/local/lib/docker/cli-plugins/docker-compose \
                || die "Could not install Docker Compose. Install it manually and re-run."
            chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
            docker compose version >/dev/null 2>&1 || die "Docker Compose still not available after install."
        fi
    fi
}

ensure_deps_mac() {
    if ! git --version >/dev/null 2>&1; then
        if have brew; then
            say "Installing git via Homebrew..."
            brew install git
        else
            die "git is not available. Run 'xcode-select --install' (or install Homebrew), then re-run."
        fi
    fi
    ok "git $(git --version | awk '{print $3}') is ready"

    if ! have docker; then
        if have brew; then
            say "Installing Docker Desktop via Homebrew (this can take a few minutes)..."
            brew install --cask docker || die "Homebrew could not install Docker Desktop. Install it from https://www.docker.com/products/docker-desktop/ and re-run."
        else
            die "Docker Desktop is not installed. Download it from https://www.docker.com/products/docker-desktop/, launch it once, then re-run."
        fi
    fi
    if ! docker info >/dev/null 2>&1; then
        say "Starting Docker Desktop..."
        open -a Docker || true
        say "Waiting for the Docker engine (first start takes a minute)..."
        wait_docker 90 || die "Docker engine did not start. Open Docker Desktop manually, wait until it is running, then re-run."
    fi
    ok "Docker daemon is running"
    docker compose version >/dev/null 2>&1 || die "Docker Compose not found. Update Docker Desktop to a recent version and re-run."
}

ensure_deps_windows() {
    # Git Bash ships git and curl.
    ok "git $(git --version | awk '{print $3}') is ready (Git Bash)"

    if ! have docker; then
        if have winget.exe; then
            say "Installing Docker Desktop via winget (this can take a few minutes)..."
            winget.exe install -e --id Docker.DockerDesktop --accept-package-agreements --accept-source-agreements || true
        fi
        have docker || die "Docker Desktop is not installed (or PATH needs a new terminal).
    Install it from https://www.docker.com/products/docker-desktop/,
    start it once, then open a NEW Git Bash window and re-run the installer."
    fi
    if ! docker info >/dev/null 2>&1; then
        say "Starting Docker Desktop..."
        powershell.exe -NoProfile -Command "Start-Process -FilePath \"\$env:ProgramFiles\\Docker\\Docker\\Docker Desktop.exe\"" >/dev/null 2>&1 || true
        say "Waiting for the Docker engine (first start takes a minute)..."
        wait_docker 90 || die "Docker engine did not start. Open Docker Desktop manually, wait until it is running, then re-run."
    fi
    ok "Docker daemon is running"
    docker compose version >/dev/null 2>&1 || die "Docker Compose not found. Update Docker Desktop to a recent version and re-run."
}

case "$PLATFORM" in
    linux|wsl) ensure_deps_linux ;;
    mac)       ensure_deps_mac ;;
    windows)   ensure_deps_windows ;;
esac
ok "Docker Compose: $(docker compose version --short 2>/dev/null || echo ok)"

# --- public IP (production) ---------------------------------------------------

is_ipv4() { # strict dotted-quad, each octet 0-255
    case "$1" in
        *[!0-9.]*|"") return 1 ;;
    esac
    _o="$1"; _n=0
    while [ -n "$_o" ]; do
        _seg="${_o%%.*}"
        [ -n "$_seg" ] && [ "$_seg" -le 255 ] 2>/dev/null || return 1
        _n=$((_n + 1))
        [ "$_o" = "$_seg" ] && _o="" || _o="${_o#*.}"
    done
    [ "$_n" -eq 4 ]
}

PUBLIC_IP=""
if [ "$WL_MODE" = "server" ]; then
    say "Detecting public IP..."
    for ip_svc in "https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com"; do
        cand="$(curl -4fsS --max-time 5 "$ip_svc" 2>/dev/null | tr -d '[:space:]')"
        # Only accept a clean IPv4: a captive portal / error page that still
        # returns 200 must not become a bogus public_ip (the server would 400
        # and abort an install that should just skip the bootstrap domain).
        if is_ipv4 "$cand"; then PUBLIC_IP="$cand"; break; fi
    done
    if [ -n "$PUBLIC_IP" ]; then
        ok "Public IP: $PUBLIC_IP"
    else
        warn "Could not detect a public IP, continuing without the HTTPS bootstrap domain."
    fi
fi

# --- validate the installation key -------------------------------------------
# The key is exchanged at the license server for a short-lived GitHub token.
# The token is used for the initial download only and is never stored; updates
# mint a fresh one with the key from .env.
#
# In production the request also carries the public IP: the license server
# creates a DNS record <organization-id>.psp-crypto-chief.com for it via the
# Cloudflare API and returns the domain. TLS is terminated by Cloudflare in
# front of this server — the stack must NOT issue a certificate for that
# name, it only has to answer plain HTTP on :80.

exchange_key() { # $1 = optional public_ip; echoes "body\nhttp_code"
    if [ -n "$1" ]; then
        _body="{\"license_key\":\"${WL_LICENSE_KEY}\",\"public_ip\":\"$1\"}"
    else
        _body="{\"license_key\":\"${WL_LICENSE_KEY}\"}"
    fi
    curl -sS -m 20 -w $'\n%{http_code}' -X POST "${WL_LICENSE_API}/v1/installer/token" \
        -H 'Content-Type: application/json' -d "$_body" 2>/dev/null
}

say "Checking the installation key..."
resp="$(exchange_key "$PUBLIC_IP")" \
    || die "Cannot reach the license server (${WL_LICENSE_API}). Check your network and try again."
http_code="${resp##*$'\n'}"
body="${resp%$'\n'*}"
# The bootstrap domain is best-effort: if the server rejects the public IP
# (400), retry without it rather than aborting a valid install.
if [ "$http_code" = "400" ] && [ -n "$PUBLIC_IP" ]; then
    warn "License server rejected the detected IP; continuing without the bootstrap domain."
    PUBLIC_IP=""
    resp="$(exchange_key "")" \
        || die "Cannot reach the license server (${WL_LICENSE_API}). Check your network and try again."
    http_code="${resp##*$'\n'}"
    body="${resp%$'\n'*}"
fi
case "$http_code" in
    200) : ;;
    401) die "The installation key was rejected. Check the key or contact https://crypto-chief.com/contact/" ;;
    403) die "The installation key is revoked or expired. Contact https://crypto-chief.com/contact/ or admin@crypto-chief.com" ;;
    429) die "Too many attempts from this address. Try again in an hour." ;;
    *)   die "License server error (HTTP ${http_code:-?}). Try again later or contact support." ;;
esac
GIT_TOKEN="$(json_field "$body" token)"
[ -n "$GIT_TOKEN" ] || die "The license server returned no download token. Contact support."
srv_repo="$(json_field "$body" repo)"
[ -n "$srv_repo" ] && WL_REPO="$srv_repo"
BOOTSTRAP_DOMAIN="$(json_field "$body" domain)"
ok "Installation key accepted"
if [ -n "$BOOTSTRAP_DOMAIN" ]; then
    ok "HTTPS bootstrap domain: https://${BOOTSTRAP_DOMAIN}"
elif [ -n "$PUBLIC_IP" ]; then
    warn "No bootstrap domain returned; the install wizard will be available on the bare IP."
fi

# --- download ----------------------------------------------------------------

if [ -e "$WL_DIR" ]; then
    if [ -d "$WL_DIR/.git" ]; then
        die "Found an existing installation in $WL_DIR.
    To update it, use the admin panel (Configuration -> Updates) or run:
      cd $WL_DIR && sh scripts/update.sh"
    fi
    [ -z "$(ls -A "$WL_DIR" 2>/dev/null)" ] || die "$WL_DIR exists and is not empty. Remove it or set WL_DIR to another path."
fi

say "Downloading PSP Crypto Platform (${WL_CHANNEL} version) into ${WL_DIR}..."
CLONE_URL="https://x-access-token:${GIT_TOKEN}@github.com/${WL_REPO}.git"
export GIT_TERMINAL_PROMPT=0
if ! git clone --branch "$WL_CHANNEL" "$CLONE_URL" "$WL_DIR" 2>/dev/null; then
    warn "Branch '${WL_CHANNEL}' not found, falling back to the default branch."
    rm -rf "$WL_DIR"
    git clone "$CLONE_URL" "$WL_DIR" || die "git clone failed. Check the key and network connectivity."
    WL_CHANNEL="$(git -C "$WL_DIR" rev-parse --abbrev-ref HEAD)"
fi
# The download token expires within an hour and must not stay in the remote
# URL. The remote is left without credentials; updates authenticate with a
# fresh token minted from the license key in .env.
git -C "$WL_DIR" remote set-url origin "https://github.com/${WL_REPO}.git"
chmod 700 "$WL_DIR" 2>/dev/null || true
ok "Downloaded version $(cat "$WL_DIR/VERSION" 2>/dev/null || echo '?') (branch: ${WL_CHANNEL})"

# --- .env ---------------------------------------------------------------------

if [ ! -f "$WL_DIR/.env" ]; then
    say "Generating .env..."
    {
        echo "# Generated by the PSP Crypto Platform installer on $(date -u +%Y-%m-%dT%H:%M:%SZ)."
        echo "# Full reference: .env.example"
        echo
        echo "# Fixed compose project name: admin-panel updates run compose from a"
        echo "# container, so the name must not depend on the directory."
        echo "COMPOSE_PROJECT_NAME=psp-crypto"
        echo
        echo "# Host path of this installation, used by the self-update sidecar."
        echo "WL_REPO_DIR=${WL_DIR}"
        echo "WL_CHANNEL=${WL_CHANNEL}"
        echo
        echo "# Installation key: in-admin updates use it to fetch new versions."
        echo "WL_LICENSE_KEY=${WL_LICENSE_KEY}"
        echo "WL_LICENSE_API=${WL_LICENSE_API}"
        echo
        echo "POSTGRES_PASSWORD=$(rand_hex 16)"
        echo
        if [ "$WL_MODE" = "server" ]; then
            echo "# Production: dev webhook routes are off, the mock provider is disabled."
            echo "APP_ENV=production"
            if [ -n "$BOOTSTRAP_DOMAIN" ]; then
                echo "URL=https://${BOOTSTRAP_DOMAIN}"
                echo "# HTTPS bootstrap domain (<organization-id>.psp-crypto-chief.com), issued"
                echo "# by the license server. DNS and TLS are handled by Cloudflare in"
                echo "# front of this server — the stack must serve this host over plain"
                echo "# HTTP on port 80 and never issue a certificate for it."
                echo "WL_BOOTSTRAP_DOMAIN=${BOOTSTRAP_DOMAIN}"
            fi
            echo
            echo "# Host bind for the setup-wizard / backend port 1337. With a bootstrap"
            echo "# domain the wizard is reached over HTTPS via Cloudflare -> :80, so 1337"
            echo "# is kept on loopback only and never exposed to the internet. Without a"
            echo "# domain it is published on all interfaces so the wizard is reachable at"
            echo "# http://<ip>:1337. Compose must publish it as \${WL_WIZARD_BIND}:1337:1337."
            if [ -n "$BOOTSTRAP_DOMAIN" ]; then
                echo "WL_WIZARD_BIND=127.0.0.1"
            else
                echo "WL_WIZARD_BIND=0.0.0.0"
            fi
        else
            echo "# Local install: demo mode (mock provider and dev routes enabled)."
            echo "APP_ENV=development"
            echo
            echo "# Local machine only — never expose the wizard port outside the host."
            echo "WL_WIZARD_BIND=127.0.0.1"
        fi
    } > "$WL_DIR/.env"
    chmod 600 "$WL_DIR/.env" 2>/dev/null || true
    ok ".env created"
else
    warn ".env already exists, keeping it as is."
fi

# --- build and start ----------------------------------------------------------

say "Building and starting the stack (docker compose up -d --build)..."
say "This takes 5-10 minutes on a small machine."
cd "$WL_DIR"
docker compose up -d --build

say "Waiting for the platform to become healthy..."
HEALTH_OK=0
for _ in $(seq 1 60); do
    if curl -fsS --max-time 3 http://127.0.0.1:1337/health >/dev/null 2>&1; then
        HEALTH_OK=1
        break
    fi
    sleep 3
done
[ "$HEALTH_OK" -eq 1 ] || warn "The backend did not answer on :1337/health yet. Check logs: cd $WL_DIR && docker compose logs -f"

# Verify the public bootstrap address actually opens the wizard before we
# rely on it (port 1337 is kept loopback-only when a domain is present, so
# the domain is the only external way in). DNS/Cloudflare may need a moment.
DOMAIN_OK=0
if [ -n "$BOOTSTRAP_DOMAIN" ]; then
    say "Checking the HTTPS address ${BOOTSTRAP_DOMAIN}..."
    for _ in $(seq 1 20); do
        if curl -fsS --max-time 5 "https://${BOOTSTRAP_DOMAIN}/health" >/dev/null 2>&1; then
            DOMAIN_OK=1
            break
        fi
        sleep 3
    done
    if [ "$DOMAIN_OK" -eq 1 ]; then
        ok "Reachable: https://${BOOTSTRAP_DOMAIN}"
    else
        warn "https://${BOOTSTRAP_DOMAIN} did not answer yet (DNS can take a few minutes to propagate)."
    fi
fi

# --- summary -------------------------------------------------------------------

local_ip() {
    case "$PLATFORM" in
        mac)
            ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true ;;
        windows)
            powershell.exe -NoProfile -Command "(Get-NetIPConfiguration | Where-Object { \$_.IPv4DefaultGateway -ne \$null } | Select-Object -First 1).IPv4Address.IPAddress" 2>/dev/null | tr -d '\r\n ' || true ;;
        *)
            hostname -I 2>/dev/null | awk '{print $1}' || true ;;
    esac
}

printf '\n'
printf '%s================================================================%s\n' "$C_OK" "$C_OFF"
printf '%s  PSP Crypto Platform is up and running%s\n' "$C_OK" "$C_OFF"
printf '%s================================================================%s\n' "$C_OK" "$C_OFF"
printf '\n'
if [ "$WL_MODE" = "server" ] && [ -n "$BOOTSTRAP_DOMAIN" ]; then
    printf '  Open the install wizard to finish the setup:\n\n'
    printf '      %shttps://%s/install%s\n\n' "$C_INFO" "$BOOTSTRAP_DOMAIN" "$C_OFF"
    printf '  HTTPS is provided by Cloudflare in front of this server —\n'
    printf '  the certificate is managed there, nothing is issued locally.\n'
    if [ "$DOMAIN_OK" -ne 1 ]; then
        printf '  DNS can take a few minutes to propagate on the first open.\n'
    fi
    printf '\n'
    printf '  Only port 80 needs to be open in your firewall / cloud security\n'
    printf '  group — Cloudflare forwards the wizard traffic to it. Port 1337\n'
    printf '  is bound to localhost only and is NOT exposed to the internet.\n'
    printf '  Port 443 will be needed for your own domains later.\n'
    printf '\n'
    printf '  If you need the wizard before DNS is ready, reach the local\n'
    printf '  port over an SSH tunnel from your machine:\n'
    printf '      %sssh -L 1337:127.0.0.1:1337 <user>@%s%s\n' "$C_INFO" "$PUBLIC_IP" "$C_OFF"
    printf '  then open %shttp://localhost:1337/install%s\n' "$C_INFO" "$C_OFF"
elif [ "$WL_MODE" = "server" ] && [ -n "$PUBLIC_IP" ]; then
    printf '  Open the install wizard to finish the setup:\n\n'
    printf '      %shttp://%s:1337/install%s\n' "$C_INFO" "$PUBLIC_IP" "$C_OFF"
    printf '\n'
    printf '  The license server did not return an HTTPS bootstrap domain,\n'
    printf '  so the wizard is served on the bare IP. Make sure port 1337\n'
    printf '  is open in your firewall / cloud security group.\n'
elif [ "$WL_MODE" = "server" ]; then
    printf '  Open the install wizard to finish the setup:\n\n'
    printf '      %shttp://<your-server-ip>:1337/install%s\n' "$C_INFO" "$C_OFF"
    printf '\n'
    printf '  (public IP detection failed; use the server address you know.\n'
    printf '   Port 1337 must be open in your firewall / cloud security group.)\n'
else
    LAN_IP="$(local_ip)"
    printf '  Open the install wizard to finish the setup:\n\n'
    printf '      %shttp://localhost:1337/install%s\n' "$C_INFO" "$C_OFF"
    if [ -n "$LAN_IP" ]; then
        printf '      %shttp://%s:1337/install%s   (from other devices on your network)\n' "$C_INFO" "$LAN_IP" "$C_OFF"
    fi
fi
printf '\n'
printf '  The wizard covers the admin account, branding, Crypto Chief\n'
printf '  API keys, SMTP and custom domains.\n'
printf '\n'
printf '  Installed in:  %s\n' "$WL_DIR"
printf '  Logs:          cd %s && docker compose logs -f\n' "$WL_DIR"
printf '  Updates:       admin panel -> Configuration -> Updates\n'
printf '\n'
exit 0
