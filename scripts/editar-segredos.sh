#!/usr/bin/env bash
# Abre os segredos no editor, decifrados so em memoria. O sops recifra ao salvar.
source "$(dirname "$0")/lib.sh"
exigir_chave_mestra
construir_imagem
docker run --rm -it \
  -v "$RAIZ":/repo -w /repo \
  -v "$CHAVE_MESTRA":/age.key:ro \
  -e SOPS_AGE_KEY_FILE=/age.key \
  -e EDITOR="${EDITOR:-vi}" \
  "$IMAGEM" sops "$ARQUIVO_SEGREDOS"
