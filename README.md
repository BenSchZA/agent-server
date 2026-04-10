# Agent Server

Secure Hetzner Cloud server provisioned with OpenTofu. Zero exposed ports except WireGuard VPN. All web traffic routes through a Cloudflare Tunnel. Runs Claude Code with the Telegram plugin as a persistent service via tmux.

## Architecture

```
Telegram ──► Claude Code (Telegram plugin) ──► tools / local services
Internet  ──► Cloudflare Tunnel ──► cloudflared container ──► local services
You       ──► WireGuard VPN (UDP 51820) ──► SSH (VPN-only)
```

- **Server**: Hetzner CAX11 (ARM64), 2 vCPU, 4GB RAM, 40GB SSD, Ubuntu 24.04
- **Region**: nbg1 (Nuremberg, eu-central)
- **Firewall**: All inbound blocked except WireGuard UDP/51820
- **SSH**: Bound to WireGuard interface only, root login disabled, password auth off
- **Docker**: Installed with compose plugin, managed by non-root `deploy` user
- **Claude Code**: Native install (`~/.local/bin/claude`), runs in tmux via systemd with Telegram channel
- **Telegram plugin**: Bun-based MCP server forwarding Telegram messages to Claude
- **fail2ban**: Enabled with SSH jail
- **Automatic security updates**: Enabled via unattended-upgrades

## Prerequisites

- [OpenTofu](https://opentofu.org/) >= 1.6
- [WireGuard](https://www.wireguard.com/install/) client and tools (`brew install wireguard-tools`)
- Hetzner Cloud API token ([generate one](https://console.hetzner.cloud/projects))
- Cloudflare Tunnel token ([create a tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/create-remote-tunnel/))
- Telegram bot token (create one with [@BotFather](https://t.me/BotFather) — send `/newbot`)

## Quick reference

```
make help
```

| Command            | Description                                   |
|--------------------|-----------------------------------------------|
| `make keys`        | Generate WireGuard and SSH keys               |
| `make init`        | Initialize OpenTofu providers                 |
| `make plan`        | Preview infrastructure changes                |
| `make deploy`      | Deploy the server and generate wg-client.conf |
| `make destroy`     | Tear down all infrastructure                  |
| `make vpn-up`      | Connect WireGuard VPN                         |
| `make vpn-down`    | Disconnect WireGuard VPN                      |
| `make vpn-status`  | Show WireGuard connection status              |
| `make ssh`         | SSH into the server                           |
| `make reset-hostkey` | Remove stale SSH host key (after rebuild)   |
| `make status`      | Check cloud-init provisioning status          |
| `make logs`        | View Claude service logs                      |

## Setup

### 1. Generate keys

```bash
make keys
```

Generates WireGuard key pairs and an SSH key (`~/.ssh/id_server_agent`). Prints the values to add to `terraform.tfvars`.

### 2. Configure variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Fill in `terraform.tfvars` with the values from `make keys` plus your API tokens:

```hcl
server_name           = "agent"
hcloud_token          = "your-hetzner-api-token"
ssh_public_key        = "ssh-ed25519 AAAA... deploy@agent"
wg_server_private_key = "<from server_private.key>"
wg_client_public_key  = "<from client_public.key>"
wg_server_address     = "10.0.0.1/24"       # default, change if needed
wg_client_allowed_ip  = "10.0.0.2/32"       # default, change if needed
telegram_bot_token    = "123456789:AAHfiqksKZ8..."
```

### 3. Deploy

```bash
make init
make deploy
```

This provisions the server and auto-generates `wg-client.conf` with the correct endpoint IP.

### 4. Connect

```bash
make vpn-up
make status   # wait for cloud-init to finish (~3-4 min)
make ssh
```

If you get a host key warning after a rebuild, run `make reset-hostkey` first.

### 5. Start Cloudflare Tunnel (on server)

```bash
cp ~/.env.example ~/.env
# Edit ~/.env with your Cloudflare Tunnel token
docker compose up -d
```

### 6. Authenticate Claude Code via OAuth (on server)

```bash
claude
```

Claude prints an OAuth URL — open it in your local browser and authorize. The token is saved to `~/.claude/` and persists across sessions. Exit Claude after authenticating (`/exit`).

### 7. Install Telegram plugin (on server)

```bash
claude
```

Inside the Claude session:

```
/plugin install telegram@claude-plugins-official
/telegram:configure <your-telegram-bot-token>
```

Exit Claude (`/exit`).

### 8. Start Claude service (on server)

The service runs Claude in a tmux session so it has a TTY:

```bash
sudo systemctl start claude
sudo systemctl status claude
```

Attach to see the running session:

```bash
TERM=xterm-256color tmux attach -t claude
```

Detach with `Ctrl+B` then `D`.

### 9. Pair Telegram

1. DM your bot on Telegram — it replies with a 6-character pairing code
2. In a separate SSH session (`make ssh`), run `claude` then `/telegram:access pair <code>`
3. Lock down access: `/telegram:access policy allowlist`

Your bot is now live. Messages to the Telegram bot are handled by Claude Code.

## Managing the Claude service

```bash
# View logs locally
make logs

# On the server:
sudo systemctl start claude
sudo systemctl stop claude
sudo systemctl restart claude

# Attach to the tmux session
TERM=xterm-256color tmux attach -t claude
# Detach: Ctrl+B then D
```

## Giving Claude access to a GitHub repo

The recommended approach is a **fine-grained personal access token** (PAT) scoped to specific repos. Alternatively, use **deploy keys** for single-repo read-only access.

### Option A: Deploy key (per-repo, most locked down)

On the server, generate a GitHub SSH key:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_github -N "" -C "deploy@agent"
cat ~/.ssh/id_github.pub
```

Configure SSH to use it for GitHub:

```bash
cat >> ~/.ssh/config << 'EOF'
Host github.com
  IdentityFile ~/.ssh/id_github
  IdentitiesOnly no
EOF
```

Then add the public key as a deploy key on your repo: **GitHub repo > Settings > Deploy keys > Add deploy key**. Choose read-only or read/write.

This key is scoped to exactly one repo. Repeat for additional repos.

### Option B: Fine-grained PAT (multi-repo, granular permissions)

1. Go to **GitHub > Settings > Developer Settings > Personal Access Tokens > Fine-grained tokens**
2. Create a token scoped to specific repos with the permissions you need (e.g. read/write contents, PRs, issues)
3. On the server, authenticate the GitHub CLI:

```bash
echo "<your-token>" | gh auth login --with-token
```

This gives Claude access to `gh` commands (clone, PRs, issues) for the scoped repos.

## Adding services

Add services to `docker-compose.yaml` on the server. Configure routing in the Cloudflare Tunnel dashboard to point at `localhost:<port>`.

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
| `Makefile` | Setup, connect, and teardown commands |
| `main.tf` | Server, firewall, SSH key, and provider config |
| `variables.tf` | Input variables (`server_name` used as prefix) |
| `outputs.tf` | Server IP and WireGuard endpoint |
| `cloud-init.yaml` | Server provisioning (WireGuard, Docker, Claude Code, Bun, Telegram plugin, SSH, fail2ban, UFW) |
| `docker-compose.yaml` | Local copy of the compose file deployed to the server |
| `env.example` | Environment variable template |
| `terraform.tfvars.example` | Terraform variable template |

## Teardown

```bash
make vpn-down
make destroy
```
