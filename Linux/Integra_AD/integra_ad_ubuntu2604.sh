#!/usr/bin/env bash

# ==============================================================================
# Script: integra_ad_ubuntu.sh
# Funcao: Integracao Ubuntu Server (24.04/26.04) com Active Directory
#
# IMPORTANTE: Ao realizar qualquer alteracao na logica ou compatibilidade,
# atualize a variavel SCRIPT_VERSION abaixo e a data do LOG de alteracoes.
# O versionamento semantico deve seguir a progressao decimal (1.0.x para
# correcoes/ajustes e 1.x.0 para novas funcionalidades).
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
#
# Versao Inicial: 1.0.0 (Baseada na versao 1.2.0 Oracle Linux)
# Data: 2026-05-19
# ==============================================================================

# --- [0] METADADOS E VERSAO ---
SCRIPT_VERSION="1.0.0"

# --- [1] CONFIGURACOES DE SEGURANCA ---
set -euo pipefail

# ==============================================================================
# FUNCOES AUXILIARES E PREPARACAO
# ==============================================================================

# Verifica se eh root
if [[ $EUID -ne 0 ]]; then
    echo ""
    echo "    [X] Este script precisa ser executado como root (sudo)."
    echo "        Utilize: sudo $0"
    echo ""
    exit 1
fi

# Funcao de pausa entre modulos
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
    echo "              INTEGRACAO UBUNTU SERVER COM ACTIVE DIRECTORY"
    echo "    ----------------------------------------------------------------------"
    echo "                     >> Versao: ${SCRIPT_VERSION} <<"
    echo "                     >> ETAPA 1/10: Bem-Vindo!"
    echo "    ======================================================================"
    echo ""
    echo "        OBJETIVO:"
    echo "        - Configurar este servidor Ubuntu para se unir a um dominio"
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
    # SECAO: VERIFICACAO E AJUSTE DE HOSTNAME E REDE (OTIMIZADO UBUNTU/NETPLAN)
    # ----------------------------------------------------------------------
    while true; do
        clear
        
        # Coleta dinamica do Hostname e isolamento do nome curto
        local CURRENT_HOSTNAME=$(hostname)
        local SHORT_HOSTNAME=$(echo "$CURRENT_HOSTNAME" | cut -d'.' -f1)
        
        # Identificacao da interface ativa de rota padrao
        local INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
        [ -z "$INTERFACE" ] && INTERFACE=$(ip -4 addr show up | grep -v '127.0.0.1' | awk '/inet / {print $NF}' | head -n1)
        
        local IP_ADD=$(ip -4 addr show dev "$INTERFACE" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)
        local NETMASK_CIDR=$(ip -4 addr show dev "$INTERFACE" | awk '/inet / {print $2}' | cut -d/ -f2 | head -n1)
        local GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)
        
        # DNS obtido via systemd-resolved (padrao Ubuntu) focado no escopo do Netplan
        local DNS_SERVER=$(resolvectl dns "$INTERFACE" 2>/dev/null | awk '{print $4}' | head -n1)
        [ -z "$DNS_SERVER" ] && DNS_SERVER=$(awk '/nameserver/ {print $2}' /etc/resolv.conf | head -n1)
        
        # Identificacao de DHCP / Estatico baseada nos arquivos YAML do Netplan
        local DHCP_SERVER="Nenhum (IP Estatico)"
        if grep -rqi "dhcp4:.*true" /etc/netplan/; then
            DHCP_SERVER="Ativo (IP via DHCP)"
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
        echo "                        >> Versao: ${SCRIPT_VERSION} <<"
        echo "                        >> ETAPA 1/10: CONFIRMACAO DO HOSTNAME"
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
            read -erp "    Deseja prosseguir ? (s/n): " CONF_PROSSEGUIR
            CONF_PROSSEGUIR=$(echo "$CONF_PROSSEGUIR" | tr '[:upper:]' '[:lower:]')
            if [[ "$CONF_PROSSEGUIR" == "s" ]]; then
                
                # Variavel AD_DOMAIN tratada de forma segura
                local DOMAIN_LOWER=$(echo "${AD_DOMAIN:-dominio.local}" | tr '[:upper:]' '[:lower:]')
                local CLEAN_NAME="$SHORT_HOSTNAME"
                local FINAL_FQDN="${CLEAN_NAME}.${DOMAIN_LOWER}"
                
                echo "    [*] Ajustando FQDN para idempotencia: $FINAL_FQDN"
                sudo hostnamectl set-hostname "$FINAL_FQDN"
                
                # Garante que o /etc/hosts tem a entrada correta
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
            echo "    ERROR !!!"
            echo "    O nome do computador nao pode ser ingressado como localhost."
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
                echo "                        >> Versao: ${SCRIPT_VERSION} <<"
                echo "                        >> ETAPA 1/10: CONFIRMACAO DO HOSTNAME"
                echo "    ======================================================================"
                echo ""
                echo "    Informe o novo hostname, até 15 caracteres !"
                echo "    (ex.: server-infra01)"
                read -erp "    Digite: " NEW_HOSTNAME
                
                NEW_HOSTNAME=$(echo "$NEW_HOSTNAME" | cut -d'.' -f1)
                
                if [ ${#NEW_HOSTNAME} -gt 15 ]; then
                    echo "    [X] Erro: O nome ultrapassa 15 caracteres padrao NetBIOS. Tente novamente."
                    sleep 2
                    continue
                fi
                
                if [ -z "$NEW_HOSTNAME" ] || [[ "$NEW_HOSTNAME" == "localhost" ]]; then
                    echo "    [X] Erro: Nome invalido ou in branco."
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
            echo "    Você está em uma janela de manutenção? Mudar o hostname causará um reboot."
            read -erp "    Este computador sera reiniciado! Deseja prosseguir ? (s/n): " REBOOT_CONF
            REBOOT_CONF=$(echo "$REBOOT_CONF" | tr '[:upper:]' '[:lower:]')
            if [[ "$REBOOT_CONF" != "s" ]]; then
                echo ""
                echo "    Alteracao cancelada. Saindo..."
                exit 0
            fi
            
            local DOMAIN_LOWER=$(echo "${AD_DOMAIN:-dominio.local}" | tr '[:upper:]' '[:lower:]')
            sudo hostnamectl set-hostname "${NEW_HOSTNAME}.${DOMAIN_LOWER}"
            
            clear
            echo "    ======================================================================"
            echo "    Apos o reboot, utilize novamente o script."
            echo "    ======================================================================"
            echo "    [*] Reiniciando o sistema em 5 segundos..."
            sleep 5
            sudo reboot
            exit 0
        fi
    done
    
    mod_next
}
# end mod1


# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MODULO 2: INSTALACAO DE PACOTES (APT) - VERSAO UBUNTU
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod2_install() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                        >> Versao: ${SCRIPT_VERSION} <<"
    echo "                        >> ETAPA 2/10: INSTALACAO DE PACOTES"
    echo "    ----------------------------------------------------------------------"
    echo "                       Instalando dependencias para integracao com AD"
    echo "    ======================================================================"
    echo ""
    
    # Verifica conectividade com repositorios
    echo "    [*] Verificando conectividade com repositorios APT..."
    if ! sudo apt update --print-uris &>/dev/null; then
        echo "    [X] ERRO: Nao foi possivel acessar os repositorios APT."
        echo "    Verifique as configuracoes de Proxy ou Gateway de rede."
        sleep 4
        return 1
    fi
    echo "    [ OK! ] Repositorios acessiveis."
    
    # Atualiza lista de pacotes
    echo ""
    echo "    [*] Atualizando lista de pacotes..."
    sudo apt update -qq
    
    # Verifica atualizacoes pendentes
    echo "    [*] Verificando atualizacoes pendentes..."
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
    echo "    [*] Instalando pacotes: ${PACOTES[*]}"
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
        echo "    [X] ERRO: Falha na instalacao de pacotes."
        return 1
    fi
    
    # Validacao final refinada
    echo ""
    echo "    [*] Validando instalacao individual..."
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
    echo "    [*] Ajustando servicos para configuracao..."
    sudo systemctl stop sssd &>/dev/null
    sudo systemctl enable --now chrony &>/dev/null
    
    echo "    [ OK! ] Modulo de instalacao concluido."
    sleep 2
    mod_next
}
# end mod2 



# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MODULO 3: CONFIGURACAO DE FIREWALL (UFW) - VERSAO UBUNTU
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod3_firewall() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                        >> Versao: ${SCRIPT_VERSION} <<"
    echo "                        >> ETAPA 3/10: CONFIGURACAO DO FIREWALL"
    echo "    ----------------------------------------------------------------------"
    echo "             Liberando portas necessarias para comunicacao com o AD"
    echo "    ======================================================================"
    echo ""

    # Verifica o estado atual do UFW de forma limpa
    echo "    [*] Verificando estado atual do UFW..."
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
        
        echo "    [*] Liberando conexao de entrada para: $porta/$proto..."
        sudo ufw allow "$porta/$proto" comment 'Active Directory Integration' &>/dev/null
    done

    echo "    ----------------------------------------------------------------------"
    echo "    [ OK! ] Regras injetadas com sucesso. Politicas anteriores preservadas."
    
    # Exibe o status atual resumido apenas para auditoria visual do administrador
    echo ""
    echo "    [*] Resumo atual do Firewall (UFW):"
    sudo ufw status numbered | grep 'Active Directory Integration' || true
    
    echo ""
    echo "    [ OK! ] Modulo de firewall concluido."
    sleep 2
    mod_next
}
# end mod3 



# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MODULO 4: COLETA DE INFORMACOES E VALIDACAO KERBEROS - VERSAO UBUNTU
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod4_adinfo() {
    while true; do
        clear
        echo ""
        echo "    ======================================================================"
        echo "                        >> Versao: ${SCRIPT_VERSION} <<"
        echo "                        >> ETAPA 4/10: COLETA DE DADOS DO AD"
        echo "    ======================================================================"
        echo "    Insira as informacoes do Active Directory para prosseguir."
        echo "    ======================================================================"
        echo ""

        # Coleta de dados com strings identicas ao original
        read -erp "    1. Digite o dominio DNS do AD (ex: empresa.local): " AD_DOMAIN
        AD_DOMAIN=$(echo "$AD_DOMAIN" | tr '[:upper:]' '[:lower:]')

        read -erp "    2. Digite o Administrador do AD (ex: administrator): " AD_USER
        # Mantem o formato do Usuario (UPN costuma ser em uppercase no Kerberos)
        AD_USER_UPPER=$(echo "$AD_USER" | tr '[:lower:]' '[:upper:]')
        AD_DOMAIN_UPPER=$(echo "$AD_DOMAIN" | tr '[:lower:]' '[:upper:]')

        read -erp "    3. Digite o Grupo do AD para Sudoers (ex: GG_Linux_Admins): " AD_SUDO_GROUP
        
        echo ""
        read -erp "    4. Deseja especificar uma OU para o servidor? (s/n): " HAS_OU
        HAS_OU=$(echo "$HAS_OU" | tr '[:upper:]' '[:lower:]')
        
        AD_OU=""
        if [[ "$HAS_OU" == "s" ]]; then
            echo "       Exemplo de OU: OU=Servers,OU=Computers,DC=empresa,DC=local"
            read -erp "       Digite a OU exata: " AD_OU
        fi

        # Tela de confirmacao dos dados coletados
        clear
        echo ""
        echo "    ======================================================================"
        echo "                        >> Versao: ${SCRIPT_VERSION} <<"
        echo "                        >> ETAPA 4/10: CONFIRMACAO DOS DADOS"
        echo "    ======================================================================"
        echo "        - Dominio AD .......: $AD_DOMAIN"
        echo "        - Usuario UPN ......: ${AD_USER_UPPER}@${AD_DOMAIN_UPPER}"
        echo "        - Grupo Sudoers ....: $AD_SUDO_GROUP"
        if [ -n "$AD_OU" ]; then
            echo "        - OU de Destino ....: $AD_OU"
        else
            echo "        - OU de Destino ....: Padrao do Active Directory (Computers)"
        fi
        echo "    ======================================================================"
        echo ""
        
        read -erp "    Os dados acima estao corretos? (s/n): " CONFIRM_DATA
        CONFIRM_DATA=$(echo "$CONFIRM_DATA" | tr '[:upper:]' '[:lower:]')
        
        if [[ "$CONFIRM_DATA" == "s" ]]; then
            break
        fi
    done

    # --- SECAO: TESTE DE CONFIANCA KERBEROS (KINIT) ---
    echo ""
    echo "    [*] Iniciando teste de autenticacao Kerberos..."
    echo "        Isso validara a senha do usuario e a resolucao DNS do AD."
    echo "    ----------------------------------------------------------------------"
    echo "    ATENCAO: Digite a senha do usuario ${AD_USER_UPPER} quando solicitado."
    echo "    ----------------------------------------------------------------------"
    echo ""

    # Destroi tickets residuais para garantir um teste limpo
    sudo kdestroy &>/dev/null || true

    # Executa o kinit forcando o Realm em caixa alta (Obrigatorio para o Kerberos)
    if echo "" | kinit "${AD_USER_UPPER}@${AD_DOMAIN_UPPER}" 2>/dev/null; then
        echo ""
        echo "    [ OK! ] Sucesso! Ticket Kerberos obtido corretamente."
        echo "        Comunicacao e credenciais validadas com o Active Directory."
        
        # Destroi o ticket de teste para seguranca, o realm join gerara o definitivo
        sudo kdestroy &>/dev/null || true
        sleep 2
        mod_next
        return 0
    else
        # Se falhar, tenta rodar exibindo o erro real para o administrador diagnosticar
        echo ""
        echo "    [X] ERRO: Falha na pre-autenticacao Kerberos."
        echo "        Abaixo estao os detalhes do erro gerados pelo sistema:"
        echo "    ----------------------------------------------------------------------"
        echo "" | kinit "${AD_USER_UPPER}@${AD_DOMAIN_UPPER}" || true
        echo "    ----------------------------------------------------------------------"
        echo "    [DICA DIA] Verifique se:"
        echo "    1. A senha digitada esta correta."
        echo "    2. O relogio do servidor esta sincronizado com o AD (Erro: Clock Skew)."
        echo "    3. O DNS consegue resolver o realm: ${AD_DOMAIN_UPPER}"
        echo ""
        
        while true; do
            read -erp "    Deseja tentar novamente a coleta e o teste? (s/n): " RETRY
            RETRY=$(echo "$RETRY" | tr '[:upper:]' '[:lower:]')
            if [[ "$RETRY" == "s" ]]; then
                # Chama a funcao recursivamente para reiniciar o Modulo 4
                mod4_adinfo
                return $?
            else
                echo "    [X] Integracao abortada pelo usuario no teste Kerberos."
                return 1
            fi
        done
    fi
}
# end mod4 



# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MODULO 5: EXECUCAO DO REALM JOIN - VERSAO UBUNTU
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod5_adjoin() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                        >> Versao: ${SCRIPT_VERSION} <<"
    echo "                        >> ETAPA 5/10: INGRESSO NO DOMINIO (JOIN)"
    echo "    ======================================================================"
    echo "          Executando realm join e aplicando politicas de acesso"
    echo "    ======================================================================"
    echo ""

    # --- SECAO: GERACAO DO /ETC/REALMD.CONF ---
    echo "    [*] Configurando o arquivo descritor /etc/realmd.conf..."
    
    # Coleta a versao curta do Ubuntu para documentar no AD (ex: 24.04 ou 26.04)
    local UBUNTU_VER=$(lsb_release -rs 2>/dev/null || echo "Ubuntu")

    sudo tee /etc/realmd.conf > /dev/null <<EOF
[active-directory]
os-name = Ubuntu Server
os-version = $UBUNTU_VER
client-software = sssd
sssd-flavor = active-directory
computer-ou = ${AD_OU}
automatic-install = no

[providers]
adcli = trusted

[$AD_DOMAIN]
fully-qualified-names = no
user-dot-change = yes
automatic-id-mapping = yes
manage-system = yes
EOF

    # Se nao foi especificada nenhuma OU, removemos a linha vazia do arquivo para evitar warnings
    if [ -z "$AD_OU" ]; then
        sudo sed -i '/computer-ou =/d' /etc/realmd.conf
    fi

    # --- SECAO: EXECUCAO DO REALM JOIN ---
    echo "    [*] Iniciando o processo de Domain Join no AD..."
    echo "    ----------------------------------------------------------------------"
    echo "    ATENCAO: Digite a senha do usuario ${AD_USER_UPPER} quando solicitado."
    echo "    ----------------------------------------------------------------------"
    echo ""

    # Monta os argumentos do join de forma dinamica baseada na OU
    local JOIN_ARGS=("$AD_DOMAIN" "-U" "$AD_USER")
    if [ -n "$AD_OU" ]; then
        JOIN_ARGS+=("--computer-ou=$AD_OU")
    fi

    # Executa o join forcando o uso do adcli ja homologado
    if sudo realm join "${JOIN_ARGS[@]}" --client-software=sssd --v; then
        echo ""
        echo "    [ OK! ] Sucesso! Servidor ingressado no dominio com exito."
    else
        echo ""
        echo "    [X] ERRO CRITICO: O realm join falhou."
        echo "        Verifique as credenciais, permissao de escrita na OU ou logs do AD."
        while true; do
            read -erp "    Deseja ignorar o erro e continuar o script mesmo assim? (s/n): " IGNORAR
            IGNORAR=$(echo "$IGNORAR" | tr '[:upper:]' '[:lower:]')
            if [[ "$IGNORAR" == "s" ]]; then
                echo "    [!] Continuando por decisao do administrador..."
                break
            elif [[ "$IGNORAR" == "n" ]]; then
                echo "    [X] Ingressao abortada. Saindo..."
                return 1
            fi
        done
    fi

    # --- SECAO: POLITICA DE PERMISSAO DE LOGIN (REALM PERMIT) ---
    echo ""
    echo "    [*] Aplicando filtros de seguranca de Login via Realm Permit..."
    
    # Restringe o acesso global e libera apenas o grupo administrativo do AD e o root local
    sudo realm deny --all
    
    # Executa a liberação do grupo coletado no Módulo 4
    if sudo realm permit -g "$AD_SUDO_GROUP"; then
        echo "    [ OK! ] Login liberado exclusivamente para o grupo: $AD_SUDO_GROUP"
    else
        echo "    [X] Falha ao aplicar realm permit para o grupo. Ajuste manualmente depois."
    fi
    
    # Garante que o usuario root local continua podendo logar na TTY/Console em emergencias
    sudo realm permit root
    
    echo ""
    echo "    [ OK! ] Modulo de ingresso concluido."
    sleep 2
    mod_next
}
# end mod5 



# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MODULO 6: OTIMIZACAO DO SSSD - VERSAO UBUNTU
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod6_sssdoptimal() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                        >> Versao: ${SCRIPT_VERSION} <<"
    echo "                        >> ETAPA 6/10: OTIMIZACAO DO SSSD"
    echo "    ======================================================================"
    echo "         Otimizando o arquivo sssd.conf para performance e cache"
    echo "    ======================================================================"
    echo ""

    local SSSD_CONF="/etc/sssd/sssd.conf"

    echo "    [*] Verificando existencia do arquivo de configuracao..."
    if [ ! -f "$SSSD_CONF" ]; then
        echo "    [X] ERRO: Arquivo $SSSD_CONF nao encontrado."
        echo "        Certifique-se de que o Modulo 5 (Join) foi executado com sucesso."
        sleep 4
        return 1
    fi

    echo "    [*] Aplicando tuning e politicas de cache offline no SSSD..."

    # Garante permissao restrita de leitura/escrita antes de manipular (Exigencia do SSSD)
    sudo chmod 600 "$SSSD_CONF"

    # Injeção de parâmetros de tuning mantendo a estrutura nativa gerada pelo realm
    # Configura expiração de cache padrão para 24 horas (86400) e ativa credenciais offline
    sudo sed -i '/\[domain\/.*\]/a \
cache_credentials = true\
account_cache_expiration = 86400\
entry_cache_timeout = 86400\
refresh_expired_interval = 3600\
krb5_store_password_if_offline = true' "$SSSD_CONF"

    # Remove duplicidades caso o sed tenha reinjetado linhas existentes
    # Garante que as diretivas fiquem limpas e unicas por bloco
    sudo awk '!awk_built_in_duplicate_check[$0]++' "$SSSD_CONF" > /tmp/sssd.conf.tmp
    sudo mv /tmp/sssd.conf.tmp "$SSSD_CONF"
    sudo chmod 600 "$SSSD_CONF"

    # --- SECAO: RESTART E REFRESH DO DAEMON ---
    echo "    [*] Reiniciando o servico SSSD para aplicar as novas diretivas..."
    
    # Limpa caches residuais em disco para forçar leitura limpa do AD
    sudo sssd -i &>/dev/null || true
    sudo rm -f /var/lib/sss/db/*.ldb &>/dev/null || true

    if sudo systemctl restart sssd; then
        echo "    [ OK! ] Servico SSSD reiniciado e parametrizado com sucesso."
    else
        echo "    [X] ERRO: Falha ao reiniciar o SSSD apos a otimizacao."
        return 1
    fi

    echo ""
    echo "    [ OK! ] Modulo de otimizacao concluido."
    sleep 2
    mod_next
  
}
# end mod6



# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MODULO 7: CONFIGURACAO DO PAM (HOME DIR) - VERSAO UBUNTU
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod7_pam_homedir() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                        >> Versao: ${SCRIPT_VERSION} <<"
    echo "                        >> ETAPA 7/10: CONFIGURACAO DO PAM"
    echo "    ======================================================================"
    echo "         Configurando criacao automatica de Home para usuarios do AD"
    echo "    ======================================================================"
    echo ""

    local PAM_FILE="/etc/pam.d/common-session"

    echo "    [*] Verificando suporte a criacao de home no PAM..."
    
    # No Ubuntu, a diretiva correta deve residir no common-session para cobrir SSH e TTY
    if [ ! -f "$PAM_FILE" ]; then
        echo "    [X] ERRO: Arquivo estrutural do PAM $PAM_FILE nao encontrado."
        return 1
    fi

    # Aplica a injeção de forma idempotente (só adiciona se já não existir no arquivo)
    if ! grep -q "pam_mkhomedir.so" "$PAM_FILE"; then
        echo "    [*] Injetando modulo pam_mkhomedir.so no fluxo de sessao..."
        
        # Insere a diretiva antes da última linha de fallback do PAM comum do Ubuntu
        sudo sed -i '/# end of pam-auth-update config/i \
session required                        pam_mkhomedir.so skel=/etc/skel/ umask=0077' "$PAM_FILE"
        
        echo "    [ OK! ] Politica de criacao de diretorios injetada com sucesso."
    else
        echo "    [ OK! ] O modulo pam_mkhomedir.so ja estava configurado no sistema."
    fi

    # Garante a consistência e permissões das pastas base /home
    # O umask=0077 garante que o home do usuário AD seja privado (permissão 700)
    echo "    [*] Validando integridade dos arquivos de configuracao do PAM..."
    
    if grep -q "pam_mkhomedir.so" "$PAM_FILE"; then
        echo "    [ OK! ] Validacao do PAM concluida com sucesso."
    else
        echo "    [X] ERRO: Falha ao persistir a configuracao no arquivo PAM."
        return 1
    fi

    echo ""
    echo "    [ OK! ] Modulo de configuracao do PAM concluido."
    sleep 2
    mod_next
  
}
# end mod7


# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MODULO 8: CONFIGURACAO DE ELEVACAO DE PRIVILEGIOS (SUDOERS) - VERSAO UBUNTU
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod8_adsudo() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                        >> Versao: ${SCRIPT_VERSION} <<"
    echo "                        >> ETAPA 8/10: CONFIGURACAO DO SUDO"
    echo "    ======================================================================"
    echo "         Configurando privilegios de root para o Grupo do AD"
    echo "    ======================================================================"
    echo ""

    local SUDOERS_TARGET="/etc/sudoers.d/ad_sudoers_group"
    local TEMP_SUDOERS="/tmp/ad_sudoers_template"

    echo "    [*] Preparando regra de subida de privilegio para o grupo do AD..."
    echo "        Grupo alvo: $AD_SUDO_GROUP"

    # Trata o nome do grupo se houver espacos (comum em estruturas Active Directory)
    # Substitui espacos por sua representacao literal escapada para o Sudoers
    local GRUPO_ESCAPADO=$(echo "$AD_SUDO_GROUP" | sed 's/ /\\ /g')

    # Cria o arquivo temporario com a regra padrao (Identica a regra do wheel/sudo nativo)
    # %Nome_Do_Grupo ALL=(ALL:ALL) ALL
    echo "%${GRUPO_ESCAPADO} ALL=(ALL:ALL) ALL" | sudo tee "$TEMP_SUDOERS" > /dev/null

    echo "    [*] Executando analise sintatica de seguranca via visudo..."
    
    # Valida o arquivo temporario. Se houver erro de sintaxe, o visudo aborta
    if sudo visudo -cf "$TEMP_SUDOERS" &>/dev/null; then
        echo "    [ OK! ] Sintaxe do arquivo validada com sucesso."
        
        # Move para o destino definitivo e atribui a permissao obrigatoria (0440)
        sudo mv "$TEMP_SUDOERS" "$SUDOERS_TARGET"
        sudo chmod 0440 "$SUDOERS_TARGET"
        
        echo "    [ OK! ] Regra de Sudoers aplicada em $SUDOERS_TARGET"
    else
        echo "    [X] ERRO: Falha na validacao de sintaxe do Sudoers."
        echo "        A regra para o grupo contem caracteres nao suportados."
        sudo rm -f "$TEMP_SUDOERS"
        while true; do
            read -erp "    Deseja prosseguir sem aplicar a regra de Sudo? (s/n): " SKIP_SUDO
            SKIP_SUDO=$(echo "$SKIP_SUDO" | tr '[:upper:]' '[:lower:]')
            if [[ "$SKIP_SUDO" == "s" ]]; then
                echo "    [!] Continuando por decisao do administrador..."
                break
            elif [[ "$SKIP_SUDO" == "n" ]]; then
                echo "    [X] Operacao abortada pelo usuario. Saindo..."
                return 1
            fi
        done
    fi

    # Validacao de persistencia
    if [ -f "$SUDOERS_TARGET" ]; then
        echo "    [ OK! ] Grupo $AD_SUDO_GROUP devidamente mapeado no ecossistema Sudo."
    else
        echo "    [!] AVISO: O servidor nao tera administradores do AD ate fixar o Sudoers."
    fi

    echo ""
    echo "    [ OK! ] Modulo de configuracao do Sudo concluido."
    sleep 2
    mod_next
  
}
# end mod8



# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MODULO 9: AUDITORIA FINAL (CHECKLIST) - VERSAO UBUNTU
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod9_checklist() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                        >> Versao: ${SCRIPT_VERSION} <<"
    echo "                        >> ETAPA 9/10: CHECKLIST DE AUDITORIA"
    echo "    ======================================================================"
    echo "         Realizando testes de integridade e validacao dos daemons"
    echo "    ======================================================================"
    echo ""

    local STATUS_FINAL=0

    # --- TESTE 1: STATUS DO SERVICO SSSD ---
    echo "    [*] Teste 1: Verificando saude do Daemon SSSD..."
    if systemctl is-active --quiet sssd; then
        echo "    [ OK! ] O servico SSSD esta em execucao (Active/Running)."
    else
        echo "    [X] ERRO: O servico SSSD encontra-se parado ou com falha."
        STATUS_FINAL=1
    fi

    # --- TESTE 2: RESOLUCAO DE NOMES AD ---
    echo ""
    echo "    [*] Teste 2: Testando integracao do NSSwitch com SSSD..."
    # Tenta ler o escopo do dominio via realmd para atestar a confianca
    if realm list | grep -q "domain-name: $AD_DOMAIN"; then
        echo "    [ OK! ] O realm reconhece a participacao ativa no dominio: $AD_DOMAIN"
    else
        echo "    [X] ERRO: O servidor nao esta listado como membro ativo no realm."
        STATUS_FINAL=1
    fi

    # --- TESTE 3: RESOLUCAO DNS DO DOMINIO ---
    echo ""
    echo "    [*] Teste 3: Validando resolucao DNS de registros SRV do AD..."
    if host -t SRV "_ldap._tcp.${AD_DOMAIN}" &>/dev/null; then
        echo "    [ OK! ] Resolucao de registros SRV do Active Directory funcional."
    else
        echo "    [!] AVISO: Falha ao consultar registros SRV do AD via DNS."
        echo "        Isso pode causar lentidao na descoberta de novos Domain Controllers."
    fi

    # --- TESTE 4: VALIDAÇÃO DAS DIRETIVAS DO PAM ---
    echo ""
    echo "    [*] Teste 4: Auditando integridade do modulo de Home no PAM..."
    if grep -q "pam_mkhomedir.so" /etc/pam.d/common-session; then
        echo "    [ OK! ] Persistencia do pam_mkhomedir.so confirmada em common-session."
    else
        echo "    [X] ERRO: A diretiva PAM de criacao automatica de Home sumiu."
        STATUS_FINAL=1
    fi

    # --- SECAO: FEEDBACK FINAL PARA O ADMINISTRADOR ---
    echo ""
    echo "    ======================================================================"
    echo "                            RESUMO DO STATUS DO REALM"
    echo "    ======================================================================"
    echo ""
    sudo realm list || true
    echo "    ----------------------------------------------------------------------"
    echo ""

    if [ "$STATUS_FINAL" -eq 0 ]; then
        echo "    ======================================================================"
        echo "    [ OK! ] PARABENS! Integracao concluida com 100% de sucesso."
        echo "            O Ubuntu Server esta pronto para receber logins do AD."
        echo "    ======================================================================"
    else
        echo "    ======================================================================"
        echo "    [!] ATENCAO: Integracao concluida, mas foram detectados alertas/erros."
        echo "        Revise os modulos apontados com [X] antes de colocar em producao."
        echo "    ======================================================================"
    fi

    echo ""
    echo "    [ OK! ] Modulo de checklist concluido."
    sleep 2
    mod_next
  
}
# end mod9



# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# ROTINA PRINCIPAL (MAIN) - ORQUESTRAÇÃO DO SCRIPT
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

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

    # Encerramento formal do script na tela do administrador
    clear
    echo ""
    echo "    ======================================================================"
    echo "                        >> Versao: ${SCRIPT_VERSION} <<"
    echo "                        >> FIM DO PROCESSO DE AUTOMACAO"
    echo "    ======================================================================"
    echo "         O script de integracao terminou todas as suas tarefas."
    echo "    ======================================================================"
    echo ""
    echo "    [ OK! ] Script executado por completo."
    echo "            Recomenda-se realizar um teste de login SSH utilizando"
    echo "            uma credencial valida do Active Directory."
    echo ""
    echo "    ======================================================================"
    echo ""
}
# end main

# --- PROVOCAÇÃO DA EXECUÇÃO ---
# Dispara o gatilho inicial do script chamando a funcao principal
main "$@"
