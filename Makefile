# Shortcuts for every phase. Run `make help`.
SHELL := /bin/bash
URL ?= http://localhost:8080
VAULT := $(if $(wildcard ansible/group_vars/all/vault.yml),--ask-vault-pass)

help:            ## Show this help
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

# ---- Phase 1: local ----
test:            ## Run unit tests
	cd app && python3 -m pytest -q

up:              ## Start everything locally with Docker Compose
	docker compose up -d --build

down:            ## Stop the local stack (keeps data)
	docker compose down

scale:           ## Run 3 app replicas locally
	docker compose up -d --scale app=3 && docker compose restart web

smoke:           ## Smoke test (make smoke URL=http://1.2.3.4)
	scripts/smoke-test.sh $(URL)

# ---- Phase 3: cloud ----
infra:           ## Create the VPC + server with Terraform
	cd terraform && terraform init && terraform apply

configure:       ## Harden server, install k3s, monitoring and app with Ansible
	cd ansible && ansible-galaxy collection install -r requirements.yml && ansible-playbook site.yml $(VAULT)

deploy:          ## Deploy a specific image tag (make deploy TAG=abc123)
	cd ansible && ansible-playbook site.yml $(VAULT) --tags deploy -e image_tag=$(TAG)

destroy:         ## Delete ALL cloud resources (stops the bill)
	cd terraform && terraform destroy

.PHONY: help test up down scale smoke infra configure deploy destroy
