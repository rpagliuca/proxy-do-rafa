#!/usr/bin/env bash
# Destroi tudo. E o unico jeito de o custo voltar a zero.
source "$(dirname "$0")/lib.sh"

eval "$(exportar_segredos)"
export TF_VAR_state_passphrase="$tofu_state_passphrase"
export TF_VAR_ssh_public_key="$ssh_public_key"
export TF_VAR_cloudflare_zone_id="$cloudflare_zone_id"
export TF_VAR_aws_region="${REGIAO:-sa-east-1}"
export CLOUDFLARE_API_TOKEN="$cloudflare_api_token"

aws_exec tofu -chdir=tofu init -input=false >/dev/null
aws_exec tofu -chdir=tofu destroy -input=false -auto-approve

rm -rf clientes/gerado .local/inventario.yml
verde "destruido. custo de volta a zero."
echo
echo "Confira que nao sobrou nada:  make orfaos"
