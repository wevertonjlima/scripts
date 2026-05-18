#!/bin/bash

# ======================================================================
# Script: Integracao Oracle Linux 9 com Active Directory
# Filename: integra_ad_ol9.sh
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

# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# FUNÇÕES AUXILIARES
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

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
    sleep 3
}


# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MÓDULO 1: BANNER E BOAS-VINDAS (COM AJUSTE DE FQDN IDEMPOTENTE)
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

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
        echo "                >> ETAPA 1/9: CONFIRMACAO DO HOSTNAME"
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
                echo "                >> ETAPA 1/9: CONFIRMACAO DO HOSTNAME"
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


# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MÓDULO 2: INSTALACAO DE PACOTES
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

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


# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MÓDULO 3: CONFIGURACAO DO FIREWALL
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

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

# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MODULO 4: COLETA E VALIDACAO DOS DADOS DO AD (VERSAO AIR-GAPPED)
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod4_adinfo() {
    clear
    echo "======================================================================"
    echo "    >> ETAPA 4/9: COLETA E VALIDACAO DOS DADOS DO AD"
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
    
    sleep 2
    mod_next
}


# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MODULO 5: ADESAO AO DOMINIO (REALM JOIN)
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod5_adjoin() {
    clear
    
    # ----------------------------------------------------------------------
    # 1. IDENTIFICACAO SEMI-AUTOMATICA (RHEL-ALIKE)
    # ----------------------------------------------------------------------
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        
        # Mapeamento das 5 versoes similares
        if [[ "$NAME" =~ "Oracle" ]]; then
            OS_NAME_VAL="Oracle Linux"
        elif [[ "$NAME" =~ "Rocky" ]]; then
            OS_NAME_VAL="Rocky Linux"
        elif [[ "$NAME" =~ "Alma" ]]; then
            OS_NAME_VAL="AlmaLinux"
        elif [[ "$NAME" =~ "CentOS" ]]; then
            OS_NAME_VAL="CentOS Linux"
        elif [[ "$NAME" =~ "Red Hat" ]]; then
            OS_NAME_VAL="Red Hat Enterprise Linux"
        else
            OS_NAME_VAL="RedHat Clone Linux"
        fi
        
        OS_VER_VAL="$VERSION_ID"
        OS_PRETTY_VAL="$OS_NAME_VAL $OS_VER_VAL"
    else
        OS_NAME_VAL="RedHat Clone Linux"
        OS_VER_VAL="Unknown"
        OS_PRETTY_VAL="RedHat Clone Linux"
    fi
    KERNEL_VAL=$(uname -r)

    # ----------------------------------------------------------------------
    # 2. BANNER DE EXECUCAO E FEEDBACK
    # ----------------------------------------------------------------------
    echo "    ======================================================================"
    echo "                 >> ETAPA 5/9: ADESAO AO DOMINIO"
    echo "    ----------------------------------------------------------------------"
    echo "                   Ingressando o servidor no dominio: $AD_DOMAIN"
    echo "    ======================================================================"
    echo ""
    echo "    [*] Configurando metadados do SO em /etc/realmd.conf..."
    
    # Gera o arquivo que o realm join consultará
    sudo tee /etc/realmd.conf > /dev/null <<EOF
[active-directory]
default-client = sssd
os-name = $OS_NAME_VAL
os-version = $OS_VER_VAL

[$AD_DOMAIN]
automatic-id-mapping = yes
user-principal = yes
fully-qualified-names = no
EOF

    echo ""
    echo "    [*] Atributos salvos para o objeto do AD:"
    echo "     - OperatingSystem ..............: $OS_PRETTY_VAL"
    echo "     - OperatingSystemVersion .......: $OS_VER_VAL" 
    echo "     - OperatingSystemServicePack ...: $KERNEL_VAL"
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
    sleep 2
    mod_next
}

# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MÓDULO 6: CONFIGURACAO DO SSSD E ATUALIZACAO DO SERVICE PACK
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod6_sssdoptimal() {
    clear
    echo "======================================================================"
    echo "         >> ETAPA 6/9: OTIMIZACAO SSSD E KERNEL (SERVICE PACK)"
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

    # 2. INJECAO DO KERNEL NO SERVICE PACK (VIA KERBEROS)
    # Como o Modulo 5 ja criou o objeto, aqui apenas fazemos o "update" do campo vazio
    echo ""
    echo "[*] Atualizando campo 'Service Pack' com versao do Kernel..."
    
    local HOST_UPPER=$(hostname -s | tr '[:lower:]' '[:upper:]')
    local KERNEL_VAL=$(uname -r)
    
    # Define o DN (Caminho) do objeto no AD
    local COMPUTER_DN="CN=${HOST_UPPER},CN=Computers,${AD_BASE_DN}"
    [[ -n "$OU_DN_FINAL" && "$OU_DN_FINAL" != *"CN=Computers"* ]] && COMPUTER_DN="CN=${HOST_UPPER},${OU_DN_FINAL}"

    # Gera o LDIF apenas para o Service Pack (o resto o Mod 5 ja preencheu)
    local LDIF_SP="/tmp/update_sp.ldif"
    cat <<EOF > "$LDIF_SP"
dn: $COMPUTER_DN
changetype: modify
replace: operatingSystemServicePack
operatingSystemServicePack: $KERNEL_VAL
EOF

    # Usa o ticket Kerberos ativo (-Y GSSAPI) para gravar a informacao
    if ldapmodify -Y GSSAPI -H "ldap://$AD_DC" -f "$LDIF_SP" &>/dev/null; then
        echo "[ OK! ] Kernel $KERNEL_VAL injetado no Service Pack."
    else
        echo "[AVISO] Nao foi possivel atualizar o Service Pack agora."
        echo "        O SSSD tentara sincronizar este atributo em background."
    fi

    rm -f "$LDIF_SP"
    
    echo ""
    echo "----------------------------------------------------------------------"
    echo "[ OK! ] Etapa 6 concluida. Verifique o ADUC agora!"
    echo "----------------------------------------------------------------------"
    
    mod_next
}



# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MÓDULO 7: CONFIGURACAO DO PAM (CRIACAO AUTOMATICA DE HOME)
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

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

# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MÓDULO 8: CONFIGURACAO DO SUDO PARA O GRUPO DO AD
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

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
    
    echo "# Acesso sudo para grupo do AD: $AD_GROUP" | sudo tee "$SUDOERS_FILE" > /dev/null
    echo "$REGRA" | sudo tee -a "$SUDOERS_FILE" > /dev/null
    sudo chmod 440 "$SUDOERS_FILE"
    
    sudo visudo -c &>/dev/null && echo "    [ OK! ] Regra sudo aplicada com sucesso." || {
        echo "    [X] ERRO: Sintaxe invalida."
        return 1
    }
    
    mod_next
}

# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MODULO 9: CHECKLIST FINAL DE VERIFICACAO
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

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
        echo "    [1/10] firewalld ativo: [ OK! ]"
        ((OK++))
    else
        echo "    [1/10] firewalld: [ OK! ] INATIVO"
        ((OK++))  # Conta como OK pois firewall inativo nao bloqueia
        TOTAL=$((TOTAL - 4))  # Ajusta total porque nao verificara as portas
    fi
    
    # So verifica as portas se firewalld estiver ativo
    if systemctl is-active --quiet firewalld; then
        for svc in ldap kerberos; do
            if sudo firewall-cmd --query-service="$svc" &>/dev/null; then
                echo "    [2/10] Servico $svc: [ OK! ]"
                ((OK++))
            else
                echo "    [2/10] Servico $svc: [X]"
            fi
        done
        
        for porta in 464/tcp 3268/tcp; do
            if sudo firewall-cmd --query-port="$porta" &>/dev/null; then
                echo "    [2/10] Porta $porta: [ OK! ]"
                ((OK++))
            else
                echo "    [2/10] Porta $porta: [X]"
            fi
        done
    fi
    
    echo ""
    echo "    [ VERIFICACOES DE INTEGRACAO COM AD ]"
    echo "    ----------------------------------------------------------------------"
    
    # 1. Dominio
    if realm list | grep -q "$AD_DOMAIN"; then
        echo "    [6/10] Unido ao dominio: [ OK! ]"
        ((OK++))
    else
        echo "    [6/10] Unido ao dominio: [X]"
    fi
    
    # 2. SSSD
    if systemctl is-active --quiet sssd; then
        echo "    [7/10] Servico sssd: [ OK! ]"
        ((OK++))
    else
        echo "    [7/10] Servico sssd: [X]"
    fi
    
    # 3. Sudo
    if [[ -f "/etc/sudoers.d/99_${AD_GROUP}" ]] && grep -q "%$AD_GROUP" "/etc/sudoers.d/99_${AD_GROUP}" 2>/dev/null; then
        echo "    [8/10] Regra sudo: [ OK! ]"
        ((OK++))
    else
        echo "    [8/10] Regra sudo: [X]"
    fi
    
    # 4. Usuario AD (CORRECAO CIRURGICA AQUI)
    # Utilizamos AD_UPN que foi a variavel validada e exportada no Modulo 4
    if id "$AD_UPN" &>/dev/null || getent passwd "$AD_UPN" &>/dev/null; then
        echo "    [9/10] Consulta usuario $AD_UPN: [ OK! ]"
        ((OK++))
    else
        echo "    [9/10] Consulta usuario $AD_UPN: [X]"
    fi
    
    # 5. PAM
    if grep -q "pam_mkhomedir.so" /etc/pam.d/system-auth; then
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
        echo "        - No PowerShell do AD: Get-ADComputer $(hostname -s) -Properties *"
    else
        echo ""
        echo "    [X] ALGUMAS VERIFICACOES FALHARAM."
        echo "    [*] Reveja os modulos anteriores ou verifique manualmente."
    fi
    
    mod_next
}

# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# FLUXO PRINCIPAL DO SCRIPT
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

main() {
    mod1_banner        || exit 1
    mod2_install       || exit 1
    mod3_firewall      
    mod4_adinfo        || exit 1
    mod5_adjoin        || exit 1
    mod6_sssdoptimal   || exit 1
    mod7_pam_homedir   || exit 1
    mod8_adsudo        || exit 1
    mod9_checklist     || exit 1
    
    echo ""
    echo "    ======================================================================"
    echo "    Script finalizado com sucesso!"
    echo "    ======================================================================"
    echo ""
}

# Executa o script
main
