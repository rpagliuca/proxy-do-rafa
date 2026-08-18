#!/usr/bin/env bash
# Cria o bucket de state. Roda uma vez na vida.
source "$(dirname "$0")/lib.sh"
aws_exec tofu -chdir=bootstrap init -input=false
aws_exec tofu -chdir=bootstrap apply -input=false
verde "bucket de state pronto"
