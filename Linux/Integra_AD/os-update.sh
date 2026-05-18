#!/usr/bin/env bash

# =====================================================================================
# SCRIPT: os-update.sh
# DESCRIÇÃO: Atualiza atributos do objeto computador no Active Directory
# REQUISITOS: kinit válido + conectividade LDAP/Kerberos
# =====================================================================================

set -euo pipefail

# -------------------------------------------------------------------------------------
# Banner
# -------------------------------------------------------------------------------------
show_banner() {
    clear
    echo ""
    echo "    ===================================================================================="
    echo "        >> ATUALIZAÇÃO DO OBJETO COMPUTADOR NO ACTIVE DIRECTORY"
    echo "    ===================================================================================="
    echo ""
}

# -------------------------------------------------------------------------------------
# Descoberta do domínio via DNS
# -------------------------------------------------------------------------------------
detect_domain() {

    while true; do
        show_banner
        read -erp "    Informe o domínio AD (ex: acme.labs): " AD_DOMAIN_INPUT

        AD_DOMAIN=$(echo "$AD_DOMAIN_INPUT" | tr '[:upper:]' '[:lower:]')

        echo "    [*] Validando domínio via DNS..."
        sleep 1

        if dig +short "$AD_DOMAIN" | grep -q '.'; then
            DC_LIST=$(dig +short _ldap._tcp.dc._msdcs."$AD_DOMAIN" SRV | awk '{print $4}' | sed 's/\.$//')

            if [ -n "$DC_LIST" ]; then
                AD_DC=$(echo "$DC_LIST" | head -n1)
                echo "    [✔] DC encontrado: $AD_DC"
                sleep 2
                break
            else
                echo "    [X] Nenhum DC encontrado via SRV."
                sleep 2
            fi
        else
            echo "    [X] Domínio inválido."
            sleep 2
        fi
    done

    AD_BASE_DN="DC=$(echo "$AD_DOMAIN" | sed 's/\./,DC=/g')"
    AD_REALM=$(echo "$AD_DOMAIN" | tr '[:lower:]' '[:upper:]')
}

# -------------------------------------------------------------------------------------
# Validação Kerberos
# -------------------------------------------------------------------------------------
check_kerberos() {

    show_banner

    echo "    [OK!] Active Directory validado: $AD_DOMAIN"
    echo ""

    # ------------------------------------------------------------
    # Se já existe ticket válido → usa direto
    # ------------------------------------------------------------
    if klist &>/dev/null; then
        echo "    [✔] Ticket Kerberos já existente."
        sleep 2
        return
    fi

    echo "    [ ! ] Nenhum ticket Kerberos encontrado."
    echo ""

    # ------------------------------------------------------------
    # Solicita apenas o usuário (sem domínio)
    # ------------------------------------------------------------
    read -erp "    Informe apenas o usuário (ex: user_joinad): " KRB_USER_SHORT

    # Monta UPN automaticamente
    KRB_USER="${KRB_USER_SHORT}@${AD_REALM}"

    echo ""
    echo "    [*] Autenticando no Kerberos como: $KRB_USER"
    sleep 1

    kinit "$KRB_USER"

    if klist &>/dev/null; then
        echo ""
        echo "    [✔] Autenticação Kerberos realizada com sucesso."
        sleep 2
    else
        echo ""
        echo "    [X] Falha na autenticação Kerberos."
        exit 1
    fi
}

# -------------------------------------------------------------------------------------
# Atualização do objeto AD
# -------------------------------------------------------------------------------------
update_ad_object() {

    show_banner

    HOSTNAME_SHORT=$(hostname -s)
    COMPUTER_NAME=$(echo "$HOSTNAME_SHORT" | tr '[:lower:]' '[:upper:]')

    # Detecta SO
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$NAME"
        OS_VERSION="$VERSION_ID"
    else
        OS_NAME=$(uname -s)
        OS_VERSION=$(uname -r)
    fi

    OS_SP="Kernel $(uname -r)"

    echo "    [*] Localizando objeto no AD..."
    sleep 1

    COMPUTER_DN=$(ldapsearch -LLL -Y GSSAPI \
        -H "ldap://$AD_DC" \
        -b "$AD_BASE_DN" \
        "(sAMAccountName=${COMPUTER_NAME}\$)" dn | awk '/^dn:/ {print $2}')

    if [ -z "$COMPUTER_DN" ]; then
        echo "    [X] Objeto do computador não encontrado."
        exit 1
    fi

    echo "    [✔] Objeto encontrado:"
    echo "        $COMPUTER_DN"
    sleep 2

    # ------------------------------------------------------------------
    # Confirmação
    # ------------------------------------------------------------------
    show_banner

    echo "    Atenção."
    echo "    Seguem os dados que serão atualizados no objeto computador:"
    echo ""
    printf "     * Computador          : %-30s\n" "$COMPUTER_NAME"
    printf "     * OS                  : %-30s\n" "$OS_NAME"
    printf "     * OS Version          : %-30s\n" "$OS_VERSION"
    printf "     * OS Service Pack     : %-30s\n" "$OS_SP"
    echo ""

    read -rp "    Deseja prosseguir? (s/n): " CONFIRM

    [[ ! "$CONFIRM" =~ ^[sS]$ ]] && {
        echo "    [!] Operação cancelada."
        exit 0
    }

    # ------------------------------------------------------------------
    # Atualização
    # ------------------------------------------------------------------
    echo ""
    echo "    [*] Atualizando atributos no AD..."
    sleep 1

ldapmodify -Y GSSAPI \
    -H "ldap://$AD_DC" <<EOF
dn: $COMPUTER_DN
changetype: modify
replace: operatingSystem
operatingSystem: $OS_NAME
-
replace: operatingSystemVersion
operatingSystemVersion: $OS_VERSION
-
replace: operatingSystemServicePack
operatingSystemServicePack: $OS_SP
EOF






    echo ""
    echo "    [✔] Atualização concluída com sucesso!"
}

# -------------------------------------------------------------------------------------
# MAIN
# -------------------------------------------------------------------------------------
main() {
    detect_domain
    check_kerberos
    update_ad_object
}

main "$@"
