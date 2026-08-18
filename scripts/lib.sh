#!/usr/bin/env bash
# Funcoes comuns. Todo script deste diretorio comeca com `source scripts/lib.sh`.
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ"

: "${PERFIL_AWS:=rafael-pessoal}"
: "${CHAVE_MESTRA:=$HOME/.config/proxy-do-rafa/age.key}"
: "${IMAGEM:=proxy-do-rafa/ferramentas:1}"
ARQUIVO_SEGREDOS="secrets/segredos.sops.yaml"

vermelho() { printf '\033[31m%s\033[0m\n' "$*" >&2; }
verde()    { printf '\033[32m%s\033[0m\n' "$*"; }
aviso()    { printf '\033[33m%s\033[0m\n' "$*" >&2; }

erro() { vermelho "ERRO: $*"; exit 1; }

exigir_chave_mestra() {
  [[ -f "$CHAVE_MESTRA" ]] || erro "chave mestra nao encontrada em $CHAVE_MESTRA.
Ela e a UNICA coisa que nao vive neste repositorio. Recupere com:
  pass show proxy-do-rafa/age-key > $CHAVE_MESTRA && chmod 600 $CHAVE_MESTRA
(a decriptacao do pass exige a YubiKey, que fica no laptop2021)"
}

construir_imagem() {
  docker build -q -t "$IMAGEM" ferramentas/ >/dev/null
}

# Roda um comando dentro da imagem de ferramentas, com a chave mestra montada
# somente-leitura. A chave nunca e copiada para dentro da imagem.
ferramentas() {
  construir_imagem
  docker run --rm -i \
    -v "$RAIZ":/repo -w /repo \
    -v "$CHAVE_MESTRA":/age.key:ro \
    -e SOPS_AGE_KEY_FILE=/age.key \
    "$IMAGEM" "$@"
}

# Decifra os segredos e devolve `export CHAVE=valor` linha a linha.
#
# Todos os valores sao de UMA linha por desenho (PEM e chave SSH vao em base64):
# assim o formato dotenv basta, e nao e preciso um parser de YAML no meio do
# caminho entre o segredo e o processo que o usa.
exportar_segredos() {
  exigir_chave_mestra
  [[ -f "$ARQUIVO_SEGREDOS" ]] || erro "$ARQUIVO_SEGREDOS nao existe. Rode: make segredos-iniciais"
  ferramentas sops -d --output-type dotenv "$ARQUIVO_SEGREDOS" | sed 's/^/export /'
}

# ⚠️ Falha de substituicao de comando NAO interrompe uma cadeia `&&`. Todo valor
# lido de segredo passa por aqui antes de ser usado.
exigir_valor() {
  local nome="$1" valor="${2:-}"
  [[ -n "$valor" ]] || erro "$nome veio vazio dos segredos. Rode: make segredos"
  [[ "$valor" != PREENCHER* ]] || erro "$nome ainda esta com o valor de exemplo. Rode: make segredos"
}

aws_exec() {
  command -v aws-vault >/dev/null || erro "aws-vault nao encontrado"
  aws-vault exec "$PERFIL_AWS" -- "$@"
}
