# proxy-do-rafa

Uma saída privada **efêmera** na AWS: sobe por comando, serve de primeiro salto
para atravessar rede corporativa fechada, e é destruída quando não é mais
precisa. Custo fora de uso: **zero**.

```
make up      # ~2 minutos: infraestrutura + configuração + validação + QR
             # ...viagem...
make down    # destrói tudo
```

## O problema que ele resolve

Rede corporativa (ou de hotel, ou de país com censura) que bloqueia VPN por
lista: os endpoints do Tailscale, os IPs conhecidos da NordVPN, categorias
inteiras de domínio. O bloqueio funciona porque **o destino é conhecido**.

Esta ferramenta cria um destino que ninguém conhece: um IP novo, que nunca
apareceu em lista nenhuma, falando um protocolo que se parece com uma visita
comum a um site comum. Passado o primeiro salto, o resto da internet volta ao
normal — Tailscale, NordVPN, o que for.

Não é uma VPN comercial nem um substituto de uma. É um trampolim.

## Como o disfarce funciona

O caminho principal é **VLESS + XTLS-REALITY** na porta 443/tcp.

REALITY não tem certificado próprio. Quando alguém abre uma conexão, o servidor
faz o handshake TLS **contra um site real** — `www.microsoft.com`, por padrão —
e devolve ao cliente aquele handshake. Na prática:

- o firewall que inspeciona a conexão vê um TLS legítimo, com certificado válido
  emitido por uma CA pública, do site decoy;
- o SNI é o do decoy, então a conexão passa até em rede que só permite SNI de
  uma lista;
- se o firewall **sondar ativamente** — abrir ele mesmo a conexão para ver o que
  responde — recebe o site real;
- não existe domínio nosso para bloquear nem certificado nosso para catalogar;
- o IP é novo a cada `make up`, então reputação de IP não pega.

O decoy é `www.microsoft.com` por um motivo prático: bloquear a Microsoft
quebraria o Windows e o Office da própria empresa, então quase nenhuma rede
corporativa bloqueia.

### Os outros dois caminhos

| Caminho | Porta | Quando serve |
|---|---|---|
| **VLESS + REALITY** | 443/tcp | principal, e o mais difícil de detectar |
| **Hysteria2** | 443/udp | bem mais rápido — quando a rede deixa UDP passar |
| **VLESS + WebSocket** pela Cloudflare | 443/tcp (borda da Cloudflare) | reserva: rede com proxy HTTP obrigatório e MITM de TLS, onde o REALITY não sobrevive |

O cliente traz os três e alterna entre eles sem reimportar nada.

### Tailscale de brinde

O servidor entra na tailnet (endpoint `tailscale` embutido no sing-box), e o
cliente alcança os outros aparelhos do Rafael **por dentro** do túnel — inclusive
escolhendo um exit node arbitrário da tailnet.

Isso importa especialmente no Android, onde só **uma** VPN pode estar ativa por
vez: sing-box e Tailscale não coexistiriam. Com o endpoint embutido, um app só
entrega o túnel e a tailnet.

## O que ele não resolve

Registrado de propósito, porque descobrir isso dentro da rede fechada é caro:

- **Rede que exige proxy HTTP com MITM de TLS** quebra o REALITY, por definição:
  ele depende de o handshake chegar intacto. É para isso que existe o caminho
  WebSocket pela Cloudflare — mais lento, e a Cloudflare enxerga o túnel por
  dentro (o conteúdo continua cifrado ponta a ponta se for HTTPS; se for HTTP
  puro, não).
- **Compartilhar pelo hotspot do celular não funciona de forma transparente no
  Android sem root.** Quem está no tethering ignora a `VpnService`. O que
  funciona é o app expor proxy na LAN e os outros aparelhos apontarem para o
  celular como proxy explícito — ver [docs/clientes.md](docs/clientes.md).
- **O endpoint Tailscale do sing-box tem defeitos abertos** de alcançabilidade
  de peers no Android/iOS. É bônus, não garantia.

## Custo

| | sa-east-1 | us-east-1 |
|---|---|---|
| Ligado 24 h | ~US$ 0,46 | ~US$ 0,37 |
| **Destruído** | **US$ 0,00** | **US$ 0,00** |
| Egress | US$ 0,150/GB | US$ 0,090/GB |

Os primeiros 100 GB/mês de egress são gratuitos na conta. Vídeo pelo túnel
consome 1–3 GB **por hora** — é o item que pode surpreender, não a instância.

`make status` mostra há quanto tempo está ligado e quanto já custou.
`make orfaos` procura instâncias vivas que o state não conhece — o único jeito
de esta ferramenta gerar custo silencioso.

## Segurança e a chave mestra

Este repositório é **público** e contém segredos — todos cifrados pelo
[SOPS](https://github.com/getsops/sops) com uma chave [age](https://age-encryption.org).

**Uma única coisa vive fora daqui: a chave privada age.** Ela fica em
`~/.config/proxy-do-rafa/age.key` e no `pass` (`proxy-do-rafa/age-key`). Com ela,
qualquer máquina reconstrói tudo. Sem ela, o repositório inteiro é inútil para
quem o encontrar.

O SOPS cifra **valor a valor**: as chaves do YAML continuam legíveis no git, só
os valores viram texto cifrado. É a vantagem sobre `ansible-vault`, que cifra o
arquivo inteiro e transforma qualquer alteração num blob ilegível no diff.

Duas decisões que sustentam isso:

1. **Nenhum segredo passa pelo state do OpenTofu.** Não há `tls_private_key`, não
   há parâmetro SSM com valor real, não há variável sensível. O token da
   Cloudflare entra por variável de ambiente do provider, que não é persistida.
   O state é cifrado por cima (encriptação nativa do OpenTofu, PBKDF2 com 600 mil
   iterações), mas isso é a segunda camada — não a única.
2. **Par de chaves SSH dedicado**, gerado para esta stack. Comprometer a máquina
   descartável não toca em mais nada.

## Primeira vez

```bash
make segredos-iniciais   # gera a chave mestra e os segredos derivados
                         # GUARDE A CHAVE: pass insert -m proxy-do-rafa/age-key < ~/.config/proxy-do-rafa/age.key
                         #                 pass git push
make segredos            # preencher os quatro valores PREENCHER-*
make bootstrap           # cria o bucket de state (uma vez na vida)
make up
```

Os valores manuais dependem de painel externo:

| Valor | Onde obter |
|---|---|
| `cloudflare_api_token` | dash.cloudflare.com → perfil → API Tokens. Permissões `Zone:DNS:Edit` + **`Zone:Zone Settings:Edit`** + `Zone:Zone:Read`, restritas a `eleprograma.com.br`. Ver [docs/cloudflare.md](docs/cloudflare.md) |
| `cloudflare_zone_id` | página inicial da zona no painel da Cloudflare |
| `tailscale_oauth_client_id` e `..._secret` | login.tailscale.com → Settings → OAuth clients. Escopos `auth_keys` (write) e `devices:core` (read), tag `tag:proxy-do-rafa` |

**Por que OAuth client e não uma auth key guardada aqui:** auth key do Tailscale
expira em no máximo 90 dias, e o vencimento produz a pior falha possível — o
túnel sobe, tudo parece certo, e a tailnet simplesmente não está lá. O OAuth
client não expira; a auth key é cunhada a cada `make up`, de uso único, efêmera
e válida por 10 minutos. Detalhes e a configuração da tag em
[docs/tailscale.md](docs/tailscale.md).

Também é preciso declarar a tag na policy do tailnet:

```jsonc
"tagOwners": { "tag:proxy-do-rafa": ["autogroup:admin"] }
```

## Ferramental

Nada precisa estar instalado além de `docker`, `tofu`, `aws-vault`, `jq` e `git`.
Ansible, SOPS, age, sing-box e InSpec vivem numa imagem com **versão e sha256
fixados** (`ferramentas/Dockerfile`) — duas máquinas construindo em dias
diferentes produzem a mesma ferramenta.

## Estrutura

```
bootstrap/   bucket de state (roda uma vez)
tofu/        a infraestrutura: máquina, portas, DNS
ansible/     o que faz a máquina ser um proxy
inspec/      servidor/  o que o playbook prometeu está lá?
             disfarce/  o disfarce se sustenta, visto de fora?
clientes/    modelo da configuração de cliente
scripts/     o que os alvos do Makefile executam
docs/        runbook, clientes, modelo de ameaça
```

## Documentação

- [docs/runbook.md](docs/runbook.md) — subir, destruir, diagnosticar
- [docs/clientes.md](docs/clientes.md) — Linux, Android, compartilhar com outros aparelhos
- [docs/cloudflare.md](docs/cloudflare.md) — o token (são três permissões, não duas) e o zone id
- [docs/tailscale.md](docs/tailscale.md) — como a tailnet convive com uma máquina que não dura
- [docs/ameacas.md](docs/ameacas.md) — contra o que isto protege, e contra o que não

## Licença

MIT.
