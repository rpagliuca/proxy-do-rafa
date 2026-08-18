#!/usr/bin/env bash
# Destroi tudo. E o unico jeito de o custo voltar a zero.
source "$(dirname "$0")/lib.sh"

eval "$(exportar_segredos)"
exportar_variaveis_tofu

aws_exec tofu -chdir=tofu init -input=false >/dev/null
aws_exec tofu -chdir=tofu destroy -input=false -auto-approve

rm -rf clientes/gerado .local/inventario.yml
verde "destruido. custo de volta a zero."
echo
echo "Confira que nao sobrou nada:  make orfaos"
