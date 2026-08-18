# Caminho de reserva: WebSocket atras da Cloudflare.
#
# ─── Por que existe, se o REALITY ja funciona ─────────────────────────────────
#
# O REALITY morre num cenario especifico e comum em rede corporativa: proxy HTTP
# obrigatorio com MITM de TLS, onde uma CA da empresa reassina todo o trafego. O
# REALITY depende de o handshake chegar intacto ao servidor; um MITM quebra isso
# por definicao.
#
# Nesse cenario o que passa e trafego que PARECA uma visita comum a um site
# comum, e que o proxy consiga reassinar sem perceber diferenca. E o que este
# caminho entrega: TLS para a borda da Cloudflare, WebSocket por dentro.
#
# ─── Por que no modo proxied (nuvem laranja) ──────────────────────────────────
#
# 1. O trafego termina em IP da Cloudflare, nao no nosso. Rede corporativa
#    raramente bloqueia a Cloudflare inteira — metade da web esta atras dela.
# 2. O certificado e da Cloudflare: nada de Let's Encrypt, nada de porta 80
#    aberta, nada de limite de emissao a cada `make up` (o IP muda toda vez, e
#    reemitir certificado 5 vezes por semana esbarraria no limite do Let's
#    Encrypt justo numa viagem).
# 3. Libera a 443/tcp inteira para o REALITY, porque a Cloudflare alcanca a
#    origem numa porta alternativa.
#
# ⚠️ O preco: a Cloudflare termina o TLS e portanto ve o tunel por dentro. O que
# ela ve e o trafego dele ja cifrado ponta a ponta para os destinos finais
# (HTTPS comum), mas qualquer coisa que ele acesse em HTTP puro passaria legivel
# por la. Registrado; para trafego sensivel, usar o caminho REALITY.

resource "cloudflare_dns_record" "proxy" {
  zone_id = var.cloudflare_zone_id
  name    = var.dominio
  type    = "A"
  content = aws_instance.proxy.public_ip
  proxied = true

  # ttl = 1 significa "automatico", e e obrigatorio quando proxied = true.
  ttl = 1

  comment = "proxy-do-rafa — efemero, recriado a cada make up"
}

# SSL da zona em "full": a Cloudflare fala HTTPS com a origem e aceita o
# certificado autoassinado que o Ansible instala la.
#
# Nao e "flexible" (que falaria HTTP puro com a origem, expondo o tunel no
# trecho Cloudflare→AWS) nem "strict" (que exigiria um certificado emitido pela
# CA de origem da Cloudflare, mais um segredo para gerir sem ganho real: o
# unico cliente daquela porta e a propria Cloudflare, e o security group ja
# garante isso).
#
# ⚠️ Isto e uma configuracao de ZONA, nao de registro: vale para
# eleprograma.com.br inteiro. A zona hoje nao serve mais nada — se um dia
# servir, reavaliar.
resource "cloudflare_zone_setting" "ssl" {
  zone_id    = var.cloudflare_zone_id
  setting_id = "ssl"
  value      = "full"
}
