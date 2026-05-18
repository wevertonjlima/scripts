#!/bin/bash

# Script: Integracao Oracle Linux 9 com Active Directory  %%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
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
# ======================================================================
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
# Versao: 1.2.0 - WORKS !!!
# Data: 2026-04-28
# Autor: Adaptado de script Ubuntu para Oracle Linux
# ======================================================================



# FUNÇÕES AUXILIARES %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
#
# Verifica se é root
if [[ $EUID -ne 0 ]]; then
    echo ""
    echo "    [X] Este script precisa ser executado como root (sudo)."
    echo "        Utilize: sudo $0"
    echo ""
    exit 1
fi


# Função de pausa entre módulos
mod_next() {
    printf "\n\n    >>> Prosseguindo...\n\n"
    sleep 4
}



# MÓDULO 1: BANNER E BOAS-VINDAS (COM AJUSTE DE FQDN IDEMPOTENTE) %%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
mod1_banner() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "              INTEGRACAO ORACLE LINUX 9 COM ACTIVE DIRECTORY"
    echo "    ----------------------------------------------------------------------"
    echo "                    >> ETAPA 1/10: Bem-Vindo!"
    echo "    ======================================================================"
    echo ""
    echo "        OBJETIVO:"
    echo "        - Configurar este servidor Oracle Linux para se unir a um domínio"
    echo "          Active Directory, permitindo login de usuários."
    echo ""
    echo "        CARACTERISTICAS:"
    echo "        - Controle de login local/ssh através de Grupo de Segurança do AD"
    echo "        - Permissao de root através de Grupo de Segurança do AD"
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
        
        # Coleta dinamica do Hostname e Rede
        local CURRENT_HOSTNAME=$(hostname)
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
        echo "                >> ETAPA 1/10: CONFIRMACAO DO HOSTNAME"
        echo "    ======================================================================"
        echo "                - Hostname ...: $CURRENT_HOSTNAME"
        echo "                "
        echo "                - IP Add .....: $IP_ADD"
        echo "                - Mascara ....: $MASK_LEGIVEL"
        echo "                - Gateway ....: $GATEWAY"
        echo "                - DNS ........: $DNS_SERVER"
        echo "                "
        echo "                - DHCP SERVER.: $DHCP_SERVER"
        echo "    ----------------------------------------------------------------------"

        # --- LOGICA DE VALIDACAO ---
        if [ "$CURRENT_HOSTNAME" != "localhost" ] && [ "$CURRENT_HOSTNAME" != "localhost.localdomain" ] && [ -n "$CURRENT_HOSTNAME" ]; then
            # Hostname valido detectado
            read -erp "    Deseja prosseguir ? (s/n): " CONF_PROSSEGUIR
            CONF_PROSSEGUIR=$(echo "$CONF_PROSSEGUIR" | tr '[:upper:]' '[:lower:]')
            if [[ "$CONF_PROSSEGUIR" == "s" ]]; then
                
                # --- [ CORRECAO DE IDEMPOTENCIA E FQDN ] ---
                # Garante que o hostname atual sera tratado para conter o FQDN antes do join
                # Ex: Se for 'bishop' vira 'bishop.dexter.labs'
                # Ex: Se for 'bishop.dexter.labs' CONTINUA 'bishop.dexter.labs'
                
                local DOMAIN_LOWER=$(echo "$AD_DOMAIN" | tr '[:upper:]' '[:lower:]')
                # Remove o dominio do nome atual para evitar duplicacao (sed remove o .dominio)
                local CLEAN_NAME=$(echo "$CURRENT_HOSTNAME" | sed "s/\.${DOMAIN_LOWER}//g")
                local FINAL_FQDN="${CLEAN_NAME}.${DOMAIN_LOWER}"
                
                echo "    [*] Ajustando FQDN para idempotencia: $FINAL_FQDN"
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
            # Erro: Hostname e localhost
            echo "    ERROR !!!"
            echo "    O nome do computador não pode ser ingressado como localhost."
            echo ""
            read -erp "    Deseja ALTERAR o hostname ? (s/n): " ALTERAR
            ALTERAR=$(echo "$ALTERAR" | tr '[:upper:]' '[:lower:]')
            
            if [[ "$ALTERAR" != "s" ]]; then
                echo ""
                echo "    O script não pode continuar com hostname invalido. Saindo..."
                exit 1
            fi
            
            # --- LOOP-HOSTNAME ---
            while true; do
                clear
                echo "    ======================================================================"
                echo "                >> ETAPA 1/10: CONFIRMACAO DO HOSTNAME"
                echo "    ======================================================================"
                echo ""
                echo "    Informe o novo hostname, até 15 caracteres !"
                echo "    (ex.: server-infra01)"
                read -erp "    Digite: " NEW_HOSTNAME
                
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
            
            # Aplica a mudanca com o dominio para ja nascer com FQDN
            local DOMAIN_LOWER=$(echo "$AD_DOMAIN" | tr '[:upper:]' '[:lower:]')
            sudo hostnamectl set-hostname "${NEW_HOSTNAME}.${DOMAIN_LOWER}"
            
            clear
            echo "    ======================================================================"
            echo "    Após o reboot, utilize novamente o script \"integra-ad\"."
            echo "    ======================================================================"
            echo "    [*] Reiniciando o sistema em 5 segundos..."
            sleep 5
            sudo reboot
            exit 0
        fi
    done
    
    mod_next
}



# MÓDULO 2: INSTALACAO DE PACOTES %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod2_install() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                    >> ETAPA 2/10: INSTALACAO DE PACOTES"
    echo "    ----------------------------------------------------------------------"
    echo "              Instalando dependencias para integracao com AD"
    echo "    ======================================================================"
    echo ""
    
    # Verifica conectividade com repositórios
    echo "    [*] Verificando conectividade com repositórios DNF..."
    if ! sudo dnf repolist &>/dev/null; then
        echo "    [X] ERRO: Nao foi possivel acessar os repositorios DNF."
        sleep 4
        return 1
    fi
    echo "    [ OK! ] Repositorios acessiveis."
    
    # Verifica atualizações pendentes
    echo ""
    echo "    [*] Verificando atualizacoes pendentes..."
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
    echo "    [*] Instalando pacotes: ${PACOTES[*]}"
    
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
    echo "    [*] Validando instalacao..."
    local OK=true
    for pkg in "${PACOTES[@]}"; do
        rpm -q "$pkg" &>/dev/null && echo "    [OK] $pkg" || { echo "    [X] $pkg"; OK=false; }
    done
    
    $OK || return 1
    
    sudo systemctl stop sssd &>/dev/null
    mod_next
}



# MÓDULO 3: CONFIGURACAO DO FIREWALL %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod3_firewall() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                   >> ETAPA 3/10: CONFIGURACAO DO FIREWALL"
    echo "    ----------------------------------------------------------------------"
    echo "              Liberando portas para comunicacao com o AD"
    echo "    ======================================================================"
    echo ""
    
    if ! systemctl is-active --quiet firewalld; then
        echo "    [*] Firewall inativo. Pulando configuracao."
        mod_next
        return 0
    fi
    
    echo "    [*] Firewall ativo detectado. Liberando portas..."
    
    local RELOAD=false
    local SERVICOS="ldap kerberos"
    local PORTAS="464/tcp 3268/tcp"
    
    for svc in $SERVICOS; do
        if ! sudo firewall-cmd --query-service="$svc" &>/dev/null; then
            sudo firewall-cmd --permanent --add-service="$svc" && RELOAD=true
            echo "    [ OK! ] Servico $svc liberado"
        else
            echo "    [*] Servico $svc ja liberado"
        fi
    done
    
    for porta in $PORTAS; do
        if ! sudo firewall-cmd --query-port="$porta" &>/dev/null; then
            sudo firewall-cmd --permanent --add-port="$porta" && RELOAD=true
            echo "    [ OK! ] Porta $porta liberada"
        else
            echo "    [*] Porta $porta ja liberada"
        fi
    done
    
    $RELOAD && sudo firewall-cmd --reload && echo "    [ OK! ] Firewall recarregado."
    
    mod_next
}




# MODULO 4: COLETA E VALIDACAO DOS DADOS DO AD (VERSAO AIR-GAPPED) %%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod4_adinfo() {
    clear
    echo "======================================================================"
    echo "    >> ETAPA 4/10: COLETA E VALIDACAO DOS DADOS DO AD"
    echo "======================================================================"
    echo ""

    # --- [1] Dominio AD ---
    while true; do
        echo "Informe o nome do dominio!?"
        echo "(ex: meudominio.local)"
        read -erp "Digite: " AD_DOMAIN_INPUT
        
        AD_DOMAIN=$(echo "$AD_DOMAIN_INPUT" | tr '[:upper:]' '[:lower:]')
        AD_REALM=$(echo "$AD_DOMAIN" | tr '[:lower:]' '[:upper:]')
        
        echo ""
        echo "[*] Verificando DNS e localizando DCs..."
        
        if dig +short "$AD_DOMAIN" | grep -q '.'; then
            AD_DC=$(dig +short "$AD_DOMAIN" | head -n1)
            if [ -z "$AD_DC" ]; then
                AD_DC=$(dig +short "_ldap._tcp.dc._msdcs.$AD_DOMAIN" SRV | awk '{print $4}' | sed 's/\.$//' | head -n1)
            fi

            if [ -n "$AD_DC" ]; then
                echo "[ OK! ] Dominio resolvido. DC: $AD_DC"
                AD_BASE_DN="DC=$(echo "$AD_DOMAIN" | sed 's/\./,DC=/g')"
                break
            fi
        fi
        echo "[X] Erro: Dominio nao resolvivel. Verifique o /etc/resolv.conf."
        echo "----------------------------------------------------------------------"
    done

    echo "----------------------------------------------------------------------"

    # --- [2] Credenciais ---
    while true; do
        echo ""
        echo "Informe a conta de servico!?"
        echo "(ex: usr-service)"
        read -erp "Digite: " AD_USER_ONLY
        
        AD_UPN="${AD_USER_ONLY}@${AD_REALM}"
        
        echo ""
        echo "Informe a senha para a conta $AD_UPN !?"
        read -s -p "Senha: " AD_PASS
        echo ""

        echo ""
        echo "[*] Validando credenciais via Kerberos..."
        
        if echo "$AD_PASS" | kinit "$AD_UPN" >/dev/null 2>&1; then
            echo "[ OK! ] Credenciais validas para $AD_UPN"
            kdestroy >/dev/null 2>&1
            break
        else
            echo "[X] Falha na autenticacao!"
            echo "    Dica: Verifique a senha ou sincronismo de tempo (ntp/chrony)."
            echo "----------------------------------------------------------------------"
            unset AD_PASS
        fi
    done

    echo "----------------------------------------------------------------------"

    # --- [3] Grupo de Sudo ---
    echo ""
    echo "Informe o nome do grupo do AD para SUDO !?"
    echo "(ex: Admins_Linux)"
    read -erp "Digite: " AD_GROUP

    # --- [4] RESUMO DE CONFIRMACAO E AJUSTE DE HOSTNAME (SUA SOLICITACAO) ---
    clear
    local HOST_SHORT=$(hostname -s)
    local FINAL_FQDN="${HOST_SHORT}.${AD_DOMAIN}"
    
    echo "======================================================================"
    echo "          CONFIRME AS INFORMACOES PARA O INGRESSO"
    echo "======================================================================"
    echo " - FQDN Computador .....: $FINAL_FQDN"
    echo " - Conta de Servico ....: $AD_UPN"
    echo " - Grupo Admin Linux ...: $AD_GROUP"
    echo " - Controlador Dominio .: $AD_DC"
    echo "======================================================================"
    echo ""
    
    read -erp "Os dados acima estao corretos? (s/n): " CONF_FINAL
    if [[ "$(echo "$CONF_FINAL" | tr '[:upper:]' '[:lower:]')" != "s" ]]; then
        echo "[!] Operacao cancelada pelo usuario. Reiniciando coleta..."
        sleep 1
        mod4_adinfo
        return
    fi

    # Aplica o Hostname FQDN de forma definitiva agora que o dominio foi validado
    echo ""
    echo "[*] Aplicando Hostname FQDN: $FINAL_FQDN"
    sudo hostnamectl set-hostname "$FINAL_FQDN"
    
    # Ajuste idempotente no /etc/hosts para garantir resolucao local
    if ! grep -q "$FINAL_FQDN" /etc/hosts; then
        echo "127.0.0.1   $FINAL_FQDN $HOST_SHORT" | sudo tee -a /etc/hosts > /dev/null
    fi

    echo "[*] Dados validados e Hostname atualizado."
    
    export AD_DOMAIN AD_DC AD_BASE_DN AD_UPN AD_PASS AD_GROUP AD_REALM
        
    mod_next
}



# MODULO 5: ADESAO AO DOMINIO (REALM JOIN) %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod5_adjoin() {
    clear
    
    # ----------------------------------------------------------------------
    # 1. IDENTIFICACAO SEMI-AUTOMATICA - REMOVIDA (DIRETRIZ DE PRIVACIDADE DE OS)
    # ----------------------------------------------------------------------

    # ----------------------------------------------------------------------
    # 2. BANNER DE EXECUCAO E FEEDBACK
    # ----------------------------------------------------------------------
    echo "    ======================================================================"
    echo "                 >> ETAPA 5/10: ADESAO AO DOMINIO"
    echo "    ----------------------------------------------------------------------"
    echo "                    Ingressando o servidor no dominio: $AD_DOMAIN"
    echo "    ======================================================================"
    echo ""
    echo "    [*] Configurando padroes do client em /etc/realmd.conf..."
    
    # Gera o arquivo omitindo os campos os-name e os-version
    sudo tee /etc/realmd.conf > /dev/null <<EOF
[active-directory]
default-client = sssd

[$AD_DOMAIN]
automatic-id-mapping = yes
user-principal = yes
fully-qualified-names = no
EOF

    echo ""
    echo "    ----------------------------------------------------------------------"


    # ----------------------------------------------------------------------
    # 3. AUTENTICACAO E JOIN
    # ----------------------------------------------------------------------
    # Garante que temos o UPN para o prompt
    [ -z "$AD_UPN" ] && AD_UPN="usr_joinad@${AD_DOMAIN^^}"

    echo "    Informe a senha para a conta $AD_UPN !?"
    read -rs -p "    Senha: " SENHA_LOCAL
    echo ""

    echo ""
    echo "    [*] Executando Realm Join... (Aguarde a comunicacao com o DC)"
    
    if [ -n "$OU_DN_FINAL" ]; then
        echo "$SENHA_LOCAL" | sudo realm join --user="$AD_UPN" --computer-ou="$OU_DN_FINAL" "$AD_DOMAIN"
    else
        echo "$SENHA_LOCAL" | sudo realm join --user="$AD_UPN" "$AD_DOMAIN"
    fi

    if [ $? -eq 0 ]; then
        echo "    [v] Servidor ingressado com sucesso!"
        # Aplica a permissao de grupo definida no Modulo 1
        sudo realm permit -g "$AD_GROUP"
        echo "    [v] Acesso liberado para o grupo: $AD_GROUP"
    else
        echo ""
        echo "    [X] ERRO: Falha no ingresso ao dominio."
        echo "    Dica: Verifique se o computador ja existe no AD ou se a senha expirou."
        unset SENHA_LOCAL
        return 1
    fi

    unset SENHA_LOCAL
    
    mod_next
}



# MÓDULO 6: CONFIGURACAO DO SSSD  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod6_sssdoptimal() {
    clear
    echo "======================================================================"
    echo "         >> ETAPA 6/10: OTIMIZACAO SSSD E TUNING DE CACHE"
    echo "----------------------------------------------------------------------"
    echo "           Refinando atributos e otimizando o cache local"
    echo "======================================================================"
    echo ""
    
    local SSSD_CONF="/etc/sssd/sssd.conf"
    
    # 1. OTIMIZACAO DO SSSD (TRANSPARENTE)
    echo "[*] Aplicando ajustes de performance no SSSD..."
    sudo systemctl stop sssd &>/dev/null
    
    # Remove FQDN e melhora o cache
    sudo sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/' "$SSSD_CONF"
    sudo sed -i '/^\[domain\//a enumerate = False\nentry_cache_timeout = 5400' "$SSSD_CONF"
    
    sudo chmod 600 "$SSSD_CONF"
    sudo systemctl start sssd
    echo "[ OK! ] SSSD otimizado e reiniciado."

    # 2. ATUALIZACAO DE ATRIBUTOS DE OS - REMOVIDO (DIRETRIZ DE PRIVACIDADE DE OS)
    
    echo ""
    echo "----------------------------------------------------------------------"
    echo "[ OK! ] Etapa 6 concluida. SSSD configurado com sucesso!"
    echo "----------------------------------------------------------------------"
    
    mod_next
}



# MÓDULO 7: CONFIGURACAO DO PAM (CRIACAO AUTOMATICA DE HOME)  %%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod7_pam_homedir() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "           >> ETAPA 7/10: CONFIGURACAO DO PAM (CRIACAO DE HOME)"
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



# MÓDULO 8: CONFIGURACAO DO SUDO PARA O GRUPO DO AD  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod8_adsudo() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "               >> ETAPA 8/10: CONFIGURACAO DO SUDO"
    echo "    ----------------------------------------------------------------------"
    echo "         Concedendo acesso sudo ao grupo: $AD_GROUP"
    echo "    ======================================================================"
    echo ""
    
    local SUDOERS_FILE="/etc/sudoers.d/99_${AD_GROUP}"
    local REGRA="%$AD_GROUP ALL=(ALL) ALL"
    
    echo "# Acesso sudo para grupo do AD: $AD_GROUP" | sudo tee "$SUDOERS_FILE" > /dev/null
    echo "$REGRA" | sudo tee -a "$SUDOERS_FILE" > /dev/null
    sudo chmod 440 "$SUDOERS_FILE"
    
    sudo visudo -c &>/dev/null && echo "    [ OK! ] Regra sudo aplicada com sucesso." || {
        echo "    [X] ERRO: Sintaxe invalida."
        return 1
    }
    
    mod_next
}



# MODULO 9: Atualizacao Informacoes do Sistema Operaciona no Objeto do AD.  %%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod9_atualizar_info_so_ad() {
    
	# --------------------------------------------------------------------------
    # FUNCAO   : atualizar_info_so_ad
    # OBJETIVO : Capturar dados locais do SO e atualizar os atributos correspondentes
    #            (operatingSystem, operatingSystemVersion, operatingSystemServicePack)
    #            no objeto Computador dentro do Active Directory.
    # RETORNO  : 0 se atualizado com sucesso, 1 em caso de falha crtica.
    # --------------------------------------------------------------------------
    
    echo "================================================================================"
    echo "       INICIANDO ATUALIZACAO DE ATRIBUTOS DO SISTEMA OPERACIONAL NO AD"
    echo "================================================================================"
    echo ""

    # --- [0] COLETA E TRATAMENTO DE DADOS LOCAIS ---
    local HOSTNAME_SHORT
    local COMPUTER_NAME
    local OS_NAME
    local OS_VERSION
    local OS_SP
    local COMPUTER_DN

    HOSTNAME_SHORT=$(hostname -s)
    COMPUTER_NAME=$(echo "$HOSTNAME_SHORT" | tr '[:lower:]' '[:upper:]')

    # Extracao segura dos dados do os-release e uname (sem aspas/simbolos)
    OS_NAME=$(grep '^PRETTY_NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    OS_VERSION=$(grep '^VERSION=' /etc/os-release | cut -d'=' -f2 | tr -d '"')
    OS_SP=$(uname -r)

    echo "    [*] Dados locais coletados:"
    echo "        -> Computador: $COMPUTER_NAME"
    echo "        -> Sistema Operacional: $OS_NAME"
    echo "        -> Versao do SO: $OS_VERSION"
    echo "        -> Kernel (Service Pack): $OS_SP"
    echo ""

    # --- [1] BUSCA DO DISTINGUISHED NAME (DN) NO AD ---
    echo "    [*] Localizando objeto computador no Active Directory..."
    
    # Utilizacao do -o ldif-wrap=no para evitar quebra de linha em DNs extensos
    # e sed para garantir captura de caminhos com espacos em branco
    COMPUTER_DN=$(ldapsearch -LLL -Y GSSAPI -o ldif-wrap=no \
        -H "ldap://${AD_DC}" \
        -b "${AD_BASE_DN}" \
        "(sAMAccountName=${COMPUTER_NAME}\$)" dn 2>/dev/null | sed -n 's/^dn: //p')

    if [ -z "${COMPUTER_DN}" ]; then
        echo "    [X] ERRO: Objeto do computador [${COMPUTER_NAME}] nao foi localizado no AD."
        echo "        Verifique se o hostname esta correto ou se a maquina ja foi desativada."
        return 1
    fi

    echo "    [?] Objeto localizado com sucesso!"
    echo "        DN: ${COMPUTER_DN}"
    echo ""

    # --- [2] CONFIRMACAO DO OPERADOR ---
    local CONFIRM
    echo "    ------------------------------------------------------------------------"
    echo "    AVISO: Os atributos do objeto acima serao subscritos no Active Directory."
    echo "    ------------------------------------------------------------------------"
    read -erp "    Deseja prosseguir com a gravacao no AD? (s/n): " CONFIRM

    if [[ ! "${CONFIRM}" =~ ^[sS]$ ]]; then
        echo ""
        echo "    [!] Operacao cancelada pelo usuario."
        echo ""
        return 0
    fi

    # --- [3] GRAVACAO DOS ATRIBUTOS VIA LDAPMODIFY ---
    echo ""
    echo "    [*] Enviando modificacoes via LDAP/GSSAPI..."

# Here-Doc alinhado a esquerda para compatibilidade estrita do interpretador Bash
ldapmodify -Y GSSAPI -H "ldap://${AD_DC}" <<EOF
dn: ${COMPUTER_DN}
changetype: modify
replace: operatingSystem
operatingSystem: ${OS_NAME}
-
replace: operatingSystemVersion
operatingSystemVersion: ${OS_VERSION}
-
replace: operatingSystemServicePack
operatingSystemServicePack: ${OS_SP}
EOF

    # Validacao do codigo de retorno do ldapmodify
    if [ $? -eq 0 ]; then
        echo ""
        echo "    [?] SUCESSO: Atributos do SO atualizados com exito no Active Directory!"
        echo "================================================================================"
        echo ""
        return 0
    else
        echo ""
        echo "    [X] ERRO: Falha ao executar ldapmodify. Verifique as permissoes de escrita"
        echo "        do seu ticket Kerberos sobre os atributos do objeto computador."
        echo "================================================================================"
        echo ""
        return 1
    fi
	
	mod_next
}



# MODULO 10: CHECKLIST FINAL DE VERIFICACAO  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod10_checklist() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                >> ETAPA 10/10: CHECKLIST FINAL"
    echo "    ======================================================================"
    echo ""
    
    local OK=0
    local TOTAL=10 
    
    echo "    [ VERIFICACOES DE FIREWALL ]"
    echo "    ----------------------------------------------------------------------"
    
    if systemctl is-active --quiet firewalld; then
        echo "    [1/10] firewalld ativo: [ OK! ]"
        ((OK++))
        
        # Verifica os servicos
        if sudo firewall-cmd --query-service=ldap &>/dev/null; then
            echo "    [2/10] Servico ldap: [ OK! ]"
            ((OK++))
        else
            echo "    [2/10] Servico ldap: [X]"
        fi

        if sudo firewall-cmd --query-service=kerberos &>/dev/null; then
            echo "    [3/10] Servico kerberos: [ OK! ]"
            ((OK++))
        else
            echo "    [3/10] Servico kerberos: [X]"
        fi
        
        # Verifica as portas
        if sudo firewall-cmd --query-port=464/tcp &>/dev/null; then
            echo "    [4/10] Porta 464/tcp: [ OK! ]"
            ((OK++))
        else
            echo "    [4/10] Porta 464/tcp: [X]"
        fi

        if sudo firewall-cmd --query-port=3268/tcp &>/dev/null; then
            echo "    [5/10] Porta 3268/tcp: [ OK! ]"
            ((OK++))
        else
            echo "    [5/10] Porta 3268/tcp: [X]"
        fi
    else
        echo "    [1/10] firewalld: [ OK! ] INATIVO"
        echo "    [2/10] Servico ldap: [ OK! ] (Firewall Inativo)"
        echo "    [3/10] Servico kerberos: [ OK! ] (Firewall Inativo)"
        echo "    [4/10] Porta 464/tcp: [ OK! ] (Firewall Inativo)"
        echo "    [5/10] Porta 3268/tcp: [ OK! ] (Firewall Inativo)"
        OK=$((OK + 5))
    fi
    
    echo ""
    echo "    [ VERIFICACOES DE INTEGRACAO COM AD ]"
    echo "    ----------------------------------------------------------------------"
    
    # 6. Dominio
    if realm list | grep -q "$AD_DOMAIN"; then
        echo "    [6/10] Unido ao dominio: [ OK! ]"
        ((OK++))
    else
        echo "    [6/10] Unido ao dominio: [X]"
    fi
    
    # 7. SSSD
    if systemctl is-active --quiet sssd; then
        echo "    [7/10] Servico sssd: [ OK! ]"
        ((OK++))
    else
        echo "    [7/10] Servico sssd: [X]"
    fi
    
    # 8. Sudo
    if [[ -f "/etc/sudoers.d/99_${AD_GROUP}" ]] && grep -q "%$AD_GROUP" "/etc/sudoers.d/99_${AD_GROUP}" 2>/dev/null; then
        echo "    [8/10] Regra sudo: [ OK! ]"
        ((OK++))
    else
        echo "    [8/10] Regra sudo: [X]"
    fi
    
    # 9. Usuario AD
    if id "$AD_UPN" &>/dev/null || getent passwd "$AD_UPN" &>/dev/null; then
        echo "    [9/10] Consulta usuario $AD_UPN: [ OK! ]"
        ((OK++))
    else
        echo "    [9/10] Consulta usuario $AD_UPN: [X]"
    fi
    
    # 10. PAM
    if grep -q "pam_mkhomedir.so" /etc/pam.d/system-auth 2>/dev/null || grep -q "pam_mkhomedir.so" /etc/pam.d/common-session 2>/dev/null; then
        echo "    [10/10] pam_mkhomedir: [ OK! ]"
        ((OK++))
    else
        echo "    [10/10] pam_mkhomedir: [X]"
    fi
    
    echo ""
    echo "    ======================================================================"
    echo "    CHECKLIST FINAL: $OK de $TOTAL itens validados."
    echo "    ======================================================================"
    
    if [[ "$OK" -eq "$TOTAL" ]]; then
        echo ""
        echo "    [ OK! ] INTEGRACAO CONCLUIDA COM SUCESSO!"
        echo ""
        echo "    [*] Recomendacoes finais:"
        echo "        - Teste login: ssh $AD_UPN@localhost"
        echo "        - Teste sudo: sudo -l"
        echo "        - No PowerShell do AD: Get-ADComputer \$(hostname -s) -Properties *"
    else
        echo ""
        echo "    [X] ALGUMAS VERIFICACOES FALHARAM."
        echo "    [*] Reveja os modulos anteriores ou verifique manualmente."
    fi
    
    # Se a funcao mod_next existir no script, ela sera chamada aqui
    if declare -f mod_next &>/dev/null; then
        mod_next
    fi
	
}



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
    mod9_atualizar_info_so_ad            || exit 1
    mod10_checklist                      || exit 1
    
    echo ""
    echo "    ======================================================================"
    echo "    Script finalizado com sucesso!"
    echo "    ======================================================================"
    echo ""
}

# Executa o script
main "$@"
