#!/usr/bin/env bash
# Valida o que subiu: primeiro na maquina, depois de fora.
source "$(dirname "$0")/lib.sh"

eval "$(exportar_segredos)"
exportar_variaveis_tofu

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

# ⚠️ --no-create-lockfile: o repositorio e montado somente-leitura de proposito
# (o validador nao tem por que escrever no que ele valida), e sem esta flag o
# InSpec tenta gravar inspec.lock e morre com um backtrace de Ruby de 20 linhas
# — "Read-only file system", que nao parece problema de flag.
echo "==> InSpec: estado do servidor"
docker run --rm \
  -v "$RAIZ":/repo:ro -v "$TMP":/segredos:ro \
  "$IMAGEM_INSPEC" exec /repo/inspec/servidor \
    -t "ssh://ec2-user@$IP" -i /segredos/chave_ssh --sudo \
    --chef-license accept-silent --no-create-lockfile \
  || falhou=1

echo
echo "==> InSpec: o disfarce visto de fora"
docker run --rm \
  -v "$RAIZ":/repo:ro \
  "$IMAGEM_INSPEC" exec /repo/inspec/disfarce \
    --input ip="$IP" dominio="$DOMINIO" decoy="$DECOY" \
    --chef-license accept-silent --no-create-lockfile \
  || falhou=1

# ⚠️ A falha do Tailscale e SILENCIOSA: o tunel funciona, so a tailnet nao. Sem
# esta checagem, ela so apareceria quando ele tentasse alcancar outro aparelho —
# de dentro da rede fechada, que e onde nao da para investigar nada.
echo
echo "==> Tailscale: o no entrou na tailnet?"
TAG=$(grep '^tailscale_tag:' ansible/roles/sing-box/defaults/main.yml | awk '{print $2}' | tr -d '"')
if TOKEN=$(token_tailscale 2>/dev/null) && [[ -n "$TOKEN" ]]; then
  DISPOSITIVOS=$(curl -fsS "https://api.tailscale.com/api/v2/tailnet/-/devices" \
    -H "Authorization: Bearer $TOKEN" 2>/dev/null || echo '{}')
  RECENTE=$(jq -r --arg tag "$TAG" --arg limite "$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" '
    [.devices // [] | .[]
     | select((.tags // []) | index($tag))
     | select(.lastSeen > $limite)] | length' <<<"$DISPOSITIVOS")
  if [[ "${RECENTE:-0}" -ge 1 ]]; then
    verde "  no com $TAG visto na tailnet agora"
  else
    vermelho "  NENHUM no com $TAG visto nos ultimos 10 minutos."
    vermelho "  O tunel deve estar funcionando; a tailnet NAO esta."
    vermelho "  Conferir: a tag existe em tagOwners na policy? o OAuth client tem escopo auth_keys nessa tag?"
    falhou=1
  fi
else
  aviso "  nao foi possivel falar com a API do Tailscale (escopo devices:core:read no OAuth client?)"
  aviso "  a tailnet NAO foi verificada"
fi

if [[ $falhou -ne 0 ]]; then
  vermelho "a validacao encontrou problemas — leia a saida acima ANTES de confiar nesta saida"
  exit 1
fi
verde "validado"
