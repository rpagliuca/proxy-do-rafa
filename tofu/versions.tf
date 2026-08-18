terraform {
  required_version = ">= 1.7"

  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.0" }
    cloudflare = { source = "cloudflare/cloudflare", version = "~> 5.23" }
  }

  backend "s3" {
    bucket       = "proxy-do-rafa-tofu-state-069631285051"
    key          = "proxy-do-rafa/terraform.tfstate"
    region       = "sa-east-1"
    encrypt      = true
    use_lockfile = true
  }

  # Encriptacao NATIVA do OpenTofu (1.7+): o state e cifrado nesta maquina,
  # antes de subir. O S3 guarda bytes que a AWS nao consegue ler.
  #
  # A passphrase vem do SOPS (TOFU_STATE_PASSPHRASE), decifrada com a mesma
  # chave mestra age de todo o resto — e por isso que continua sendo UMA chave.
  #
  # ⚠️ Isto e a SEGUNDA camada, nao a unica. A primeira e uma regra de desenho:
  # NENHUM segredo passa pelo state. Nao ha `tls_private_key`, nao ha SSM com
  # valor real, nao ha variavel sensivel. O token da Cloudflare entra por
  # variavel de ambiente do provider, que o Terraform nao persiste. Assim, mesmo
  # um state lido em claro nao entrega nada — a encriptacao protege metadado,
  # nao segredo.
  encryption {
    key_provider "pbkdf2" "chave" {
      passphrase = var.state_passphrase
    }
    method "aes_gcm" "metodo" {
      keys = key_provider.pbkdf2.chave
    }
    state {
      method   = method.aes_gcm.metodo
      enforced = true
    }
    plan {
      method   = method.aes_gcm.metodo
      enforced = true
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.etiquetas
  }
}

# O token vem de CLOUDFLARE_API_TOKEN no ambiente, decifrado do SOPS pelo
# scripts/lib.sh. De proposito NAO e uma variavel do OpenTofu: variavel de
# provider fica no state; variavel de ambiente nao.
provider "cloudflare" {}
