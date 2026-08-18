# Modelo de ameaça

Contra o que isto protege, e contra o que não. Escrito para ser lido **antes** da
viagem, não durante.

## Contra o que protege

| Adversário | Como bloqueia | Por que não pega |
|---|---|---|
| Filtro por categoria/domínio | lista de domínios de VPN | não há domínio nosso no caminho principal |
| Filtro por reputação de IP | listas de IP de VPN conhecidas | o IP é novo a cada `make up` |
| Bloqueio de UDP | derruba QUIC/WireGuard | o caminho principal é TCP/443 |
| Allowlist de SNI | só passa SNI de uma lista | o SNI é o do site decoy |
| Sondagem ativa | abre a conexão e olha a resposta | recebe o handshake real do decoy |
| DPI por fingerprint de TLS | reconhece bibliotecas de proxy | uTLS imita o Chrome |

## Contra o que NÃO protege

**Proxy HTTP obrigatório com MITM de TLS.** Uma CA corporativa instalada no
aparelho, reassinando todo o tráfego. O REALITY morre aí por definição: ele
depende de o handshake chegar intacto ao servidor. É para esse caso que existe o
caminho WebSocket pela Cloudflare — que passa, mas é mais lento e a Cloudflare
enxerga o túnel por dentro.

**Análise de tráfego por volume e tempo.** Uma única conexão TLS de 6 horas
movendo gigabytes não parece navegação, por mais perfeito que seja o handshake.
Contra um adversário que olhe *padrão* em vez de *conteúdo*, nada aqui ajuda.

**A própria Cloudflare, no caminho de reserva.** Ela termina o TLS e vê o
tráfego. O que trafega por dentro continua cifrado ponta a ponta se for HTTPS;
se for HTTP puro, passa legível por lá. Para tráfego sensível, use o caminho
REALITY.

**A AWS.** A máquina é dela. Tudo que sai do túnel sai identificado por um IP
faturado no CPF do dono da conta. Isto não é anonimato — é alcance.

**Política da organização.** A ferramenta contorna controle técnico; não contorna
o contrato de quem colocou o controle lá.

## Superfície da própria ferramenta

- **Repositório público.** Contém a arquitetura inteira, inclusive o site decoy
  em uso. Quem quisesse detectar *esta* instalação em particular tem o manual —
  mas a segurança não depende de segredo de desenho, e sim das chaves.
- **Chave mestra única.** Comprometê-la entrega tudo: túnel, tailnet, acesso SSH
  à máquina. Ela vive só em `~/.config/proxy-do-rafa/age.key` e no `pass`.
- **Portas abertas ao mundo.** 443/tcp e 443/udp, por necessidade — o cliente vem
  de rede arbitrária. A proteção é o protocolo: sem a chave privada REALITY, uma
  sonda recebe o site decoy.
- **8443 restrita à Cloudflare.** Se essa regra falhar, o IP de origem fica
  exposto e o modo proxied vira decoração. É um controle do InSpec
  (`disfarce-03`), justamente por ser silencioso quando quebra.
