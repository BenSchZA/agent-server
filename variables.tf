variable "server_name" {
  description = "Name used for server, firewall, and SSH key resources"
  type        = string
  default     = "agent"
}

variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key for the deploy user"
  type        = string
}

variable "wg_server_private_key" {
  description = "WireGuard server private key (generate with: wg genkey)"
  type        = string
  sensitive   = true
}

variable "wg_server_address" {
  description = "WireGuard server VPN address"
  type        = string
  default     = "10.0.0.1/24"
}

variable "wg_client_public_key" {
  description = "WireGuard client public key"
  type        = string
}

variable "wg_client_allowed_ip" {
  description = "WireGuard client allowed IP"
  type        = string
  default     = "10.0.0.2/32"
}

variable "telegram_bot_token" {
  description = "Telegram bot token from BotFather"
  type        = string
  sensitive   = true
}
