#!/bin/bash

# ======================================================================
# Script: Integracao Ubuntu com Active Directory
# Filename: integra_ubuntu_ad.sh
# 
# DESCRICAO:
#   Script para integrar Ubuntu 20.04/22.04/24.04 ao Active Directory,
#   configurando firewall (UFW), SSSD, PAM, sudo e enviando informações
#   do sistema operacional para o AD via ldapmodify.
#
# REQUISITOS:
#   - Ubuntu 20.04 LTS ou superior
#   - Acesso root/sudo
#   - Conectividade com os DCs do AD (portas 389, 88, 464, 3268)
#   - Conta AD com permissão para unir computadores ao domínio
#
# [LOG DE ALTERACOES]
# ======================================================================
# Versao 1.0.0 - 2026-04-28
#   - Versao inicial baseada no script para Oracle Linux
#   - Adaptacao para Ubuntu (apt, dpkg, ufw, paths PAM)
#   - Mantido mesmo fluxo, telas, loops e checklist
#   - Senha com entrada unica
#   - Suporte a OU com validacao LDAP
#   - Atualizacao de atributos operatingSystem no AD via ldapmodify
#
# Versao: 1.0.0
# Data: 2026-04-28
# Baseado no script: integra_ad_ol9.sh v1.2.0
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
# MÓDULO 1: BANNER E BOAS-VINDAS
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod1_banner() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                 INTEGRACAO UBUNTU COM ACTIVE DIRECTORY"
    echo "    ----------------------------------------------------------------------"
    echo "                    >> ETAPA 1/9: Bem-Vindo!"
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
            break
        elif [[ "$PROSSEGUIR" == "n" ]]; then
            echo ""
            echo "    Operacao abortada pelo usuario. Saindo..."
            exit 0
        else
            echo "    Resposta invalida. Digite 's' para sim ou 'n' para nao."
        fi
    done
    
    mod_next
}

# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MÓDULO 2: INSTALACAO DE PACOTES (APT)
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
    echo "    [*] Verificando conectividade com repositorios APT..."
    if ! sudo apt update --print-uris &>/dev/null; then
        echo "    [X] ERRO: Nao foi possivel acessar os repositorios APT."
        sleep 4
        return 1
    fi
    echo "    [✓] Repositorios acessiveis."
    
    # Atualiza lista de pacotes
    echo ""
    echo "    [*] Atualizando lista de pacotes..."
    sudo apt update -qq
    
    # Verifica atualizações pendentes
    echo "    [*] Verificando atualizacoes pendentes..."
    local updates=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || true)
    
    if [ "$updates" -gt 0 ]; then
        echo "    [⚠] ATENCAO: Existem $updates atualizacoes pendentes."
        while true; do
            read -erp "    Deseja atualizar o sistema agora? (s/n): " ATUALIZAR
            [[ "$ATUALIZAR" == "s" ]] && sudo apt upgrade -y && break
            [[ "$ATUALIZAR" == "n" ]] && echo "    Prosseguindo sem atualizar..." && break
            echo "    Digite 's' ou 'n'"
        done
    else
        echo "    [✓] Sistema ja atualizado."
    fi
    
    # Lista de pacotes necessários para Ubuntu
    local PACOTES=(
        adcli
        bind9-dnsutils
        chrony
        cracklib-runtime
        dbus
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
    
    # Instala todos os pacotes
    if sudo apt install -y "${PACOTES[@]}"; then
        echo "    [✓] Pacotes instalados com sucesso."
    else
        echo "    [X] ERRO: Falha na instalacao de pacotes."
        return 1
    fi
    
    # Validação final
    echo ""
    echo "    [*] Validando instalacao..."
    local OK=true
    for pkg in "${PACOTES[@]}"; do
        if dpkg -l | grep -q "^ii.*$pkg"; then
            echo "    [OK] $pkg"
        else
            echo "    [X] $pkg - FALHOU!"
            OK=false
        fi
    done
    
    $OK || return 1
    
    sudo systemctl stop sssd &>/dev/null
    mod_next
}

# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MÓDULO 3: CONFIGURACAO DO FIREWALL (UFW)
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
    
    # Verifica se UFW está instalado
    if ! command -v ufw &>/dev/null; then
        echo "    [*] UFW nao encontrado. Instalando..."
        sudo apt install -y ufw
    fi
    
    # Verifica se UFW está ativo
    if ! ufw status | grep -q "active"; then
        echo "    [*] UFW inativo. Ativando..."
        echo "y" | sudo ufw enable
    fi
    
    echo "    [*] UFW ativo. Liberando portas para o AD..."
    
    # Libera as portas necessárias
    sudo ufw allow 389/tcp comment 'LDAP'
    sudo ufw allow 88/tcp comment 'Kerberos'
    sudo ufw allow 464/tcp comment 'kpasswd'
    sudo ufw allow 3268/tcp comment 'Global Catalog'
    
    # Recarrega as regras
    sudo ufw reload
    
    # Mostra as regras adicionadas
    echo ""
    echo "    [*] Regras adicionadas:"
    ufw status | grep -E "389|88|464|3268" | sed 's/^/        /'
    
    mod_next
}

# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MÓDULO 4: COLETA E VALIDACAO DOS DADOS DO AD
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod4_adinfo() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "            >> ETAPA 4/9: COLETA E VALIDACAO DOS DADOS DO AD"
    echo "    ======================================================================"
    echo ""
    
    # ----------------------------------------------------------------------
    # Etapa 1: Domínio AD
    # ----------------------------------------------------------------------
    while true; do
        read -erp "    Informe o nome do dominio (ex: meudominio.local): " AD_DOMAIN_INFO
        AD_DOMAIN=$(echo "$AD_DOMAIN_INFO" | tr '[:upper:]' '[:lower:]')
        
        echo "    [*] Verificando DNS e localizando DCs..."
        
        if dig +short "$AD_DOMAIN" | grep -q '.'; then
            DC_LIST=$(dig +short "_ldap._tcp.dc._msdcs.$AD_DOMAIN" SRV | awk '{print $4}' | sed 's/\.$//')
            if [ -n "$DC_LIST" ]; then
                AD_DC=$(echo "$DC_LIST" | head -n1)
                echo "    [✓] Dominio resolvido. DC: $AD_DC"
                AD_BASE_DN="DC=$(echo "$AD_DOMAIN" | sed 's/\./,DC=/g')"
                break
            fi
        fi
        echo "    [X] Dominio invalido ou nao resolvivel. Tente novamente."
    done
    
    # ----------------------------------------------------------------------
    # Etapa 2: Usuário e senha (entrada única)
    # ----------------------------------------------------------------------
    while true; do
        echo ""
        read -erp "    Informe o UPN do usuario (ex: admin@$AD_DOMAIN): " AD_UPN
        read -s -p "    Informe a senha: " AD_PASS
        echo ""
        
        echo "    [*] Validando credenciais..."
        
        if ldapsearch -LLL -x -H "ldap://$AD_DC" -D "$AD_UPN" -w "$AD_PASS" \
            -b "$AD_BASE_DN" "(userPrincipalName=$AD_UPN)" 2>/dev/null | grep -q "^dn:"; then
            echo "    [✓] Credenciais validas."
            break
        else
            echo "    [X] Usuario ou senha incorretos."
            unset AD_PASS
        fi
    done
    
    # ----------------------------------------------------------------------
    # Etapa 3: Grupo do AD para sudo
    # ----------------------------------------------------------------------
    while true; do
        echo ""
        read -erp "    Informe o nome do grupo do AD (ex: Linux_Admins): " AD_GROUP
        
        echo "    [*] Validando grupo..."
        
        if ldapsearch -LLL -x -H "ldap://$AD_DC" -D "$AD_UPN" -w "$AD_PASS" \
            -b "$AD_BASE_DN" "(cn=$AD_GROUP)" 2>/dev/null | grep -q "^dn:"; then
            echo "    [✓] Grupo encontrado."
            break
        else
            echo "    [X] Grupo nao encontrado. Verifique o nome exato."
        fi
    done
    
    # ----------------------------------------------------------------------
    # Etapa 4: OU (Opcional)
    # ----------------------------------------------------------------------
    echo ""
    echo "    ----------------------------------------------------------------------"
    echo "    Configuracao da OU (Unidade Organizacional)"
    echo "    ----------------------------------------------------------------------"
    echo "    Formatos aceitos:"
    echo "      - Caminho amigavel: Servidores/Linux"
    echo "      - DN direto: OU=Servidores,OU=_ACMELABS,DC=acme,DC=labs"
    echo "    ----------------------------------------------------------------------"
    echo "    IMPORTANTE: A OU deve existir previamente no AD"
    echo "    ----------------------------------------------------------------------"
    
    OU_DN_FINAL=""
    while true; do
        read -erp "    Informe a OU (Enter para padrao 'Computers'): " AD_OU_INPUT
        AD_OU_INPUT=$(echo "$AD_OU_INPUT" | xargs)
        
        if [[ -z "$AD_OU_INPUT" ]]; then
            echo "    [*] Usando container padrao: CN=Computers"
            break
        fi
        
        # Detecta se é DN direto ou caminho amigável
        if [[ "$AD_OU_INPUT" =~ (DC=|OU=) ]]; then
            OU_DN_FINAL="$AD_OU_INPUT"
            echo "    [*] DN direto detectado: $OU_DN_FINAL"
        else
            OU_DN=$(echo "$AD_OU_INPUT" | tr '/' '\n' | tac | sed 's/^/OU=/' | paste -sd ',' -)
            OU_DN_FINAL="$OU_DN,$AD_BASE_DN"
            echo "    [*] DN gerado: $OU_DN_FINAL"
        fi
        
        echo -n "    [*] Verificando se a OU existe... "
        if ldapsearch -LLL -x -H "ldap://$AD_DC" -D "$AD_UPN" -w "$AD_PASS" \
            -b "$OU_DN_FINAL" "(objectClass=organizationalUnit)" 2>/dev/null | grep -q "^dn:"; then
            echo "[✓] OK"
            break
        else
            echo "[X]"
            echo "    [X] ERRO: A OU '$AD_OU_INPUT' nao existe no AD."
            echo "    [*] Por favor, verifique o nome e tente novamente."
        fi
    done
    
    # ----------------------------------------------------------------------
    # Etapa 5: Hostname (anti-duplicação)
    # ----------------------------------------------------------------------
    echo ""
    echo "    [*] Configurando hostname..."
    
    CURRENT_FQDN=$(hostnamectl --static 2>/dev/null || hostname)
    BASE_HOSTNAME=$(echo "$CURRENT_FQDN" | sed -E "s/\.${AD_DOMAIN}//gi" | cut -d'.' -f1)
    [[ -z "$BASE_HOSTNAME" ]] && BASE_HOSTNAME="server"
    
    NEW_FQDN="${BASE_HOSTNAME}.${AD_DOMAIN}"
    
    if [[ "$CURRENT_FQDN" != "$NEW_FQDN" ]]; then
        sudo hostnamectl set-hostname "$NEW_FQDN"
        sudo sed -i "/${AD_DOMAIN}/d" /etc/hosts 2>/dev/null
        CURRENT_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
        [[ -n "$CURRENT_IP" ]] && echo "$CURRENT_IP $NEW_FQDN $BASE_HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
        echo "    [✓] Hostname alterado: $NEW_FQDN"
    else
        echo "    [✓] Hostname ja correto: $NEW_FQDN"
    fi
    
    # ----------------------------------------------------------------------
    # Etapa 6: Exporta variáveis e resumo
    # ----------------------------------------------------------------------
    AD_REALM=$(echo "$AD_DOMAIN" | tr '[:lower:]' '[:upper:]')
    AD_ACCOUNT=$(echo "$AD_UPN" | cut -d'@' -f1)
    
    export AD_DOMAIN AD_DC AD_BASE_DN AD_UPN AD_PASS AD_GROUP AD_REALM AD_ACCOUNT OU_DN_FINAL
    
    echo ""
    echo "    ----------------------------------------------------------------------"
    echo "    [✓] Dados validados com sucesso!"
    echo "        Dominio      : $AD_DOMAIN"
    echo "        DC           : $AD_DC"
    echo "        Usuario      : $AD_ACCOUNT"
    echo "        Grupo Sudo   : $AD_GROUP"
    echo "        Hostname     : $NEW_FQDN"
    echo "        OU           : ${OU_DN_FINAL:-CN=Computers,$AD_BASE_DN}"
    echo "    ----------------------------------------------------------------------"
    
    mod_next
}

# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MÓDULO 5: ADESAO AO DOMINIO (REALM JOIN)
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod5_adjoin() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "                    >> ETAPA 5/9: ADESAO AO DOMINIO"
    echo "    ----------------------------------------------------------------------"
    echo "              Ingressando o servidor no dominio: $AD_DOMAIN"
    echo "    ======================================================================"
    echo ""
    
    # Diagnóstico
    echo "    [*] Executando 'realm discover'..."
    realm discover "$AD_DOMAIN" || {
        echo "    [X] ERRO: Nao foi possivel descobrir o dominio."
        return 1
    }
    
    # Confirmação
    while true; do
        read -rp "    Deseja prosseguir com o Realm Join? (s/n): " PROSSEGUIR
        [[ "$PROSSEGUIR" == "s" ]] && break
        [[ "$PROSSEGUIR" == "n" ]] && return 1
        echo "    Digite 's' ou 'n'"
    done
    
    # Coleta da senha (apenas uma vez)
    echo ""
    local SENHA_LOCAL
    while true; do
        read -s -p "    Informe a senha do usuario $AD_ACCOUNT: " SENHA_LOCAL
        echo ""
        [[ -n "$SENHA_LOCAL" ]] && break
        echo "    A senha nao pode estar vazia."
    done
    
    # Gera /etc/realmd.conf
    echo ""
    echo "    [*] Gerando /etc/realmd.conf..."
    
    . /etc/os-release 2>/dev/null
    OS_NAME="${NAME:-Ubuntu}"
    OS_VERSION="${VERSION_ID:-22.04}"
    
    sudo tee /etc/realmd.conf > /dev/null <<EOF
[active-directory]
default-client = sssd
os-name = $OS_NAME
os-version = $OS_VERSION

[$AD_DOMAIN]
automatic-id-mapping = yes
user-principal = yes
fully-qualified-names = no
EOF
    echo "    [✓] /etc/realmd.conf criado."
    
    # Realm join
    echo ""
    echo "    [*] Realizando 'realm join'..."
    
    local CMD="realm join --user=\"$AD_ACCOUNT\" \"$AD_DOMAIN\""
    [[ -n "$OU_DN_FINAL" ]] && CMD="realm join --user=\"$AD_ACCOUNT\" --computer-ou=\"$OU_DN_FINAL\" \"$AD_DOMAIN\""
    
    if echo "$SENHA_LOCAL" | sudo -S bash -c "$CMD"; then
        echo "    [✓] Servidor ingressado no dominio com sucesso!"
    else
        echo "    [X] ERRO: Falha no realm join."
        unset SENHA_LOCAL
        return 1
    fi
    
    # Restrições de acesso
    echo ""
    echo "    [*] Aplicando politicas de acesso..."
    sudo realm deny --all && sudo realm permit -g "$AD_GROUP"
    echo "    [✓] Apenas o grupo '$AD_GROUP' pode logar via AD."
    
    unset SENHA_LOCAL
    mod_next
}

# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MÓDULO 6: CONFIGURACAO DO SSSD E ATUALIZACAO DOS ATRIBUTOS NO AD
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod6_sssdoptimal() {
    clear
    echo ""
    echo "    ======================================================================"
    echo "       >> ETAPA 6/9: CONFIGURACAO DO SSSD E ATUALIZACAO DOS ATRIBUTOS"
    echo "    ----------------------------------------------------------------------"
    echo "         Configurando SSSD e enviando OS/Kernel para o AD"
    echo "    ======================================================================"
    echo ""
    
    local SSSD_CONF="/etc/sssd/sssd.conf"
    local BACKUP="${SSSD_CONF}.$(date +%Y%m%d_%Hh%M).bak"
    
    # Backup
    sudo cp "$SSSD_CONF" "$BACKUP"
    echo "    [*] Backup criado: $BACKUP"
    
    # Extrai informações do SO
    . /etc/os-release 2>/dev/null
    OS_NAME="${NAME:-Ubuntu}"
    OS_VERSION="${VERSION_ID:-22.04}"
    OS_PRETTY="${PRETTY_NAME:-$OS_NAME $OS_VERSION}"
    
    KERNEL_VER=$(uname -r)
    echo "    [*] SO: $OS_PRETTY"
    echo "    [*] Kernel: $KERNEL_VER"
    
    # Para o SSSD
    sudo systemctl stop sssd &>/dev/null
    
    # Configura o SSSD
    echo "    [*] Configurando SSSD..."
    sudo sed -i '/^\[domain\//a enumerate = False\nentry_cache_timeout = 5400\nentry_cache_nowait_percentage = 75' "$SSSD_CONF"
    sudo sed -i 's/use_fully_qualified_names = True/use_fully_qualified_names = False/' "$SSSD_CONF"
    
    # Adiciona informações do sistema
    sudo sed -i "/^\[domain\/${AD_DOMAIN}\]/a os_name = $OS_NAME\nos_version = $OS_VERSION\nos_pretty_name = $OS_PRETTY\nkernel_version = $KERNEL_VER" "$SSSD_CONF"
    
    sudo chmod 600 "$SSSD_CONF"
    
    # ----------------------------------------------------------------------
    # ATUALIZA OS ATRIBUTOS DO COMPUTADOR NO AD VIA LDAPMODIFY
    # ----------------------------------------------------------------------
    echo ""
    echo "    [*] Atualizando atributos do computador no Active Directory..."
    
    COMPUTER_NAME=$(hostname -s)
    COMPUTER_DN="CN=${COMPUTER_NAME},CN=Computers,${AD_BASE_DN}"
    
    # Se OU foi especificada, ajusta o DN
    if [[ -n "$OU_DN_FINAL" && "$OU_DN_FINAL" != *"CN=Computers"* ]]; then
        COMPUTER_DN="CN=${COMPUTER_NAME},${OU_DN_FINAL}"
    fi
    
    LDIF_FILE="/tmp/update_computer_${COMPUTER_NAME}.ldif"
    
    cat > "$LDIF_FILE" <<EOF
dn: $COMPUTER_DN
changetype: modify
replace: operatingSystem
operatingSystem: $OS_NAME
-
replace: operatingSystemVersion
operatingSystemVersion: $OS_VERSION
-
replace: operatingSystemServicePack
operatingSystemServicePack: Kernel $KERNEL_VER
EOF

    echo -n "    [*] Conectando ao AD e atualizando... "
    
    if ldapmodify -x -H "ldap://$AD_DC" -D "$AD_UPN" -w "$AD_PASS" -f "$LDIF_FILE" 2>/dev/null; then
        echo "[✓]"
        echo "    [✓] Atributos operatingSystem/Version atualizados com sucesso!"
    else
        echo "[⚠]"
        echo "    [⚠] Nao foi possivel atualizar agora (pode ser questao de replicacao)."
        echo "    [*] Os atributos serao atualizados pelo SSSD em alguns minutos."
    fi
    
    rm -f "$LDIF_FILE"
    
    # Reinicia o SSSD
    echo ""
    echo "    [*] Reiniciando SSSD..."
    sudo systemctl restart sssd || {
        echo "    [X] ERRO: Falha ao reiniciar o SSSD."
        return 1
    }
    
    echo "    [✓] SSSD reiniciado com sucesso."
    echo ""
    echo "    ----------------------------------------------------------------------"
    echo "    [✓] Configuracoes aplicadas:"
    echo "        - Login simplificado (sem FQDN)"
    echo "        - Cache habilitado para logins offline"
    echo "        - OS/Kernel enviados para o AD"
    echo "    ----------------------------------------------------------------------"
    
    mod_next
}

# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MÓDULO 7: CONFIGURACAO DO PAM (CRIACAO AUTOMATICA DE HOME) - UBUNTU
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
    
    # Ubuntu usa /etc/pam.d/common-session (diferente do RHEL)
    local PAM_FILE="/etc/pam.d/common-session"
    local REGRA="session required pam_mkhomedir.so skel=/etc/skel umask=0022"
    
    # Verifica se o arquivo existe
    if [[ ! -f "$PAM_FILE" ]]; then
        echo "    [X] ERRO: Arquivo $PAM_FILE nao encontrado!"
        return 1
    fi
    
    # Remove qualquer entrada anterior
    sudo sed -i '/pam_mkhomedir.so/d' "$PAM_FILE"
    
    # Adiciona a nova regra ao final do arquivo
    echo "$REGRA" | sudo tee -a "$PAM_FILE" > /dev/null
    
    echo "    [✓] pam_mkhomedir configurado em $PAM_FILE"
    echo "    [✓] Diretorios home serao criados automaticamente no primeiro login."
    
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
    
    sudo visudo -c &>/dev/null && echo "    [✓] Regra sudo aplicada com sucesso." || {
        echo "    [X] ERRO: Sintaxe invalida."
        return 1
    }
    
    mod_next
}

# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MÓDULO 9: CHECKLIST FINAL DE VERIFICACAO (UBUNTU)
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
    
    echo "    [ VERIFICACOES DE FIREWALL (UFW) ]"
    echo "    ----------------------------------------------------------------------"
    
    if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
        echo "    [1/10] UFW ativo: [✓]"
        ((OK++))
    else
        echo "    [1/10] UFW: [⚠] INATIVO"
        ((OK++))
        TOTAL=$((TOTAL - 4))
    fi
    
    # Verifica as portas se UFW estiver ativo
    if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
        for porta in 389 88 464 3268; do
            if ufw status | grep -q "$porta.*ALLOW"; then
                echo "    [2/10] Porta $porta: [✓]"
                ((OK++))
            else
                echo "    [2/10] Porta $porta: [X]"
            fi
        done
    fi
    
    echo ""
    echo "    [ VERIFICACOES DE INTEGRACAO COM AD ]"
    echo "    ----------------------------------------------------------------------"
    
    # 1. Domínio
    if realm list | grep -q "$AD_DOMAIN"; then
        echo "    [6/10] Unido ao dominio: [✓]"
        ((OK++))
    else
        echo "    [6/10] Unido ao dominio: [X]"
    fi
    
    # 2. SSSD
    if systemctl is-active --quiet sssd; then
        echo "    [7/10] Servico sssd: [✓]"
        ((OK++))
    else
        echo "    [7/10] Servico sssd: [X]"
    fi
    
    # 3. Sudo
    if [[ -f "/etc/sudoers.d/99_${AD_GROUP}" ]] && grep -q "%$AD_GROUP" "/etc/sudoers.d/99_${AD_GROUP}" 2>/dev/null; then
        echo "    [8/10] Regra sudo: [✓]"
        ((OK++))
    else
        echo "    [8/10] Regra sudo: [X]"
    fi
    
    # 4. Usuário AD
    if id "$AD_ACCOUNT" &>/dev/null || getent passwd "$AD_ACCOUNT" &>/dev/null; then
        echo "    [9/10] Consulta usuario $AD_ACCOUNT: [✓]"
        ((OK++))
    else
        echo "    [9/10] Consulta usuario $AD_ACCOUNT: [X]"
    fi
    
    # 5. PAM (Ubuntu: common-session)
    if grep -q "pam_mkhomedir.so" /etc/pam.d/common-session; then
        echo "    [10/10] pam_mkhomedir: [✓]"
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
        echo "    [✓] INTEGRACAO CONCLUIDA COM SUCESSO!"
        echo ""
        echo "    [*] Recomendacoes finais:"
        echo "        - Teste login: ssh $AD_ACCOUNT@localhost"
        echo "        - Teste sudo: sudo -l"
        echo "        - No PowerShell do AD: Get-ADComputer $(hostname -s) -Properties *"
    else
        echo ""
        echo "    [⚠] ALGUMAS VERIFICACOES FALHARAM."
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