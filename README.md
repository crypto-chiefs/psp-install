# PSP Crypto Platform — Self-Hosted White-Label Crypto Payment Gateway

[![Product page](https://img.shields.io/badge/product-crypto--chief.com%2Fwhitelabel-1f6feb)](https://crypto-chief.com/whitelabel/)
[![REST API docs](https://img.shields.io/badge/docs-REST%20API-2ea44f)](https://docs-processing.crypto-chief.com)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-555)](#requirements)
[![Docker Compose](https://img.shields.io/badge/stack-Docker%20Compose-2496ED?logo=docker&logoColor=white)](#install)

**PSP Crypto Platform** is **self-hosted crypto payment processing software** —
a **white-label crypto payment gateway** you run on your own server, under
your own brand, with your own merchants. Accept cryptocurrency payments
(pay-in), send crypto payouts (pay-out), issue static deposit addresses and
sweep funds automatically across Bitcoin, Ethereum, Tron, TON, Solana and
other major networks, including stablecoins such as USDT and USDC. Payment
processing is powered by the [Crypto Chief](https://crypto-chief.com/whitelabel/)
network; the brand, the data and the merchant relationships stay with you.

This repository contains the public **one-command installer**. The platform
itself is distributed from a private repository and requires an installation
key (see [Getting an installation key](#getting-an-installation-key)).

```bash
bash <(curl -sSL https://raw.githubusercontent.com/crypto-chiefs/psp-install/main/scripts/install.sh)
```

Built for payment companies, fintechs, exchanges and agencies that want to
**launch their own crypto payment service (PSP)** without building processing
infrastructure from scratch.

## What you get

- **Crypto payments.** Invoices (pay-in), payouts (pay-out), static deposit
  addresses and automatic sweeps across the major networks and coins.
- **Hosted payment page.** A ready-to-use crypto checkout with QR codes,
  asset selection and live payment status. Share payment links or embed it
  on your site.
- **Merchant cabinets.** Unlimited merchants, team members with roles,
  wallets, transaction history, CSV reports, API keys and webhooks.
- **Admin panel.** Dashboard, cross-merchant journals (transactions,
  withdrawals, sweeps, static deposits), fee plans and billing, webhook
  monitor, audit log.
- **White label.** Your name, logo and colors. Custom domains for the admin
  panel, merchant cabinets and payment pages, with automatic Let's Encrypt
  certificates.
- **Developer API.** HTTP API for server-to-server integrations plus signed
  webhooks, compatible with the [Crypto Chief SDKs](https://docs-sdk.crypto-chief.com).
- **Flexible deployment.** Publish on a public IP with automatic TLS — or
  through a **Cloudflare Tunnel** with zero open inbound ports, on a VPS,
  behind NAT or on-prem.
- **One-click updates.** Built-in updater with a version changelog, run
  straight from the admin panel.

## Supported blockchains and assets

Bitcoin, Ethereum, BNB Smart Chain, Polygon, Tron, TON, Solana, Litecoin,
Dogecoin, XRP and more, with native coins and stablecoins (USDT, USDC).
The current list of networks and assets is in the
[REST API reference](https://docs-processing.crypto-chief.com).

## Under the hood

Go backend, Next.js frontends, PostgreSQL, Formance Ledger and Caddy,
shipped as a single Docker Compose stack. Everything runs on your server
and your data stays with you.

## Requirements

- A Linux server (Debian, Ubuntu, RHEL, Fedora, openSUSE, Arch or Alpine)
  with 2+ GB RAM and 20 GB of disk. macOS and Windows (Git Bash) are fine
  for local evaluation.
- Port 80 reachable from the internet (production installs) — Cloudflare
  forwards the wizard traffic to it; port 443 is needed once you add your
  own domains. The backend/wizard port 1337 is bound to localhost only and
  is not exposed. (Without a bootstrap domain the installer publishes 1337
  so you can reach the wizard at `http://<ip>:1337`.)
  With the **Cloudflare Tunnel** install mode no inbound port is needed at
  all — only outbound access to Cloudflare on port 7844.
- An installation key.

## Getting an installation key

The platform is downloaded from a private repository, so the installer asks
for an installation key. To get one, contact the Crypto Chief team:

- <https://crypto-chief.com/contact/>
- admin@crypto-chief.com

## Install

Run on the server (as root on Linux):

```bash
bash <(curl -sSL https://raw.githubusercontent.com/crypto-chiefs/psp-install/main/scripts/install.sh)
```

The installer asks for your installation key and where you are installing.
It then installs git, Docker and Docker Compose if they are missing,
downloads the latest stable version and starts the stack.

- **Public server**: production mode. The installer prints a ready HTTPS
  link like `https://<organization-id>.psp-crypto-chief.com/install`. No
  domain and no certificate setup needed at this point: the license server
  creates the DNS record for your public IP automatically and Cloudflare
  handles TLS in front of your server.
- **Local computer**: demo mode at `http://localhost:1337/install`.
- **Cloudflare Tunnel**: production on your own domain with **no inbound
  port at all** — see below.

Open the link and finish the setup in the web wizard: create the admin
account, set your branding, connect your Crypto Chief API keys, configure
SMTP and your custom domains.

Non-interactive install:

```bash
WL_LICENSE_KEY=<your-key> WL_MODE=server \
  bash <(curl -sSL https://raw.githubusercontent.com/crypto-chiefs/psp-install/main/scripts/install.sh)
```

Optional environment variables: `WL_DIR` sets the install directory (default
`~/psp-crypto`), `WL_CHANNEL` sets the release branch (default `stable`),
`WL_LICENSE_API` overrides the license server URL.

### Install behind a Cloudflare Tunnel (Zero Trust)

Choose **3) Cloudflare Tunnel** and the platform is published on your own
domain without opening a single port. A `cloudflared` connector inside the
stack dials out to Cloudflare on port 7844 and Cloudflare proxies your
hostname into it, terminating TLS at the edge — nothing listens on 80, 443
or 1337, and no certificate is ever issued or renewed on your machine. It
works the same on a VPS, behind NAT, and on a laptop.

The installer asks for a Cloudflare API token and your domain, then does the
rest itself:

1. verifies the token against Cloudflare and checks it is active,
2. installs `jq` (or downloads the official static binary) so the API
   responses are parsed exactly, not guessed at,
3. resolves your zone and its account,
4. creates the tunnel and routes your hostname to the platform,
5. creates the proxied DNS record,
6. writes the configuration, starts the stack and verifies that
   `https://<your-hostname>/health` actually answers.

Create the API token at
<https://dash.cloudflare.com/profile/api-tokens> → *Create Token* →
*Custom token*, with:

| Scope | Permission |
|---|---|
| Account | Cloudflare Tunnel → Edit |
| Zone | DNS → Edit |
| Zone | Zone → Read |

One hostname is enough — it serves the wizard, admin panel, merchant
cabinet, payment pages, API and incoming webhooks by path. The installer
can also create per-app subdomains (`admin.`, `merchant.`, `pay.`, `api.`)
on the same tunnel: pick **Per-app subdomains** in the layout question. The
platform picks them up on its first boot, so the wizard's Domains step
comes pre-filled and each cabinet opens on its own address right away.

Re-running the installer is safe on the Cloudflare side: the tunnel name is
derived from the hostname, so an existing tunnel is reused rather than
duplicated, and a DNS record that points anywhere other than a tunnel is
never overwritten without an explicit confirmation.

Non-interactive:

```bash
WL_LICENSE_KEY=<your-key> WL_MODE=cloudflare \
CF_API_TOKEN=<cloudflare-token> CF_ZONE=example.com CF_HOSTNAME=psp.example.com \
  bash <(curl -sSL https://raw.githubusercontent.com/crypto-chiefs/psp-install/main/scripts/install.sh)
```

Add `CF_LAYOUT=single` to skip the layout question, or pass the subdomains
directly (any subset): `CF_ADMIN_HOSTNAME=admin.example.com`
`CF_MERCHANT_HOSTNAME=merchant.example.com` `CF_PAYMENT_HOSTNAME=pay.example.com`
`CF_API_HOSTNAME=api.example.com`.

If you later add a login gate in Cloudflare Access, scope the policy to the
`/admin` path (or to the admin hostname when you use subdomains): an Access
application covering everything would also gate incoming payment webhooks
and the public payment pages.

## Updating

Open **Configuration -> Updates** in the admin panel: it shows the version
changelog and updates the platform in one click. Manual alternative on the
server:

```bash
cd ~/psp-crypto && sh scripts/update.sh
```

## Uninstall

```bash
cd ~/psp-crypto
docker compose down -v
cd / && rm -rf ~/psp-crypto
```

Note: `down -v` deletes the database volumes. Back up first if you need the
data.

If you installed in the **Cloudflare Tunnel** mode, also clean up the
resources the installer created in your Cloudflare account: delete the
tunnel in **Zero Trust → Networks → Tunnels** and the `CNAME` records
pointing at `<tunnel-id>.cfargotunnel.com` in the zone's DNS.

## Self-hosted vs hosted crypto payment gateway

|  | Hosted gateway (SaaS) | PSP Crypto Platform (self-hosted) |
|---|---|---|
| Branding | The provider's brand | **Your brand** — name, logo, colors, custom domains |
| Merchants | The provider's customers | **Your merchants**, onboarded by you |
| Fees | Set by the provider | **Your fee plans** and billing |
| Data | On the provider's servers | **On your server** — PostgreSQL and ledger you control |
| Infrastructure | None to manage | One Docker Compose stack with one-click updates |

## FAQ

**What is PSP Crypto Platform?**
PSP Crypto Platform is self-hosted, white-label crypto payment processing
software: a complete crypto payment gateway — pay-ins, payouts, hosted
checkout, merchant cabinets, admin panel and developer API — that you install
on your own server and run under your own brand. Payment processing is
powered by the Crypto Chief network.

**How do I start my own crypto payment gateway?**
Three steps: get an installation key from the
[Crypto Chief team](https://crypto-chief.com/contact/), run the one-command
installer on a Linux server, then finish the web wizard — admin account,
branding, API keys, SMTP and domains.

**Do I need a domain to launch?**
No. In production mode the installer prints a ready HTTPS link like
`https://<organization-id>.psp-crypto-chief.com/install` — the DNS record
for your public IP is created automatically and TLS is handled by
Cloudflare, so nothing needs to be issued or configured locally. Connect
your own domains later in the admin panel. If you already have a domain on
Cloudflare, pick the **Cloudflare Tunnel** install mode instead and launch
on your own domain right away.

**Can I run a crypto payment gateway without opening any ports?**
Yes. The **Cloudflare Tunnel** install mode publishes PSP Crypto Platform
on your own domain with zero inbound ports: a `cloudflared` connector
inside the stack dials out to Cloudflare (port 7844) and Cloudflare proxies
your hostname into it, terminating TLS at the edge. The installer creates
the tunnel, the routes and the DNS records itself from a Cloudflare API
token — it works on a VPS, behind NAT and even on a home machine.

**Which cryptocurrencies does it support?**
Bitcoin, Ethereum, BNB Smart Chain, Polygon, Tron, TON, Solana, Litecoin,
Dogecoin, XRP and more, plus stablecoins such as USDT and USDC. See the
[REST API reference](https://docs-processing.crypto-chief.com) for the
current list.

**Is it really white-label?**
Yes. You set your own name, logo and colors, and connect custom domains for
the admin panel, merchant cabinets and payment pages — with automatic
Let's Encrypt certificates, or TLS at the Cloudflare edge when installed
behind a Cloudflare Tunnel.

**Does it have an API and SDKs?**
Yes. The platform exposes an HTTP API for server-to-server integrations plus
signed webhooks, compatible with the Crypto Chief SDKs — for example the
[official Go SDK](https://github.com/crypto-chiefs/cryptochief-crypto-processing-go).
See the [REST API reference](https://docs-processing.crypto-chief.com) and
the [SDK documentation](https://docs-sdk.crypto-chief.com).

**Can I evaluate it on a laptop before renting a server?**
Yes. Choose "local computer" in the installer (or set `WL_MODE=local`) and
the stack starts in demo mode at `http://localhost:1337/install`. macOS and
Windows (Git Bash) work for local evaluation.

**How do updates work?**
Open **Configuration -> Updates** in the admin panel: it shows the version
changelog and updates the platform in one click. Or run
`sh scripts/update.sh` from the install directory on the server.

**How much does it cost?**
The platform is licensed via installation keys. Contact the Crypto Chief
team for pricing: <https://crypto-chief.com/contact/> or
admin@crypto-chief.com.

## Documentation and related projects

- Product page — [crypto-chief.com/whitelabel](https://crypto-chief.com/whitelabel/)
- REST API reference — [docs-processing.crypto-chief.com](https://docs-processing.crypto-chief.com)
- SDK documentation — [docs-sdk.crypto-chief.com](https://docs-sdk.crypto-chief.com)
- Official Go SDK — [crypto-chiefs/cryptochief-crypto-processing-go](https://github.com/crypto-chiefs/cryptochief-crypto-processing-go)

## Support

Questions, licensing, installation keys: <https://crypto-chief.com/contact/>
or admin@crypto-chief.com.
