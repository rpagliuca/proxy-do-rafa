#!/usr/bin/env bash
# Mostra a credencial do proxy da LAN, para configurar em outro aparelho.
source "$(dirname "$0")/lib.sh"
eval "$(exportar_segredos)"
exigir_valor proxy_local_senha "${proxy_local_senha:-}"
echo "proxy HTTP/SOCKS no aparelho que roda o sing-box:"
echo "  porta:   2080"
echo "  usuario: rafael"
echo "  senha:   $proxy_local_senha"
