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

App oficial **sing-box** — Play Store, F-Droid ou GitHub Releases.

1. Copie `clientes/gerado/cliente.json` para o celular (Google Drive, cabo, o que
   for mais rápido).
2. No app: **New Profile** → Type: **Local** → **Import from file** → escolha o
   arquivo.
3. Conecte.

Use o `cliente.json`, e não o QR: o link `vless://` só carrega o caminho REALITY.
Pelo arquivo você tem os três caminhos, a tailnet e o proxy da LAN.

**Caminho rápido, quando só quer navegar no próprio celular:** `make qr` imprime
o QR do link REALITY, e o app importa por `+` → *Import from clipboard/QR*.

## Hotspot: fazer os outros aparelhos saírem por aqui

**O que NÃO funciona:** ligar o hotspot e esperar que o tráfego dos aparelhos
conectados atravesse o túnel sozinho. No Android sem root, o tráfego do
tethering **ignora a VpnService** — é limitação do sistema, não do app. As
soluções que fazem isso de forma transparente (VPN Hotspot e similares) **exigem
root**.

**O que funciona:** a configuração de cliente traz um proxy escutando na rede
local, com senha. Os outros aparelhos apontam para o celular explicitamente.

```
celular na rede corporativa  ──túnel──>  54.233.164.97  ──>  internet livre
     ↑ proxy 2080 (com senha)
     │
  aparelhos no hotspot, com proxy manual configurado
```

### Passo a passo

1. No celular, conecte o sing-box (o perfil importado acima).
2. Ligue o hotspot.
3. Conecte o outro aparelho ao hotspot e descubra o IP do celular naquela rede —
   no Android costuma ser **`192.168.43.1`**. Confirme no aparelho conectado
   (o gateway da rede é o celular).
4. Nesse aparelho, configure **proxy HTTP manual**:

   | Campo | Valor |
   |---|---|
   | Servidor | o IP do celular no hotspot (ex. `192.168.43.1`) |
   | Porta | `2080` |
   | Usuário | `rafael` |
   | Senha | `make senha-do-proxy` |

O mesmo vale sem hotspot: se o celular e o outro aparelho estiverem na **mesma
rede Wi-Fi**, o aparelho pode usar o celular como proxy do mesmo jeito.

### Por que com senha

O proxy escuta em `0.0.0.0`, porque quem vai usá-lo está em outro aparelho. Sem
senha, qualquer um na mesma rede — o Wi-Fi do hotel, a rede do escritório —
sairia pela sua saída, **na sua conta da AWS**. A senha é gerada junto com os
outros segredos e vive cifrada no repositório.

### O limite honesto disto

É proxy **explícito**, não roteamento. Navegador respeita; aplicativo que ignora
a configuração de proxy do sistema, não. Para cobertura total no aparelho
conectado, o caminho é instalar o sing-box nele também — o mesmo
`cliente.json` serve em Linux, Windows, macOS, Android e iOS.

Alternativa sem essa limitação: rodar o cliente no laptop e compartilhar a
conexão do laptop, onde o roteamento é de verdade.

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
