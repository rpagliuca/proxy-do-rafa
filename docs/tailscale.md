# Tailscale numa máquina que não dura

A máquina é destruída e recriada a cada viagem. A tailnet, não. Este arquivo é
sobre como as duas coisas convivem.

## O que a efemeridade NÃO quebra

O cliente alcança o proxy pelo **IP público**, não pela tailnet. O proxy roteia
`100.64.0.0/10` para dentro da tailnet, e os peers (Raspberry Pi, laptops, EC2)
têm IP de tailnet estável.

Então o nó ser novo a cada subida não atrapalha o caminho. O que muda a cada
`make up` é só a identidade do nó do proxy — que ninguém referencia.

## O que quebra, e a correção

### 1. Auth key expira em 90 dias, no máximo

É o limite do Tailscale, não uma escolha. Uma key guardada no repositório
funcionaria por até 90 dias e depois produziria o pior tipo de falha: o `make up`
sobe, o túnel funciona, a navegação funciona, e **a tailnet simplesmente não
está lá**. Descoberto de dentro da rede fechada, que é onde não dá para
investigar nada.

**Correção: OAuth client.** Ele **não expira** (só o access token, que dura 1 h e
vive em memória). O que fica cifrado no repositório é o par
`client_id` + `client_secret`; a auth key é **cunhada na hora**, a cada `make up`:

| Propriedade da key cunhada | Por quê |
|---|---|
| uso único (`reusable: false`) | serve para uma máquina e acaba |
| efêmera (`ephemeral: true`) | o nó some sozinho da tailnet quando a máquina é destruída — sem acumular `proxy-do-rafa-1`, `-2`, `-3` |
| pré-aprovada (`preauthorized: true`) | não trava esperando aprovação manual |
| validade de 10 minutos | se vazar, está morta antes de servir para alguém |

### 2. O nome do nó não é estável

Enquanto o nó anterior não foi coletado, o novo entra como `proxy-do-rafa-1`,
depois `-2`. ACL que referencie o nó **pelo nome** para de casar sem avisar.

**Correção: tag.** O nó entra com `tag:proxy-do-rafa`, e é a tag que as ACLs
referenciam. Ela é estável por definição.

Efeito colateral bem-vindo: **dispositivo com tag tem expiração de chave
desabilitada por padrão** — some mais um relógio contando contra você.

### 3. A falha é silenciosa

Por isso `make verify` consulta a API e confirma que existe um nó com a tag visto
na tailnet nos últimos 10 minutos. Se não existe, ele reprova — em vez de deixar
você descobrir no hotel.

## Configuração, uma vez

### a) A tag na policy do tailnet

Em `login.tailscale.com` → **Access controls**, acrescente:

```jsonc
"tagOwners": {
  "tag:proxy-do-rafa": ["autogroup:admin"]
}
```

Se sua policy restringe tráfego (a padrão de tailnet pessoal não restringe),
garanta que a tag alcança o que precisa alcançar.

### b) O OAuth client

`login.tailscale.com` → **Settings** → **OAuth clients** → *Generate OAuth client*.

| Campo | Valor |
|---|---|
| Escopos | `auth_keys` (write) — obrigatório · `devices:core` (read) — para o `make verify` conferir que o nó entrou |
| Tags | `tag:proxy-do-rafa` |

Guarde os dois valores:

```bash
make segredos
# tailscale_oauth_client_id: ...
# tailscale_oauth_client_secret: ...
```

O escopo `auth_keys` **exige** tag: o client só consegue cunhar keys para as tags
que você concedeu a ele. Vazado, ele não cria acesso fora dessa tag.

## Escotilha: quando a API do Tailscale não é alcançável

A cunhagem acontece no seu laptop, que pode estar exatamente na rede que bloqueia
o Tailscale — o cenário que esta ferramenta existe para resolver. Nesse caso,
gere uma auth key antes de entrar na rede e passe pelo ambiente:

```bash
TAILSCALE_AUTHKEY=tskey-auth-... make config
```

Vale para `make config` e para `make up`. É escotilha, não o caminho normal: ela
volta a ter todos os problemas descritos acima.

## Escolher um exit node da tailnet

O proxy entra com `accept_routes: true`. Para fazer o tráfego sair por **outro**
aparelho da tailnet (e não pela EC2), acrescente `exit_node` ao endpoint em
`ansible/roles/sing-box/templates/config.json.j2` e rode `make config`.

Referencie o exit node pelo IP de tailnet ou pelo nome **dele** — que é estável.
Nunca pelo nome do proxy.
