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

# IP de borda da Cloudflare, fixado agora para o caminho de reserva nao depender
# de DNS na hora do uso. Ver o comentario no modelo.
IP_BORDA=$(dig +short A "$DOMINIO" @1.1.1.1 2>/dev/null | grep -E '^[0-9.]+$' | head -1)
[[ -n "$IP_BORDA" ]] || IP_BORDA=$(getent ahostsv4 "$DOMINIO" | awk '{print $1}' | head -1)
exigir_valor "IP de borda da Cloudflare" "$IP_BORDA"

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
    "ip_da_borda": "$IP_BORDA",
}, open(sys.argv[2], "w"))
PY

construir_imagem
# Renderiza E valida. Uma config de cliente entregue sem passar pelo
# `sing-box check` so seria descoberta quebrada de dentro da rede fechada, que
# e o pior lugar possivel para depurar JSON.
docker run --rm \
  -v "$RAIZ":/repo -w /repo \
  -v "$TMP":/dados \
  "$IMAGEM" ansible localhost -c local -i localhost, -m template \
    -a "src=clientes/modelo.json.j2 dest=/dados/cliente-tun.json" \
    -e @/dados/vars.json >/dev/null

# ⚠️ A derivacao roda AQUI, e nao dentro do container: ela usa aspas simples, e
# o `docker run ... bash -c '...'` ja esta entre aspas simples. Aninhar as duas
# coisas produz um erro de sintaxe do Python que nao parece ter relacao nenhuma
# com Docker.
#
# ⚠️ auto_detect_interface = false na variante de proxy, e true na de TUN. A
# diferenca nao e estetica:
#
#   No TUN ele e NECESSARIO — sem ele o trafego do proprio tunel entraria no
#   tunel, em laco.
#
#   No proxy ele QUEBRA quando existe outra VPN ativa. Ele amarra o socket na
#   interface "padrao" (a fisica), e o kill-switch do NordVPN recusa tudo que
#   sai por ali: "dial tcp: i/o timeout" no TCP, "write udp: operation not
#   permitted" no UDP. Medido em 2026-08-18, numa rede corporativa: com ele, os
#   tres caminhos falham; sem ele, dois passam na hora. Desligado, o socket
#   segue a tabela de rotas normal e entra na VPN que ja esta la.
python3 -c "
import json
c = json.load(open('$TMP/cliente-tun.json'))
c['inbounds'] = [i for i in c['inbounds'] if i['type'] != 'tun']
c['route']['rules'] = [r for r in c['route']['rules'] if r.get('action') != 'hijack-dns']
c['route']['auto_detect_interface'] = False
json.dump(c, open('$TMP/cliente-proxy.json', 'w'), indent=2)"

docker run --rm -v "$TMP":/dados "$IMAGEM" bash -c \
  "sing-box check -c /dados/cliente-tun.json && sing-box check -c /dados/cliente-proxy.json"

cp "$TMP/cliente-tun.json"   clientes/gerado/cliente-tun.json
cp "$TMP/cliente-proxy.json" clientes/gerado/cliente-proxy.json
chmod 600 clientes/gerado/cliente-tun.json clientes/gerado/cliente-proxy.json

# Link de importacao rapida no Android. So o caminho REALITY: e o unico dos tres
# que o formato de URL representa sem perder seguranca (o Hysteria2 precisaria de
# `insecure=1`, porque o certificado e autoassinado e fixado — e isso se importa
# pelo JSON, nao por URL).
URL="vless://${vless_uuid}@${IP}:443?encryption=none&security=reality&sni=${DECOY}&fp=chrome&pbk=${reality_public_key}&sid=${reality_short_id}&type=tcp&flow=xtls-rprx-vision#proxy-do-rafa"
printf '%s\n' "$URL" > clientes/gerado/reality.url
chmod 600 clientes/gerado/reality.url

verde "gerado:"
echo "  clientes/gerado/cliente-tun.json    — captura TUDO. Precisa de root."
echo "  clientes/gerado/cliente-proxy.json  — proxy em 2080, sem root."
echo "                                        Use ESTE quando houver outra VPN ativa."
echo "  clientes/gerado/reality.url         — link rapido, so o caminho principal"
echo
echo "QR do link rapido (aponte o app do celular):"
qrencode -t ANSIUTF8 -m 1 < clientes/gerado/reality.url 2>/dev/null \
  || docker run --rm -i "$IMAGEM" qrencode -t ANSIUTF8 -m 1 < clientes/gerado/reality.url
