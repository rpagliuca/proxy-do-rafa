# Saida privada efemera.
#
# Uma EC2 que sobe, serve de primeiro salto por algumas horas ou dias, e e
# destruida. Nada aqui e permanente de proposito: o unico recurso que sobrevive
# a um `make down` e o bucket de state, no modulo bootstrap/.
#
# O que faz esta maquina passar por rede fechada esta no sing-box, configurado
# pelo Ansible — nao aqui. Este arquivo so entrega uma maquina com as portas
# certas abertas e um IP que ninguem nunca viu antes.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  etiquetas = {
    Projeto = "proxy-do-rafa"
    Gerido  = "opentofu"
    Efemero = "sim"
  }
}

# ─── Rede ─────────────────────────────────────────────────────────────────────

# ⚠️ name_prefix + create_before_destroy, e nao `name` fixo.
#
# Varias mudancas neste recurso FORCAM SUBSTITUICAO — trocar a `description` e
# a mais traicoeira, porque parece cosmetica. Sem create_before_destroy o
# OpenTofu destroi primeiro; a AWS recusa, porque a instancia ainda usa o grupo;
# e o apply fica RETENTANDO por 15 minutos com "Still destroying...".
#
# Aconteceu em 2026-08-18: um apply ficou 8 minutos preso nisso e foi
# interrompido. Nada se perdeu — a instancia continuou no ar com o grupo antigo,
# justamente porque a destruicao nao podia acontecer — mas o apply nao terminou,
# e um apply interrompido no meio e a forma mais confiavel de produzir state
# divergente.
#
# Com create_before_destroy o grupo novo nasce, a instancia passa a aponta-lo, e
# so entao o antigo morre. `name` fixo impediria isso: dois grupos com o mesmo
# nome nao coexistem, entao o prefixo e obrigatorio para o padrao funcionar.
resource "aws_security_group" "proxy" {
  name_prefix = "proxy-do-rafa-"
  description = "Saida privada efemera: 443/tcp demultiplexado por SNI (REALITY e WebSocket) e 443/udp (Hysteria2)"
  vpc_id      = data.aws_vpc.default.id

  # 443/tcp — VLESS + XTLS-REALITY, o caminho principal.
  #
  # Aberto ao mundo porque o cliente vem de rede arbitraria: hotel, escritorio
  # de cliente, aeroporto. A protecao nao e a origem, e o protocolo — sem a
  # chave privada REALITY, uma sonda que abra esta porta recebe o handshake do
  # site decoy e conclui que aqui mora um site comum.
  ingress {
    description = "VLESS + XTLS-REALITY"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 443/udp — Hysteria2. Mesma porta, protocolo diferente: nao conflita com o
  # REALITY e nao gasta uma segunda porta "estranha" que chamaria atencao.
  ingress {
    description = "Hysteria2 (QUIC)"
    from_port   = 443
    to_port     = 443
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # A 8443 NAO aparece aqui, e isso e proposital.
  #
  # O caminho WebSocket vive em 127.0.0.1:8443, atras do nginx. A Cloudflare
  # chega pela 443 como qualquer outro cliente, e o demultiplexador decide o
  # destino pelo SNI.
  #
  # A tentativa anterior era abrir a 8443 para as faixas da Cloudflare. Nao
  # funcionava: a Cloudflare encaminha para a origem NA MESMA PORTA que o
  # cliente usou — cliente na 443, origem na 443 — entao ela nunca falava com a
  # 8443, e a requisicao caia no REALITY e voltava 400.

  # SSH: so existe se admin_cidr foi preenchido. Vazio = porta 22 fechada, e o
  # acesso administrativo passa a ser por AWS Systems Manager.
  dynamic "ingress" {
    for_each = length(var.admin_cidr) > 0 ? [1] : []
    content {
      description = "SSH administrativo"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.admin_cidr
    }
  }

  egress {
    description = "Saida liberada: e literalmente o servico que esta maquina presta"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_key_pair" "admin" {
  key_name_prefix = "proxy-do-rafa-"
  public_key      = var.ssh_public_key
}

# ─── IAM: so o suficiente para o Systems Manager ──────────────────────────────
# Sem isto, uma rede que bloqueie a porta 22 deixaria a maquina inalcancavel —
# e o cenario de uso desta ferramenta e exatamente "rede que bloqueia coisas".
# O agente do SSM ja vem na AMI; falta so a permissao.

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "proxy" {
  name_prefix        = "proxy-do-rafa-"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.proxy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "proxy" {
  name_prefix = "proxy-do-rafa-"
  role        = aws_iam_role.proxy.name
}

# ─── A maquina ────────────────────────────────────────────────────────────────

resource "aws_instance" "proxy" {
  ami                         = nonsensitive(data.aws_ssm_parameter.al2023_arm64.value)
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.proxy.id]
  key_name                    = aws_key_pair.admin.key_name
  iam_instance_profile        = aws_iam_instance_profile.proxy.name
  associate_public_ip_address = true

  # Sem AMI fixada, ao contrario de uma stack permanente: aqui a maquina e
  # recriada toda vez que sobe, entao "imagem nova recria a instancia" nao e
  # efeito colateral — e o comportamento pretendido, e traz correcao de
  # seguranca de graca.

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  metadata_options {
    http_tokens = "required"
  }

  user_data = file("${path.module}/userdata.sh")

  tags = { Name = "proxy-do-rafa" }
}
