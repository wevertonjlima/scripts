#!/usr/bin/env bash

# ==============================================================================
# Script ....: integra_ubuntu.sh
# Funcao ....: Integracao Ubuntu Server com Active Directory
# Created ...: Weverton Lima <wevertonjlima@gmail.com>
# Powered By : Gemini Agent, Morgana Linux Witch. 
#
# DESCRICAO:
#   Script para integrar Ubuntu Server ao Active Directory,
#   configurando firewall, SSSD, PAM, sudo e validando o ambiente.
#
# REQUISITOS:
#   - Ubuntu Server 24.04 LTS ou 26.04 LTS
#   - Acesso root/sudo
#   - Conectividade com os DCs do AD (portas 389, 88, 464, 3268)
#   - Conta AD com permissao para unir computadores ao dominio
#   - Grupo AD que será indicado como SUDO neste sistema.
#
# Data: 2026-05-21
#
# Ultimos ajustes:
# - inserção de LOG
# - ajuste de visualização de solicitações de confirmações interativas (S ou N)?
# - ajuste no MOD 5, para inclusão de kernel no objeto do AD.
#
# ==============================================================================

# --- [0] CONFIGURACOES DE SEGURANCA ---
set -euo pipefail

# --- [1] METADADOS E VERSAO ---
SCRIPT_VERSION="1.3.0"

# --- [2] INFRAESTRUTURA DE LOGS (FASE 1 - VERSAO RIGOROSA) ---
LOG_DIR="$(dirname "$(readlink -f "$0")")"
LOG_FILE="${LOG_DIR}/integra_ad_ubuntu_$(date +%Y-%m-%d_%H-%M).log"

touch "$LOG_FILE"
chown root:sudo "$LOG_FILE"
chmod 644 "$LOG_FILE"

# >>> Funcao interna para alimentar o log com marcos de execucao
log_event() {
    local tipo="$1"
    local mensagem="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [${tipo}] - ${mensagem}" >> "$LOG_FILE"
}

# >>> Captura o Ctrl+C (SIGINT) e encerra registrando formalmente no log
trap_ctrl_c() {
    echo ""
    echo "    [X] Execucao interrompida pelo usuario (Ctrl+C). Saindo..."
    log_event "INTERRUPCAO" "O usuario abortou o script via Ctrl+C."
    exit 130
}
trap trap_ctrl_c SIGINT


# --- [3] Funcoes Auxiliares e Preparacao ---

# >>> Verifica se eh root
if [[ $EUID -ne 0 ]]; then
    echo ""
    echo "    [X] Este script precisa ser executado como root (sudo)."
    echo "        Utilize: sudo $0"
    echo ""
    exit 1
fi

# >>> Funcao de pausa entre modulos
mod_next() {
    printf "\n\n    >>> Prosseguindo...\n\n"
    sleep 4
}

# --- [4] Variaveis Globais utilizadas entre os Modulos ---
# Inicializadas vazias para evitar erros de 'unbound variable' (set -u)
# Note: A variavel AD_PASS (senha) NAO e declarada aqui por seguranca.
AD_DOMAIN=""
AD_REALM=""
AD_DC=""
AD_BASE_DN=""
AD_UPN=""
AD_USER_ONLY=""
AD_GROUP=""
AD_OU=""
FINAL_FQDN=""
SHORT_HOSTNAME=""
OU_DN_FINAL="" 
SYS_OS=""
SYS_VER=""
SYS_SP=""
# end mod_intro


# MÓDULO 1: BANNER E BOAS-VINDAS (COM AJUSTE DE FQDN IDEMPOTENTE) %%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
mod1_banner() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "              INTEGRACAO UBUNTU SERVER COM ACTIVE DIRECTORY"
    echo "    ----------------------------------------------------------------------"
    echo "                      Versao : ${SCRIPT_VERSION} "
    echo "                      Etapa 1: Bem-Vindo! "
    echo "    ======================================================================"
    echo ""
    echo "        OBJETIVO:"
    echo "        - Integrar este servidor linux para se unir a um dominio"
    echo "          Active Directory, permitindo login de usuarios."
    echo ""
    echo "        CARACTERISTICAS:"
    echo "        - Controle de login local/ssh através de Grupo de Seguranca do AD"
    echo "        - Permissao de root através de Grupo de Seguranca do AD"
    echo "        - Cache de credenciais permitindo login offline"
    echo "        - Envio automatico das informacoes do SO (Nome, Versão e Kernel) para o AD"
    echo ""
    echo "        IMPORTANTE!"
    echo "        - Tenha em maos as seguintes informacoes sobre o Active Directory:"
    echo "        ------------------------------------------------------------------"
    echo "        * Nome do Dominio DNS do AD"
    echo "        * Nome da Conta de Servico e Sennha do usuario que ira integrar ao AD"
    echo "        * Nome do Grupo do AD que será Administrador deste servidor"
    echo "        * (Opcional) OU onde o computador sera registrado"
    echo ""
    echo "    ======================================================================"
    echo ""
    
    local PROSSEGUIR=""
    local CONF_PROSSEGUIR=""
    local ALTERAR=""
    local NEW_HOSTNAME=""
    local CONF_HOST=""
    local REBOOT_CONF=""
    
    if [ -z "${AD_DOMAIN+x}" ]; then
        AD_DOMAIN="dominio.local"
    fi
    
    while true; do
        read -erp "    Deseja prosseguir com a instalacao e configuracao? (s/n): " PROSSEGUIR
        PROSSEGUIR="${PROSSEGUIR,,}"
        
        if [[ "$PROSSEGUIR" == "s" ]]; then
            echo ""
            echo "    Iniciando as configuracoes..."
            log_event "INFO" "Usuario aceitou o termo inicial e avancou."
            sleep 1
            break
        elif [[ "$PROSSEGUIR" == "n" ]]; then
            echo ""
            echo "    Operacao abortada pelo usuario. Saindo..."
            log_event "AVISO" "Usuario recusou o termo inicial. Script encerrado."
            exit 0
        else
            echo ""
            echo "    Resposta invalida. Digite 's' para sim ou 'n' para nao."
            echo ""
        fi
    done


    # SECAO: VERIFICACAO E AJUSTE DE HOSTNAME E REDE (OTIMIZADO UBUNTU/NETPLAN)
    # ----------------------------------------------------------------------
    while true; do
        clear
        
        local CURRENT_HOSTNAME=$(hostname)
        local SHORT_HOSTNAME=$(echo "$CURRENT_HOSTNAME" | cut -d'.' -f1)
        
        local INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
        [ -z "$INTERFACE" ] && INTERFACE=$(ip -4 addr show up | grep -v '127.0.0.1' | awk '/inet / {print $NF}' | head -n1)
        
        local IP_ADD=$(ip -4 addr show dev "$INTERFACE" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)
        local NETMASK_CIDR=$(ip -4 addr show dev "$INTERFACE" | awk '/inet / {print $2}' | cut -d/ -f2 | head -n1)
        local GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)
        
        local DNS_SERVER=$(resolvectl dns "$INTERFACE" 2>>"$LOG_FILE" | awk '{print $4}' | head -n1)
        [ -z "$DNS_SERVER" ] && DNS_SERVER=$(awk '/nameserver/ {print $2}' /etc/resolv.conf | head -n1)
        
        local DHCP_SERVER="Nenhum (IP Estatico)"
        if grep -rqi "dhcp4:.*true" /etc/netplan/; then
            DHCP_SERVER="Ativo (IP via DHCP)"
        fi
        
        local MASK_LEGIVEL=""
        case "$NETMASK_CIDR" in
            24) MASK_LEGIVEL="255.255.255.0 (/$NETMASK_CIDR)" ;;
            16) MASK_LEGIVEL="255.255.0.0 (/$NETMASK_CIDR)" ;;
            8)  MASK_LEGIVEL="255.0.0.0 (/$NETMASK_CIDR)" ;;
            *)  MASK_LEGIVEL="Cidr /$NETMASK_CIDR" ;;
        esac

        echo ""
		echo "    ======================================================================"
		echo "                     Integra AD v: ${SCRIPT_VERSION} "
		echo "    ----------------------------------------------------------------------"
        echo "                        Etapa 1: Bem-Vindo!"
		echo "                     Verificacao de Hostname e Rede"
        echo "    ======================================================================"
		echo ""
		echo "                    - Hostname ...: $SHORT_HOSTNAME"
        echo "                    "
        echo "                    - IP Add .....: $IP_ADD"
        echo "                    - Mascara ....: $MASK_LEGIVEL"
        echo "                    - Gateway ....: $GATEWAY"
        echo "                    - DNS ........: $DNS_SERVER"
        echo "                    "
        echo "                    - DHCP SERVER.: $DHCP_SERVER"
        echo "    ----------------------------------------------------------------------"

        if [ "$SHORT_HOSTNAME" != "localhost" ] && [ -n "$SHORT_HOSTNAME" ]; then
            read -erp "    Deseja prosseguir ? (s/n): " CONF_PROSSEGUIR
            CONF_PROSSEGUIR="${CONF_PROSSEGUIR,,}"
            
            if [[ "$CONF_PROSSEGUIR" == "s" ]]; then
                local DOMAIN_LOWER=$(echo "$AD_DOMAIN" | tr '[:upper:]' '[:lower:]')
                local CLEAN_NAME="$SHORT_HOSTNAME"
                local FINAL_FQDN="${CLEAN_NAME}.${DOMAIN_LOWER}"

                echo "    [  *  ] Ajustando FQDN para idempotencia: $FINAL_FQDN"
                log_event "INFO" "Hostname valido ($SHORT_HOSTNAME). Aplicando FQDN: $FINAL_FQDN"
                
                sudo hostnamectl set-hostname "$FINAL_FQDN" 2>>"$LOG_FILE"
                
                if ! grep -q "$FINAL_FQDN" /etc/hosts; then
                    echo "127.0.0.1   $FINAL_FQDN $CLEAN_NAME" | sudo tee -a /etc/hosts > /dev/null 2>>"$LOG_FILE"
                fi
                break
            elif [[ "$CONF_PROSSEGUIR" == "n" ]]; then
                echo ""
                echo "    Operacao abortada pelo usuario. Saindo..."
                log_event "AVISO" "Usuario rejeitou as informacoes de rede atuais."
                exit 0
            else
                echo ""
                echo "    Resposta invalida. Digite 's' para sim ou 'n' para nao."
                sleep 2
            fi
        else
            log_event "AVISO" "Hostname invalido ($SHORT_HOSTNAME). Forcando alteracao."
            echo "    ERROR !!!"
            echo "    O nome do computador nao pode ser ingressado como localhost."
            echo ""
            read -erp "    Deseja ALTERAR o hostname ? (s/n): " ALTERAR
            ALTERAR="${ALTERAR,,}"
            
            if [[ "$ALTERAR" != "s" ]]; then
                echo ""
                echo "    O script nao pode continuar com hostname invalido. Saindo..."
                log_event "ERRO" "Usuario recusou corrigir o hostname 'localhost'."
                exit 1
            fi
            
            while true; do
                clear
                echo      "    ======================================================================"
                echo      "                        Etapa1: CONFIRMACAO DO HOSTNAME "
                echo      "    ======================================================================"
                echo      ""
                echo      "    Informe o novo hostname, até 15 caracteres !"
                echo      "    (ex.: server-infra01)"
                read -erp "    Digite: " NEW_HOSTNAME
                
                NEW_HOSTNAME=$(echo "$NEW_HOSTNAME" | cut -d'.' -f1)
                
                if [ ${#NEW_HOSTNAME} -gt 15 ]; then
                    echo "    [ERROR] O nome ultrapassa 15 caracteres padrao NetBIOS. Tente novamente."
                    sleep 2
                    continue
                fi
                
                if [ -z "$NEW_HOSTNAME" ] || [[ "$NEW_HOSTNAME" == "localhost" ]]; then
                    echo "    [ERROR] Nome invalido ou em branco."
                    sleep 2
                    continue
                fi
                
                echo ""
                read -erp "    Confirma novo hostname: $NEW_HOSTNAME (s/n) ? " CONF_HOST
                CONF_HOST="${CONF_HOST,,}"
                if [[ "$CONF_HOST" == "s" ]]; then
                    break
                fi
            done
            
            echo ""
            echo      "    Você está em uma janela de manutenção? Mudar o hostname causará um reboot."
            read -erp "    Este computador sera reiniciado! Deseja prosseguir ? (s/n): " REBOOT_CONF
            REBOOT_CONF="${REBOOT_CONF,,}"
            if [[ "$REBOOT_CONF" != "s" ]]; then
                echo ""
                echo  "    Alteracao cancelada. Saindo..."
                log_event "AVISO" "Alteracao de hostname cancelada pelo usuario."
                exit 0
            fi
            
            local DOMAIN_LOWER=$(echo "$AD_DOMAIN" | tr '[:upper:]' '[:lower:]')
            log_event "INFO" "Reboot agendado para aplicar novo hostname: ${NEW_HOSTNAME}.${DOMAIN_LOWER}"
            
            sudo hostnamectl set-hostname "${NEW_HOSTNAME}.${DOMAIN_LOWER}" 2>>"$LOG_FILE"
            
            clear
            echo "    ======================================================================"
            echo "        Apos o reboot, utilize novamente o script."
            echo "    ======================================================================"
            echo "        [  *  ] Reiniciando o sistema em 5 segundos..."
            sleep 5
            sudo reboot
            exit 0
        fi
    done
    
    echo ""
    echo "    [ OK! ] Modulo de banner e rede concluido."
    log_event "INFO" "Modulo 1 concluido com sucesso."
    sleep 2
    mod_next
}
# end mod1


# MODULO 2: INSTALACAO DE PACOTES (APT) - VERSAO UBUNTU %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
mod2_install() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                        Versao : ${SCRIPT_VERSION} "
    echo "                        Etapa 2: INSTALACAO DE PACOTES"
    echo "    ----------------------------------------------------------------------"
    echo "                       Instalando dependencias para integracao com AD"
    echo "    ======================================================================"
    echo ""
    
    # Verifica conectividade com repositorios
    echo "    [  *  ] Verificando conectividade com repositorios APT..."
    if ! sudo apt update --print-uris &>/dev/null; then
        echo "    [ERROR] Nao foi possivel acessar os repositorios APT."
        echo "    Verifique as configuracoes de Proxy ou Gateway de rede."
        sleep 4
        return 1
    fi
    echo "    [ OK! ] Repositorios acessiveis."
    
    # Atualiza lista de pacotes
    echo ""
    echo "    [  *  ] Atualizando lista de pacotes..."
    sudo apt update -qq
    
    # Verifica atualizacoes pendentes
    echo "    [  *  ] Verificando atualizacoes pendentes..."
    local updates=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || true)
    
    if [ "$updates" -gt 0 ]; then
        echo "    [!] ATENCAO: Existem $updates atualizacoes pendentes."
        while true; do
            read -erp "    Deseja atualizar o sistema agora? (s/n): " ATUALIZAR
            [[ "$ATUALIZAR" == "s" ]] && sudo apt upgrade -y && break
            [[ "$ATUALIZAR" == "n" ]] && echo "    Prosseguindo sem atualizar..." && break
            echo "    Digite 's' ou 'n'"
        done
    else
        echo "    [ OK! ] Sistema ja atualizado."
    fi
    
    # Lista de pacotes necessarios para Ubuntu (Sua lista validada 26.04)
    local PACOTES=(
        adcli
        bind9-dnsutils
        chrony
        cracklib-runtime
        dbus
        krb5-user
        ldap-utils
        libnss-sss
        libpam-sss
        oddjob
        oddjob-mkhomedir
        packagekit
        realmd
        samba-common-bin
        sssd
        sssd-tools
        ufw
    )
    
    echo ""
    echo "    [  *  ] Instalando pacotes: ${PACOTES[*]}"
    echo "    ----------------------------------------------------------------------"
    echo "    AVISO: O processo pode demorar dependendo da velocidade da conexao."
    echo "    ----------------------------------------------------------------------"

    # A variavel DEBIAN_FRONTEND=noninteractive impede que o krb5-user 
    # abra telas de configuracao manual no meio do script.
    if sudo DEBIAN_FRONTEND=noninteractive apt install -y "${PACOTES[@]}"; then
        echo ""
        echo "    [ OK! ] Pacotes instalados com sucesso."
    else
        echo ""
        echo "    [ERROR] Falha na instalacao de pacotes."
        return 1
    fi
    
    # Validacao final refinada
    echo ""
    echo "    [  *  ] Validando instalacao individual..."
    local OK=true
    for pkg in "${PACOTES[@]}"; do
        # dpkg-query eh mais rapido e preciso que grep no dpkg -l
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            echo "    [OK] $pkg"
        else
            echo "    [X] $pkg - FALHOU!"
            OK=false
        fi
    done
    
    if [ "$OK" = false ]; then
        echo ""
        echo "    [X] ERRO CRITICO: Um ou mais pacotes falharam. Abortando."
        return 1
    fi
    
    # Preparacao final do ambiente
    echo ""
    echo "    [  *  ] Ajustando servicos para configuracao..."
    sudo systemctl stop sssd &>/dev/null
    sudo systemctl enable --now chrony &>/dev/null
    
    echo "    [ OK! ] Modulo de instalacao concluido."
    sleep 2
    mod_next
}
# end mod2 


# MODULO 3: CONFIGURACAO DE FIREWALL (UFW) - VERSAO UBUNTU %%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
mod3_firewall() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                        Versao : ${SCRIPT_VERSION} "
    echo "                        Etapa 3: CONFIGURACAO DO FIREWALL"
    echo "    ----------------------------------------------------------------------"
    echo "             Liberando portas necessarias para comunicacao com o AD"
    echo "    ======================================================================"
    echo ""

    # Verifica o estado atual do UFW de forma limpa
    echo "    [  *  ] Verificando estado atual do UFW..."
    if ! sudo ufw status | grep -q "Status: active"; then
        echo "    [ OK! ] O Firewall (UFW) esta DESATIVADO neste servidor."
        echo "        Nenhuma regra sera aplicada para respeitar a diretriz do sistema."
        sleep 2
        mod_next
        return 0
    fi

    echo "    [!] O Firewall (UFW) esta ATIVO. Injetando regras do Active Directory..."
    echo "    ----------------------------------------------------------------------"

    # Lista de portas estruturais do Active Directory (TCP e UDP)
    # Formato: "porta/protocolo" -> Comentario descritivo
    local REGRAS_AD=(
        "53/tcp"     # DNS SECURE / RESOLUCAO
        "53/udp"     # DNS RESOLUCAO
        "88/tcp"     # KERBEROS AUTH
        "88/udp"     # KERBEROS AUTH
        "123/udp"    # NTP / CHRONY SYNC
        "135/tcp"    # RPC ENDPOINT MAPPER
        "389/tcp"    # LDAP PROTOCOL
        "389/udp"    # LDAP PROTOCOL
        "445/tcp"    # SMB DIRECT / NETLOGON
        "464/tcp"    # KERBEROS PASSWORD
        "464/udp"    # KERBEROS PASSWORD
        "636/tcp"    # LDAPS (LDAP OVER SSL)
        "3268/tcp"   # GLOBAL CATALOG
        "3269/tcp"   # GLOBAL CATALOG SSL
    )

    # Injeção incremental das regras (Sem alterar ou apagar as regras existentes)
    for regra in "${REGRAS_AD[@]}"; do
        local porta="${regra%%/*}"
        local proto="${regra##*/}"
        
        echo "    [  *  ] Liberando conexao de entrada para: $porta/$proto..."
        sudo ufw allow "$porta/$proto" comment 'Active Directory Integration' &>/dev/null
    done

    echo "    ----------------------------------------------------------------------"
    echo "    [ OK! ] Regras injetadas com sucesso. Politicas anteriores preservadas."
    
    # Exibe o status atual resumido apenas para auditoria visual do administrador
    echo ""
    echo "    [  *  ] Resumo atual do Firewall (UFW):"
    sudo ufw status numbered | grep 'Active Directory Integration' || true
    
    echo ""
    echo "    [ OK! ] Modulo de firewall concluido."
    sleep 2
    mod_next
}
# end mod3 


# MODULO 4: COLETA E VALIDACAO DOS DADOS DO AD %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
mod4_adinfo() {
    clear
    echo "======================================================================"
    echo "                      Versao : ${SCRIPT_VERSION} "
    echo "                      Etapa 4: COLETA E VALIDACAO DOS DADOS DO AD <<"
    echo "======================================================================"
    echo ""

    # Apenas variaveis de controle de fluxo interno permanecem locais
    local AD_DOMAIN_INPUT=""
    local CONF_FINAL=""
    local HAS_OU=""
    local AD_PASS="" # [MELHORIA] Mantem a senha local para nao virar variavel global do shell

    # --- [1] Dominio AD e Validacao DNS em Tempo Real ---
    while true; do
        echo "Informe o nome do dominio!?"
        echo "(ex: meudominio.local)"
        read -erp "Digite: " AD_DOMAIN_INPUT

        AD_DOMAIN=$(echo "$AD_DOMAIN_INPUT" | tr '[:upper:]' '[:lower:]')
        AD_REALM=$(echo "$AD_DOMAIN" | tr '[:lower:]' '[:upper:]')

        echo ""
        echo "[  * ] Verificando DNS e localizando DCs..."

        if dig +short "$AD_DOMAIN" 2>>"$LOG_FILE" | grep -q '.'; then
            AD_DC=$(dig +short "$AD_DOMAIN" 2>>"$LOG_FILE" | head -n1)
            if [ -z "$AD_DC" ]; then
                AD_DC=$(dig +short "_ldap._tcp.dc._msdcs.$AD_DOMAIN" SRV 2>>"$LOG_FILE" | awk '{print $4}' | sed 's/\.$//' | head -n1)
            fi

            if [ -n "$AD_DC" ]; then
                echo "[ OK! ] Dominio resolvido. DC: $AD_DC"
                log_event "INFO" "Dominio $AD_DOMAIN resolvido com sucesso no DC $AD_DC"
                AD_BASE_DN="DC=$(echo "$AD_DOMAIN" | sed 's/\./,DC=/g')"
                break
            fi
        fi
        
        echo ""
        echo "[ERROR] Dominio nao resolvivel. Verifique o /etc/resolv.conf."
        log_event "AVISO" "Falha ao resolver o dominio DNS: $AD_DOMAIN"
        echo "----------------------------------------------------------------------"
        echo ""
    done

    echo "----------------------------------------------------------------------"


    # --- [2] Credenciais e Validacao Kerberos (KINIT) em Tempo Real ---
    while true; do
        echo ""
        echo "Informe a conta de servico!?"
        echo "(ex: usr-service)"
        read -erp "Digite: " AD_USER_ONLY

        if [ -z "$AD_USER_ONLY" ]; then
            echo "[ERROR] O usuario nao pode ser vazio."
            continue
        fi

        AD_UPN="${AD_USER_ONLY}@${AD_REALM}"

        echo ""
        echo "Informe a senha para a conta $AD_UPN !?"
        read -s -p "Senha: " AD_PASS
        echo ""

        echo ""
        echo "[  * ] Validando credenciais via Kerberos..."

        # Mantido conforme o seu design original por conta do fluxo macro
        sudo kdestroy &>/dev/null || true

        if echo "$AD_PASS" | kinit "$AD_UPN" >/dev/null 2>&1; then
            echo "[ OK! ] Credenciais validas para $AD_UPN"
            log_event "INFO" "Credenciais do usuario $AD_UPN validadas com sucesso via kinit."
            sudo kdestroy &>/dev/null || true
            break
        else
            echo ""
            echo "[X] Falha na autenticacao!"
            echo "    Dica: Verifique a senha ou sincronismo de tempo (ntp/chrony)."
            log_event "AVISO" "Falha de autenticacao Kerberos para o usuario $AD_UPN"
            echo "----------------------------------------------------------------------"
            unset AD_PASS
        fi
    done

    echo "----------------------------------------------------------------------"

    # --- [3] Grupo de Sudo ---
    while true; do
        echo ""
        echo "Informe o nome do grupo do AD para SUDO !?"
        echo "(ex: Admins_Linux)"
        read -erp "Digite: " AD_GROUP
        
        if [ -n "$AD_GROUP" ]; then
            break
        else
            echo "[ERROR] O nome do grupo nao pode ser vazio."
        fi
    done

    echo "----------------------------------------------------------------------"
		
    # --- [4] Tratamento Interativo da OU ---
    while true; do
        echo ""
        echo "Deseja utilizar o container padrao Computers no Active Directory?"
        read -erp "(s/n): " HAS_OU
        HAS_OU="${HAS_OU,,}"
        
        if [[ "$HAS_OU" == "s" ]]; then
            AD_OU="" 
            echo "[ OK! ] Utilizando container padrao do Active Directory."
            break
        elif [[ "$HAS_OU" == "n" ]]; then
            echo ""
            echo "Exemplo de OU: OU=Servers,OU=Computers,DC=empresa,DC=local"
            read -erp "Digite a OU exata: " AD_OU
            if [ -n "$AD_OU" ]; then
                echo "[ OK! ] Container customizado definido."
                break
            else
                echo "[ERROR] O caminho da OU nao pode ser vazio se selecionou 'n'."
            fi
        else
            echo ""
            echo "Resposta invalida. Digite 's' para sim ou 'n' para nao."
        fi
    done

    # --- [5] Resumo de Confirmacao Interativo ---
    clear
    local HOST_SHORT=$(hostname -s)
    local FINAL_FQDN="${HOST_SHORT}.${AD_DOMAIN}"
    local OU_DISPLAY="$AD_OU"
    [ -z "$OU_DISPLAY" ] && OU_DISPLAY="Padrao do Active Directory (Computers)"

    echo "======================================================================"
    echo "          CONFIRME AS INFORMACOES PARA O INGRESSO"
    echo "======================================================================"
    echo " - FQDN Computador .....: $FINAL_FQDN"
    echo " - Conta de Servico ....: $AD_UPN"
    echo " - Grupo Admin Linux ...: $AD_GROUP"
    echo " - Controlador Dominio .: $AD_DC"
    echo " - Container ...........: $OU_DISPLAY"
    echo "======================================================================"
    echo ""

    read -erp "Os dados acima estao corretos? (s/n): " CONF_FINAL
    if [[ "$(echo "$CONF_FINAL" | tr '[:upper:]' '[:lower:]')" != "s" ]]; then
        echo ""
        echo "[!] Operacao cancelada pelo usuario. Reiniciando coleta..."
        log_event "INFO" "Usuario rejeitou o resumo de confirmacao. Reiniciando Modulo 4."
        unset AD_PASS
        sleep 2
        mod4_adinfo
        return
    fi

    # --- [6] Aplicacao Definitiva do Hostname FQDN ---
    echo ""
    echo "[  * ] Aplicando Hostname FQDN: $FINAL_FQDN"
    log_event "INFO" "Aplicando FQDN definitivo pos-validacao: $FINAL_FQDN"
    sudo hostnamectl set-hostname "$FINAL_FQDN" 2>>"$LOG_FILE"

    if ! grep -q "$FINAL_FQDN" /etc/hosts; then
        echo "127.0.0.1   $FINAL_FQDN $HOST_SHORT" | sudo tee -a /etc/hosts > /dev/null 2>>"$LOG_FILE"
    fi

    echo "[ OK! ] Dados validados e Hostname atualizado."
    log_event "INFO" "Modulo 4 finalizado com sucesso. Hostname e variaveis de ambiente prontas."

    # [BLINDAGEM] Expura a senha local definitivamente antes de passar o bastao
    unset AD_PASS

    # Garante visibilidade global total para o Modulo 5 (Isolando a senha com sucesso!)
    export AD_DOMAIN AD_DC AD_BASE_DN AD_UPN AD_GROUP AD_REALM AD_OU AD_USER_ONLY

    mod_next
}
# end mod4


# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MODULO 5: ADESAO AO DOMINIO (REALM JOIN)
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
mod5_adjoin() {
    clear

    # ----------------------------------------------------------------------
    # Bloco 0. BANNER DE EXECUCAO E FEEDBACK
    # ----------------------------------------------------------------------
    echo "    ======================================================================"
    echo "                     Etapa 5: ADESAO AO DOMINIO <<"
    echo "    ----------------------------------------------------------------------"
    echo "                        Ingressando o servidor no dominio: $AD_DOMAIN"
    echo "    ======================================================================"
    echo ""
    echo "    [  * ] Configurando padroes do client em /etc/realmd.conf..."
    echo "    -----------------------------------------------------------------------"
	echo ""
	log_event "INFO" "Iniciando a geracao do arquivo /etc/realmd.conf para $AD_DOMAIN"
	
	
	# --- AJUSTE DE ESCOPO E SEGURANCA ---
    local SENHA_LOCAL=""  # [MELHORIA] Mantem a senha local para nao virar variavel global do shell

  
    # --- COLETA UNIFICADA DE METADADOS (Sem retrabalho) ---
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        # Padronizando com as strings amigaveis que funcionaram no seu print do AD
        readonly SYS_OS="$PRETTY_NAME"
        readonly SYS_VER="$VERSION"
    else
        readonly SYS_OS=$(uname -s)
        readonly SYS_VER=$(uname -r)
    fi
    readonly SYS_SP="Kernel $(uname -r)"
	
	
	
	# ------------------------------------------------------------------------------------------
    # Bloco 1. Geração do arquivo /etc/realmd.conf
    # ------------------------------------------------------------------------------------------
	
	# Criacao dinamica do "realmd.conf" baseado nas info do /etc/os-release .
    echo "    [  *  ] Gerando arquivo /etc/realmd.conf com dados do sistema operacional..."
	
	if ! sudo tee /etc/realmd.conf > /dev/null <<EOF
[config]
default-client = sssd

[active-directory]
os-name = ${SYS_OS}
os-version = ${SYS_VER}

[$AD_DOMAIN]
automatic-id-mapping = yes
user-principal = yes
fully-qualified-names = no
EOF

	then
        echo "    [ERROR] Falha ao criar o arquivo /etc/realmd.conf."
        return 1
    else
        echo "    [!] Arquivo /etc/realmd.conf criado com sucesso!"
    fi

    sleep 1

    # ----------------------------------------------------------------------
    # Bloco 2. AUTENTICACAO E JOIN
    # ----------------------------------------------------------------------
    if [ -z "$AD_UPN" ]; then
        AD_UPN="usr_joinad@${AD_DOMAIN^^}"
    fi

    echo "    Informe a senha para a conta $AD_UPN !?"
    read -rs -p "    Senha: " SENHA_LOCAL
    echo ""

    echo ""
    echo "    [  *  ] Executando Realm Join... (Aguarde a comunicacao com o DC)"
    log_event "INFO" "Disparando comando realm join para o dominio $AD_DOMAIN com o usuario $AD_UPN"

    if [ -n "$AD_OU" ]; then
        echo "$SENHA_LOCAL" | sudo realm join --user="$AD_UPN" --computer-ou="$AD_OU" "$AD_DOMAIN" 2>>"$LOG_FILE"
    else
        echo "$SENHA_LOCAL" | sudo realm join --user="$AD_UPN" "$AD_DOMAIN" 2>>"$LOG_FILE"
    fi


    # -----------------------------------------------------------------------------------
	# Bloco 3. Validacao Do Join E Atualizacao Do Atributos de Sistema Operacional
    #	       no Objeto Computador No Active Directory.                 
    # -----------------------------------------------------------------------------------
    if [ $? -eq 0 ]; then
        echo "    [v] Servidor ingressado com sucesso!"
        log_event "INFO" "Adesao ao realm executada com sucesso absoluto."
        
        sudo realm permit -g "$AD_GROUP" 2>>"$LOG_FILE"
        echo "    [v] Acesso liberado para o grupo: $AD_GROUP"
        log_event "INFO" "Permissao de login concedida ao grupo $AD_GROUP"

        # Reaproveitamento do script OS-UPDATE.SH .
        echo ""
        echo "    [  *  ] Atualizando atributos de inventario do OS no Active Directory..."
        sleep 5
        log_event "INFO" "Iniciando atualizacao de atributos LDAP via GSSAPI."

        # Garante/Valida o Ticket Kerberos na sessão atual do usuário usando a senha em memória.
        if ! klist &>/dev/null; then
            log_event "INFO" "Gerando ticket Kerberos local para $AD_UPN usando credencial em memoria."
            kinit "$AD_UPN" 2>>"$LOG_FILE" <<< "$SENHA_LOCAL"
        fi

        # Ajuste do hostname em UPPERCASE exatamente como no seu os-update.
        local COMPUTER_NAME=$(hostname -s | tr '[:lower:]' '[:upper:]')

        # Montagem direta do DN baseada no input de OU questionado acima.
        local COMPUTER_DN=""
        if [ -n "${AD_OU:-}" ]; then
            COMPUTER_DN="CN=${COMPUTER_NAME},${AD_OU}"
        else
            COMPUTER_DN="CN=${COMPUTER_NAME},CN=Computers,${AD_BASE_DN}"
        fi

        log_event "INFO" "DN definido para atualizacao: $COMPUTER_DN. Enviando modificacoes..."
        
        # Executa o ldapmodify idêntico ao os-update.sh com o GSSAPI agora autenticado no contexto do usuário
        ldapmodify -Y GSSAPI -H "ldap://$AD_DC" 2>>"$LOG_FILE" <<EOF
dn: $COMPUTER_DN
changetype: modify
replace: operatingSystem
operatingSystem: $SYS_OS
-
replace: operatingSystemVersion
operatingSystemVersion: $SYS_VER
-
replace: operatingSystemServicePack
operatingSystemServicePack: $SYS_SP
EOF

        if [ $? -eq 0 ]; then
            echo "    [v] Atributos do OS atualizados com sucesso no AD!"
            log_event "INFO" "Atributos operatingSystem injetados via GSSAPI com sucesso."
        else
            echo "    [!] Aviso: Falha ao gravar os atributos no objeto do AD."
            log_event "WARN" "ldapmodify retornou erro durante a gravacao."
        fi
        
    else
        echo ""
        echo "    [ERROR] Falha no ingresso ao dominio."
        echo "    Dica: Verifique se o computador ja existe no AD ou se a senha expirou."
        log_event "ERRO" "O comando realm join retornou codigo de falha."
        unset SENHA_LOCAL
        return 1
    fi


    unset SENHA_LOCAL
    mod_next
}
# end mod 5


# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MODULO 6: OTIMIZACAO DO SSSD - VERSAO UBUNTU
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod6_sssdoptimal() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                        Versao : ${SCRIPT_VERSION} "
    echo "                        Etapa 6: OTIMIZACAO DO SSSD <<"
    echo "    ======================================================================"
    echo "          Otimizando o arquivo sssd.conf para performance e cache"
    echo "    ======================================================================"
    echo ""

    local SSSD_CONF="/etc/sssd/sssd.conf"

    echo "    [  *  ] Verificando existencia do arquivo de configuracao..."
    if [ ! -f "$SSSD_CONF" ]; then
        echo "    [ERROR] Arquivo $SSSD_CONF nao encontrado."
        echo "        Certifique-se de que o Modulo 5 (Join) foi executado com sucesso."
        log_event "ERRO" "Arquivo $SSSD_CONF ausente antes da otimizacao."
        sleep 4
        return 1
    fi

    echo "    [  *  ] Aplicando tuning e politicas de cache offline no SSSD..."
    log_event "INFO" "Iniciando tuning de performance no arquivo $SSSD_CONF"

    # Garante permissao restrita de leitura/escrita antes de manipular (Exigencia do SSSD)
    sudo chmod 600 "$SSSD_CONF" 2>>"$LOG_FILE"

    # Injeção de parâmetros de tuning mantendo a estrutura nativa gerada pelo realm
    # Configura expiração de cache padrão para 24 horas (86400) e ativa credenciais offline
    sudo sed -i '/\[domain\/.*\]/a \
cache_credentials = true\
account_cache_expiration = 86400\
entry_cache_timeout = 86400\
refresh_expired_interval = 3600\
krb5_store_password_if_offline = true' "$SSSD_CONF" 2>>"$LOG_FILE"

    # Remove duplicidades caso o sed tenha reinjetado linhas existentes
    # Garante que as diretivas fiquem limpas e unicas por bloco
    sudo awk '!awk_built_in_duplicate_check[$0]++' "$SSSD_CONF" > /tmp/sssd.conf.tmp 2>>"$LOG_FILE"
    sudo mv /tmp/sssd.conf.tmp "$SSSD_CONF" 2>>"$LOG_FILE"
    sudo chmod 600 "$SSSD_CONF" 2>>"$LOG_FILE"

    # --- SECAO: RESTART E REFRESH DO DAEMON ---
    echo "    [  *  ] Reiniciando o servico SSSD para aplicar as novas diretivas..."
    
    # Limpa caches residuais em disco para forçar leitura limpa do AD
    sudo sssd -i &>/dev/null || true
    sudo rm -f /var/lib/sss/db/*.ldb &>/dev/null || true

    if sudo systemctl restart sssd 2>>"$LOG_FILE"; then
        echo "    [ OK! ] Servico SSSD reiniciado e parametrizado com sucesso."
        log_event "INFO" "SSSD reiniciado com sucesso apos aplicacao do tuning."
    else
        echo "    [ERROR] Falha ao reiniciar o SSSD apos a otimizacao."
        log_event "ERRO" "Falha critica no restart do servico SSSD."
        return 1
    fi

    echo ""
    echo "    [ OK! ] Modulo de otimizacao concluido."
    log_event "INFO" "Modulo 6 executado com sucesso."
    sleep 2
    mod_next
}
# end mod6


# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MODULO 7: CONFIGURACAO DO PAM (HOME DIR) - VERSAO UBUNTU
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod7_pam_homedir() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                        Versao : ${SCRIPT_VERSION} "
    echo "                        Etapa 7: CONFIGURACAO DO PAM <<"
    echo "    ======================================================================"
    echo "          Configurando criacao automatica de Home para usuarios do AD"
    echo "    ======================================================================"
    echo ""

    local PAM_FILE="/etc/pam.d/common-session"

    echo "    [  *  ] Verificando suporte a criacao de home no PAM..."
    
    # No Ubuntu, a diretiva correta deve residir no common-session para cobrir SSH e TTY
    if [ ! -f "$PAM_FILE" ]; then
        echo "    [ERROR] Arquivo estrutural do PAM $PAM_FILE nao encontrado."
        log_event "ERRO" "Arquivo estrutural $PAM_FILE nao existe no sistema."
        return 1
    fi

    # Aplica a injeção de forma idempotente (só adiciona se já não existir no arquivo)
    if ! grep -q "pam_mkhomedir.so" "$PAM_FILE"; then
        echo "    [  *  ] Injetando modulo pam_mkhomedir.so no fluxo de sessao..."
        log_event "INFO" "Injetando pam_mkhomedir.so em $PAM_FILE"
        
        # Insere a diretiva antes da última linha de fallback do PAM comum do Ubuntu
        sudo sed -i '/# end of pam-auth-update config/i \
session required                        pam_mkhomedir.so skel=/etc/skel/ umask=0077' "$PAM_FILE" 2>>"$LOG_FILE"
        
        echo "    [ OK! ] Politica de criacao de diretorios injetada com sucesso."
    else
        echo "    [ OK! ] O modulo pam_mkhomedir.so ja estava configurado no sistema."
    fi

    # Garante a consistência e permissões das pastas base /home
    # O umask=0077 garante que o home do usuário AD seja privado (permissão 700)
    echo "    [  *  ] Validando integridade dos arquivos de configuracao do PAM..."
    
    if grep -q "pam_mkhomedir.so" "$PAM_FILE"; then
        echo "    [ OK! ] Validacao do PAM concluida com sucesso."
        log_event "INFO" "Modulo PAM auditado e validado de forma funcional."
    else
        echo "    [ERROR] Falha ao persistir a configuracao no arquivo PAM."
        log_event "ERRO" "Injecao do pam_mkhomedir.so falhou na validacao pos-escrita."
        return 1
    fi

    echo ""
    echo "    [ OK! ] Modulo de configuracao do PAM concluido."
    log_event "INFO" "Modulo 7 finalizado com sucesso."
    sleep 2
    mod_next
}
# end mod7


# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MODULO 8: CONFIGURACAO DE ELEVACAO DE PRIVILEGIOS (SUDOERS) - VERSAO UBUNTU
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod8_adsudo() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                        Versao : ${SCRIPT_VERSION} "
    echo "                        Etapa 8: CONFIGURACAO DO SUDO <<"
    echo "    ======================================================================"
    echo "          Configurando privilegios de root para o Grupo do AD"
    echo "    ======================================================================"
    echo ""

    local SUDOERS_TARGET="/etc/sudoers.d/ad_sudoers_group"
    local TEMP_SUDOERS="/tmp/ad_sudoers_template"
    local SKIP_SUDO=""

    echo "    [  *  ] Preparando regra de subida de privilegio para o grupo do AD..."
    echo "        Grupo alvo: $AD_GROUP"
    log_event "INFO" "Preparando ad_sudoers para o grupo mapeado: $AD_GROUP"

    # Trata o nome do grupo se houver espacos (comum em estruturas Active Directory)
    # Substitui espacos por sua representacao literal escapada para o Sudoers
    local GRUPO_ESCAPADO=$(echo "$AD_GROUP" | sed 's/ /\\ /g')

    # Cria o arquivo temporario com a regra padrao (Identica a regra do wheel/sudo nativo)
    echo "%${GRUPO_ESCAPADO} ALL=(ALL:ALL) ALL" | sudo tee "$TEMP_SUDOERS" > /dev/null 2>>"$LOG_FILE"

    echo "    [  *  ] Executando analise sintatica de seguranca via visudo..."
    
    # Valida o arquivo temporario. Se houver erro de sintaxe, o visudo aborta
    if sudo visudo -cf "$TEMP_SUDOERS" &>/dev/null; then
        echo "    [ OK! ] Sintaxe do arquivo validada com sucesso."
        
        # Move para o destino definitivo e atribui a permissao obrigatoria (0440)
        sudo mv "$TEMP_SUDOERS" "$SUDOERS_TARGET" 2>>"$LOG_FILE"
        sudo chmod 0440 "$SUDOERS_TARGET" 2>>"$LOG_FILE"
        
        echo "    [ OK! ] Regra de Sudoers aplicada em $SUDOERS_TARGET"
        log_event "INFO" "Arquivo de sudoers customizado aplicado em $SUDOERS_TARGET"
    else
        echo "    [ERROR] Falha na validacao de sintaxe do Sudoers."
        echo "        A regra para o grupo contem caracteres nao suportados."
        log_event "ERRO" "O visudo barrou a sintaxe gerada para o grupo $AD_GROUP"
        sudo rm -f "$TEMP_SUDOERS" &>/dev/null || true
        
        while true; do
            read -erp "    Deseja prosseguir sem aplicar a regra de Sudo? (s/n): " SKIP_SUDO
            SKIP_SUDO="${SKIP_SUDO,,}"
            if [[ "$SKIP_SUDO" == "s" ]]; then
                echo "    [!] Continuando por decisao do administrador..."
                log_event "AVISO" "Administrador pulou falha do sudoers e seguiu com a execucao."
                break
            elif [[ "$SKIP_SUDO" == "n" ]]; then
                echo "    [X] Operacao abortada pelo usuario. Saindo..."
                log_event "ERRO" "Execucao interrompida pelo administrador por erro no Sudoers."
                exit 1
            else
                echo "    Resposta invalida. Digite 's' para sim ou 'n' para nao."
            fi
        done
    fi

    # Validacao de persistencia
    if [ -f "$SUDOERS_TARGET" ]; then
        echo "    [ OK! ] Grupo $AD_GROUP devidamente mapeado no ecossistema Sudo."
    else
        echo "    [!] AVISO: O servidor nao tera administradores do AD ate fixar o Sudoers."
        log_event "AVISO" "Arquivo final $SUDOERS_TARGET nao existe em disco."
    fi

    echo ""
    echo "    [ OK! ] Modulo de configuracao do Sudo concluido."
    log_event "INFO" "Modulo 8 finalizado com sucesso."
    sleep 2
    mod_next
}
# end mod8


# MODULO 9: AUDITORIA FINAL (CHECKLIST) - VERSAO UBUNTU %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod9_checklist() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                        Versao : ${SCRIPT_VERSION} "
    echo "                        Etapa 9: CHECKLIST DE AUDITORIA <<"
    echo "    ======================================================================"
    echo "          Realizando testes de integridade e validacao dos daemons"
    echo "    ======================================================================"
    echo ""

    local STATUS_FINAL=0

    # --- TESTE 1: STATUS DO SERVICO SSSD ---
    echo "    [  *  ] Teste 1: Verificando saude do Daemon SSSD..."
    if systemctl is-active --quiet sssd; then
        echo "    [ OK! ] O servico SSSD esta em execucao (Active/Running)."
        log_event "INFO" "Checklist: Servico SSSD validado como Ativo."
    else
        echo "    [ERROR] O servico SSSD encontra-se parado ou com falha."
        log_event "ERRO" "Checklist: Servico SSSD esta inativo!"
        STATUS_FINAL=1
    fi

    # --- TESTE 2: RESOLUCAO DE NOMES AD ---
    echo ""
    echo "    [  *  ] Teste 2: Testando integracao do NSSwitch com SSSD..."
    if realm list 2>>"$LOG_FILE" | grep -q "domain-name: $AD_DOMAIN"; then
        echo "    [ OK! ] O realm reconhece a participacao ativa no dominio: $AD_DOMAIN"
        log_event "INFO" "Checklist: Participacao ativa no realm confirmada."
    else
        echo "    [ERROR] O servidor nao esta listado como membro ativo no realm."
        log_event "ERRO" "Checklist: Servidor ausente na listagem do realm."
        STATUS_FINAL=1
    fi

    # --- TESTE 3: RESOLUCAO DNS DO DOMINIO ---
    echo ""
    echo "    [  *  ] Teste 3: Validando resolucao DNS de registros SRV do AD..."
    if host -t SRV "_ldap._tcp.${AD_DOMAIN}" &>/dev/null; then
        echo "    [ OK! ] Resolucao de registros SRV do Active Directory funcional."
        log_event "INFO" "Checklist: Registros SRV DNS consultados com sucesso."
    else
        echo "    [!] AVISO: Falha ao consultar registros SRV do AD via DNS."
        echo "        Isso pode causar lentidao na descoberta de novos Domain Controllers."
        log_event "AVISO" "Checklist: Alerta na resolucao SRV do DNS do AD."
    fi

    # --- TESTE 4: VALIDAÇÃO DAS DIRETIVAS DO PAM ---
    echo ""
    echo "    [  *  ] Teste 4: Auditando integridade do modulo de Home no PAM..."
    if grep -q "pam_mkhomedir.so" /etc/pam.d/common-session; then
        echo "    [ OK! ] Persistencia do pam_mkhomedir.so confirmada em common-session."
        log_event "INFO" "Checklist: Diretiva pam_mkhomedir.so confirmada."
    else
        echo "    [ERROR] A diretiva PAM de criacao automatica de Home sumiu."
        log_event "ERRO" "Checklist: pam_mkhomedir sumiu do common-session!"
        STATUS_FINAL=1
    fi

    # --- SECAO: FEEDBACK FINAL PARA O ADMINISTRADOR ---
    echo ""
    echo "    ======================================================================"
    echo "                             RESUMO DO STATUS DO REALM"
    echo "    ======================================================================"
    echo ""
    sudo realm list 2>>"$LOG_FILE" || true
    echo "    ----------------------------------------------------------------------"
    echo ""

    if [ "$STATUS_FINAL" -eq 0 ]; then
        echo "    ======================================================================"
        echo "    [ OK! ] PARABENS! Integracao concluida com 100% de sucesso."
        echo "            O Ubuntu Server esta pronto para receber logins do AD."
        echo "    ======================================================================"
        log_event "INFO" "Integracao finalizada e homologada com sucesso absoluto."
    else
        echo "    ======================================================================"
        echo "    [!] ATENCAO: Integracao concluida, mas foram detectados alertas/erros."
        echo "        Revise os modulos apontados com [X] antes de colocar em producao."
        echo "    ======================================================================"
        log_event "AVISO" "Integracao concluida, porem com falhas apontadas no checklist final."
    fi

    echo ""
    echo "    [ OK! ] Modulo de checklist concluido."
    sleep 2
    mod_next
}
# end mod9



# ROTINA PRINCIPAL (MAIN) - ORQUESTRAÇÃO DO SCRIPT %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

main() {
    # Executa a Fase II: Os 9 Módulos Sequenciais de Runtime
    mod1_banner
    mod2_install
    mod3_firewall
    mod4_adinfo
    mod5_adjoin
    mod6_sssdoptimal
    mod7_pam_homedir
    mod8_adsudo
    mod9_checklist

}
# end main
main "$@"
