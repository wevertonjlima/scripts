#!/bin/bash

# ==============================================================================
# Script: AD-find-dcs.bash
# Versão: 1.1
# Descrição:
#     Lista os Controladores de Domínio (Domain Controllers - DCs) do Active 
#     Directory consultando registros SRV via DNS.
#
# Uso:
#     ./find_dcs.sh dominio.com
#
# Exemplo:
#     ./find_dcs.sh exemplo.local
#
# Requisitos:
#     - Utilitário `dig` (geralmente presente no pacote `dnsutils` ou `bind-utils`)
#
# Autor: BASH (Shell script programming genius)
# Data: 03 de Outubro de 2025
# ==============================================================================

print_banner() {
    cat << "EOF"
----------------------------------------------------
|              AD DC Finder v1.1                   |
----------------------------------------------------
| Descrição: Consulta o DNS para listar os         |
| Controladores de Domínio (DCs) de um AD.         |
----------------------------------------------------
EOF
}

find_dcs() {
    local domain="$1"

    if [ -z "$domain" ]; then
        print_banner
        echo
        echo "⚠️  ERRO: Domínio não informado!"
        echo "Uso: $0 dominio.com"
        echo
        return 1
    fi

    local srv_records
    srv_records=$(dig +short _ldap._tcp.dc._msdcs."$domain" SRV)

    if [ -z "$srv_records" ]; then
        echo "❌ Nenhum controlador de domínio encontrado para o domínio: $domain"
        echo "Verifique se o domínio está correto ou se o servidor DNS responde por ele."
        return 2
    fi

    local dc_list
    dc_list=$(echo "$srv_records" | awk '{print $NF}' | sed 's/\.$//')

    echo
    echo "✅ Controladores de Domínio encontrados para o AD: $domain"
    echo "============================================="

    local count=1
    while read -r dc; do
        echo "- $(printf "%02d" "$count") - $dc"
        ((count++))
    done <<< "$dc_list"
    echo
}

# Execução principal
find_dcs "$@"
