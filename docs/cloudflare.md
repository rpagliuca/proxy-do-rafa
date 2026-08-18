# Cloudflare: o token e o zone id

O OpenTofu faz duas coisas na Cloudflare: cria o registro A de
`proxy-do-rafa.eleprograma.com.br` apontando para o IP da máquina (em modo
**proxied**), e garante que o SSL da zona está em **Full**.

São duas operações diferentes, e é isso que define as permissões do token.

## Criar o token

`dash.cloudflare.com` → ícone do perfil (canto superior direito) → **My Profile**
→ **API Tokens** → **Create Token** → **Create Custom Token** (*Get started*).

Atalho: <https://dash.cloudflare.com/profile/api-tokens>

### Permissões — as três, não duas

| Tipo | Recurso | Nível |
|---|---|---|
| Zone | **DNS** | Edit |
| Zone | **Zone Settings** | Edit |
| Zone | **Zone** | Read |

⚠️ **`Zone Settings: Edit` é obrigatória** e é fácil de esquecer. Sem ela o
`tofu apply` cria o registro DNS e **falha depois**, ao aplicar
`cloudflare_zone_setting.ssl` — deixando a stack pela metade: máquina no ar,
DNS criado, SSL não configurado. O erro da API é um `403` que não diz qual
permissão falta.

`Zone: Read` é o que permite ao provider resolver a zona antes de escrever nela.

### Zone Resources

**Include** → **Specific zone** → `eleprograma.com.br`

Restringir à zona importa: o repositório é público, e um token limitado a uma
zona vale muito menos para quem o encontrar do que um token de conta inteira.

*Client IP Address Filtering* e *TTL* podem ficar em branco — o IP de origem muda
a cada viagem, que é o ponto da ferramenta.

**Continue to summary** → **Create Token** → copie o valor. Ele aparece **uma vez
só**.

## Pegar o zone id

`dash.cloudflare.com` → clique em `eleprograma.com.br` → aba **Overview** → coluna
da direita, no rodapé: **Zone ID** (32 caracteres hexadecimais).

Não é segredo — aparece em qualquer captura de tela do painel — mas mora no
mesmo arquivo cifrado por conveniência, para tudo o que o `make up` precisa ficar
num lugar só.

## Guardar

```bash
make segredos
# cloudflare_api_token: <o token copiado>
# cloudflare_zone_id:   <os 32 caracteres>
```

## Conferir antes de gastar um apply

```bash
source scripts/lib.sh && eval "$(exportar_segredos)"
T="$cloudflare_api_token"; Z="$cloudflare_zone_id"

# Zone Read
curl -s -H "Authorization: Bearer $T" \
  "https://api.cloudflare.com/client/v4/zones/$Z" | jq -r .result.name

# Zone Settings Write — regrava o MESMO valor, entao nao muda nada
A=$(curl -s -H "Authorization: Bearer $T" \
  "https://api.cloudflare.com/client/v4/zones/$Z/settings/ssl" | jq -r .result.value)
curl -s -X PATCH -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones/$Z/settings/ssl" -d "{\"value\":\"$A\"}" | jq .success

# DNS Write — cria e apaga um TXT de teste
ID=$(curl -s -X POST -H "Authorization: Bearer $T" -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones/$Z/dns_records" \
  -d '{"type":"TXT","name":"_proxy-do-rafa-teste","content":"permissao ok","ttl":60}' | jq -r .result.id)
curl -s -X DELETE -H "Authorization: Bearer $T" \
  "https://api.cloudflare.com/client/v4/zones/$Z/dns_records/$ID" | jq .result.id
```

⚠️ **Nao use `/user/tokens/verify` para conferir.** Com os tokens do formato novo
(prefixo `cfat_`) ele responde `"Invalid API Token"` mesmo com o token
funcionando — medido em 2026-08-18. Confira exercitando as permissoes de
verdade, como acima: e o unico teste que corresponde ao que o `tofu apply` vai
fazer.

As tres checagens acima sao inofensivas de proposito: a de settings regrava o
valor que ja estava la, e a de DNS apaga o que criou. Elas existem para a falha
de permissao aparecer ANTES do apply — e nao no meio dele, com a maquina ja no
ar e o DNS ja criado.

## Por que modo proxied (nuvem laranja)

Está explicado em `tofu/cloudflare.tf`, junto do código. Em uma linha: o tráfego
termina em IP da Cloudflare — que rede corporativa quase nunca bloqueia — e isso
dispensa Let's Encrypt e libera a 443/tcp inteira para o REALITY.
