#!/usr/bin/env bash
# Gera a chave mestra e todos os segredos derivados. Roda UMA vez na vida do
# repositorio.
#
# Tudo o que da para gerar sozinho e gerado aqui; o que depende de um painel
# externo (Cloudflare, Tailscale) fica com um valor PREENCHER-* explicito, para
# falhar alto em vez de subir uma maquina meio configurada.
source "$(dirname "$0")/lib.sh"

[[ -f "$ARQUIVO_SEGREDOS" ]] && erro "$ARQUIVO_SEGREDOS ja existe. Para editar: make segredos"

mkdir -p "$(dirname "$CHAVE_MESTRA")"
chmod 700 "$(dirname "$CHAVE_MESTRA")"

construir_imagem

if [[ ! -f "$CHAVE_MESTRA" ]]; then
  echo "==> gerando a chave mestra age"
  docker run --rm "$IMAGEM" age-keygen 2>/dev/null > "$CHAVE_MESTRA"
  chmod 600 "$CHAVE_MESTRA"
  verde "chave mestra criada em $CHAVE_MESTRA"
  aviso "GUARDE-A AGORA — sem ela nada neste repositorio pode ser lido:"
  aviso "  pass insert -m proxy-do-rafa/age-key < $CHAVE_MESTRA && pass git push"
fi

CHAVE_PUBLICA=$(grep '^# public key: ' "$CHAVE_MESTRA" | cut -d' ' -f4)
exigir_valor "chave publica age" "$CHAVE_PUBLICA"
sed -i "s|age: .*|age: $CHAVE_PUBLICA|" .sops.yaml
verde "chave publica registrada em .sops.yaml"

echo "==> gerando os segredos derivados"
TMP=$(mktemp -d /dev/shm/proxy-do-rafa.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
chmod 700 "$TMP"

docker run --rm -v "$TMP":/saida "$IMAGEM" bash -c '
set -euo pipefail
cd /saida
sing-box generate reality-keypair > reality.txt
sing-box generate uuid            > uuid.txt
sing-box generate rand 24 --base64 > hy2.txt
sing-box generate rand 8 --hex     > shortid.txt
sing-box generate rand 12 --hex    > wspath.txt

# Par de chaves SSH dedicado a esta stack. Dedicado, e nao a chave pessoal do
# Rafael, porque o repositorio e publico e a maquina e descartavel: comprometer
# uma nao pode tocar em mais nada.
ssh-keygen -t ed25519 -N "" -C "proxy-do-rafa" -f chave_ssh >/dev/null

# Certificado autoassinado da origem, 10 anos.
#
# Autoassinado e nao Let'"'"'s Encrypt porque a origem so e alcancada pela
# Cloudflare (modo full) e pelo cliente Hysteria2, que fixa o certificado. Uma
# CA publica nao acrescentaria confianca nenhuma aqui, e traria emissao,
# renovacao e limite de taxa para dentro de um fluxo que precisa funcionar
# dentro de um hotel.
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
  -subj "/CN=proxy-do-rafa.eleprograma.com.br" \
  -addext "subjectAltName=DNS:proxy-do-rafa.eleprograma.com.br" \
  -keyout tls_key.pem -out tls_cert.pem 2>/dev/null
chmod -R a+r /saida
'

REALITY_PRIV=$(grep PrivateKey "$TMP/reality.txt" | awk '{print $2}')
REALITY_PUB=$(grep PublicKey  "$TMP/reality.txt" | awk '{print $2}')
exigir_valor "chave privada REALITY" "$REALITY_PRIV"
exigir_valor "chave publica REALITY" "$REALITY_PUB"

# Sem comentarios de propósito: o sops cifra comentarios junto com os valores, e
# uma dica cifrada nao ajuda ninguem. As instrucoes estao no README.
cat > "$TMP/segredos.yaml" <<YAML
tofu_state_passphrase: "$(docker run --rm "$IMAGEM" sing-box generate rand 32 --base64)"
vless_uuid: "$(cat "$TMP/uuid.txt")"
reality_private_key: "$REALITY_PRIV"
reality_public_key: "$REALITY_PUB"
reality_short_id: "$(cat "$TMP/shortid.txt")"
hysteria2_password: "$(cat "$TMP/hy2.txt")"
ws_path: "/$(cat "$TMP/wspath.txt")"
ssh_public_key: "$(cat "$TMP/chave_ssh.pub")"
ssh_private_key_b64: "$(base64 -w0 < "$TMP/chave_ssh")"
tls_cert_pem_b64: "$(base64 -w0 < "$TMP/tls_cert.pem")"
tls_key_pem_b64: "$(base64 -w0 < "$TMP/tls_key.pem")"
cloudflare_api_token: "PREENCHER-token-da-cloudflare"
cloudflare_zone_id: "PREENCHER-id-da-zona"
tailscale_oauth_client_id: "PREENCHER-oauth-client-id"
tailscale_oauth_client_secret: "PREENCHER-oauth-client-secret"
YAML

# Cifra com a chave publica explicita, sem depender das regras do .sops.yaml:
# aqui o arquivo em claro esta em /dev/shm, cujo caminho nao casaria com o
# path_regex e faria o sops recusar com "no matching creation rules" — erro que
# se le como problema de chave.
#
# SEM --encrypted-regex: o padrao ja cifra todos os valores. Ver o aviso no
# .sops.yaml sobre lookahead em RE2.
docker run --rm \
  -v "$TMP":/claro:ro \
  -v "$CHAVE_MESTRA":/age.key:ro -e SOPS_AGE_KEY_FILE=/age.key \
  "$IMAGEM" sops -e --age "$CHAVE_PUBLICA" \
    --input-type yaml --output-type yaml \
    /claro/segredos.yaml > "$ARQUIVO_SEGREDOS"

# ⚠️ CONFERIR o que foi gravado, e nao o codigo de saida do sops.
#
# Em 2026-08-18 um --encrypted-regex com lookahead fez o sops gravar o arquivo
# INTEIRO EM CLARO e sair com codigo 0. "Deu certo" era falso, e num repositorio
# publico isso teria significado publicar a chave privada SSH e a do REALITY.
chaves=$(grep -cE '^[a-z0-9_]+:' "$TMP/segredos.yaml")
# `sops:` (metadados) nao e cifrado por desenho — e o que permite decifrar o
# resto. O arquivo em claro nao tem essa chave, entao a contagem so bate se ela
# for excluida do lado cifrado.
cifrados=$(grep -cE '^[a-z0-9_]+: ENC\[AES256_GCM' "$ARQUIVO_SEGREDOS" || true)
if [[ "$chaves" -ne "$cifrados" ]]; then
  rm -f "$ARQUIVO_SEGREDOS"
  erro "o sops gravou $cifrados de $chaves valores cifrados. Arquivo apagado."
fi
if grep -qE 'BEGIN (EC |OPENSSH )?PRIVATE|ssh-ed25519 AAAA' "$ARQUIVO_SEGREDOS"; then
  rm -f "$ARQUIVO_SEGREDOS"
  erro "segredo em claro detectado no arquivo cifrado. Arquivo apagado."
fi
verde "conferido: $cifrados de $chaves valores cifrados"

verde "segredos cifrados em $ARQUIVO_SEGREDOS"
echo
aviso "FALTA VOCE: preencher os quatro valores PREENCHER-* com  make segredos"
