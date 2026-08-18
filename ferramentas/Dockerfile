# ⚠️ TUDO FIXADO POR VERSAO E POR SHA256.
#
# A imagem tem que ser determinada pelo repositorio: duas maquinas construindo
# em dias diferentes precisam produzir a mesma ferramenta. Sem isso, o que
# provisiona o servidor deixa de ser o que esta versionado aqui.
#
# Para atualizar qualquer item: trocar versao E hash no mesmo commit.
FROM python:3.12-slim@sha256:646fb0bca3dd3ea1bcc6feb72c17ed16eed6e10cffc732fcc1478bd3e7f02d7b

ARG ANSIBLE_CORE_VERSAO=2.21.2
ARG SOPS_VERSAO=3.13.3
ARG SOPS_SHA256=e5bec3346a873ae91d871550f3e698c1aad962aff462a080e40f25fde17fef6b
ARG AGE_VERSAO=1.3.1
ARG AGE_SHA256=bdc69c09cbdd6cf8b1f333d372a1f58247b3a33146406333e30c0f26e8f51377
ARG SINGBOX_VERSAO=1.13.19
ARG SINGBOX_SHA256=ef88a9e577d474210867bd708933d042e9b70106529df2656182c9db90106aa1

RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
      openssh-client ca-certificates curl qrencode openssl \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "ansible-core==${ANSIBLE_CORE_VERSAO}"

# sops: cifra valor a valor no YAML. age: a chave mestra.
RUN curl -fsSL -o /usr/local/bin/sops \
      "https://github.com/getsops/sops/releases/download/v${SOPS_VERSAO}/sops-v${SOPS_VERSAO}.linux.amd64" \
    && echo "${SOPS_SHA256}  /usr/local/bin/sops" | sha256sum -c - \
    && chmod +x /usr/local/bin/sops

RUN curl -fsSL -o /tmp/age.tgz \
      "https://github.com/FiloSottile/age/releases/download/v${AGE_VERSAO}/age-v${AGE_VERSAO}-linux-amd64.tar.gz" \
    && echo "${AGE_SHA256}  /tmp/age.tgz" | sha256sum -c - \
    && tar xzf /tmp/age.tgz -C /tmp \
    && mv /tmp/age/age /tmp/age/age-keygen /usr/local/bin/ \
    && rm -rf /tmp/age /tmp/age.tgz

# sing-box aqui e usado so para `generate` (chaves) e `check` (validar config
# ANTES de ela chegar no servidor). O servidor instala o seu proprio binario,
# arm64, com o mesmo numero de versao.
RUN curl -fsSL -o /tmp/sb.tgz \
      "https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSAO}/sing-box-${SINGBOX_VERSAO}-linux-amd64.tar.gz" \
    && echo "${SINGBOX_SHA256}  /tmp/sb.tgz" | sha256sum -c - \
    && tar xzf /tmp/sb.tgz -C /tmp \
    && mv "/tmp/sing-box-${SINGBOX_VERSAO}-linux-amd64/sing-box" /usr/local/bin/ \
    && rm -rf /tmp/sb.tgz "/tmp/sing-box-${SINGBOX_VERSAO}-linux-amd64"

WORKDIR /repo
