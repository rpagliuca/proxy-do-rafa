#!/usr/bin/env bash
# Prova que o trafego ATRAVESSA o tunel, caminho por caminho.
#
# ─── Por que este teste existe ────────────────────────────────────────────────
#
# Em 2026-08-18 o proxy subiu com tudo verde: 8 de 8 controles no servidor,
# 4 de 4 no disfarce, o no na tailnet. E o tunel nao passava um byte.
#
# O decoy configurado (www.microsoft.com) nao servia para o REALITY. Com o decoy
# errado a autenticacao falha e o servidor faz EXATAMENTE o que deveria fazer com
# uma sonda: repassa a conexao para o site real. Entao `disfarce-01` — que sonda
# a porta 443 e confere que volta um certificado valido do decoy — PASSA.
# O disfarce estava perfeito. O tunel e que estava quebrado.
#
# A licao: nenhuma checagem de estado prova travessia. So travessia prova
# travessia. Este teste manda um pacote de verdade e confere que ele saiu do
# outro lado, comparando o IP publico visto de fora com o IP do servidor.
source "$(dirname "$0")/lib.sh"

eval "$(exportar_segredos)"
exportar_variaveis_tofu

IP=$(aws_exec tofu -chdir=tofu output -raw ip_publico)
exigir_valor "IP publico" "$IP"
[[ -f clientes/gerado/cliente.json ]] || erro "clientes/gerado/cliente.json nao existe. Rode: make qr"

construir_imagem

CAMINHOS="${CAMINHOS:-reality hysteria2 websocket}"
PORTA=1080
falhou=0

for caminho in $CAMINHOS; do
  printf '%-12s ' "$caminho"

  TMP=$(mktemp -d /dev/shm/proxy-do-rafa.XXXXXX); chmod 700 "$TMP"
  python3 - "$caminho" "$TMP/config.json" "$PORTA" <<'PY'
import json, sys
caminho, destino, porta = sys.argv[1], sys.argv[2], int(sys.argv[3])
c = json.load(open('clientes/gerado/cliente.json'))
# Troca o TUN por um proxy local: TUN exige privilegio e mudaria a rota da
# maquina inteira. O socks percorre exatamente o mesmo outbound.
c['inbounds'] = [{"type": "mixed", "tag": "s", "listen": "0.0.0.0", "listen_port": porta}]
# Forca ESTE caminho, em vez de deixar o seletor escolher: um teste que nao diz
# por onde passou nao prova nada sobre o caminho que se quis testar.
c['outbounds'] = [o for o in c['outbounds'] if o.get('tag') != 'saida']
c['route']['rules'] = [r for r in c['route']['rules'] if r.get('action') != 'hijack-dns']
c['route']['final'] = caminho
c['dns'] = {"servers": [{"type": "local", "tag": "dns-local"}], "final": "dns-local"}
c['route']['default_domain_resolver'] = {"server": "dns-local"}
json.dump(c, open(destino, 'w'), indent=2)
PY

  if ! docker run --rm -v "$TMP":/cfg:ro "$IMAGEM" sing-box check -c /cfg/config.json >/dev/null 2>&1; then
    vermelho "config invalida"; falhou=1; rm -rf "$TMP"; continue
  fi

  NOME="proxy-do-rafa-teste-$caminho"
  docker rm -f "$NOME" >/dev/null 2>&1 || true
  docker run -d --name "$NOME" -p "127.0.0.1:$PORTA:$PORTA" -v "$TMP":/cfg:ro \
    "$IMAGEM" sing-box run -c /cfg/config.json >/dev/null 2>&1
  sleep 4

  VISTO=$(curl -s --max-time 25 -x "socks5h://127.0.0.1:$PORTA" https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)

  if [[ "$VISTO" == "$IP" ]]; then
    verde "OK  (saiu por $VISTO)"
  elif [[ -z "$VISTO" ]]; then
    vermelho "NAO PASSOU"
    docker logs "$NOME" 2>&1 | grep -iE 'error' | tail -2 | sed 's/^/             /'
    falhou=1
  else
    # Passou, mas saiu por outro IP: alguem esta no meio, ou a rota nao e a que
    # se pensa. Silenciar isto seria pior do que falhar.
    vermelho "SAIU POR OUTRO IP: $VISTO (esperado $IP)"
    falhou=1
  fi

  docker rm -f "$NOME" >/dev/null 2>&1 || true
  rm -rf "$TMP"
done

[[ $falhou -eq 0 ]] || erro "ha caminho que nao transporta trafego"
verde "todos os caminhos transportam trafego de verdade"
