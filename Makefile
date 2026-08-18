# proxy-do-rafa — saida privada efemera
#
# Os alvos sao finos de proposito: quem faz o trabalho sao os scripts em
# scripts/, que dao para ler, testar com `bash -n` e rodar sozinhos. Makefile
# que vira linguagem de programacao e Makefile que ninguem depura.

SHELL := /bin/bash
.DEFAULT_GOAL := ajuda

REGIAO ?= sa-east-1
export REGIAO

.PHONY: ajuda bootstrap segredos-iniciais segredos up down config check verify qr status orfaos fmt lint

ajuda:  ## mostra esta ajuda
	@echo "proxy-do-rafa — saida privada efemera"
	@echo
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Uso normal:  make up  ...viagem...  make down"
	@echo "Outra regiao: make up REGIAO=eu-central-1"

bootstrap:  ## cria o bucket de state (uma vez na vida)
	@scripts/bootstrap.sh

segredos-iniciais:  ## gera a chave mestra e todos os segredos (uma vez na vida)
	@scripts/gerar-segredos-iniciais.sh

segredos:  ## edita os segredos cifrados
	@scripts/editar-segredos.sh

up:  ## sobe a saida: infraestrutura + configuracao + validacao + configs
	@scripts/subir.sh

down:  ## destroi tudo (e o unico jeito de o custo voltar a zero)
	@scripts/destruir.sh

config:  ## reaplica so a configuracao (Ansible) na maquina que ja existe
	@scripts/configurar.sh

check:  ## simula a configuracao sem aplicar (ansible --check --diff)
	@scripts/configurar.sh --check --diff

verify:  ## roda o InSpec: estado do servidor + disfarce visto de fora
	@scripts/validar.sh

qr:  ## regenera as configs de cliente e imprime o QR
	@scripts/gerar-clientes.sh

status:  ## o que esta no ar agora
	@scripts/status.sh

orfaos:  ## procura instancias do projeto vivas fora do state
	@scripts/orfaos.sh

fmt:  ## formata o OpenTofu
	@tofu fmt -recursive

lint:  ## checagens que nao tocam a AWS
	@tofu fmt -check -recursive -diff
	@tofu -chdir=tofu init -backend=false -input=false >/dev/null && tofu -chdir=tofu validate
	@for f in scripts/*.sh; do bash -n "$$f" || exit 1; done
	@echo "ok"
