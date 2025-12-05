ifndef MK_COMMON_ANSIBLE_VAULT_INCLUDED
MK_COMMON_ANSIBLE_VAULT_INCLUDED := 1

# Vault password file to use with --vault-password-file
ANSIBLE_VAULT_PASS_FILE ?= vault_password.txt

# Directory and filename prefix for secrets
ANSIBLE_VAULT_VARS_DIR   ?= vars
ANSIBLE_VAULT_FILE_PREFIX ?= secrets

# Environments to manage (dev, prod, stage, etc.)
ANSIBLE_VAULT_ENVIRONMENTS ?= dev prod

# Derived file lists
ANSIBLE_VAULT_PLAINTEXT_FILES := \
  $(foreach env,$(ANSIBLE_VAULT_ENVIRONMENTS), \
    $(ANSIBLE_VAULT_VARS_DIR)/$(ANSIBLE_VAULT_FILE_PREFIX).$(env).yaml)

ANSIBLE_VAULT_ENCRYPTED_FILES := \
  $(foreach env,$(ANSIBLE_VAULT_ENVIRONMENTS), \
    $(ANSIBLE_VAULT_VARS_DIR)/$(ANSIBLE_VAULT_FILE_PREFIX).$(env).vault.yaml)

# Internal: ensure ansible-vault is installed
.PHONY: ansible-vault-check
ansible-vault-check:
	@if ! command -v ansible-vault >/dev/null 2>&1; then \
	  echo "Error: ansible-vault not found in PATH."; \
	  echo "Install Ansible, e.g.:"; \
	  echo "  pipx install ansible-core   # or"; \
	  echo "  pip install --user ansible-core"; \
	  exit 1; \
	fi

# ---- Encrypt / decrypt per environment --------------------------------------

# Encrypt one environment:
#   make vault-encrypt ENV=dev
.PHONY: vault-encrypt
vault-encrypt: ansible-vault-check ## Encrypt secrets for ENV (e.g. ENV=dev)
	@if [ -z "$$ENV" ]; then \
	  echo "Usage: make vault-encrypt ENV=<env>"; \
	  echo "       where <env> is one of: $(ANSIBLE_VAULT_ENVIRONMENTS)"; \
	  exit 1; \
	fi
	ansible-vault encrypt \
	  --output $(ANSIBLE_VAULT_VARS_DIR)/$(ANSIBLE_VAULT_FILE_PREFIX).$$ENV.vault.yaml \
	  --vault-password-file $(ANSIBLE_VAULT_PASS_FILE) \
	  $(ANSIBLE_VAULT_VARS_DIR)/$(ANSIBLE_VAULT_FILE_PREFIX).$$ENV.yaml

# Decrypt one environment:
#   make vault-decrypt ENV=dev
.PHONY: vault-decrypt
vault-decrypt: ansible-vault-check ## Decrypt secrets for ENV (e.g. ENV=dev)
	@if [ -z "$$ENV" ]; then \
	  echo "Usage: make vault-decrypt ENV=<env>"; \
	  echo "       where <env> is one of: $(ANSIBLE_VAULT_ENVIRONMENTS)"; \
	  exit 1; \
	fi
	ansible-vault decrypt \
	  $(ANSIBLE_VAULT_VARS_DIR)/$(ANSIBLE_VAULT_FILE_PREFIX).$$ENV.vault.yaml \
	  --vault-password-file $(ANSIBLE_VAULT_PASS_FILE) \
	  --output $(ANSIBLE_VAULT_VARS_DIR)/$(ANSIBLE_VAULT_FILE_PREFIX).$$ENV.yaml

# ---- Bulk operations ---------------------------------------------------------

.PHONY: vault-encrypt-all
vault-encrypt-all: ansible-vault-check ## Encrypt secrets for all environments
	@for env in $(ANSIBLE_VAULT_ENVIRONMENTS); do \
	  echo "Encrypting $$env ..."; \
	  ansible-vault encrypt \
	    --output "$(ANSIBLE_VAULT_VARS_DIR)/$(ANSIBLE_VAULT_FILE_PREFIX).$$env.vault.yaml" \
	    --vault-password-file "$(ANSIBLE_VAULT_PASS_FILE)" \
	    "$(ANSIBLE_VAULT_VARS_DIR)/$(ANSIBLE_VAULT_FILE_PREFIX).$$env.yaml"; \
	done

.PHONY: vault-decrypt-all
vault-decrypt-all: ansible-vault-check ## Decrypt secrets for all environments
	@for env in $(ANSIBLE_VAULT_ENVIRONMENTS); do \
	  echo "Decrypting $$env ..."; \
	  ansible-vault decrypt \
	    "$(ANSIBLE_VAULT_VARS_DIR)/$(ANSIBLE_VAULT_FILE_PREFIX).$$env.vault.yaml" \
	    --vault-password-file "$(ANSIBLE_VAULT_PASS_FILE)" \
	    --output "$(ANSIBLE_VAULT_VARS_DIR)/$(ANSIBLE_VAULT_FILE_PREFIX).$$env.yaml"; \
	done

# ---- Cleanup -----------------------------------------------------------------

.PHONY: vault-clean-plaintext
vault-clean-plaintext: ## Remove all decrypted secrets (plaintext .yaml)
	rm -f $(ANSIBLE_VAULT_PLAINTEXT_FILES)

endif  # MK_COMMON_ANSIBLE_VAULT_INCLUDED
