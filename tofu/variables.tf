variable "state_passphrase" {
  description = <<-EOT
    Passphrase da encriptacao nativa do state. Vem do SOPS via
    TF_VAR_state_passphrase — nunca digitada, nunca em arquivo em claro.
  EOT
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = <<-EOT
    Onde o proxy sobe. sa-east-1 por padrao: ~21 ms do Brasil contra ~120 ms de
    us-east-1. O egress e mais caro aqui (US$0,150/GB contra US$0,090/GB), mas
    latencia e o que se sente em navegacao interativa.

    Trocar por viagem e esperado: `make up REGIAO=eu-central-1`.
  EOT
  type        = string
  default     = "sa-east-1"
}

variable "instance_type" {
  description = <<-EOT
    t4g.micro (ARM64, 1 GiB). O sing-box e um binario Go que copia bytes; o
    limite pratico e banda, nao CPU.

    Nao usar t4g.nano: a vazao de rede de BASE escala com o tamanho da
    instancia, e banda e exatamente o que se esta comprando aqui.
  EOT
  type        = string
  default     = "t4g.micro"
}

variable "ssh_public_key" {
  description = <<-EOT
    Chave publica do par dedicado a esta stack (a privada vive no SOPS).

    Par dedicado, e nao a chave pessoal do Rafael, por dois motivos: o
    repositorio e publico, e a maquina e descartavel — comprometer uma nao pode
    tocar em mais nada.
  EOT
  type        = string
}

variable "admin_cidr" {
  description = <<-EOT
    De onde o SSH e aceito. O `make up` detecta o IP publico atual e passa
    <ip>/32 — porque quem usa isto esta viajando, e IP de hotel muda todo dia.

    Lista vazia fecha a porta 22 por completo. Nesse caso o acesso e por
    AWS Systems Manager (o agente e a role ja estao prontos; ver docs/runbook.md).
  EOT
  type        = list(string)
  default     = []
}

variable "cloudflare_zone_id" {
  description = <<-EOT
    ID da zona eleprograma.com.br na Cloudflare. Nao e segredo — aparece na
    pagina inicial da zona no painel — por isso e variavel comum e nao vem do
    SOPS.
  EOT
  type        = string
}

variable "dominio" {
  description = "FQDN do caminho de reserva (WebSocket atras da Cloudflare)."
  type        = string
  default     = "proxy-do-rafa.eleprograma.com.br"
}

variable "porta_origem_websocket" {
  description = <<-EOT
    Porta em que a Cloudflare fala com a origem.

    8443 e nao 443 por um motivo concreto: assim a 443/tcp fica inteira para o
    REALITY. A Cloudflare so alcanca origem HTTPS em portas de uma lista curta
    (443, 2053, 2083, 2087, 2096, 8443) — 8443 e a unica dessa lista que nao
    conflita.
  EOT
  type        = number
  default     = 8443
}
