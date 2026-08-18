#!/usr/bin/env bash
# Sobe a saida: infraestrutura, configuracao, validacao e configs de cliente.
source "$(dirname "$0")/lib.sh"

eval "$(exportar_segredos)"
exigir_valor cloudflare_api_token "${cloudflare_api_token:-}"
exigir_valor cloudflare_zone_id   "${cloudflare_zone_id:-}"
exigir_valor tailscale_oauth_client_id     "${tailscale_oauth_client_id:-}"
exigir_valor tailscale_oauth_client_secret "${tailscale_oauth_client_secret:-}"
exigir_valor tofu_state_passphrase "${tofu_state_passphrase:-}"
exigir_valor ssh_public_key       "${ssh_public_key:-}"

: "${REGIAO:=sa-east-1}"

# De onde o SSH sera aceito. Detectado toda vez porque quem usa isto esta
# viajando: o IP de ontem e de outro hotel.
echo "==> descobrindo o IP publico desta maquina"
MEU_IP=$(curl -fsS --max-time 10 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' \
      || curl -fsS --max-time 10 https://ifconfig.me 2>/dev/null | tr -d '[:space:]' || true)
if [[ -n "$MEU_IP" ]]; then
  echo "    $MEU_IP — a porta 22 sera aberta so para ele"
  ADMIN_CIDR="[\"$MEU_IP/32\"]"
else
  aviso "nao foi possivel descobrir o IP publico; a porta 22 fica FECHADA."
  aviso "o acesso administrativo sera por: aws ssm start-session --target <id>"
  ADMIN_CIDR="[]"
fi

# ADMIN_CIDR e definido ACIMA e lido pelo helper. A ordem importa.
exportar_variaveis_tofu

echo "==> opentofu"
aws_exec tofu -chdir=tofu init -input=false -upgrade >/dev/null
aws_exec tofu -chdir=tofu apply -input=false -auto-approve

IP=$(aws_exec tofu -chdir=tofu output -raw ip_publico)
exigir_valor "IP publico" "$IP"
verde "maquina no ar: $IP"

"$RAIZ/scripts/configurar.sh"
"$RAIZ/scripts/validar.sh"
"$RAIZ/scripts/gerar-clientes.sh"

echo
verde "pronto. configs de cliente em clientes/gerado/"
echo "custo estimado: US\$ $(aws_exec tofu -chdir=tofu output -raw custo_por_dia_usd)/dia ligado, mais egress."
aviso "quando terminar:  make down   (e o unico jeito de o custo voltar a zero)"
