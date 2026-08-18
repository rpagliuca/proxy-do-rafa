# Runbook

## Uso normal

```bash
make up      # sobe, configura, valida e imprime o QR
make status  # o que está no ar e quanto já custou
make down    # destrói — é o único jeito de o custo voltar a zero
```

`make up` é idempotente: rodar duas vezes não cria duas máquinas.

## Trocar de região

```bash
make up REGIAO=eu-central-1
```

Escolha por latência ao lugar de onde você está, não por preferência: a latência
é o que se sente em navegação interativa. `sa-east-1` fica a ~21 ms do Brasil,
`us-east-1` a ~120 ms.

⚠️ Trocar de região com uma máquina no ar **recria** a máquina (a AMI é por
região). Destrua antes.

## Reaplicar só a configuração

```bash
make check   # simula: ansible --check --diff, não muda nada
make config  # aplica
make verify  # InSpec: servidor + disfarce
```

Ler o `--check` de verdade: num diff de `template`, o lado `+++` é o arquivo
**já renderizado**. Chave dupla `{{ }}` ali é sempre defeito.

## Quando o SSH não conecta

`make up` abre a porta 22 apenas para o IP público detectado no momento. Se o IP
mudou (trocou de rede, o hotel renovou o DHCP), rode `make up` de novo: ele
detecta o IP atual e ajusta a regra.

Se a rede bloqueia a 22 por completo, o caminho é o Systems Manager — o agente e
a permissão já estão na máquina:

```bash
aws-vault exec rafael-pessoal -- aws ssm start-session \
  --region "$(tofu -chdir=tofu output -raw regiao)" \
  --target "$(tofu -chdir=tofu output -raw id_da_instancia)"
```

Precisa do `session-manager-plugin` instalado na máquina local.

## Diagnóstico, na ordem

**1. O serviço está de pé?**
```bash
ssh -i <chave> ec2-user@<ip> 'systemctl status sing-box; journalctl -u sing-box -n 50 --no-pager'
```

**2. O disfarce se sustenta?**
```bash
make verify
```
O perfil `disfarce` faz, de fora, as mesmas sondas que um firewall faria. É o
teste que importa: um serviço de pé com as portas certas não vale nada se ele se
identifica quando sondado.

**3. O cliente conecta mas não navega?**
Quase sempre é DNS. O cliente resolve por `1.1.1.1` **através** do túnel
(`detour: saida`) de propósito — resolver localmente vazaria os domínios visitados
para o resolvedor da rede corporativa, que é exatamente quem não deve saber.

**4. Hysteria2 lento?**
Confira os buffers de UDP (`make verify`, controle `rede-01`). Sem eles o próprio
sing-box registra `failed to sufficiently increase receive buffer size`.

## Trocar o site decoy

Editar `singbox_decoy` em `ansible/roles/sing-box/defaults/main.yml`, depois
`make config` e regenerar o cliente com `make qr`.

Requisitos do decoy: TLS 1.3, HTTP/2, e — o que mais importa — **ser um destino
que a rede fechada já permite**. Um decoy bloqueado transforma o disfarce em alvo.

## Custo saiu do esperado

```bash
make status   # horas ligadas e custo estimado
make orfaos   # instâncias vivas que o state não conhece
```

`make orfaos` existe porque o único jeito de esta ferramenta gerar custo
silencioso é um `destroy` que falhou no meio. A conta só apareceria no fim do mês.

## Perdi a chave mestra

Não há recuperação: é o desenho. Todos os segredos do repositório ficam
ilegíveis, e a máquina que estiver no ar terá de ser terminada pelo console da
AWS.

```bash
pass show proxy-do-rafa/age-key > ~/.config/proxy-do-rafa/age.key
chmod 600 ~/.config/proxy-do-rafa/age.key
```

(A decriptação do `pass` exige a YubiKey, que fica no laptop2021.)

Se a chave se perdeu de verdade: `make segredos-iniciais` gera tudo de novo, e as
configurações de cliente antigas param de servir.

## O state

Fica em `s3://proxy-do-rafa-tofu-state-069631285051`, versionado pelo S3 e
cifrado pelo OpenTofu antes de sair desta máquina.

O bucket tem `prevent_destroy`: destruí-lo levaria junto o state da stack no ar,
e com ele a capacidade de destruir o que está custando dinheiro.
