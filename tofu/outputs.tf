output "ip_publico" {
  description = "IP da saida. Novo a cada `make up` — e por isso que nenhuma lista de bloqueio o conhece."
  value       = aws_instance.proxy.public_ip
}

output "id_da_instancia" {
  description = "Para `aws ssm start-session --target <id>` quando a porta 22 estiver fechada."
  value       = aws_instance.proxy.id
}

output "dominio" {
  description = "FQDN do caminho de reserva (WebSocket atras da Cloudflare)."
  value       = var.dominio
}

output "regiao" {
  value = var.aws_region
}

output "custo_por_dia_usd" {
  description = <<-EOT
    Custo aproximado de deixar ligado 24 h, sem egress. Precos on-demand de
    sa-east-1 medidos na API de pricing da AWS em 2026-08-18:
    t4g.micro US$0,0134/h + IPv4 publico US$0,005/h.

    Egress e a parte que varia: US$0,150/GB em sa-east-1, com os primeiros
    100 GB/mes gratuitos na conta. Video pelo tunel consome 1–3 GB por HORA.
  EOT
  value       = format("%.2f", (0.0134 + 0.005) * 24)
}
