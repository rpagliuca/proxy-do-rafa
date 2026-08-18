#!/usr/bin/env bash
# Aplica a configuracao na maquina que ja existe.
source "$(dirname "$0")/lib.sh"

eval "$(exportar_segredos)"

IP=$(aws_exec tofu -chdir=tofu output -raw ip_publico)
exigir_valor "IP publico" "$IP"

mkdir -p .local && chmod 700 .local
cat > .local/inventario.yml <<YAML
# Gerado por scripts/configurar.sh a partir do state. Nao editar a mao:
# a fonte de verdade e o OpenTofu, e um arquivo editado a mao vira a segunda
# fonte — que e sempre a que fica velha.
proxy:
  hosts:
    $IP:
YAML

# /dev/shm: nunca toca disco. O diretorio e apagado no trap, e mesmo que nao
# fosse, nao sobrevive a um reboot.
TMP=$(mktemp -d /dev/shm/proxy-do-rafa.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
chmod 700 "$TMP"

printf '%s' "$ssh_private_key_b64" | base64 -d > "$TMP/chave_ssh"
chmod 600 "$TMP/chave_ssh"

# So as variaveis que o playbook consome. `dominio` e `porta_origem_websocket`
# vem do OpenTofu, nao dos segredos, porque quem manda neles e a infraestrutura.
cat > "$TMP/vars.json" <<JSON
{
  "tailscale_authkey": "$tailscale_authkey",
  "vless_uuid": "$vless_uuid",
  "reality_private_key": "$reality_private_key",
  "reality_short_id": "$reality_short_id",
  "hysteria2_password": "$hysteria2_password",
  "ws_path": "$ws_path",
  "tls_cert_pem_b64": "$tls_cert_pem_b64",
  "tls_key_pem_b64": "$tls_key_pem_b64",
  "dominio": "$(aws_exec tofu -chdir=tofu output -raw dominio)",
  "porta_origem_websocket": 8443
}
JSON

echo "==> ansible"
construir_imagem
docker run --rm -i \
  -v "$RAIZ":/repo -w /repo/ansible \
  -v "$TMP":/segredos:ro \
  "$IMAGEM" ansible-playbook site.yml \
    --private-key /segredos/chave_ssh \
    -e @/segredos/vars.json \
    "${@:-}"
