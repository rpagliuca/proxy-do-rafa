# AWS: a conta, a credencial e uma dívida

## Conta

`069631285051` (`rafael-pessoal` no aws-vault), região padrão `sa-east-1`.

## A dívida: o perfil usa a credencial ROOT da conta

```
$ aws-vault exec --no-session rafael-pessoal -- aws sts get-caller-identity
arn:aws:iam::069631285051:root
```

Isso já cobrou um preço concreto. A AWS **proíbe chamadas a IAM e STS com
credencial temporária de root** — exatamente as que o `aws-vault exec` cria por
padrão (`GetSessionToken`). O primeiro `make up` morreu no meio do apply com:

```
Error: creating IAM Role (...): api error InvalidClientTokenId:
The security token included in the request is invalid
```

A mensagem manda investigar o lugar errado: "token inválido" se lê como
credencial expirada ou perfil trocado. A credencial estava perfeita — a operação
é que é proibida para aquele *tipo* de credencial. E como a restrição vale só
para IAM e STS, o bucket S3 e o security group subiram normalmente antes de
bater nela: **metade da stack de pé, e o erro no meio do caminho.**

Contorno em vigor: `scripts/lib.sh` chama `aws-vault exec --no-session`, que usa
a chave de longa duração e faz o IAM funcionar.

### O que fazer quando der

Criar um usuário IAM dedicado e apontar o perfil para ele:

1. Usuário `proxy-do-rafa-operador`, sem console.
2. Política com o mínimo: EC2 (instância, security group, key pair), IAM
   (`CreateRole`, `PutRolePolicy`, `AttachRolePolicy`, `CreateInstanceProfile`,
   `PassRole` — restritos ao prefixo `proxy-do-rafa-*`), SSM `GetParameter` na
   AMI pública, e S3 no bucket de state.
3. Chaves no `pass` (`proxy-do-rafa/aws-operador`) e no `~/.aws/config`.
4. Voltar `aws_exec` a usar sessão temporária — que é o comportamento seguro, e
   passa a funcionar assim que a credencial deixar de ser root.
5. **Apagar as chaves de acesso do root.**

Enquanto isso não acontece, uma chave de longa duração com poder total sobre a
conta vive no chaveiro deste laptop. É a maior exposição desta ferramenta — maior
que qualquer coisa no repositório, que só guarda segredos cifrados e escopados.

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
