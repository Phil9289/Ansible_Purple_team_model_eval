# Raccourcis du labo PentAGI Purple Team.
# "make help" pour la liste.
.DEFAULT_GOAL := help
SHELL := /bin/bash

.PHONY: help preflight up up-ollama down purge status logs mission-juice mission-dvwa validate

help: ## Affiche cette aide
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

preflight: ## Vérifie les prérequis (ajoute GEN=1 pour générer les secrets)
	@./scripts/preflight.sh $(if $(GEN),--gen-secrets,)

up: ## Démarre le labo (cerveau selon .env)
	@./scripts/lab-up.sh

up-ollama: ## Démarre le labo avec le cerveau Ollama hors-ligne
	@./scripts/lab-up.sh --with-ollama

down: ## Arrête le labo (garde les données)
	@./scripts/lab-down.sh

purge: ## Arrête le labo ET supprime les volumes (IRRÉVERSIBLE)
	@./scripts/lab-down.sh --purge

status: ## État des conteneurs + test d'isolation + atteignabilité des cibles
	@./scripts/lab-status.sh

logs: ## Suit les logs du backend (make logs SVC=pgvector pour un autre service)
	@./scripts/lab-logs.sh $(SVC)

mission-juice: ## Lance une mission autonome contre Juice Shop (PENTAGI_API_TOKEN requis)
	@./scripts/new-mission.sh --target juice

mission-dvwa: ## Lance une mission autonome contre DVWA (PENTAGI_API_TOKEN requis)
	@./scripts/new-mission.sh --target dvwa
