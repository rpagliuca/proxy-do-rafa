# Clientes

`make up` gera dois arquivos em `clientes/gerado/` (ambos fora do git):

| Arquivo | O que é |
|---|---|
| `cliente.json` | configuração completa, com os três caminhos. É esta que se importa. |
| `reality.url` | link `vless://` do caminho principal, para importar por QR |

## Por que o link rápido só traz o REALITY

O formato de URL não representa certificado fixado. O Hysteria2 usa certificado
autoassinado (fixado no cliente, que é o que o torna seguro sem CA), então o link
teria de trazer `insecure=1` — e aí a fixação, que é a proteção, desaparece.

Pelo `cliente.json` os três caminhos vêm certos. O link é atalho, não substituto.

## Linux

```bash
sudo cp clientes/gerado/cliente.json /etc/sing-box/config.json
sudo sing-box run -c /etc/sing-box/config.json
```

Modo TUN com `auto_route`: todo o tráfego da máquina passa a sair pelo túnel,
inclusive o do Tailscale, sem configurar nada em cada aplicação.

O tráfego para o IP do próprio servidor é excluído explicitamente (`route.rules`)
— sem isso, o túnel tentaria entrar em si mesmo.

## Android

App oficial **sing-box** (Play Store ou F-Droid).

**Caminho rápido:** `make qr` imprime o QR do link REALITY. No app:
`+` → *Import from clipboard/QR*.

**Caminho completo (recomendado):** copie `clientes/gerado/cliente.json` para o
aparelho e importe como perfil local. Só assim você tem os três caminhos e pode
alternar entre eles quando a rede mudar.

### Compartilhar com outros aparelhos

O objetivo — conectar o celular à rede corporativa, ligar o túnel, e os outros
aparelhos saírem por ele — **não funciona de forma transparente no Android sem
root**. Quem está no tethering ignora a `VpnService`; é limitação do sistema, não
do app.

O que funciona:

1. No app sing-box, ative **Allow connections from LAN** e anote a porta do
   proxy misto (padrão `2080`).
2. Ligue o hotspot do celular.
3. Nos outros aparelhos, configure **manualmente** o proxy HTTP/SOCKS apontando
   para o IP do celular na rede do hotspot, porta `2080`.

Cada aparelho passa a sair pelo túnel — mas por configuração explícita de proxy,
aplicação por aplicação, não por roteamento. Navegador funciona; aplicativo que
ignora as configurações de proxy do sistema, não.

Alternativa sem essa limitação: rodar o cliente no laptop e compartilhar a
conexão do laptop.

## Trocar de caminho quando a rede muda

No app (ou pela API do Clash, no Linux), o outbound `saida` é um **selector** com
os três. Ordem prática para tentar:

1. **reality** — comece sempre por ele;
2. **hysteria2** — se a rede deixa UDP passar, é bem mais rápido;
3. **websocket** — quando os dois falham, o que costuma indicar proxy corporativo
   obrigatório com MITM de TLS.

## Depois de `make down`

Todas as configurações de cliente param de valer: o IP mudou. Rode `make up` e
`make qr` de novo. Isso é o desenho, não um incômodo — IP que não se repete é IP
que nenhuma lista de bloqueio conhece.
