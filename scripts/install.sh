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
#   WL_MODE           server | local | cloudflare (skips the prompt)
#   WL_DIR            install directory (default: ~/psp-crypto)
#   WL_CHANNEL        release branch (default: stable)
#   WL_REPO           source repository slug
#   WL_LICENSE_API    license server URL
#
# Cloudflare Tunnel mode (WL_MODE=cloudflare) — skips those prompts too:
#   CF_API_TOKEN      Cloudflare API token (Zone:Read + DNS:Edit on the zone,
#                     Account:Cloudflare Tunnel:Edit)
#   CF_ZONE           domain you own in that Cloudflare account (example.com)
#   CF_HOSTNAME       main hostname of the platform (psp.example.com)
#   CF_LAYOUT         single | split — skips the domain-layout question;
#                     split prompts for (or defaults) the four hostnames below
#   CF_ADMIN_HOSTNAME     per-app subdomains, created on the same tunnel and
#   CF_MERCHANT_HOSTNAME  picked up by the platform on first boot (the wizard's
#   CF_PAYMENT_HOSTNAME   Domains step comes pre-filled). Setting any of them
#   CF_API_HOSTNAME       implies split; leave one empty to skip it.
#   CF_TUNNEL_NAME    tunnel name (default: psp-<hostname with dots as dashes>;
#                     stable, so a re-run reuses the tunnel instead of creating
#                     a twin)

set -euo pipefail

WL_REPO="${WL_REPO:-crypto-chiefs/cryptochief-whitelabel}"
WL_CHANNEL="${WL_CHANNEL:-stable}"
WL_LICENSE_KEY="${WL_LICENSE_KEY:-}"
WL_MODE="${WL_MODE:-}"
WL_LICENSE_API="${WL_LICENSE_API:-https://license.crypto-chief.com}"

CF_API="https://api.cloudflare.com/client/v4"
CF_API_TOKEN="${CF_API_TOKEN:-}"
CF_ZONE="${CF_ZONE:-}"
CF_HOSTNAME="${CF_HOSTNAME:-}"
CF_LAYOUT="${CF_LAYOUT:-}"
CF_ADMIN_HOSTNAME="${CF_ADMIN_HOSTNAME:-}"
CF_MERCHANT_HOSTNAME="${CF_MERCHANT_HOSTNAME:-}"
CF_PAYMENT_HOSTNAME="${CF_PAYMENT_HOSTNAME:-}"
CF_API_HOSTNAME="${CF_API_HOSTNAME:-}"
CF_TUNNEL_NAME="${CF_TUNNEL_NAME:-}"
CF_ZONE_ID=""
CF_ACCOUNT_ID=""
CF_TUNNEL_ID=""
CF_TUNNEL_TOKEN=""
ALL_HOSTNAMES=""
JQ=""

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

WL_DIR="${WL_DIR:-$HOME/psp-crypto}"

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
    echo "  3) Cloudflare Tunnel   (production on YOUR domain, no open ports —"
    echo "                          works on a VPS, behind NAT or on a laptop)"
    choice=""
    ask choice "Choose 1, 2 or 3 [default: $([ "$default_mode" = server ] && echo 1 || echo 2)]: "
    case "$choice" in
        1) WL_MODE="server" ;;
        2) WL_MODE="local" ;;
        3) WL_MODE="cloudflare" ;;
        "") WL_MODE="$default_mode" ;;
        *) die "Invalid choice '$choice', expected 1, 2 or 3." ;;
    esac
fi
case "$WL_MODE" in server|local|cloudflare) : ;; *) die "WL_MODE must be 'server', 'local' or 'cloudflare'." ;; esac
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

# --- jq (Cloudflare mode only) -------------------------------------------------
# The Cloudflare API answers with nested JSON (zone id and account id come from
# the same object, tunnel id and token from another) and this installer creates
# real, billable resources from those values. Grepping them out with sed would
# happily pick the wrong "id" and point a DNS record at nothing, so the flow
# refuses to guess: it installs jq, or downloads the official static binary when
# the platform has no package manager.
#
# pkg_install / PKG come from ensure_deps_linux, which has already run above —
# bash keeps nested function definitions after the outer function executes.
ensure_jq() {
    if have jq; then
        JQ="$(command -v jq)"
        ok "jq $("$JQ" --version 2>/dev/null || echo present)"
        return 0
    fi

    say "Installing jq (needed to talk to the Cloudflare API)..."
    case "$PLATFORM" in
        linux|wsl) pkg_install jq >/dev/null 2>&1 || true ;;
        mac)       have brew && brew install jq >/dev/null 2>&1 || true ;;
    esac
    if have jq; then
        JQ="$(command -v jq)"
        ok "jq installed"
        return 0
    fi

    _jq_asset=""
    case "$(uname -m)" in
        x86_64|amd64)  _jq_arch="amd64" ;;
        aarch64|arm64) _jq_arch="arm64" ;;
        *)             _jq_arch="" ;;
    esac
    case "$PLATFORM" in
        linux|wsl) [ -n "$_jq_arch" ] && _jq_asset="jq-linux-${_jq_arch}" ;;
        mac)       [ -n "$_jq_arch" ] && _jq_asset="jq-macos-${_jq_arch}" ;;
        windows)   _jq_asset="jq-windows-amd64.exe" ;;
    esac
    if [ -n "$_jq_asset" ]; then
        say "Downloading jq (${_jq_asset})..."
        _jq_dir="${TMPDIR:-/tmp}/psp-install"
        mkdir -p "$_jq_dir"
        _jq_bin="${_jq_dir}/jq"
        if curl -fsSL "https://github.com/jqlang/jq/releases/latest/download/${_jq_asset}" -o "$_jq_bin" 2>/dev/null; then
            chmod +x "$_jq_bin" 2>/dev/null || true
            if "$_jq_bin" --version >/dev/null 2>&1; then
                JQ="$_jq_bin"
                ok "jq ready ($_jq_bin)"
                return 0
            fi
        fi
    fi

    die "jq is required for the Cloudflare Tunnel flow but could not be installed.
    Install it (e.g. 'apt install jq', 'brew install jq', or from https://jqlang.github.io/jq/)
    and re-run the installer."
}

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
    _body="{\"license_key\":\"${WL_LICENSE_KEY}\""
    [ -n "$1" ] && _body="${_body},\"public_ip\":\"$1\""
    # Local install has no public IP — ask the license server for an ngrok
    # tunnel so Crypto Chief webhooks can reach localhost.
    [ "$WL_MODE" = "local" ] && _body="${_body},\"tunnel\":true"
    _body="${_body}}"
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
# Local-install dev tunnel (ngrok), issued by the license server.
NGROK_DOMAIN="$(json_field "$body" ngrok_domain)"
NGROK_AUTHTOKEN="$(json_field "$body" ngrok_authtoken)"
ok "Installation key accepted"
if [ -n "$BOOTSTRAP_DOMAIN" ]; then
    ok "HTTPS bootstrap domain: https://${BOOTSTRAP_DOMAIN}"
elif [ -n "$PUBLIC_IP" ]; then
    warn "No bootstrap domain returned; the install wizard will be available on the bare IP."
fi
if [ "$WL_MODE" = "local" ]; then
    if [ -n "$NGROK_DOMAIN" ] && [ -n "$NGROK_AUTHTOKEN" ]; then
        ok "Public dev tunnel: https://${NGROK_DOMAIN}"
    else
        warn "No dev tunnel returned — running in demo mode; external webhooks won't reach localhost."
    fi
fi

# --- existing installation guard ----------------------------------------------
# Checked BEFORE the Cloudflare flow: it creates real resources (a tunnel, DNS
# records), and dying on "directory already exists" only after that would leave
# them behind on every failed re-run.

if [ -e "$WL_DIR" ]; then
    if [ -d "$WL_DIR/.git" ]; then
        die "Found an existing installation in $WL_DIR.
    To update it, use the admin panel (Configuration -> Updates) or run:
      cd $WL_DIR && sh scripts/update.sh"
    fi
    [ -z "$(ls -A "$WL_DIR" 2>/dev/null)" ] || die "$WL_DIR exists and is not empty. Remove it or set WL_DIR to another path."
fi

# --- Cloudflare Tunnel ---------------------------------------------------------
# Turns the entrance inside out: cloudflared dials OUT to Cloudflare (TCP/UDP
# 7844) and Cloudflare proxies the operator's hostname into the stack. No inbound
# port, no A record for this machine, no certificate issued locally — which is
# also why the stack must be told (TLS_TERMINATION=edge) never to attempt ACME:
# a challenge can't reach an origin that has no way in.
#
# Everything the platform needs is created here, at install time: the tunnel, its
# ingress rule and the proxied DNS record. All of it lands on ONE hostname that
# serves the whole product by path (/install, /admin, /merchant, /pay/*, /api/*,
# /v1/*, /webhook/*), the same shape as the technical bootstrap domain in server
# mode.

cf_call() { # $1 method, $2 path, $3 optional body -> CF_CODE, CF_BODY
    _cf_resp=""
    if [ -n "${3:-}" ]; then
        _cf_resp="$(curl -sS -m 30 -w $'\n%{http_code}' -X "$1" "${CF_API}$2" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H 'Content-Type: application/json' --data "$3" 2>/dev/null)" || _cf_resp=$'\n000'
    else
        _cf_resp="$(curl -sS -m 30 -w $'\n%{http_code}' -X "$1" "${CF_API}$2" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" 2>/dev/null)" || _cf_resp=$'\n000'
    fi
    CF_CODE="${_cf_resp##*$'\n'}"
    CF_BODY="${_cf_resp%$'\n'*}"
}

cf_json() { printf '%s' "$CF_BODY" | "$JQ" -r "$1 // empty" 2>/dev/null; }

cf_ok() {
    case "$CF_CODE" in 2*) : ;; *) return 1 ;; esac
    [ "$(cf_json '.success')" = "true" ]
}

# Cloudflare puts the actionable part in errors[].message ("Invalid request
# headers", "Authentication error"); surface it instead of a bare HTTP code.
cf_error() {
    _m="$(printf '%s' "$CF_BODY" | "$JQ" -r '[.errors[]? | "\(.code): \(.message)"] | join("; ")' 2>/dev/null)"
    [ -n "$_m" ] && printf '%s' "$_m" || printf 'HTTP %s' "${CF_CODE:-?}"
}

looks_like_domain() { # rough shape check: at least two dot-separated labels
    case "$1" in
        ""|*[!a-zA-Z0-9.-]*|.*|*.|*..*) return 1 ;;
    esac
    case "$1" in *.*) return 0 ;; *) return 1 ;; esac
}

normalize_hostname() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]'; }

# check_hostname_in_zone <hostname> — shape, zone membership, and a TLS-coverage
# warning: Cloudflare's free Universal certificate covers only ONE label below
# the zone apex. admin.example.com is covered; admin.psp.example.com is not —
# visitors get a TLS error unless the zone has Total TLS / an Advanced
# Certificate. A warning, not a death: the operator may have one.
check_hostname_in_zone() {
    looks_like_domain "$1" || die "'$1' is not a valid hostname."
    case "$1" in
        "$CF_ZONE") return 0 ;;  # zone apex — fine on a dedicated domain
        *".$CF_ZONE") : ;;
        *) die "$1 is not inside the zone $CF_ZONE — the installer can only create records in that zone." ;;
    esac
    case "${1%.$CF_ZONE}" in
        *.*) warn "$1 is more than one level below ${CF_ZONE}: the free Universal certificate will NOT cover it. Enable Total TLS (or an Advanced Certificate) on the zone, or pick a single-level name." ;;
    esac
}

# cf_dns_lookup <hostname> → CF_DNS_RECORD_ID / CF_DNS_TARGET ("" if absent)
cf_dns_lookup() {
    cf_call GET "/zones/${CF_ZONE_ID}/dns_records?name=$1"
    cf_ok || die "Cloudflare rejected the DNS lookup for $1: $(cf_error)
    The token needs Zone -> DNS -> Edit on ${CF_ZONE}."
    CF_DNS_RECORD_ID="$(cf_json '.result[0].id')"
    CF_DNS_TARGET="$(cf_json '.result[0].content')"
}

# cf_dns_guard <hostname> — a record that already points somewhere else is
# someone's live site; never silently repoint it. Runs BEFORE anything is
# created, so an abort leaves the Cloudflare account exactly as it was.
cf_dns_guard() {
    cf_dns_lookup "$1"
    [ -n "$CF_DNS_RECORD_ID" ] || return 0
    case "$CF_DNS_TARGET" in
        *.cfargotunnel.com) : ;;  # an old tunnel of ours, safe to repoint
        *)
            warn "$1 already resolves to ${CF_DNS_TARGET}."
            _ow=""
            ask _ow "Replace that DNS record? [y/N]: "
            case "$_ow" in
                y|Y|yes|YES) : ;;
                *) die "Aborted. Re-run with different hostnames (CF_HOSTNAME / CF_*_HOSTNAME=...)." ;;
            esac
            ;;
    esac
}

# cf_dns_upsert <hostname> — proxied CNAME to the tunnel. Proxied is not
# optional: an unproxied record cannot resolve a *.cfargotunnel.com target.
# The guard above has already cleared any overwrite with the operator.
cf_dns_upsert() {
    cf_dns_lookup "$1"
    _dns_body="{\"type\":\"CNAME\",\"name\":\"$1\",\"content\":\"${CF_TUNNEL_ID}.cfargotunnel.com\",\"proxied\":true,\"ttl\":1}"
    if [ -n "$CF_DNS_RECORD_ID" ]; then
        cf_call PUT "/zones/${CF_ZONE_ID}/dns_records/${CF_DNS_RECORD_ID}" "$_dns_body"
    else
        cf_call POST "/zones/${CF_ZONE_ID}/dns_records" "$_dns_body"
    fi
    cf_ok || die "Could not create the DNS record for $1: $(cf_error)
    The token needs Zone -> DNS -> Edit on ${CF_ZONE}."
    ok "DNS: $1 -> ${CF_TUNNEL_ID}.cfargotunnel.com (proxied)"
}

if [ "$WL_MODE" = "cloudflare" ]; then
    ensure_jq

    # 1. API token. Verified against Cloudflare before anything is created —
    #    a typo here would otherwise surface as a confusing failure three
    #    requests later, after a tunnel has already been made.
    _tries=0
    while :; do
        if [ -z "$CF_API_TOKEN" ]; then
            echo
            echo "Cloudflare API token. Create one at"
            echo "  https://dash.cloudflare.com/profile/api-tokens -> Create Token -> Custom token"
            echo "with these permissions:"
            echo "  Account -> Cloudflare Tunnel -> Edit"
            echo "  Zone    -> DNS              -> Edit"
            echo "  Zone    -> Zone             -> Read"
            ask CF_API_TOKEN "Cloudflare API token: " silent
        fi
        [ -n "$CF_API_TOKEN" ] || die "No Cloudflare API token provided."

        say "Verifying the Cloudflare token..."
        cf_call GET "/user/tokens/verify"
        if [ "$CF_CODE" = "000" ]; then
            die "Cannot reach the Cloudflare API. Check this machine's outbound network access and try again."
        fi
        if cf_ok && [ "$(cf_json '.result.status')" = "active" ]; then
            ok "Cloudflare token is valid and active"
            break
        fi
        _tries=$((_tries + 1))
        warn "Token rejected by Cloudflare: $(cf_error)"
        [ "$_tries" -ge 3 ] && die "Could not verify the Cloudflare API token after 3 attempts."
        CF_API_TOKEN=""
    done

    # 2. Zone. The account id comes from the same object — the tunnel is an
    #    account-level resource, and it must be the account that owns the zone.
    _tries=0
    while :; do
        if [ -z "$CF_ZONE" ]; then
            echo
            echo "Which of your Cloudflare domains should the platform live on?"
            ask CF_ZONE "Domain (e.g. example.com): "
        fi
        CF_ZONE="$(printf '%s' "$CF_ZONE" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
        if ! looks_like_domain "$CF_ZONE"; then
            warn "'$CF_ZONE' does not look like a domain name."
            CF_ZONE=""
            _tries=$((_tries + 1))
            [ "$_tries" -ge 3 ] && die "No valid domain provided."
            continue
        fi

        say "Looking up the zone $CF_ZONE..."
        cf_call GET "/zones?name=${CF_ZONE}"
        cf_ok || die "Cloudflare rejected the zone lookup: $(cf_error)
    The token needs Zone -> Zone -> Read."
        CF_ZONE_ID="$(cf_json '.result[0].id')"
        CF_ACCOUNT_ID="$(cf_json '.result[0].account.id')"
        if [ -n "$CF_ZONE_ID" ] && [ -n "$CF_ACCOUNT_ID" ]; then
            ok "Zone $CF_ZONE found"
            break
        fi
        warn "$CF_ZONE is not in this Cloudflare account, or the token has no access to it."
        CF_ZONE=""
        _tries=$((_tries + 1))
        [ "$_tries" -ge 3 ] && die "Could not resolve a Cloudflare zone."
    done

    # 3. Hostnames. The main one always exists and serves everything by path;
    #    per-app subdomains are optional sugar on the same tunnel — the platform
    #    picks them up on first boot (WL_*_DOMAIN in .env → seeded into the
    #    installation), so the wizard's Domains step comes pre-filled.
    if [ -z "$CF_HOSTNAME" ]; then
        echo
        echo "Main hostname of the platform."
        echo "It serves the setup wizard, incoming webhooks, the API and (unless"
        echo "you add per-app subdomains next) the admin panel, merchant cabinet"
        echo "and payment pages too."
        ask CF_HOSTNAME "Hostname [default: psp.${CF_ZONE}]: "
    fi
    CF_HOSTNAME="$(normalize_hostname "${CF_HOSTNAME:-psp.${CF_ZONE}}")"
    check_hostname_in_zone "$CF_HOSTNAME"

    if [ -z "${CF_ADMIN_HOSTNAME}${CF_MERCHANT_HOSTNAME}${CF_PAYMENT_HOSTNAME}${CF_API_HOSTNAME}" ] && [ -z "$CF_LAYOUT" ]; then
        echo
        echo "Domain layout:"
        echo "  1) Single hostname          https://${CF_HOSTNAME}/admin, /merchant, /pay/..."
        echo "  2) Per-app subdomains too   admin.${CF_ZONE}, merchant.${CF_ZONE}, pay.${CF_ZONE}, api.${CF_ZONE}"
        _lay=""
        ask _lay "Choose 1 or 2 [default: 1]: "
        case "$_lay" in
            2) CF_LAYOUT="split" ;;
            ""|1) CF_LAYOUT="single" ;;
            *) die "Invalid choice '$_lay', expected 1 or 2." ;;
        esac
    fi
    if [ "$CF_LAYOUT" = "split" ]; then
        if [ -z "$CF_ADMIN_HOSTNAME" ]; then
            ask CF_ADMIN_HOSTNAME "Admin panel hostname      [default: admin.${CF_ZONE}, '-' to skip]: "
            CF_ADMIN_HOSTNAME="${CF_ADMIN_HOSTNAME:-admin.${CF_ZONE}}"
        fi
        if [ -z "$CF_MERCHANT_HOSTNAME" ]; then
            ask CF_MERCHANT_HOSTNAME "Merchant cabinet hostname [default: merchant.${CF_ZONE}, '-' to skip]: "
            CF_MERCHANT_HOSTNAME="${CF_MERCHANT_HOSTNAME:-merchant.${CF_ZONE}}"
        fi
        if [ -z "$CF_PAYMENT_HOSTNAME" ]; then
            ask CF_PAYMENT_HOSTNAME "Payment pages hostname    [default: pay.${CF_ZONE}, '-' to skip]: "
            CF_PAYMENT_HOSTNAME="${CF_PAYMENT_HOSTNAME:-pay.${CF_ZONE}}"
        fi
        if [ -z "$CF_API_HOSTNAME" ]; then
            ask CF_API_HOSTNAME "Public API hostname       [default: api.${CF_ZONE}, '-' to skip]: "
            CF_API_HOSTNAME="${CF_API_HOSTNAME:-api.${CF_ZONE}}"
        fi
    fi
    # '-' skips a subdomain the operator does not want.
    [ "$CF_ADMIN_HOSTNAME" = "-" ] && CF_ADMIN_HOSTNAME=""
    [ "$CF_MERCHANT_HOSTNAME" = "-" ] && CF_MERCHANT_HOSTNAME=""
    [ "$CF_PAYMENT_HOSTNAME" = "-" ] && CF_PAYMENT_HOSTNAME=""
    [ "$CF_API_HOSTNAME" = "-" ] && CF_API_HOSTNAME=""
    CF_ADMIN_HOSTNAME="$(normalize_hostname "$CF_ADMIN_HOSTNAME")"
    CF_MERCHANT_HOSTNAME="$(normalize_hostname "$CF_MERCHANT_HOSTNAME")"
    CF_PAYMENT_HOSTNAME="$(normalize_hostname "$CF_PAYMENT_HOSTNAME")"
    CF_API_HOSTNAME="$(normalize_hostname "$CF_API_HOSTNAME")"

    ALL_HOSTNAMES="$CF_HOSTNAME"
    for _h in $CF_ADMIN_HOSTNAME $CF_MERCHANT_HOSTNAME $CF_PAYMENT_HOSTNAME $CF_API_HOSTNAME; do
        check_hostname_in_zone "$_h"
        case " $ALL_HOSTNAMES " in
            *" $_h "*) die "Hostname $_h is listed twice — every hostname must be unique." ;;
        esac
        ALL_HOSTNAMES="$ALL_HOSTNAMES $_h"
    done

    # Existing-DNS guard for EVERY hostname before anything is created: an abort
    # here leaves the Cloudflare account untouched.
    for _h in $ALL_HOSTNAMES; do
        cf_dns_guard "$_h"
    done

    # 4. Tunnel. config_src=cloudflare keeps the ingress rules in the dashboard,
    #    so the connector needs nothing but its token and the operator can add
    #    hostnames later without touching this machine. The default name derives
    #    from the main hostname — stable, so a re-run after a failure finds and
    #    reuses the tunnel instead of leaving a twin per attempt.
    [ -n "$CF_TUNNEL_NAME" ] || CF_TUNNEL_NAME="psp-$(printf '%s' "$CF_HOSTNAME" | tr '.' '-')"
    cf_call GET "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel?name=${CF_TUNNEL_NAME}&is_deleted=false"
    if cf_ok && [ -n "$(cf_json '.result[0].id')" ]; then
        CF_TUNNEL_ID="$(cf_json '.result[0].id')"
        ok "Tunnel '${CF_TUNNEL_NAME}' already exists (${CF_TUNNEL_ID}) — reusing it"
    else
        say "Creating the Cloudflare Tunnel '${CF_TUNNEL_NAME}'..."
        cf_call POST "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel" \
            "{\"name\":\"${CF_TUNNEL_NAME}\",\"config_src\":\"cloudflare\"}"
        if ! cf_ok; then
            # Older API behaviour wants an explicit 32-byte secret even for a
            # remotely-managed tunnel. Retry with one before giving up.
            _tunnel_secret="$(if have openssl; then openssl rand -base64 32; else head -c 32 /dev/urandom | base64; fi | tr -d '\n')"
            cf_call POST "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel" \
                "{\"name\":\"${CF_TUNNEL_NAME}\",\"config_src\":\"cloudflare\",\"tunnel_secret\":\"${_tunnel_secret}\"}"
        fi
        cf_ok || die "Could not create the tunnel: $(cf_error)
    The token needs Account -> Cloudflare Tunnel -> Edit."
        CF_TUNNEL_ID="$(cf_json '.result.id')"
        CF_TUNNEL_TOKEN="$(cf_json '.result.token')"
        [ -n "$CF_TUNNEL_ID" ] || die "Cloudflare returned no tunnel id. Try again, or create the tunnel by hand in the Zero Trust dashboard."
        ok "Tunnel created (${CF_TUNNEL_ID})"
    fi
    if [ -z "$CF_TUNNEL_TOKEN" ]; then
        cf_call GET "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${CF_TUNNEL_ID}/token"
        cf_ok || die "Could not read the tunnel token: $(cf_error)"
        CF_TUNNEL_TOKEN="$(cf_json '.result')"
    fi
    [ -n "$CF_TUNNEL_TOKEN" ] || die "Cloudflare returned no connector token for the tunnel."

    # 5. Ingress: every hostname goes to Caddy — the stack's router, which
    #    splits the request between the backend and the three Next.js apps.
    #    Anything else gets a 404 rather than being forwarded.
    _ingress=""
    for _h in $ALL_HOSTNAMES; do
        _ingress="${_ingress}{\"hostname\":\"${_h}\",\"service\":\"http://caddy:80\"},"
    done
    say "Routing to caddy:80: ${ALL_HOSTNAMES}"
    cf_call PUT "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${CF_TUNNEL_ID}/configurations" \
        "{\"config\":{\"ingress\":[${_ingress}{\"service\":\"http_status:404\"}]}}"
    cf_ok || die "Could not configure the tunnel ingress: $(cf_error)"
    ok "Tunnel routes configured"

    # 6. DNS: a proxied CNAME to the tunnel for every hostname.
    for _h in $ALL_HOSTNAMES; do
        cf_dns_upsert "$_h"
    done
fi

# --- download ----------------------------------------------------------------

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
        if [ "$WL_MODE" = "cloudflare" ]; then
            echo "# Production: dev webhook routes are off, the mock provider is disabled."
            echo "APP_ENV=production"
            echo
            echo "# Cloudflare Tunnel stack: cloudflared instead of published ports."
            echo "# This MUST stay set — the admin-panel self-update and"
            echo "# scripts/update.sh run a bare 'docker compose up -d --remove-orphans',"
            echo "# and against the default docker-compose.yml that deletes the"
            echo "# cloudflared service and re-publishes ports 80/443."
            echo "COMPOSE_FILE=docker-compose.cloudflare.yml"
            echo
            echo "# Connector token for tunnel '${CF_TUNNEL_NAME}' (${CF_TUNNEL_ID})."
            echo "CF_TUNNEL_TOKEN=${CF_TUNNEL_TOKEN}"
            echo
            echo "# Public hostname, created by the installer: a proxied CNAME to"
            echo "# ${CF_TUNNEL_ID}.cfargotunnel.com, routed to caddy:80 by the tunnel."
            echo "URL=https://${CF_HOSTNAME}"
            echo
            echo "# TLS is terminated by Cloudflare and this origin has no inbound"
            echo "# port, so no certificate can ever be validated here. Tells the"
            echo "# stack to serve every hostname over plain HTTP, skip ACME and"
            echo "# skip the http->https redirect (it would loop through the edge)."
            echo "TLS_TERMINATION=edge"
            echo
            echo "# Debug port, loopback only: curl http://127.0.0.1:1337/health"
            echo "WL_LOCAL_BIND=127.0.0.1"
            if [ -n "${CF_ADMIN_HOSTNAME}${CF_MERCHANT_HOSTNAME}${CF_PAYMENT_HOSTNAME}${CF_API_HOSTNAME}" ]; then
                echo
                echo "# Per-app hostnames, already created on the tunnel by the installer."
                echo "# The backend writes them into the installation on first boot, so"
                echo "# routing works right away and the wizard's Domains step comes"
                echo "# pre-filled. After that the wizard/admin panel are authoritative."
                if [ -n "$CF_ADMIN_HOSTNAME" ]; then echo "WL_ADMIN_DOMAIN=${CF_ADMIN_HOSTNAME}"; fi
                if [ -n "$CF_MERCHANT_HOSTNAME" ]; then echo "WL_MERCHANT_DOMAIN=${CF_MERCHANT_HOSTNAME}"; fi
                if [ -n "$CF_PAYMENT_HOSTNAME" ]; then echo "WL_PAYMENT_DOMAIN=${CF_PAYMENT_HOSTNAME}"; fi
                if [ -n "$CF_API_HOSTNAME" ]; then echo "WL_API_DOMAIN=${CF_API_HOSTNAME}"; fi
            fi
            if [ -n "$CF_ADMIN_HOSTNAME" ]; then
                echo
                echo "# Links in invite / reset-password emails point at the admin panel's"
                echo "# own hostname instead of the main one."
                echo "ADMIN_PANEL_URL=https://${CF_ADMIN_HOSTNAME}"
            fi
        elif [ "$WL_MODE" = "server" ]; then
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
            if [ -n "$NGROK_DOMAIN" ] && [ -n "$NGROK_AUTHTOKEN" ]; then
                echo "# Public dev tunnel (ngrok), issued by the license server: gives this"
                echo "# local install a stable public HTTPS URL so Crypto Chief webhooks"
                echo "# reach it. COMPOSE_PROFILES=tunnel makes 'docker compose up' start"
                echo "# the bundled ngrok service (forwards the tunnel into Caddy)."
                echo "URL=https://${NGROK_DOMAIN}"
                echo "NGROK_DOMAIN=${NGROK_DOMAIN}"
                echo "NGROK_AUTHTOKEN=${NGROK_AUTHTOKEN}"
                echo "COMPOSE_PROFILES=tunnel"
                echo
            fi
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
CHECK_DOMAIN="$BOOTSTRAP_DOMAIN"
# In Cloudflare mode the tunnel is the ONLY way in — there is no port to fall
# back to — so this check is what tells the operator whether the install worked.
[ "$WL_MODE" = "cloudflare" ] && CHECK_DOMAIN="$CF_HOSTNAME"
if [ -n "$CHECK_DOMAIN" ]; then
    say "Checking the HTTPS address ${CHECK_DOMAIN}..."
    for _ in $(seq 1 20); do
        if curl -fsS --max-time 5 "https://${CHECK_DOMAIN}/health" >/dev/null 2>&1; then
            DOMAIN_OK=1
            break
        fi
        sleep 3
    done
    if [ "$DOMAIN_OK" -eq 1 ]; then
        ok "Reachable: https://${CHECK_DOMAIN}"
    elif [ "$WL_MODE" = "cloudflare" ]; then
        warn "https://${CHECK_DOMAIN} did not answer yet. Check the connector: cd $WL_DIR && docker compose logs -f cloudflared"
    else
        warn "https://${CHECK_DOMAIN} did not answer yet (DNS can take a few minutes to propagate)."
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
if [ "$WL_MODE" = "cloudflare" ]; then
    printf '  Open the install wizard to finish the setup:\n\n'
    printf '      %shttps://%s/install%s\n\n' "$C_INFO" "$CF_HOSTNAME" "$C_OFF"
    printf '  Everything runs through your Cloudflare Tunnel:\n'
    printf '    tunnel     %s (%s)\n' "$CF_TUNNEL_NAME" "$CF_TUNNEL_ID"
    printf '    main       https://%s\n' "$CF_HOSTNAME"
    if [ -n "$CF_ADMIN_HOSTNAME" ]; then printf '    admin      https://%s\n' "$CF_ADMIN_HOSTNAME"; fi
    if [ -n "$CF_MERCHANT_HOSTNAME" ]; then printf '    merchant   https://%s\n' "$CF_MERCHANT_HOSTNAME"; fi
    if [ -n "$CF_PAYMENT_HOSTNAME" ]; then printf '    payments   https://%s\n' "$CF_PAYMENT_HOSTNAME"; fi
    if [ -n "$CF_API_HOSTNAME" ]; then printf '    API        https://%s\n' "$CF_API_HOSTNAME"; fi
    printf '    DNS        every hostname -> %s.cfargotunnel.com (proxied)\n' "$CF_TUNNEL_ID"
    printf '\n'
    printf '  %sNo inbound port is needed%s — not 80, not 443, not 1337. The\n' "$C_OK" "$C_OFF"
    printf '  connector dials out to Cloudflare on port 7844, and TLS is\n'
    printf '  terminated there, so nothing is issued or renewed on this machine.\n'
    if [ "$DOMAIN_OK" -ne 1 ]; then
        printf '\n'
        printf '  The address did not answer during the check — give DNS a minute,\n'
        printf '  then watch the connector: docker compose logs -f cloudflared\n'
    fi
    printf '\n'
    printf '  Want a login gate in front of the admin panel? Zero Trust ->\n'
    printf '  Access -> Applications, and scope the policy to the %s/admin%s path.\n' "$C_INFO" "$C_OFF"
    printf '  %sDo not put it on the whole hostname%s: that would also gate\n' "$C_WARN" "$C_OFF"
    printf '  /webhook/saas and the public payment pages, and payments would\n'
    printf '  start bouncing off a login screen.\n'
elif [ "$WL_MODE" = "server" ] && [ -n "$BOOTSTRAP_DOMAIN" ]; then
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
    if [ -n "$NGROK_DOMAIN" ]; then
        printf '\n'
        printf '  Public HTTPS tunnel (so Crypto Chief webhooks reach this machine):\n'
        printf '      %shttps://%s%s\n' "$C_INFO" "$NGROK_DOMAIN" "$C_OFF"
        printf '  Set it as your Crypto Chief API keys in the wizard, then payments\n'
        printf '  and webhooks work end-to-end against your local stack.\n'
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
