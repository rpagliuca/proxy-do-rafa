# AWS: a conta e a credencial

## Conta

`069631285051`, região padrão `sa-east-1`.

## Credencial

Desde 26/11/2026 o tofu e os scripts usam a role `com-mfa/administracao-com-mfa`, assumida
pelo secrets-broker com o código do MFA (perfil `pessoal-aws-conta-pessoal-role-administracao-com-mfa`,
`scripts/lib.sh`). A chave da raiz deixou de ser usada. O IAM da conta fica no repositório
`aws-contas-pessoais-iam`.

Lição que fica: credencial temporária de root (`GetSessionToken` sem MFA) não chama IAM nem
STS, e o erro é `InvalidClientTokenId`, que parece credencial expirada.
## O que a stack cria

| Recurso | Custo |
|---|---|
| EC2 t4g.micro | US$ 0,0134/h |
| IPv4 público | US$ 0,005/h |
| gp3 8 GiB | ~US$ 0,001/h |
| Security group, key pair, role IAM | grátis |
| Bucket de state (permanente) | centavos por ano |

Egress: US$ 0,150/GB em `sa-east-1`, com 100 GB/mês grátis na conta.

`make down` remove tudo menos o bucket de state. `make orfaos` procura instâncias
vivas que o state não conhece.
