# Bucket do state do OpenTofu. Roda UMA vez, com `make bootstrap`.
#
# O state DESTE modulo e local e nao versionado (ver .gitignore): ele contem
# apenas o nome de um bucket, e um state de bootstrap versionado num repositorio
# publico e um artefato permanente sem beneficio. Se ele se perder, o conserto e
# uma linha:
#
#   tofu -chdir=bootstrap import aws_s3_bucket.state <nome-do-bucket>
#
# O que NAO se perde e o que importa: o state da stack principal vive dentro
# deste bucket, versionado pelo proprio S3 e encriptado pelo OpenTofu.

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
  # Sem profile fixo: rodar via `aws-vault exec rafael-pessoal -- tofu ...`.
}

variable "aws_region" {
  description = "Regiao do bucket de state. Independe da regiao onde o proxy sobe."
  type        = string
  default     = "sa-east-1"
}

variable "nome_do_bucket" {
  description = "Nome do bucket. Global na AWS inteira, por isso o sufixo com o numero da conta."
  type        = string
  default     = "proxy-do-rafa-tofu-state-069631285051"
}

resource "aws_s3_bucket" "state" {
  bucket = var.nome_do_bucket

  # A stack e efemera de proposito, mas o BUCKET nao: destrui-lo levaria junto o
  # state da stack que estiver no ar, e com ele a capacidade de destruir o que
  # esta custando dinheiro. Orfao de EC2 e o unico jeito de esta ferramenta
  # gerar custo silencioso.
  lifecycle {
    prevent_destroy = true
  }
}

# Versionamento: um `apply` interrompido no meio pode gravar state truncado.
# Com versionamento, a versao anterior continua la.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Segunda camada. A primeira e a encriptacao nativa do OpenTofu, que cifra o
# state ANTES de ele sair desta maquina — o S3 nunca ve o conteudo em claro.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "nome_do_bucket" {
  value = aws_s3_bucket.state.id
}
