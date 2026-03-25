terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
  }
  required_version = ">= 1.6.0"
}

provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_firewall" "server" {
  name = "agent-server-fw"

  # WireGuard UDP
  rule {
    direction = "in"
    protocol  = "udp"
    port      = "51820"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  # Allow all outbound (needed for Cloudflare tunnel, apt, etc.)
  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "any"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction       = "out"
    protocol        = "icmp"
    destination_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "agent" {
  name        = "agent-server"
  server_type = "cax11"
  image       = "ubuntu-24.04"
  location    = "nbg1"
  firewall_ids = [hcloud_firewall.server.id]

  user_data = templatefile("${path.module}/cloud-init.yaml", {
    wg_server_private_key = var.wg_server_private_key
    wg_server_address     = var.wg_server_address
    wg_client_public_key  = var.wg_client_public_key
    wg_client_allowed_ip  = var.wg_client_allowed_ip
  })
}
