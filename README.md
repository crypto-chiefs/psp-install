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

The installer asks for your installation key and whether this is a public
server or a local computer. It then installs git, Docker and Docker Compose
if they are missing, downloads the latest stable version and starts the
stack.

- **Public server**: production mode. The installer prints a ready HTTPS
  link like `https://<organization-id>.psp-crypto-chief.com/install`. No
  domain and no certificate setup needed at this point: the license server
  creates the DNS record for your public IP automatically and Cloudflare
  handles TLS in front of your server.
- **Local computer**: demo mode at `http://localhost:1337/install`.

Open the link and finish the setup in the web wizard: create the admin
account, set your branding, connect your Crypto Chief API keys, configure
SMTP and your custom domains.

Non-interactive install:

```bash
WL_LICENSE_KEY=<your-key> WL_MODE=server \
  bash <(curl -sSL https://raw.githubusercontent.com/crypto-chiefs/psp-install/main/scripts/install.sh)
```

Optional environment variables: `WL_DIR` sets the install directory (default
`/opt/psp-crypto`, or `~/psp-crypto` on macOS/Windows), `WL_CHANNEL` sets the
release branch (default `stable`), `WL_LICENSE_API` overrides the license
server URL.

## Updating

Open **Configuration -> Updates** in the admin panel: it shows the version
changelog and updates the platform in one click. Manual alternative on the
server:

```bash
cd /opt/psp-crypto && sh scripts/update.sh
```

## Uninstall

```bash
cd /opt/psp-crypto
docker compose down -v
cd / && rm -rf /opt/psp-crypto
```

Note: `down -v` deletes the database volumes. Back up first if you need the
data.

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
your own domains later in the admin panel.

**Which cryptocurrencies does it support?**
Bitcoin, Ethereum, BNB Smart Chain, Polygon, Tron, TON, Solana, Litecoin,
Dogecoin, XRP and more, plus stablecoins such as USDT and USDC. See the
[REST API reference](https://docs-processing.crypto-chief.com) for the
current list.

**Is it really white-label?**
Yes. You set your own name, logo and colors, and connect custom domains for
the admin panel, merchant cabinets and payment pages — each with automatic
Let's Encrypt certificates.

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
