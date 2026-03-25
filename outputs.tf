output "server_ip" {
  description = "Public IP of the server (use for WireGuard endpoint)"
  value       = hcloud_server.agent.ipv4_address
}

output "server_ipv6" {
  description = "IPv6 address of the server"
  value       = hcloud_server.agent.ipv6_address
}

output "wireguard_endpoint" {
  description = "WireGuard endpoint for client config"
  value       = "${hcloud_server.agent.ipv4_address}:51820"
}
