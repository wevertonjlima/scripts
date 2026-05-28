#!/usr/bin/env bash
# ==============================================================================
# Script: os-update.sh
# Funcao: Atualiza atributos do objeto computador no Active Directory com Logs
#
# IMPORTANTE: Ao realizar qualquer alteracao na logica ou compatibilidade,
# atualize a variavel SCRIPT_VERSION abaixo e a data do LOG de alteracoes.
# O versionamento semantico deve seguir a progressao decimal (1.0.x para
# correcoes/ajustes e 1.x.0 para novas funcionalidades).
#
# Versao Inicial: 1.0.0
# Alteracao: 2026-05-28 (Resolucao de duplicacao de escopo na checagem Kerberos)
# ==============================================================================

# --- [0] METADADOS E VERSAO ---
SCRIPT_VERSION="1.2.1"

# --- [1] CONFIGURACOES DE SEGURANCA ---
set -euo pipefail

# --- [2] CONFIGURACOES DE LOG ---
# Captura o diretorio real onde o script esta armazenado
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define o arquivo de log diretamente no mesmo diretorio, sem subpastas
LOG_FILE="${SCRIPT_DIR}/os-update_$(date +%Y%m%d).log"

# Funcao centralizada para escrita de logs
log_message() {
    local LOG_LEVEL="$1"
    local MESSAGE="$2"
    local TIMESTAMP
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Grava no arquivo de log
    echo "[${TIMESTAMP}] [${LOG_LEVEL}] ${MESSAGE}" >> "$LOG_FILE"
    
    # Exibe na tela apenas se for erro ou aviso para nao poluir o TTY do usuario
    if [ "${LOG_LEVEL}" == "ERROR" ]; then
        echo "    [X] ERRO CRITICO: ${MESSAGE}"
    elif [ "${LOG_LEVEL}" == "WARN" ]; then
        echo "    [!] AVISO: ${MESSAGE}"
    fi
}

# --- [3] BANNER ---
show_banner() {
    clear
    echo ""
    echo "    ===================================================================================="
    echo "        >> ATUALIZACAO DO OBJETO COMPUTADOR NO ACTIVE DIRECTORY (LOG ATIVO)"
    echo "    ===================================================================================="
    echo ""
}

# --- [4] DESCOBERTA DO DOMINIO ---
detect_domain() {
    log_message "INFO" "Iniciando fase de descoberta de dominio DNS."
    while true; do
        show_banner
        read -erp "    Informe o dominio AD (ex: acme.labs): " AD_DOMAIN_INPUT

        AD_DOMAIN=$(echo "$AD_DOMAIN_INPUT" | tr '[:upper:]' '[:lower:]')

        echo "    [*] Validando dominio via DNS..."
        log_message "INFO" "Validando o dominio informado: ${AD_DOMAIN}"
        sleep 1

        if dig +short "$AD_DOMAIN" 2>>"$LOG_FILE" | grep -q '.'; then
            log_message "INFO" "Dominio ${AD_DOMAIN} respondeu ao DNS. Buscando registros SRV LDAP."
            DC_LIST=$(dig +short _ldap._tcp.dc._msdcs."$AD_DOMAIN" SRV 2>>"$LOG_FILE" | awk '{print $4}' | sed 's/\.$//')

            if [ -n "$DC_LIST" ]; then
                AD_DC=$(echo "$DC_LIST" | head -n1)
                log_message "INFO" "Domain Controller (DC) identificado com sucesso: ${AD_DC}"
                echo "    [V] DC encontrado: $AD_DC"
                sleep 2
                break
            else
                log_message "WARN" "Nenhum Domain Controller encontrado via SRV para ${AD_DOMAIN}."
                echo "    [X] Nenhum DC encontrado via SRV."
                sleep 2
            fi
        else
            log_message "WARN" "Resolucao DNS falhou ou o dominio ${AD_DOMAIN} e invalido."
            echo "    [X] Dominio invalido."
            sleep 2
        fi
    done

    AD_BASE_DN="DC=$(echo "$AD_DOMAIN" | sed 's/\./,DC=/g')"
    AD_REALM=$(echo "$AD_DOMAIN" | tr '[:lower:]' '[:upper:]')
    log_message "INFO" "Parametros definidos -> Base DN: ${AD_BASE_DN} | Realm: ${AD_REALM}"
}

# --- [5] VALIDACAO KERBEROS ---
check_kerberos() {
    show_banner
    echo "    [OK!] Active Directory validado: $AD_DOMAIN"
    echo ""

    log_message "INFO" "Verificando a validade real do ticket Kerberos no cache (klist -s)."
    
    # Klist -s checa se o ticket existe E se NAO esta expirado
    if klist -s; then
        log_message "INFO" "Ticket Kerberos valido e ativo encontrado no cache do sistema."
        echo "    [V] Ticket Kerberos valido ja existente."
        sleep 2
        return
    fi

    log_message "WARN" "Nenhum ticket valido ou ativo localizado (Cache vazio ou expirado)."
    echo "    [ ! ] Nenhum ticket Kerberos valido/ativo encontrado no momento."
    echo ""
    read -erp "    Informe apenas o usuario (ex: user_joinad): " KRB_USER_SHORT

    KRB_USER="${KRB_USER_SHORT}@${AD_REALM}"
    log_message "INFO" "Iniciando kinit para renovacao do principal: ${KRB_USER}"
    echo ""
    echo "    [*] Autenticando no Kerberos como: $KRB_USER"
    sleep 1

    # Forca a geracao de um novo ticket e valida dentro do escopo correto
    if kinit "$KRB_USER" 2>>"$LOG_FILE"; then
        if klist -s; then
            log_message "INFO" "Autenticacao realizada com sucesso. Novo ticket ativo para ${KRB_USER}."
            echo ""
            echo "    [V] Autenticacao Kerberos realizada com sucesso."
            sleep 2
        else
            log_message "ERROR" "Kinit executado, mas klist -s ainda acusa ticket invalido."
            exit 1
        fi
    else
        log_message "ERROR" "Falha no comando kinit para o usuario ${KRB_USER}."
        exit 1
    fi
}

# --- [6] ATUALIZACAO DO OBJETO AD ---
update_ad_object() {
    show_banner

    HOSTNAME_SHORT=$(hostname -s)
    COMPUTER_NAME=$(echo "$HOSTNAME_SHORT" | tr '[:lower:]' '[:upper:]')

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$NAME"
        OS_VERSION="$VERSION_ID"
    else
        OS_NAME=$(uname -s)
        OS_VERSION=$(uname -r)
    fi

    OS_SP="Kernel $(uname -r)"

    log_message "INFO" "Buscando objeto computador correspondente a ${COMPUTER_NAME}$ no AD."
    echo "    [*] Localizando objeto no AD..."
    sleep 1

    # Captura os erros estruturais do ldapsearch (ex: GSSAPI failure) diretamente para o arquivo de log
    COMPUTER_DN=$(ldapsearch -LLL -Y GSSAPI -o ldif-wrap=no \
        -H "ldap://$AD_DC" \
        -b "$AD_BASE_DN" \
        "(sAMAccountName=${COMPUTER_NAME}\$)" dn 2>>"$LOG_FILE" | sed -n 's/^dn: //p')

    if [ -z "$COMPUTER_DN" ]; then
        log_message "ERROR" "Nao foi possivel localizar o Distinguished Name (DN) para o computador ${COMPUTER_NAME}$ no LDAP."
        exit 1
    fi

    log_message "INFO" "Objeto localizado com sucesso no Active Directory: ${COMPUTER_DN}"
    echo "    [V] Objeto encontrado:"
    echo "        $COMPUTER_DN"
    sleep 2

    show_banner
    echo "    AVISO DE RISCO (WARNING):"
    echo "    Esta operacao modificara atributos estruturais de producao no Active Directory."
    echo "    Seguem os dados que serao atualizados no objeto computador:"
    echo ""
    printf "     * Computador          : %-30s\n" "$COMPUTER_NAME"
    printf "     * OS                  : %-30s\n" "$OS_NAME"
    printf "     * OS Version          : %-30s\n" "$OS_VERSION"
    printf "     * OS Service Pack     : %-30s\n" "$OS_SP"
    echo ""

    read -rp "    Deseja prosseguir com a alteracao estrutural? (s/n): " CONFIRM

    [[ ! "$CONFIRM" =~ ^[sS]$ ]] && {
        log_message "WARN" "Operacao abortada pelo operador na confirmacao de seguranca."
        echo "    [!] Operacao cancelada pelo operador."
        exit 0
    }

    log_message "INFO" "Usuario confirmou a operacao. Iniciando ldapmodify."
    echo ""
    echo "    [*] Atualizando atributos no AD..."
    sleep 1

    # Redireciona a saida padrao e de erro do ldapmodify para o arquivo de log
    set +e
    ldapmodify -Y GSSAPI -H "ldap://$AD_DC" >> "$LOG_FILE" 2>&1 <<EOF
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
    LDAP_STATUS=$?
    set -e

    if [ $LDAP_STATUS -ne 0 ]; then
        log_message "ERROR" "Falha ao gravar atributos via ldapmodify. Codigo de retorno LDAP: $LDAP_STATUS"
        exit 1
    fi

    log_message "INFO" "Atributos operatingSystem, operatingSystemVersion e operatingSystemServicePack atualizados com sucesso."
    echo ""
    echo "    [V] Atualizacao concluida com sucesso!"
}

# --- [7] MAIN ---
main() {
    log_message "INFO" "=== Iniciando execucao do os-update.sh v${SCRIPT_VERSION} ==="
    detect_domain
    check_kerberos
    update_ad_object
    log_message "INFO" "=== Execucao concluida com sucesso ==="
}

main "$@"
