#!/bin/bash

# =============================================================================
# 🛡️ Script: Verificador de Grupo no Active Directory (Protocolo LDAP)
# =============================================================================
#
# 📘 Descrição:
#   Este script realiza a verificação da existência de um grupo no Active Directory,
#   usando autenticação via UPN (ex: usuario@dominio.com) e protocolo LDAP (porta 389).
#   Ele NÃO requer que o sistema esteja integrado ao domínio.
#
# 🔧 Requisitos:
#   - Sistema operacional: Debian ou Ubuntu
#   - Pacote: ldap-utils
#
# 📥 O script:
#   - Solicita o nome do grupo (com validação de caracteres permitidos)
#   - Solicita uma conta de domínio (UPN) e senha com confirmação
#   - Extrai automaticamente o base DN do sufixo da conta UPN
#   - Faz consulta segura usando ldapsearch via protocolo ldap://
#   - Exibe se o grupo foi encontrado ou não
#   - Permite repetir o processo em loop
#
# 📌 Exemplo de uso:
#   chmod +x verifica_grupo_ad_ldap.sh
#   ./verifica_grupo_ad_ldap.sh
#
# 🔒 Observações:
#   - Não armazena senhas
#   - Não grava logs
#   - Apenas grupos com caracteres válidos serão aceitos:
#     Letras, números, hífen (-), underscore (_), ponto (.)
#
# 🧠 Autor: Linux Server Expert (GPT)
# ============================================================================

clear
echo "============================================"
echo "  Verificador de Grupos no Active Directory "
echo "  (via protocolo LDAP - porta 389)          "
echo "============================================"
echo
echo "Este script verifica se um grupo existe no AD."
echo "Será necessário fornecer uma conta UPN e senha."
echo

# Verifica e instala ldap-utils se necessário
if ! command -v ldapsearch &> /dev/null; then
    echo "Ferramenta 'ldap-utils' não encontrada."
    read -p "Deseja instalar agora? (s/n): " instalar
    if [[ "$instalar" =~ ^[sS]$ ]]; then
        sudo apt update && sudo apt install -y ldap-utils
    else
        echo "Instalação cancelada. Encerrando."
        exit 1
    fi
fi

while true; do
    read -erp "Informe o nome do grupo: " grupo_raw
    grupo=$(echo "$grupo_raw" | tr -cd 'a-zA-Z0-9._-')
    if [[ -z "$grupo" ]]; then
        echo " Nome de grupo inválido. Apenas letras, números, '.', '-', '_' são permitidos."
        continue
    fi

    read -erp "Informe a conta UPN (ex: usuario@dominio.com): " upn
    if [[ ! "$upn" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        echo " UPN inválido."
        continue
    fi

    echo -n "Digite a senha: "
    read -s senha1
    echo
    echo -n "Confirme a senha: "
    read -s senha2
    echo
    if [[ "$senha1" != "$senha2" ]]; then
        echo " Senhas não conferem."
        continue
    fi

    dominio="${upn#*@}"
    base_dn=$(echo "$dominio" | awk -F. '{for (i=1;i<=NF;i++) printf "dc=%s%s", $i, (i==NF?"":",")}')
    ldap_host="ldap://$dominio"

    echo
    echo " Buscando grupo '$grupo' em $dominio (via LDAP)..."
    sleep 2
    resultado=$(ldapsearch -LLL -x -H "$ldap_host" \
        -D "$upn" -w "$senha1" \
        -b "$base_dn" "(&(objectClass=group)(sAMAccountName=$grupo))" sAMAccountName 2>/dev/null)

    if echo "$resultado" | grep -q "^sAMAccountName: "; then
        echo "✅ Grupo encontrado: $grupo"
    else
        echo " Grupo não encontrado."
    fi

    echo
    read -p "Deseja verificar outro grupo? (s/n): " repetir
    if [[ ! "$repetir" =~ ^[sS]$ ]]; then
        echo "Encerrando o script. Até logo!"
        break
    fi
    echo "--------------------------------------------"
done
