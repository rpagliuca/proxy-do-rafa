#!/usr/bin/env bash
# Gera as configuracoes de cliente a partir do state + segredos.
#
# Regenerado a cada `make up` porque o IP muda toda vez — e o IP mudar e uma
# propriedade desejada, nao um incomodo: e o que impede a saida de acumular
# reputacao em lista de bloqueio.
source "$(dirname "$0")/lib.sh"

eval "$(exportar_segredos)"
exportar_variaveis_tofu

IP=$(aws_exec tofu -chdir=tofu output -raw ip_publico)
DOMINIO=$(aws_exec tofu -chdir=tofu output -raw dominio)
exigir_valor "IP publico" "$IP"

DECOY=$(grep '^singbox_decoy:' ansible/roles/sing-box/defaults/main.yml | awk '{print $2}' | tr -d '"')
exigir_valor decoy "$DECOY"

mkdir -p clientes/gerado && chmod 700 clientes/gerado

TMP=$(mktemp -d /dev/shm/proxy-do-rafa.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
chmod 700 "$TMP"

printf '%s' "$tls_cert_pem_b64" | base64 -d > "$TMP/cert.pem"

python3 - "$TMP/cert.pem" "$TMP/vars.json" <<PY
import json, sys
cert = open(sys.argv[1]).read().strip().split("\n")
json.dump({
    "ip": "$IP",
    "dominio": "$DOMINIO",
    "decoy": "$DECOY",
    "vless_uuid": "$vless_uuid",
    "reality_public_key": "$reality_public_key",
    "reality_short_id": "$reality_short_id",
    "hysteria2_password": "$hysteria2_password",
    "ws_path": "$ws_path",
    "proxy_local_senha": "$proxy_local_senha",
    "certificado": cert,
}, open(sys.argv[2], "w"))
PY

construir_imagem
# Renderiza E valida. Uma config de cliente entregue sem passar pelo
# `sing-box check` so seria descoberta quebrada de dentro da rede fechada, que
# e o pior lugar possivel para depurar JSON.
docker run --rm \
  -v "$RAIZ":/repo -w /repo \
  -v "$TMP":/dados \
  "$IMAGEM" bash -c '
    set -e
    ansible localhost -c local -i localhost, -m template \
      -a "src=clientes/modelo.json.j2 dest=/dados/cliente.json" \
      -e @/dados/vars.json >/dev/null
    sing-box check -c /dados/cliente.json
  '

cp "$TMP/cliente.json" clientes/gerado/cliente.json
chmod 600 clientes/gerado/cliente.json

# Link de importacao rapida no Android. So o caminho REALITY: e o unico dos tres
# que o formato de URL representa sem perder seguranca (o Hysteria2 precisaria de
# `insecure=1`, porque o certificado e autoassinado e fixado — e isso se importa
# pelo JSON, nao por URL).
URL="vless://${vless_uuid}@${IP}:443?encryption=none&security=reality&sni=${DECOY}&fp=chrome&pbk=${reality_public_key}&sid=${reality_short_id}&type=tcp&flow=xtls-rprx-vision#proxy-do-rafa"
printf '%s\n' "$URL" > clientes/gerado/reality.url
chmod 600 clientes/gerado/reality.url

verde "gerado:"
echo "  clientes/gerado/cliente.json   — os tres caminhos, importar no sing-box (Linux e Android)"
echo "  clientes/gerado/reality.url    — link rapido, so o caminho principal"
echo
echo "QR do link rapido (aponte o app do celular):"
qrencode -t ANSIUTF8 -m 1 < clientes/gerado/reality.url 2>/dev/null \
  || docker run --rm -i "$IMAGEM" qrencode -t ANSIUTF8 -m 1 < clientes/gerado/reality.url
