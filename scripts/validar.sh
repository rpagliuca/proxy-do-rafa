#!/usr/bin/env bash
# Valida o que subiu: primeiro na maquina, depois de fora.
source "$(dirname "$0")/lib.sh"

eval "$(exportar_segredos)"

IP=$(aws_exec tofu -chdir=tofu output -raw ip_publico)
DOMINIO=$(aws_exec tofu -chdir=tofu output -raw dominio)
exigir_valor "IP publico" "$IP"

DECOY=$(grep '^singbox_decoy:' ansible/roles/sing-box/defaults/main.yml | awk '{print $2}' | tr -d '"')

: "${IMAGEM_INSPEC:=cincproject/auditor:7.1}"

TMP=$(mktemp -d /dev/shm/proxy-do-rafa.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
chmod 700 "$TMP"
printf '%s' "$ssh_private_key_b64" | base64 -d > "$TMP/chave_ssh"
chmod 600 "$TMP/chave_ssh"

falhou=0

echo "==> InSpec: estado do servidor"
docker run --rm \
  -v "$RAIZ":/repo:ro -v "$TMP":/segredos:ro \
  "$IMAGEM_INSPEC" exec /repo/inspec/servidor \
    -t "ssh://ec2-user@$IP" -i /segredos/chave_ssh --sudo \
    --chef-license accept-silent \
  || falhou=1

echo
echo "==> InSpec: o disfarce visto de fora"
docker run --rm \
  -v "$RAIZ":/repo:ro \
  "$IMAGEM_INSPEC" exec /repo/inspec/disfarce \
    --input ip="$IP" dominio="$DOMINIO" decoy="$DECOY" \
    --chef-license accept-silent \
  || falhou=1

if [[ $falhou -ne 0 ]]; then
  vermelho "a validacao encontrou problemas — leia a saida acima ANTES de confiar nesta saida"
  exit 1
fi
verde "validado"
