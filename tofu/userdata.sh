#!/bin/bash
# Deliberadamente quase vazio.
#
# Toda a configuracao vem do Ansible, depois, do laptop — porque configuracao
# aplicada por userdata so pode ser inspecionada DEPOIS de a maquina existir,
# enquanto um playbook aceita `--check` antes. A maquina aqui so precisa ficar
# alcancavel.
set -euxo pipefail
hostnamectl set-hostname proxy-do-rafa
# python3 e o unico requisito do Ansible. Ja vem na Amazon Linux 2023, mas
# depender de "ja vem" e como o cloud-init falha em silencio.
command -v python3 >/dev/null 2>&1 || dnf install -y python3
