#!/usr/bin/env bash
# O que esta no ar, e ha quanto tempo esta custando.
source "$(dirname "$0")/lib.sh"

eval "$(exportar_segredos)"
export TF_VAR_state_passphrase="$tofu_state_passphrase"
export TF_VAR_ssh_public_key="$ssh_public_key"
export TF_VAR_cloudflare_zone_id="$cloudflare_zone_id"
export TF_VAR_aws_region="${REGIAO:-sa-east-1}"
export CLOUDFLARE_API_TOKEN="$cloudflare_api_token"

aws_exec tofu -chdir=tofu init -input=false >/dev/null 2>&1 || true

if ! IP=$(aws_exec tofu -chdir=tofu output -raw ip_publico 2>/dev/null); then
  verde "nada no ar (custo zero)"
  exit 0
fi

ID=$(aws_exec tofu -chdir=tofu output -raw id_da_instancia)
REG=$(aws_exec tofu -chdir=tofu output -raw regiao)

echo "no ar:      $IP  ($ID, $REG)"
echo "dominio:    $(aws_exec tofu -chdir=tofu output -raw dominio)"

INICIO=$(aws_exec aws ec2 describe-instances --region "$REG" --instance-ids "$ID" \
  --query 'Reservations[0].Instances[0].LaunchTime' --output text 2>/dev/null || echo "")
if [[ -n "$INICIO" && "$INICIO" != "None" ]]; then
  SEGUNDOS=$(( $(date +%s) - $(date -d "$INICIO" +%s) ))
  HORAS=$(( SEGUNDOS / 3600 ))
  echo "ligada ha:  ${HORAS}h"
  printf "custo ate agora: ~US\$ %.2f (sem egress)\n" "$(echo "$HORAS * 0.0184" | bc -l)"
fi

aviso "lembrete: make down zera o custo"
