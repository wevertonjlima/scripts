#!/bin/bash

# Script: Integracao RedHat "Like" Linux 9 com Active Directory  %%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# 
# DESCRICAO:
#   Script para integrar Oracle Linux 9.x ao Active Directory,
#   configurando firewall, SSSD, PAM, sudo e enviando informações
#   do sistema operacional (operatingSystem/operatingSystemVersion)
#   para o AD via ldapmodify.
#
# REQUISITOS:
#   - Oracle Linux 9.x
#   - Acesso root/sudo
#   - Conectividade com os DCs do AD (portas 389, 88, 464, 3268)
#   - Conta AD com permissão para unir computadores ao domínio
#   - Conta AD com permissão para modificar atributos do computador
#
# [LOG DE ALTERACOES]
# ==============================================================================
# Versao 1.0.0 - 2026-04-26
#   - Versão inicial baseada no script Ubuntu
#   - Adaptação para Oracle Linux 9 (dnf, rpm, paths)
#
# Versao 1.1.0 - 2026-04-27
#   - Senha com entrada única (sem dupla verificação)
#   - Validação anti-duplicação de hostname
#   - Suporte a OU com validação LDAP
#
# Versao 1.2.0 - 2026-04-28
#   - Correção do envio de informações do SO para o AD via ldapmodify
#   - Adicionado operatingSystemServicePack com versão do kernel
#   - Melhorias no módulo de atualização do sistema
#   - Módulo de firewall integrado
#
# Versao: 1.4.0 
# Data: 2026-05MAI-27
# Autor: Weverton Lima <wevertonjlima@gmail.com> 
# ==============================================================================

# --- [0] CONFIGURACOES DE SEGURANCA ---
set -euo pipefail

# --- [1] METADADOS E VERSAO ---
SCRIPT_VERSION="1.4.0"

# --- [2] INFRAESTRUTURA DE LOGS (VERSAO COMPATIVEL ORACLE/UBUNTU) ---
LOG_DIR="$(dirname "$(readlink -f "$0")")"
# Alterado o nome do arquivo para refletir a integracao geral
LOG_FILE="${LOG_DIR}/integra_ad_$(date +%Y-%m-%d_%H-%M).log"

touch "$LOG_FILE"

# Identifica o grupo administrativo correto dinamicamente
if getent group wheel >/dev/null; then
    ADMIN_GROUP="wheel"
elif getent group sudo >/dev/null; then
    ADMIN_GROUP="sudo"
else
    ADMIN_GROUP="root"
fi

chown root:"$ADMIN_GROUP" "$LOG_FILE"
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


# MÓDULO 1: BANNER E BOAS-VINDAS (COM AJUSTE DE FQDN IDEMPOTENTE) %%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
mod1_banner() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "              INTEGRACAO ORACLE LINUX 9 COM ACTIVE DIRECTORY"
    echo "    ----------------------------------------------------------------------"
    echo "                    >> ETAPA 1/9: Bem-Vindo!"
    echo "    ======================================================================"
    echo ""
    echo "        OBJETIVO:"
    echo "        - Configurar este servidor Oracle Linux para se unir a um dominio"
    echo "          Active Directory, permitindo login de usuarios."
    echo ""
    echo "        CARACTERISTICAS:"
    echo "        - Controle de login local/ssh através de Grupo de Seguranca do AD"
    echo "        - Permissao de root através de Grupo de Seguranca do AD"
    echo "        - Cache de credenciais permitindo login offline"
    echo "        - Envio automatico das informacoes do SO (OS, Kernel) para o AD"
    echo ""
    echo "        IMPORTANTE!"
    echo "        - Tenha em maos as seguintes informacoes sobre o Active Directory:"
    echo "        ------------------------------------------------------------------"
    echo "        * Nome do Dominio DNS do AD"
    echo "        * Conta UPN e senha do usuario que ira integrar ao AD"
    echo "        * Nome do Grupo do AD que administrara este servidor"
    echo "        * (Opcional) OU onde o computador sera registrado"
    echo ""
    echo "    ======================================================================"
    echo ""
    
    while true; do
        read -erp "    Deseja prosseguir com a instalacao e configuracao? (s/n): " PROSSEGUIR
        PROSSEGUIR=$(echo "$PROSSEGUIR" | tr '[:upper:]' '[:lower:]')
        if [[ "$PROSSEGUIR" == "s" ]]; then
            echo ""
            echo "    Iniciando as configuracoes..."
            sleep 1
            break
        elif [[ "$PROSSEGUIR" == "n" ]]; then
            echo ""
            echo "    Operacao abortada pelo usuario. Saindo..."
            exit 0
        else
            echo "    Resposta invalida. Digite 's' para sim ou 'n' para nao."
        fi
    done

    # ----------------------------------------------------------------------
    # NOVA SECAO: VERIFICACAO E AJUSTE DE HOSTNAME E REDE (INTEGRADO)
    # ----------------------------------------------------------------------
    while true; do
        clear
        
        # Coleta dinamica do Hostname e isolamento do nome curto (Ajuste Cirurgico)
        local CURRENT_HOSTNAME=$(hostname)
        local SHORT_HOSTNAME=$(echo "$CURRENT_HOSTNAME" | cut -d'.' -f1)
        
        local INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
        [ -z "$INTERFACE" ] && INTERFACE=$(ip -4 addr show up | grep -v '127.0.0.1' | awk '/inet / {print $NF}' | head -n1)
        
        local IP_ADD=$(ip -4 addr show dev "$INTERFACE" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)
        local NETMASK_CIDR=$(ip -4 addr show dev "$INTERFACE" | awk '/inet / {print $2}' | cut -d/ -f2 | head -n1)
        local GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)
        local DNS_SERVER=$(awk '/nameserver/ {print $2}' /etc/resolv.conf | head -n1)
        
        # Identificacao dinamica de DHCP / Estatico
        local DHCP_SERVER=""
        if nmcli connection show "$INTERFACE" 2>/dev/null | grep -qi "ipv4.method:.*auto"; then
            DHCP_SERVER=$(journalctl -u NetworkManager --no-pager -n 100 2>/dev/null | grep -i "DHCP ACK" | awk '{print $NF}' | tr -d '()' | tail -n1)
            [ -z "$DHCP_SERVER" ] && DHCP_SERVER="Ativo (IP via DHCP)"
        else
            DHCP_SERVER="Nenhum (IP Estatico)"
        fi
        
        # Traducao amigavel da mascara CIDR
        local MASK_LEGIVEL=""
        case "$NETMASK_CIDR" in
            24) MASK_LEGIVEL="255.255.255.0 (/$NETMASK_CIDR)" ;;
            16) MASK_LEGIVEL="255.255.0.0 (/$NETMASK_CIDR)" ;;
            8)  MASK_LEGIVEL="255.0.0.0 (/$NETMASK_CIDR)" ;;
            *)  MASK_LEGIVEL="Cidr /$NETMASK_CIDR" ;;
        esac

        # --- BANNER-LOOP ---
        echo "    ======================================================================"
        echo "                    >> ETAPA 1/9: CONFIRMACAO DO HOSTNAME"
        echo "    ======================================================================"
        echo "                    - Hostname ...: $SHORT_HOSTNAME"
        echo "                    "
        echo "                    - IP Add .....: $IP_ADD"
        echo "                    - Mascara ....: $MASK_LEGIVEL"
        echo "                    - Gateway ....: $GATEWAY"
        echo "                    - DNS ........: $DNS_SERVER"
        echo "                    "
        echo "                    - DHCP SERVER.: $DHCP_SERVER"
        echo "    ----------------------------------------------------------------------"

        # --- LOGICA DE VALIDACAO USANDO O NOME CURTO ---
        if [ "$SHORT_HOSTNAME" != "localhost" ] && [ -n "$SHORT_HOSTNAME" ]; then
            # Hostname valido detectado
            read -erp "    Deseja prosseguir ? (s/n): " CONF_PROSSEGUIR
            CONF_PROSSEGUIR=$(echo "$CONF_PROSSEGUIR" | tr '[:upper:]' '[:lower:]')
            if [[ "$CONF_PROSSEGUIR" == "s" ]]; then
                
                # --- [ CORRECAO DE IDEMPOTENCIA E FQDN ] ---
                # Como SHORT_HOSTNAME ja removeu tudo apos o ponto de forma garantida,
                # nao precisamos mais do sed fragil. A montagem fica 100% limpa.
                local DOMAIN_LOWER=$(echo "$AD_DOMAIN" | tr '[:upper:]' '[:lower:]')
                local CLEAN_NAME="$SHORT_HOSTNAME"
                local FINAL_FQDN="${CLEAN_NAME}.${DOMAIN_LOWER}"
                
                echo "    [  *  ] Ajustando FQDN para idempotencia: $FINAL_FQDN"

                sudo hostnamectl set-hostname "$FINAL_FQDN"
                
                # Garante que o /etc/hosts tem a entrada correta para o realm join nao falhar no DNS Name
                if ! grep -q "$FINAL_FQDN" /etc/hosts; then
                    echo "127.0.0.1   $FINAL_FQDN $CLEAN_NAME" | sudo tee -a /etc/hosts > /dev/null
                fi
                break
            else
                echo ""
                echo "    Operacao abortada pelo usuario. Saindo..."
                exit 0
            fi
        else
            # Erro: Hostname eh localhost ou derivado
            echo      "    ERROR !!!"
            echo      "    O nome do computador nao pode ser ingressado como localhost."
            echo ""
            read -erp "    Deseja ALTERAR o hostname ? (s/n): " ALTERAR
            ALTERAR=$(echo "$ALTERAR" | tr '[:upper:]' '[:lower:]')
            
            if [[ "$ALTERAR" != "s" ]]; then
                echo ""
                echo "    O script nao pode continuar com hostname invalido. Saindo..."
                exit 1
            fi
            
            # --- LOOP-HOSTNAME ---
            while true; do
                clear
                echo "    ======================================================================"
                echo "                    >> ETAPA 1/9: CONFIRMACAO DO HOSTNAME"
                echo "    ======================================================================"
                echo ""
                echo "    Informe o novo hostname, até 15 caracteres !"
                echo "    (ex.: server-infra01)"
                read -erp "    Digite: " NEW_HOSTNAME
                
                # Garante limpeza caso o usuario digite com pontos por engano aqui tambem
                NEW_HOSTNAME=$(echo "$NEW_HOSTNAME" | cut -d'.' -f1)
                
                if [ ${#NEW_HOSTNAME} -gt 15 ]; then
                    echo "    [X] Erro: O nome ultrapassa 15 caracteres padrao NetBIOS. Tente novamente."
                    sleep 2
                    continue
                fi
                
                if [ -z "$NEW_HOSTNAME" ] || [[ "$NEW_HOSTNAME" == "localhost" ]]; then
                    echo "    [X] Erro: Nome invalido ou em branco."
                    sleep 2
                    continue
                fi
                
                echo ""
                read -erp "    Confirma novo hostname: $NEW_HOSTNAME (s/n) ? " CONF_HOST
                CONF_HOST=$(echo "$CONF_HOST" | tr '[:upper:]' '[:lower:]')
                if [[ "$CONF_HOST" == "s" ]]; then
                    break
                fi
            done
            
            # --- SOLICITACAO DO REBOOT ---
            echo ""
            read -erp "    Este computador sera reiniciado! Deseja prosseguir ? (s/n): " REBOOT_CONF
            REBOOT_CONF=$(echo "$REBOOT_CONF" | tr '[:upper:]' '[:lower:]')
            if [[ "$REBOOT_CONF" != "s" ]]; then
                echo ""
                echo "    Alteracao cancelada. Saindo..."
                exit 0
            fi
            
            # Aplica a mudanca com o dominio para ja nascer com FQDN correto
            local DOMAIN_LOWER=$(echo "$AD_DOMAIN" | tr '[:upper:]' '[:lower:]')
            sudo hostnamectl set-hostname "${NEW_HOSTNAME}.${DOMAIN_LOWER}"
            
            clear
            echo "    ======================================================================"
            echo "        Apos o reboot, utilize novamente o script \"integra-ad\"."
            echo "    ======================================================================"
            echo "        [  *  ] Reiniciando o sistema em 5 segundos..."
            sleep 5
            sudo reboot
            exit 0
        fi
    done
    
    mod_next
}
# end mod_1


# MÓDULO 2: INSTALACAO DE PACOTES %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
mod2_install() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                    >> ETAPA 2/9: INSTALACAO DE PACOTES"
    echo "    ----------------------------------------------------------------------"
    echo "              Instalando dependencias para integracao com AD"
    echo "    ======================================================================"
    echo ""
    
    # Verifica conectividade com repositórios
    echo     "    [  *  ] Verificando conectividade com repositórios DNF..."
    if ! sudo dnf repolist &>/dev/null; then
        echo "    [X] ERRO: Nao foi possivel acessar os repositorios DNF."
        sleep 4
        return 1
    fi
    echo "    [ OK! ] Repositorios acessiveis."
    
    # Verifica atualizações pendentes
    echo ""
    echo "    [  *  ] Verificando atualizacoes pendentes..."
    local updates=$(sudo dnf check-update --quiet 2>/dev/null | grep -c "^[a-zA-Z0-9]" || true)
    
    if [ "$updates" -gt 0 ]; then
        echo "    [ OK! ] ATENCAO: Existem $updates atualizacoes pendentes."
        while true; do
            read -erp "    Deseja atualizar o sistema agora? (s/n): " ATUALIZAR
            [[ "$ATUALIZAR" == "s" ]] && sudo dnf update -y && break
            [[ "$ATUALIZAR" == "n" ]] && echo "    Prosseguindo sem atualizar..." && break
            echo "    Digite 's' ou 'n'"
        done
    else
        echo "    [ OK! ] Sistema ja atualizado."
    fi
    
    # Lista de pacotes necessários (Adicionados pacotes krb5 para validação e suporte)
    local PACOTES=(
        adcli 
		bind-utils 
		oddjob 
		oddjob-mkhomedir
        openldap-clients 
		realmd 
		samba-common-tools 
		sssd sssd-tools
        krb5-workstation 
		krb5-pkinit 
		libkadm5
    )
    
    echo ""
    echo "    [  * ] Instalando pacotes: ${PACOTES[*]}"
    
    # Instala apenas os que faltam
    local INSTALAR=()
    for pkg in "${PACOTES[@]}"; do
        rpm -q "$pkg" &>/dev/null || INSTALAR+=("$pkg")
    done
    
    if [ ${#INSTALAR[@]} -gt 0 ]; then
        # Adicionado 'dnf clean metadata' para evitar erros de cache em trocas de repo/DVD
        sudo dnf clean metadata &>/dev/null
        sudo dnf install -y "${INSTALAR[@]}" || {
            echo "    [X] ERRO: Falha na instalacao de pacotes."
            return 1
        }
        echo "    [ OK! ] Pacotes instalados com sucesso."
    else
        echo "    [ OK! ] Todos os pacotes ja estao instalados."
    fi
    
    # Validação final
    echo ""
    echo "    [  *  ] Validando instalacao..."
    local OK=true
    for pkg in "${PACOTES[@]}"; do
        rpm -q "$pkg" &>/dev/null && echo "    [OK] $pkg" || { echo "    [X] $pkg"; OK=false; }
    done
    
    $OK || return 1
    
    sudo systemctl stop sssd &>/dev/null
    mod_next
}
# end mod_2


# MÓDULO 3: CONFIGURACAO DO FIREWALL %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
mod3_firewall() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                   >> ETAPA 3/9: CONFIGURACAO DO FIREWALL"
    echo "    ----------------------------------------------------------------------"
    echo "              Liberando portas para comunicacao com o AD"
    echo "    ======================================================================"
    echo ""
    
    if ! systemctl is-active --quiet firewalld; then
        echo "    [  *  ] Firewall inativo. Pulando configuracao."
        mod_next
        return 0
    fi
    
    echo "    [  *  ] Firewall ativo detectado. Liberando portas..."
    
    local RELOAD=false
    local SERVICOS="ldap kerberos"
    local PORTAS="464/tcp 3268/tcp"
    
    for svc in $SERVICOS; do
        if ! sudo firewall-cmd --query-service="$svc" &>/dev/null; then
            sudo firewall-cmd --permanent --add-service="$svc" && RELOAD=true
            echo "    [ OK! ] Servico $svc liberado"
        else
            echo "    [  *  ] Servico $svc ja liberado"
        fi
    done
    
    for porta in $PORTAS; do
        if ! sudo firewall-cmd --query-port="$porta" &>/dev/null; then
            sudo firewall-cmd --permanent --add-port="$porta" && RELOAD=true
            echo "    [ OK! ] Porta $porta liberada"
        else
            echo "    [  *  ] Porta $porta ja liberada"
        fi
    done
    
    $RELOAD && sudo firewall-cmd --reload && echo "    [ OK! ] Firewall recarregado."
    
    mod_next
}
# end mod_3



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



# MODULO 5: ADESAO AO DOMINIO (REALM JOIN) E ATUALIZACAO DINAMICA DE ATRIBUTOS AD
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
	
	
    # --- COLETA UNIFICADA DE METADADOS (Baseada na logica funcional do os-update.sh) ---
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        readonly SYS_OS="$NAME"
        readonly SYS_VER="$VERSION_ID"
    else
        readonly SYS_OS=$(uname -s)
        readonly SYS_VER=$(uname -r)
    fi
    readonly SYS_SP="Kernel $(uname -r)"
	
    # ------------------------------------------------------------------------------------------
    # Bloco 1. Geracao do arquivo /etc/realmd.conf
    # ------------------------------------------------------------------------------------------
    echo "    [  * ] Gerando arquivo /etc/realmd.conf com dados do sistema operacional..."
	
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
    echo "    [  * ] Executando Realm Join... (Aguarde a comunicacao com o DC)"
    log_event "INFO" "Disparando comando realm join para o dominio $AD_DOMAIN com o usuario $AD_UPN"

    if [ -n "$AD_OU" ]; then
        echo "$SENHA_LOCAL" | sudo realm join --user="$AD_UPN" --computer-ou="$AD_OU" "$AD_DOMAIN" 2>>"$LOG_FILE"
    else
        echo "$SENHA_LOCAL" | sudo realm join --user="$AD_UPN" "$AD_DOMAIN" 2>>"$LOG_FILE"
    fi

    # -----------------------------------------------------------------------------------
    # Bloco 3. Validacao Do Join E Atualizacao Dinamica Baseada no os-update.sh              
    # -----------------------------------------------------------------------------------
    if [ $? -eq 0 ]; then
        echo "    [v] Servidor ingressado com sucesso!"
        log_event "INFO" "Adesao ao realm executada com sucesso absoluto."
        
        sudo realm permit -g "$AD_GROUP" 2>>"$LOG_FILE"
        echo "    [v] Acesso liberado para o grupo: $AD_GROUP"
        log_event "INFO" "Permissao de login concedida ao grupo $AD_GROUP"

        echo ""
        echo "    [  * ] Iniciando descoberta e mapeamento LDAP do objeto..."
        log_event "INFO" "Iniciando fase de descoberta dinamica de topologia para atualizacao de atributos."

        # Descoberta automatica do Domain Controller via DNS SRV (Idêntico ao os-update.sh)
        local DC_LIST
        DC_LIST=$(dig +short _ldap._tcp.dc._msdcs."$AD_DOMAIN" SRV 2>>"$LOG_FILE" | awk '{print $4}' | sed 's/\.$//')
        local DETECTED_DC
        DETECTED_DC=$(echo "$DC_LIST" | head -n1)

        if [ -z "$DETECTED_DC" ]; then
            log_event "ERROR" "Nao foi possivel localizar um Domain Controller via DNS SRV."
            echo "    [!] Aviso: Falha na localizacao dinamica do DC. Atributos nao modificados."
            unset SENHA_LOCAL
            return 1
        fi

        local CALC_BASE_DN
        CALC_BASE_DN="DC=$(echo "$AD_DOMAIN" | sed 's/\./,DC=/g')"
        local AD_REALM
        AD_REALM=$(echo "$AD_DOMAIN" | tr '[:lower:]' '[:upper:]')

        # Forca e garante a geracao do Ticket Kerberos em cache usando as credenciais em memoria
        log_event "INFO" "Gerando ticket Kerberos local para $AD_UPN."
        echo "$SENHA_LOCAL" | kinit "$AD_UPN" 2>>"$LOG_FILE"

        # Captura e normalizacao do hostname do objeto
        local COMPUTER_NAME
        COMPUTER_NAME=$(hostname -s | tr '[:lower:]' '[:upper:]')

        # Busca dinamica do DN real do objeto no AD para evitar caminhos estaticos quebrados
        local COMPUTER_DN
        COMPUTER_DN=$(ldapsearch -LLL -Y GSSAPI -o ldif-wrap=no \
            -H "ldap://$DETECTED_DC" \
            -b "$CALC_BASE_DN" \
            "(sAMAccountName=${COMPUTER_NAME}\$)" dn 2>>"$LOG_FILE" | sed -n 's/^dn: //p')

        if [ -z "$COMPUTER_DN" ]; then
            log_event "ERROR" "Nao foi possivel localizar o Distinguished Name (DN) para ${COMPUTER_NAME}$ no LDAP."
            echo "    [!] Aviso: Objeto nao localizado via ldapsearch."
        else
            log_event "INFO" "DN localizado: $COMPUTER_DN. Enviando modificacoes estruturais via GSSAPI..."
            echo "    [  * ] Atualizando atributos de inventario do OS no Active Directory..."

            # Executa a gravacao exata que funcionou no seu script independente
            set +e
            ldapmodify -Y GSSAPI -H "ldap://$DETECTED_DC" >> "$LOG_FILE" 2>&1 <<EOF
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
            local LDAP_STATUS=$?
            set -e

            if [ $LDAP_STATUS -eq 0 ]; then
                echo "    [v] Atributos do OS atualizados com sucesso no AD!"
                log_event "INFO" "Atributos operatingSystem gravados via ldapmodify com sucesso."
            else
                echo "    [!] Aviso: Falha ao gravar os atributos no objeto do AD (Erro LDAP: $LDAP_STATUS)."
                log_event "WARN" "ldapmodify retornou erro durante a gravacao."
            fi
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



# MÓDULO 6: CONFIGURACAO DO SSSD  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
mod6_sssdoptimal() {
    clear
    echo "    ======================================================================"
    echo "         >> ETAPA 6/9: OTIMIZACAO SSSD E TUNING DE CACHE"
    echo "    ----------------------------------------------------------------------"
    echo "           Refinando atributos e otimizando o cache local"
    echo "    ======================================================================"
    echo ""
    
    local SSSD_CONF="/etc/sssd/sssd.conf"
    
    # 1. OTIMIZACAO DO SSSD (TRANSPARENTE)
    echo "    [  *  ] Aplicando ajustes de performance no SSSD..."
    sudo systemctl stop sssd &>/dev/null
    
    # Remove FQDN e melhora o cache
    sudo sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/' "$SSSD_CONF"
    sudo sed -i '/^\[domain\//a enumerate = False\nentry_cache_timeout = 5400' "$SSSD_CONF"
    
    sudo chmod 600 "$SSSD_CONF"
    sudo systemctl start sssd
    echo "    [ OK! ] SSSD otimizado e reiniciado."

    # 2. ATUALIZACAO DE ATRIBUTOS DE OS - REMOVIDO (DIRETRIZ DE PRIVACIDADE DE OS)
    
    echo ""
    echo "    ----------------------------------------------------------------------"
    echo "    [ OK! ] Etapa 6 concluida. SSSD configurado com sucesso!"
    echo "    ----------------------------------------------------------------------"
    
    mod_next
}
# end mod_6


# MÓDULO 7: CONFIGURACAO DO PAM (CRIACAO AUTOMATICA DE HOME)  %%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
mod7_pam_homedir() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "           >> ETAPA 7/9: CONFIGURACAO DO PAM (CRIACAO DE HOME)"
    echo "    ----------------------------------------------------------------------"
    echo "         Configurando criacao automatica de diretorios home"
    echo "    ======================================================================"
    echo ""
    
    local PAM_FILE="/etc/pam.d/system-auth"
    local REGRA="session required pam_mkhomedir.so skel=/etc/skel umask=0022"
    
    sudo sed -i '/pam_mkhomedir.so/d' "$PAM_FILE"
    echo "$REGRA" | sudo tee -a "$PAM_FILE" > /dev/null
    
    echo "    [ OK! ] pam_mkhomedir configurado."
    echo "    [ OK! ] Diretorios home serao criados automaticamente no primeiro login."
    
    mod_next
}
# end mod_7


# MÓDULO 8: CONFIGURACAO DO SUDO PARA O GRUPO DO AD  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
mod8_adsudo() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "               >> ETAPA 8/9: CONFIGURACAO DO SUDO"
    echo "    ----------------------------------------------------------------------"
    echo "         Concedendo acesso sudo ao grupo: $AD_GROUP"
    echo "    ======================================================================"
    echo ""
    
    local SUDOERS_FILE="/etc/sudoers.d/99_${AD_GROUP}"
    local REGRA="%$AD_GROUP ALL=(ALL) ALL"
    
    echo "    # Acesso sudo para grupo do AD: $AD_GROUP" | sudo tee "$SUDOERS_FILE" > /dev/null
    echo "    $REGRA" | sudo tee -a "$SUDOERS_FILE" > /dev/null
    sudo chmod 440 "$SUDOERS_FILE"
    
    sudo visudo -c &>/dev/null && echo "    [ OK! ] Regra sudo aplicada com sucesso." || {
        echo "    [X] ERRO: Sintaxe invalida."
        return 1
    }
    
    mod_next
}
# end mod_8


# MODULO 9: CHECKLIST FINAL DE VERIFICACAO  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
mod9_checklist() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                >> ETAPA 9/9: CHECKLIST FINAL"
    echo "    ======================================================================"
    echo ""
    
    local OK=0
    local TOTAL=10 
    
    echo "    [ VERIFICACOES DE FIREWALL ]"
    echo "    ----------------------------------------------------------------------"
    
    if systemctl is-active --quiet firewalld; then
        echo                     "    [1/10] firewalld ativo:............... [ OK! ]"
        ((OK++))
        
        # Verifica os servicos
        if sudo firewall-cmd --query-service=ldap &>/dev/null; then
            echo                 "    [2/10] Servico ldap:.................. [ OK! ]"
            ((OK++))
        else
            echo "    [2/10] Servico ldap: [X]"
        fi

        if sudo firewall-cmd --query-service=kerberos &>/dev/null; then
            echo                 "    [3/10] Servico kerberos:.............. [ OK! ]"
            ((OK++))
        else
            echo "    [3/10] Servico kerberos: [X]"
        fi
        
        # Verifica as portas
        if sudo firewall-cmd --query-port=464/tcp &>/dev/null; then
            echo                 "    [4/10] Porta 464/tcp:................. [ OK! ]"
            ((OK++))
        else
            echo "    [4/10] Porta 464/tcp: [X]"
        fi

        if sudo firewall-cmd --query-port=3268/tcp &>/dev/null; then
            echo                "    [5/10] Porta 3268/tcp:................ [ OK! ]"
            ((OK++))
        else
            echo "    [5/10] Porta 3268/tcp: [X]"
        fi
    else
        echo                    "    [1/10] firewalld ....................: [ OK! ]"
        echo                    "    [2/10] Servico ldap .................: [ OK! ]"
        echo                    "    [3/10] Servico kerberos .............: [ OK! ]"
        echo                    "    [4/10] Porta 464/tcp ................: [ OK! ]"
        echo                    "    [5/10] Porta 3268/tcp ...............: [ OK! ]"
        OK=$((OK + 5))
    fi
    
    echo ""
    echo "    [ VERIFICACOES DE INTEGRACAO COM AD ]"
    echo "    ----------------------------------------------------------------------"
    
    # 6. Dominio
    if realm list | grep -q "$AD_DOMAIN"; then
        echo                    "    [6/10] Unido ao dominio:.............. [ OK! ]"
		((OK++))
    else
        echo "    [6/10] Unido ao dominio: [X]"
    fi
    
    # 7. SSSD
    if systemctl is-active --quiet sssd; then
        echo                    "    [7/10] Servico sssd:.................. [ OK! ]"
        ((OK++))
    else
        echo "    [7/10] Servico sssd: [X]"
    fi
    
    # 8. Sudo
    if [[ -f "/etc/sudoers.d/99_${AD_GROUP}" ]] && grep -q "%$AD_GROUP" "/etc/sudoers.d/99_${AD_GROUP}" 2>/dev/null; then
        echo                    "    [8/10] Regra sudo:.................... [ OK! ]"
        ((OK++))
    else
        echo "    [8/10] Regra sudo: [X]"
    fi
    
    # 9. Usuario AD
    if id "$AD_UPN" &>/dev/null || getent passwd "$AD_UPN" &>/dev/null; then
        echo                    "    [9/10] Consulta usuario $AD_UPN: [ OK! ]"
        ((OK++))
    else
        echo "    [9/10] Consulta usuario $AD_UPN: [X]"
    fi
    
    # 10. PAM
    if grep -q "pam_mkhomedir.so" /etc/pam.d/system-auth 2>/dev/null || grep -q "pam_mkhomedir.so" /etc/pam.d/common-session 2>/dev/null; then
        echo                    "    [10/10] pam_mkhomedir:................ [ OK! ]"
        ((OK++))
    else
        echo "    [10/10] pam_mkhomedir: [X]"
    fi
    
    echo ""
    echo "    ======================================================================"
    echo "        CHECKLIST FINAL: $OK de $TOTAL itens validados."
    echo "    ======================================================================"
    
    if [[ "$OK" -eq "$TOTAL" ]]; then
        echo ""
        echo "    [ OK! ] INTEGRACAO CONCLUIDA COM SUCESSO!"
        echo ""
        echo "    [  *  ] Recomendacoes finais:"
        echo "        - Teste login: ssh $AD_UPN@localhost"
        echo "        - Teste sudo: sudo -l"
        echo "        - No PowerShell do AD: Get-ADComputer \$(hostname -s) -Properties *"
    else
        echo ""
        echo "    [X] ALGUMAS VERIFICACOES FALHARAM."
        echo "    [  *  ] Reveja os modulos anteriores ou verifique manualmente."
    fi
    
    # Se a funcao mod_next existir no script, ela sera chamada aqui
    if declare -f mod_next &>/dev/null; then
        mod_next
    fi
	
}
# end mod_9


# FLUXO PRINCIPAL DO SCRIPT  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
main() {
    mod1_banner                          || exit 1
    mod2_install                         || exit 1
    mod3_firewall                        
    mod4_adinfo                          || exit 1
    mod5_adjoin                          || exit 1
    mod6_sssdoptimal                     || exit 1
    mod7_pam_homedir                     || exit 1
    mod8_adsudo                          || exit 1
    mod9_checklist                       || exit 1
    
    echo ""
    echo "    ======================================================================"
    echo "        Script finalizado com sucesso!"
    echo "    ======================================================================"
    echo ""
}
# end mod_main


# Executa o script
main "$@"
