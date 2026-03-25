# Agent Server

Secure Hetzner Cloud server provisioned with OpenTofu. Zero exposed ports except WireGuard VPN. All web traffic routes through a Cloudflare Tunnel.

## Architecture

```
Internet ──► Cloudflare Tunnel ──► cloudflared container ──► local services
                                        │
You ──► WireGuard VPN (UDP 51820) ──► SSH (VPN-only)
```

- **Server**: Hetzner CAX11 (ARM64), 2 vCPU, 4GB RAM, 40GB SSD, Ubuntu 24.04
- **Region**: nbg1 (Nuremberg, eu-central)
- **Firewall**: All inbound blocked except WireGuard UDP/51820
- **SSH**: Bound to WireGuard interface only, root login disabled, password auth off
- **Docker**: Installed with compose plugin, managed by non-root `deploy` user
- **fail2ban**: Enabled with SSH jail
- **Automatic security updates**: Enabled via unattended-upgrades

## Prerequisites

- [OpenTofu](https://opentofu.org/) >= 1.6
- [WireGuard](https://www.wireguard.com/install/) client
- Hetzner Cloud API token ([generate one](https://console.hetzner.cloud/projects))
- Cloudflare Tunnel token ([create a tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/create-remote-tunnel/))

## Setup

### 1. Generate WireGuard keys

```bash
# Server keys
wg genkey | tee server_private.key | wg pubkey > server_public.key

# Client keys
wg genkey | tee client_private.key | wg pubkey > client_public.key
```

### 2. Configure Terraform variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
hcloud_token          = "your-hetzner-api-token"
wg_server_private_key = "<contents of server_private.key>"
wg_client_public_key  = "<contents of client_public.key>"
```

### 3. Deploy

```bash
tofu init
tofu plan
tofu apply
```

Note the `server_ip` and `wireguard_endpoint` from the output.

### 4. Configure WireGuard client

Create a client config (e.g. `wg-client.conf`):

```ini
[Interface]
PrivateKey = <contents of client_private.key>
Address = 10.0.0.2/24
DNS = 1.1.1.1

[Peer]
PublicKey = <contents of server_public.key>
Endpoint = <server_ip>:51820
AllowedIPs = 10.0.0.1/32
PersistentKeepalive = 25
```

Activate:

```bash
# macOS / Linux
sudo wg-quick up ./wg-client.conf

# Or import into WireGuard GUI app
```

### 5. Connect and start services

```bash
# SSH over VPN
ssh deploy@10.0.0.1

# On the server
cp ~/.env.example ~/.env
# Edit ~/.env with your Cloudflare Tunnel token
cd ~
docker compose up -d
```

## Adding services

Add services to `docker-compose.yaml` on the server. They don't need to expose ports publicly — configure them in your Cloudflare Tunnel dashboard to route traffic to `localhost:<port>`.

Example with a web app:

```yaml
services:
  cloudflared:
    image: cloudflare/cloudflared:latest
    container_name: cloudflared
    restart: unless-stopped
    command: tunnel run
    environment:
      - TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN}
    env_file:
      - .env
    network_mode: host

  myapp:
    image: myapp:latest
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:8080"
```

Then in Cloudflare Zero Trust dashboard, route `myapp.example.com` to `http://localhost:8080`.

## Files

| File | Purpose |
|---|---|
| `main.tf` | Server, firewall, and provider config |
| `variables.tf` | Input variables |
| `outputs.tf` | Server IP and WireGuard endpoint |
| `cloud-init.yaml` | Server provisioning (WireGuard, Docker, SSH, fail2ban, UFW) |
| `docker-compose.yaml` | Local copy of the compose file deployed to the server |
| `env.example` | Environment variable template |
| `terraform.tfvars.example` | Terraform variable template |

## Teardown

```bash
tofu destroy
```
