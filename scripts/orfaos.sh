#!/usr/bin/env bash
# Procura recursos etiquetados do projeto que estejam vivos na AWS.
#
# Existe porque o unico modo de esta ferramenta gerar custo silencioso e um
# `destroy` que falhou no meio, ou um `apply` feito com o state de outra
# maquina. A conta so aparece no fim do mes; esta checagem aparece agora.
source "$(dirname "$0")/lib.sh"

REGIOES="${REGIOES:-sa-east-1 us-east-1 eu-central-1}"
achou=0

for r in $REGIOES; do
  saida=$(aws_exec aws ec2 describe-instances --region "$r" \
    --filters "Name=tag:Projeto,Values=proxy-do-rafa" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress,LaunchTime]' \
    --output text 2>/dev/null || true)
  if [[ -n "$saida" ]]; then
    vermelho "instancias vivas em $r:"
    echo "$saida"
    achou=1
  fi
done

if [[ $achou -eq 0 ]]; then
  verde "nenhuma instancia do projeto viva nas regioes: $REGIOES"
else
  echo
  aviso "para remover:  make down   (se o state bater) ou  aws ec2 terminate-instances"
fi
