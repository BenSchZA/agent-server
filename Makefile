SSH_KEY := ~/.ssh/id_server_agent
WG_CONF := wg-client.conf
WG_SERVER_IP := 10.0.0.1

# --- Setup ---

.PHONY: keys
keys: ## Generate WireGuard and SSH keys
	wg genkey | tee server_private.key | wg pubkey > server_public.key
	wg genkey | tee client_private.key | wg pubkey > client_public.key
	ssh-keygen -t ed25519 -f $(SSH_KEY) -N "" -C "deploy@agent"
	@echo ""
	@echo "Keys generated. Add these to terraform.tfvars:"
	@echo "  ssh_public_key        = \"$$(cat $(SSH_KEY).pub)\""
	@echo "  wg_server_private_key = \"$$(cat server_private.key)\""
	@echo "  wg_client_public_key  = \"$$(cat client_public.key)\""

.PHONY: init
init: ## Initialize OpenTofu providers
	tofu init

.PHONY: plan
plan: ## Preview infrastructure changes
	tofu plan

.PHONY: reset-hostkey
reset-hostkey: ## Remove old SSH host key for server (after rebuild)
	ssh-keygen -R $(WG_SERVER_IP)

.PHONY: deploy
deploy: ## Deploy the server
	tofu apply -auto-approve
	@echo ""
	@echo "Generating wg-client.conf..."
	@SERVER_IP=$$(tofu output -raw server_ip); \
	echo "[Interface]" > $(WG_CONF); \
	echo "PrivateKey = $$(cat client_private.key)" >> $(WG_CONF); \
	echo "Address = 10.0.0.2/24" >> $(WG_CONF); \
	echo "DNS = 1.1.1.1" >> $(WG_CONF); \
	echo "" >> $(WG_CONF); \
	echo "[Peer]" >> $(WG_CONF); \
	echo "PublicKey = $$(cat server_public.key)" >> $(WG_CONF); \
	echo "Endpoint = $$SERVER_IP:51820" >> $(WG_CONF); \
	echo "AllowedIPs = 10.0.0.1/32" >> $(WG_CONF); \
	echo "PersistentKeepalive = 25" >> $(WG_CONF)
	@echo "Done. Run 'make vpn-up' to connect."

.PHONY: destroy
destroy: ## Tear down all infrastructure
	tofu destroy -auto-approve

# --- Connect ---

.PHONY: vpn-up
vpn-up: ## Connect WireGuard VPN
	sudo wg-quick up ./$(WG_CONF)

.PHONY: vpn-down
vpn-down: ## Disconnect WireGuard VPN
	sudo wg-quick down ./$(WG_CONF)

.PHONY: vpn-status
vpn-status: ## Show WireGuard connection status
	sudo wg show

.PHONY: ssh
ssh: ## SSH into the server
	ssh -i $(SSH_KEY) deploy@$(WG_SERVER_IP)

.PHONY: status
status: ## Check cloud-init provisioning status on server
	ssh -i $(SSH_KEY) deploy@$(WG_SERVER_IP) "cloud-init status"

.PHONY: logs
logs: ## View Claude service logs on server
	ssh -i $(SSH_KEY) deploy@$(WG_SERVER_IP) "journalctl -u claude -f"

# --- Help ---

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
