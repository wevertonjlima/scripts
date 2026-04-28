#!/bin/bash

# integra_ad.sh

# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# Módulo 01 – Helper Functions
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

if [[ $EUID -ne 0 ]]; then
    echo ""
    echo "    [X] Este script precisa ser executado como root (sudo)."
    echo "        Utilize: sudo $0"
    echo ""
    exit 1
fi

# Função de encerramento em cada modulo.
mod_next() {
	printf "\n\n    >>> Prosseguindo...\n\n"
	sleep 3

}


# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# Módulo 1 – Banner
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod1_banner() {
    show_banner() {
        echo ""
        echo "    ===================================================================================="
        echo "                          INTEGRAÇÃO UBUNTU COM ACTIVE DIRECTORY"
        echo "    ------------------------------------------------------------------------------------"
        echo "        >> ETAPA 1/9: Bem-Vindo!"
        echo "    ===================================================================================="
        echo ""
        echo "        OBJETIVO:"
        echo "        - Configurar este servidor Linux Ubuntu/Debian para se unir a um domínio"
        echo "          Active Directory, permitindo login de usuários."
        echo ""
		echo "        CARACTERISTICAS:"
        echo "        - Controle de login local/ssh através de Grupo de Segurança do AD."
		echo "        - Permissão de root através de Grupo de Segurança do AD."
		echo "        - Cache de credenciais permitindo login se o AD estiver offline".
		echo ""
        echo "        IMPORTANTE!"
        echo "        - Use esse script após atualizar seus sistema. Novos pacotes serão instalados."
        echo "        - Tenha em mãos as seguintes informações sobre o Active Directory:"
        echo "        ------------------------------------------------------------------"
        echo "        * Nome do Dominio DNS do AD."
        echo "        * Conta UPN e senha do usuário que irá integrar ao AD."
        echo "        * Nome do Grupo do AD que administrará este servidor."
        echo ""
        echo "    ===================================================================================="
        echo ""
    }
    clear
    show_banner
    sleep 2

    while true; do
        read -erp "  Deseja prosseguir com a instalação e configuração? (s/n): " PROSSEGUIR
        PROSSEGUIR=$(echo "$PROSSEGUIR" | tr '[:upper:]' '[:lower:]')
        if [[ "$PROSSEGUIR" == "s" ]]; then
            echo ""
            echo "Iniciando as configurações... Próxima etapa: Instalação de pacotes."
            echo ""
            break
        elif [[ "$PROSSEGUIR" == "n" ]]; then
            echo ""
            echo "Operação abortada pelo usuário. Saindo..."
            exit 0
        else
            echo "Resposta inválida. Por favor, digite 's' para sim ou 'n' para não."
        fi
    done

mod_next
}


# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# Módulo 2 – Instalação de Pacotes Essenciais
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod2_install() {

    show_banner() {
        echo ""
        echo "    ===================================================================================="
        echo "        >> ETAPA 2/9: INSTALAÇÃO DE PACOTES ESSENCIAIS"
        echo "    ------------------------------------------------------------------------------------"
        echo "           Instalando todas as dependências e utilitários."
        echo "    ===================================================================================="
        echo ""
	}

    clear
    show_banner
    sleep 2

    # Atualiza a lista de pacotes
    echo "    [*] Executando 'apt update' para buscar informações recentes de pacotes..."
    sleep 1.5
    if ! sudo apt update -q; then
        echo "    [X] ERRO: Falha ao executar 'apt update'. Verifique a conectividade de rede/repositórios."
        sleep 4
        return 1
    fi

    echo "    [!] Lista de pacotes atualizada com sucesso."

    # Checagem de Upgrades Pendentes
    echo "    [*] Verificando por atualizações de segurança pendentes..."
    # Conta o número de pacotes listados como upgradables (ignora a primeira linha do cabeçalho)
    local UPGRADABLE_COUNT=$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l)

    if [ "$UPGRADABLE_COUNT" -gt 0 ]; then
        echo ""
        echo "    ===================================================================="
        echo "        !!! ATENÇÃO: Seu sistema está desatualizado !!!"
		echo "                     Existem $UPGRADABLE_COUNT pacotes pendentes."  
		echo "    --------------------------------------------------------------------"
        echo "        Aplique as últimas atualizações de segurança/melhorias,"
        echo "        e depois retorne a executar esse script."
        echo "        (execute: 'sudo apt upgrade -y')"
        echo "    ===================================================================="
        echo ""
        sleep 3
        return 1
    fi
	
    # Instalação dos Pacotes
    echo "    [*] Instalando os seguintes pacotes:"
    sleep 1.5

    # Instala os pacotes de forma silenciosa
    sudo apt install -y -q \
        adcli chrony dnsutils ldap-utils libnss-sss libpam-sss \
        oddjob oddjob-mkhomedir packagekit realmd samba-common-bin \
        sssd sssd-tools

    [ $? -ne 0 ] && { echo "    [X] ERRO: Falha na instalação de pacotes."; return 1; }

    echo "    [!] Todos os pacotes instalados com sucesso."

    # Garante que o serviço SSSD esteja parado
    sudo systemctl stop sssd &>/dev/null

    # Inicia Verificação Final
    echo "    ------------------------------------------------------------------------------------"
    echo "    >> Iniciando Verificação Final de Instalação..."
    sleep 2

    # Lista de pacotes críticos para validação
    local CRITICAL_PACKAGES_ARRAY=(
        adcli chrony dnsutils ldap-utils libnss-sss libpam-sss \
        oddjob oddjob-mkhomedir packagekit realmd samba-common-bin \
        sssd sssd-tools
    )

    local ALL_INSTALLED=true

    # Itera sobre o array para validar a instalação
    for pkg in "${CRITICAL_PACKAGES_ARRAY[@]}"; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            echo "    [OK] $pkg"
        else
            echo "    [X] $pkg ESTÁ FALTANDO! (ERRO INTERNO)"
            ALL_INSTALLED=false
        fi
        sleep 0.2
    done

    echo "-------------------------------------------------------------------"

    # Conclusão
    if $ALL_INSTALLED; then
        echo "    [!] SUCESSO - Todos os pacotes estão instalados."; sleep 0.5
        return 0
    else
        echo "    [X] FALHA - PACOTES CRÍTICOS ESTÃO FALTANDO!"
        echo "        Verifique a rede e tente novamente."; sleep 0.5
        return 1
    fi
mod_next
}
# mod02_install


# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MÓDULO 3: Validação do Active Directory:
#           Domain / DC / AD User / AD Grupo / Hostname 
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod3_adinfo() {

    show_banner() {
        echo ""
        echo "    ===================================================================================="
        echo "        >> ETAPA 3/9: COLETA E VALIDAÇÃO DOS DADOS DO ACTIVE DIRECTORY"
        echo "    ===================================================================================="
        echo ""
    }

    clear
    show_banner
    sleep 2

    # ------------------------------------------------------------------------------------------
    # Etapa 1: Solicita e valida o domínio AD (DOMAIN_NAME)
    # ------------------------------------------------------------------------------------------
    while true; do
        clear; show_banner
        read -erp "    Informe o nome do domínio (ex: meuad.local): " AD_DOMAIN_INFO
        echo      "    [*] Verificando DNS e Localizando Controladores de Domínio..."
        sleep 1
		
		# Garante que o domínio está em minúsculas, só por segurança
		AD_DOMAIN=$(echo "$AD_DOMAIN_INFO" | tr '[:upper:]' '[:lower:]')

        if dig +short "$AD_DOMAIN" | grep -q '.'; then
            DC_LIST=$(dig +short _ldap._tcp.dc._msdcs."$AD_DOMAIN" SRV | awk '{print $4}' | sed 's/\.$//')
            if [ -n "$DC_LIST" ]; then
                AD_DC=$(echo "$DC_LIST" | head -n1)
                echo "    [!] Domínio resolvido e DC encontrado: $AD_DC"
                sleep 2
                break
            else
                echo "    [X] Nenhum DC encontrado via DNS SRV. Verifique os registros do domínio."
                sleep 2
            fi
        else
            echo "    [X] Domínio inválido ou não resolvível: $AD_DOMAIN"
            sleep 2
        fi
    done

    # ------------------------------------------------------------------------------------------
    # Etapa 2: Solicita e valida o UPN do usuário e senha
    # ------------------------------------------------------------------------------------------
    while true; do
        clear; show_banner
        echo "    Domínio detectado : $AD_DOMAIN"
        echo "    DC selecionado    : $AD_DC"
        echo "    ----------------------------------------------------------------------"
        read -erp  "    Informe o UPN do usuário (ex: user@$AD_DOMAIN): " AD_UPN

        read -s -p "    Informe a senha do usuário: " AD_PASS; echo
        read -s -p "    Confirme a senha: " AD_PASS_CONFIRM; echo

        if [ "$AD_PASS" != "$AD_PASS_CONFIRM" ]; then
            echo -e "\n    [X] As senhas não coincidem. Tente novamente."
            unset AD_PASS AD_PASS_CONFIRM
            sleep 2
            continue
        fi

        echo "    [*] Validando usuário e senha no AD..."
        sleep 1

        AD_BASE_DN="DC=$(echo "$AD_DOMAIN" | sed 's/\./,DC=/g')"

        if ldapsearch -LLL -x -H "ldap://$AD_DC" -D "$AD_UPN" -w "$AD_PASS" \
            -b "$AD_BASE_DN" "(userPrincipalName=$AD_UPN)" | grep -q "^dn:"; then
            echo "    [!] Credenciais validadas com sucesso!"
            sleep 2
            break
        else
            echo "    [X] Erro: Usuário '$AD_UPN' não encontrado ou senha incorreta."
            unset AD_PASS AD_PASS_CONFIRM
            sleep 3
        fi
    done

    # ------------------------------------------------------------------------------------------
    # Etapa 3: Solicita e valida o grupo de SUDO
    # ------------------------------------------------------------------------------------------
    while true; do
        clear; show_banner
        echo "    Domínio detectado   : $AD_DOMAIN"
        echo "    DC selecionado      : $AD_DC"
        echo "    Usuário autenticado : $AD_UPN"
        echo "    ----------------------------------------------------------------------"
        read -erp "    Informe o nome do grupo do AD (ex: Meu_Grupo_Linux): " AD_GROUP

        echo "    [*] Validando existência do grupo no AD..."
        sleep 1

        if ldapsearch -LLL -x -H "ldap://$AD_DC" -D "$AD_UPN" -w "$AD_PASS" \
            -b "$AD_BASE_DN" "(cn=$AD_GROUP)" | grep -q "^dn:"; then
            echo "    [!] Sucesso: Grupo encontrado no AD."
            sleep 2
            break
        else
            echo "    [X] Grupo '$AD_GROUP' não encontrado. Verifique o nome exato (case sensitive)."
            sleep 3
        fi
    done

    # ------------------------------------------------------------------------------------------
    # Etapa 4: Configurações finais e exportação
    # ------------------------------------------------------------------------------------------
    AD_REALM=$(echo "$AD_DOMAIN" | tr '[:lower:]' '[:upper:]')
    AD_ACCOUNT=$(echo "$AD_UPN" | cut -d'@' -f1)

	export AD_DOMAIN AD_DC AD_BASE_DN AD_UPN AD_GROUP AD_REALM AD_ACCOUNT
    unset AD_PASS AD_PASS_CONFIRM

    # ------------------------------------------------------------------------------------------
    # Etapa 5: Definição do hostname baseado em HOSTNAME + AD_DOMAIN
    # ------------------------------------------------------------------------------------------
    # Armazena o hostname atual
    OLD_HOSTNAME=$(hostname)
    
    # Concatena FQDN
    NEW_HOSTNAME="${OLD_HOSTNAME}.${AD_DOMAIN}"
    
    # Aplica o novo hostname
    echo "    [*] Configurando hostname do sistema para: $NEW_HOSTNAME"
    sudo hostnamectl set-hostname "$NEW_HOSTNAME"
    sleep 1

    # ------------------------------------------------------------------------------------------
    # Etapa 6: Resumo
    # ------------------------------------------------------------------------------------------
    clear; show_banner
    echo   "    [*] Validação concluída com sucesso!"
    echo   "    -----------------------------------------------------------"
    printf "     Domínio  AD          : %-30s\n" "$AD_DOMAIN"
    printf "     Kerberos AD          : %-30s\n" "$AD_REALM"
    printf "     DC Utilizado         : %-30s\n" "$AD_DC"
    printf "     Usuário (UPN)        : %-30s\n" "$AD_UPN"
    printf "     Grupo SUDOERS        : %-30s\n" "$AD_GROUP"
    printf "     Hostname             : %-30s\n" "$NEW_HOSTNAME"
    echo   "    ------------------------------------------------------------"
	
mod_next    
}
# mod3_adinfo



# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# Módulo 4 – Time Drift (Chrony)
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
mod4_timedrift() {

    show_banner() {
        echo ""
        echo "    ===================================================================================="
        echo "        >> ETAPA 4/9: VALIDAÇÃO DE TIME DRIFT COM O ACTIVE DIRECTORY DCs"
        echo "    ------------------------------------------------------------------------------------"
        echo "                      Utilização do pacote chrony."
        echo "    ===================================================================================="
        echo ""
    }

    clear
    show_banner
    sleep 2

    local desired_timezone="America/Maceio"
    echo "    [*] Configurando fuso horário para: $desired_timezone"
    if ! timedatectl set-timezone "$desired_timezone"; then
        echo "    [X] Aviso: Falha ao definir o fuso horário para $desired_timezone."
        echo "        O script continuará, mas verifique manualmente."
    fi
    sleep 2

    echo "    [*] Status do Timezone e Relógio:"
    timedatectl | grep -E 'Time zone|RTC|System clock' | sed 's/^/    /g'
    sleep 2

    local dc_to_check="$AD_DC"
    local ad_domain="$AD_DOMAIN"
    local max_drift_seconds=300
    local config_file="/etc/chrony/chrony.conf"

    echo "    [*] Controlador de Domínio detectado: $dc_to_check"
    echo "    [*] Drift máximo permitido: ${max_drift_seconds}s"
    sleep 1

    echo "    [*] Fazendo backup de $config_file..."
    cp "$config_file" "${config_file}.bak"
    sleep 1

    echo "    [*] Validando e atualizando configuração Chrony..."
    sleep 1

    # ============================================================
    # >>>> ADAPTAÇÃO DO SCRIPT DE ADIÇÃO DO DC (mantém NTPs atuais)
    # ============================================================

    if grep -qE "^\s*server\s+${ad_domain}\b" "$config_file"; then
        echo "    [=] Servidor '$ad_domain' já está configurado no Chrony. Nenhuma alteração necessária."
    else
        echo "    [+] Adicionando '$ad_domain' como fonte NTP preferencial..."
        tmpfile=$(mktemp)
        awk -v dc="$ad_domain" '
            BEGIN {inserted=0}
            /^server / && inserted==0 {
                print "server " dc " prefer iburst"
                inserted=1
            }
            {print}
            END {
                if (inserted==0)
                    print "server " dc " prefer iburst"
            }
        ' "$config_file" > "$tmpfile"

        mv "$tmpfile" "$config_file"
        echo "    [OK] Servidor '$ad_domain' adicionado com sucesso em $config_file"
    fi

    echo "    [*] Reiniciando o serviço chrony..."
    if ! systemctl restart chrony; then
        echo "    [X] Falha ao reiniciar o serviço chrony. Verifique com 'systemctl status chrony'."
        sleep 5
        return 1
    fi

    echo "    [*] Aguardando sincronização inicial (10s)..."
    sleep 10
    chronyc makestep 0.1 3 &>/dev/null
    sleep 2

    echo "    [*] Verificando sincronização (drift)..."
    local tracking_output offset_raw absolute_drift
    tracking_output=$(chronyc tracking 2>/dev/null)
    offset_raw=$(echo "$tracking_output" | awk -F: '/Last offset/ {gsub(/^[ \t]+/, "", $2); print $2}' | awk '{print $1}' | sed 's/[+-]//')

    if [[ -z "$offset_raw" ]]; then
        echo "    [X] Falha ao obter o 'Last offset'. Verifique NTP/UDP123."
        sleep 4
        return 1
    fi

    absolute_drift=$(echo "$offset_raw" | bc -l)
    echo "    [*] Drift atual: ${absolute_drift} segundos"

    if echo "$absolute_drift > $max_drift_seconds" | bc -l | grep -q 1; then
        echo "    [X] SINCRONIZAÇÃO REPROVADA: Drift excede 5 minutos (${absolute_drift}s)"
        return 1
    else
        echo "    [!] SINCRONIZAÇÃO APROVADA: Drift dentro do limite (${absolute_drift}s)"
        echo "    [!] Requisito Kerberos (Drift) validado com sucesso."
    fi

    echo ""
    echo "     >>> Prosseguindo ..."
    sleep 3
    return 0
}
# mod4_timedrift



# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MÓDULO 5: ADESÃO AO DOMÍNIO ACTIVE DIRECTORY
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%-

mod5_adjoin() {

    show_banner() {
        echo ""
        echo ""
        echo "    ===================================================================================="
        echo "        >> ETAPA 5/9: ADESÃO AO DOMÍNIO ACTIVE DIRECTORY"
        echo "    ------------------------------------------------------------------------------------"
        echo "           Ingressando o servidor no domínio: $AD_DOMAIN"
        echo "    ===================================================================================="
        echo ""
        echo ""
    }

    clear
    show_banner
    sleep 2

    # Coleta de dados do servidor
    local hostname_full os_description
    hostname_full=$(hostname -f)

    if [[ -f /etc/os-release ]]; then
        os_description=$(grep ^PRETTY_NAME= /etc/os-release | cut -d= -f2 | tr -d '"')
    else
        os_description="Desconhecido"
    fi

    # -------------------------------------------------------------------------
    # Etapa 1: Exibição de detalhes
    # -------------------------------------------------------------------------
    echo "    [*] Detalhes da Adesão:"
    echo "        Active Directory.............. : $AD_DOMAIN"
    echo "        Kerberos do AD................ : $AD_REALM"
    echo "        Conta do AD................... : $AD_ACCOUNT"
    echo "        Grupo de Sudoers.............. : $AD_GROUP"
    echo "        Nome do servidor.............. : $hostname_full"
    echo "        Versão do sistema operacional  : $os_description"
    echo "----------------------------------------------------------------------------"
    sleep 2

    # -------------------------------------------------------------------------
    # Etapa 1.1: Diagnóstico do domínio
    # -------------------------------------------------------------------------
    echo "    [*] Executando diagnóstico do domínio com 'realm discover'..."
    if ! realm discover "$AD_DOMAIN"; then
        echo "    [X] ERRO: Não foi possível descobrir o domínio '$AD_DOMAIN'."
        echo "        Verifique conectividade, DNS e nome do domínio."
        return 1
    fi
    sleep 2

    # Confirmação interativa
    while true; do
        read -rp "    Deseja prosseguir com o Realm Join? (s/n): " PROSSEGUIR
        PROSSEGUIR=$(echo "$PROSSEGUIR" | tr '[:upper:]' '[:lower:]')
        case "$PROSSEGUIR" in
            s)
                echo "    Prosseguindo para a inserção de credenciais..."
                sleep 1.5
                break
                ;;
            n)
                echo "    Operação cancelada pelo usuário."
                return 1
                ;;
            *)
                echo "    Entrada inválida. Use 's' para sim ou 'n' para não."
                ;;
        esac
    done

    # -------------------------------------------------------------------------
    # Etapa 2: Coleta da senha de forma segura
    # -------------------------------------------------------------------------
    local AD_PASS1_LOCAL AD_PASS2_LOCAL

    while true; do
        clear; show_banner
        echo "    ============================================================================="
        echo "        Validação da senha para a conta: $AD_ACCOUNT"
        echo "    ============================================================================="
        read -s -p "        Insira a senha...... : " AD_PASS1_LOCAL; echo
        read -s -p "        Confirme a senha.... : " AD_PASS2_LOCAL; echo

        if [[ "$AD_PASS1_LOCAL" != "$AD_PASS2_LOCAL" ]]; then
            echo -e "\n        [X] As senhas não coincidem. Tente novamente."
            unset AD_PASS1_LOCAL AD_PASS2_LOCAL
            sleep 2
            continue
        fi

        echo -e "\n        [!] Senha validada localmente. Prosseguindo..."
        sleep 1
        break
    done

    # ------------------------------------------------------------------------------------------
    # Etapa 3: Geração do arquivo /etc/realmd.conf
    # ------------------------------------------------------------------------------------------
    echo "    [*] Gerando arquivo /etc/realmd.conf com dados do sistema operacional..."

    if [[ -f /etc/os-release ]]; then
        OS_NAME=$(grep ^NAME= /etc/os-release | cut -d= -f2- | tr -d '"')
        OS_VERSION=$(grep ^VERSION= /etc/os-release | cut -d= -f2- | tr -d '"')
    else
        OS_NAME="Desconhecido"
        OS_VERSION="Desconhecido"
    fi

    if ! sudo tee /etc/realmd.conf > /dev/null <<EOF
[active-directory]
default-client = sssd
os-name = ${OS_NAME}
os-version = ${OS_VERSION}
EOF
    then
        echo "    [X] ERRO: Falha ao criar o arquivo /etc/realmd.conf."
        echo "        Verifique permissões ou problemas de disco."
        return 1
    else
        echo "    [!] Arquivo /etc/realmd.conf criado com sucesso!"
    fi

    sleep 1

    # -------------------------------------------------------------------------
    # Etapa 4: Execução do 'realm join'
    # -------------------------------------------------------------------------
    clear
    show_banner
    echo ""
    echo "    [*] Realizando 'realm join'..."
    sleep 1.5

    if echo "$AD_PASS1_LOCAL" | sudo realm join --user="$AD_ACCOUNT" "$AD_DOMAIN"; then
        echo "    [!] Ingressado no domínio com sucesso."
        sleep 1
    else
        echo "    [X] ERRO: Falha ao ingressar no domínio AD."
        echo "        Verifique a senha, permissões e 'journalctl -xeu realmd'."
        unset AD_PASS1_LOCAL AD_PASS2_LOCAL
        sleep 3
        return 1
    fi

    # -------------------------------------------------------------------------
    # Etapa 5: Restrições e permissões via realm
    # -------------------------------------------------------------------------
    echo "    [*] Aplicando políticas de acesso ao domínio..."
    if sudo realm deny --all && sudo realm permit -g "$AD_GROUP"; then
        echo "    [!] Apenas o grupo '$AD_GROUP' está autorizado a logar via AD."
    else
        echo "    [X] Aviso: Falha ao aplicar as restrições de grupo."
        echo "        A adesão foi feita, mas revise as permissões manualmente."
        unset AD_PASS1_LOCAL AD_PASS2_LOCAL
        sleep 3
        return 1
    fi

    unset AD_PASS1_LOCAL AD_PASS2_LOCAL

    echo "-----------------------------------------------------------------------------"
    echo "    [!] SUCESSO: Servidor agora é membro do domínio."
    echo "-----------------------------------------------------------------------------"
    return 0
mod_next
}
# mod5_adjoin



# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# Módulo6 – Otimização do SSSD e Melhorias de Login
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod6_sssdoptimal() {
    show_banner() {
        echo ""
        echo "    ===================================================================================="
        echo "        >> ETAPA 6/9: OTIMIZAÇÃO DO SSSD E MELHORIAS DE LOGIN"
        echo "    ===================================================================================="
        echo ""
    }

    clear
    show_banner
    sleep 1

    local sssd_conf_file="/etc/sssd/sssd.conf"
    local timestamp
    timestamp=$(date +"%Y_%m_%d_%Hh%M")
    local backup_file="${sssd_conf_file}.${timestamp}.bak"

    if [[ ! -f "$sssd_conf_file" ]]; then
        echo "    [X] Arquivo $sssd_conf_file não encontrado!"
        return 1
    fi

    echo "    [*] Criando backup: $backup_file"
    sudo cp "$sssd_conf_file" "$backup_file" || {
        echo "    [X] Falha ao criar backup!"
        return 1
    }

    echo "    [*] Parando o serviço sssd..."
    sudo systemctl stop sssd &>/dev/null

    echo "    [*] Ajustando configurações em: $sssd_conf_file"
    sleep 1

    # Substituir 'use_fully_qualified_names = True' por 'False'
    sudo sed -i 's/^[[:space:]]*use_fully_qualified_names[[:space:]]*=[[:space:]]*True/use_fully_qualified_names = False/' "$sssd_conf_file"

    # Garante que só exista uma linha correta de 'enumerate = False'
    echo "    [*] Garantindo configuração única: 'enumerate = False'"
    sudo sed -i '/^[[:space:]]*enumerate[[:space:]]*=/d' "$sssd_conf_file"
    sudo sed -i '/^\[domain\//a enumerate = False' "$sssd_conf_file"

    echo "    [*] Definindo permissões de segurança (600)..."
    sudo chmod 600 "$sssd_conf_file"

    echo "    [*] Validando sintaxe do sssd.conf via reinício do serviço..."
    sudo systemctl daemon-reexec 2>/dev/null

    if sudo systemctl restart sssd; then
        echo "    [✓] Serviço sssd reiniciado com sucesso — arquivo válido."
    else
        echo "    [X] ERRO: Falha ao reiniciar o serviço sssd."
        echo "        ➤ Verifique o conteúdo do arquivo e use: journalctl -xe | grep sssd"
        echo "        ➤ Restaure o backup com:"
        echo "            sudo cp '$backup_file' '$sssd_conf_file' && sudo chmod 600 '$sssd_conf_file'"
        return 1
    fi

    echo "    [*] Verificando status final do serviço..."
    if systemctl is-active --quiet sssd; then
        echo "    [✓] O serviço sssd está ativo e funcional."
    else
        echo "    [X] Atenção: o serviço sssd não está ativo após a modificação."
        return 1
    fi

    echo "    ------------------------------------------------------------------------"
    echo "        [!] Login simplificado ativado (ssh usuario@host)"; sleep 0.5
    echo "        [!] Cache habilitado para logins offline"; sleep 0.5
    echo "        [!] Diretórios home serão criados automaticamente"; sleep 0.5
    echo "        [!] Enumerar usuários do AD está desativado (enumerate = False)"; sleep 0.5
    echo "    ------------------------------------------------------------------------"
    return 0
mod_next
}
# mod6_sssdoptimal


# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# Módulo 7 – Homedir / PAM
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
mod7_pam_homedir() {

    show_banner() {
        echo ""
        echo "============================================================================="
        echo "    >> ETAPA 7/9: CONFIGURAÇÃO DE CRIAÇÃO AUTOMÁTICA DE HOME DIR (PAM)"
        echo "============================================================================="
        echo ""
        echo ""
    }

    clear
    show_banner
    sleep 2

    local PAM_SESSION_FILE="/etc/pam.d/common-session"
    local MKHOMEDIR_RULE="session required pam_mkhomedir.so skel=/etc/skel umask=0022"

    echo "    [*] Arquivo PAM alvo: $PAM_SESSION_FILE"; sleep 0.5
    sleep 1
    echo "    [*] Regra a ser garantida: $MKHOMEDIR_RULE"; sleep 0.5
    sleep 1

    # Remove qualquer linha anterior que contenha pam_mkhomedir.so
    if grep -q "pam_mkhomedir.so" "$PAM_SESSION_FILE"; then
        echo "    [*] Removendo entradas antigas de pam_mkhomedir.so..."
        sudo sed -i '/pam_mkhomedir.so/d' "$PAM_SESSION_FILE"
        sleep 1
    fi

    # Insere a regra correta após a linha de pam_unix.so
    echo "    [*] Inserindo a regra após 'pam_unix.so'..."
    if sudo sed -i "/^session.*required.*pam_unix.so/a $MKHOMEDIR_RULE" "$PAM_SESSION_FILE"; then
        echo "    [✓] Regra pam_mkhomedir.so inserida com sucesso."; sleep 0.5
    else
        echo "    [X] ERRO: Falha ao inserir a regra no arquivo PAM. Verifique permissões."; sleep 4
        return 1
    fi

    echo "    [✓] Módulo pam_mkhomedir.so configurado corretamente."; sleep 0.5
    echo "    [✓] Usuários do AD terão seus diretórios home criados automaticamente."; sleep 0.5
    echo "    [*] Recomenda-se testar login e sudo com uma conta do AD."; sleep 0.5
    return 0
mod_next
}
# mod7_pam_homedir



# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# MÓDULO 8: CONFIGURAÇÃO DE ACESSO SUDO PARA GRUPO AD
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod8_adsudo() {

    show_banner() {
        echo ""
        echo ""
        echo "    ============================================================================="
        echo "        >> ETAPA 8/9: PERMISSÃO ADMIN PARA GRUPO DO AD - ACESSO SUDO."
        echo "    ============================================================================="
        echo ""
        echo ""
    }

    clear
    show_banner
    sleep 2

    # Variáveis de configuração
    local ad_group="$AD_GROUP"
    local sudoers_pathfile="/etc/sudoers.d/99_$ad_group"
	local sudoers_99file="99_$ad_group"
    local admin_group="%$ad_group"
    local sudo_rule="$admin_group ALL=(ALL) ALL"
	
	export sudoers_pathfile sudoers_99file

    echo "    [*] Grupo AD a receber permissão sudo: $ad_group"; sleep 0.5
    echo "    [*] Arquivo de regra sudoers: $sudoers_pathfile"; sleep 0.5
    echo "    [*] Regra a ser aplicada: $sudo_rule"; sleep 0.5
    

    # Conteúdo do arquivo sudoers temporário
    local temp_sudoers_pathfile="/tmp/ad_sudo_temp"
    cat <<EOF > "$temp_sudoers_pathfile"
# Permite que membros do grupo AD tenham acesso sudo completo.
# Este arquivo é gerenciado pelo script de integração AD.
# Regra: %GRUPO_AD ALL=(ALL) ALL
$sudo_rule
EOF

    chmod 440 "$temp_sudoers_pathfile"

    echo "    [*] Validando a sintaxe da regra sudo com 'visudo -c'..."

    if sudo visudo -c -f "$temp_sudoers_pathfile"; then
        echo "    [!] Validação de sintaxe APROVADA."; sleep 0.5
        sudo mv "$temp_sudoers_pathfile" "$sudoers_pathfile"
        sudo chmod 440 "$sudoers_pathfile"
        echo "    [!] Regra aplicada com sucesso em $sudoers_pathfile."; sleep 0.5
    else
        echo "    [X] ERRO CRÍTICO: A validação de sintaxe da regra falhou!"; sleep 0.5
        echo "    [X] A regra sudo NÃO foi aplicada. Verifique nome do grupo e permissões."; sleep 0.5
        rm -f "$temp_sudoers_pathfile"
        sleep 2
        return 1
    fi

    echo "    --------------------------------------------------------------------"
    echo "        [!] Membros do grupo '$ad_group' agora têm acesso sudo COMPLETO."
    echo "    --------------------------------------------------------------------"
mod_next
}
#mod8_adsudo


# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# Módulo 9 – Checklist Final de Verificação
# %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

mod9_checklist() {
    clear
    echo ""
    echo ""
    echo "    ===================================================================================="
    echo "        >> ETAPA 9/9: CHECKLIST FINAL DE VERIFICAÇÃO DA INTEGRAÇÃO"
    echo "    ===================================================================================="
    echo ""
    echo ""
    sleep 2

    local PASSOS_OK=0
    local PASSOS_TOTAL=9
	

    echo "    [*] Iniciando verificação final..."
    sleep 1

    # 1. Verifica se está unido ao domínio
    echo -n "    [1/9] Verificando se o sistema está unido ao domínio... "
    if realm list | grep -q "$AD_DOMAIN"; then
        echo "[✓]"
        ((PASSOS_OK++))
    else
        echo "[X] NÃO UNIDO"
    fi
    sleep 0.5
	
	
    # 2. Verifica se o sssd está ativo
    echo -n "    [2/9] Verificando se o serviço sssd está ativo... "
    if systemctl is-active --quiet sssd; then
        echo "[✓]"
        ((PASSOS_OK++))
    else
        echo "[X] INATIVO"
    fi
	sleep 0.5

    # 3. Verifica regra sudoers
    echo -n "    [3/9] Verificando regra sudo para o grupo $AD_GROUP... "

    # Corrige/recupera caminho do arquivo se não estiver disponível
    if [[ -z "$sudoers_pathfile" ]]; then
        sudoers_pathfile="/etc/sudoers.d/99_${AD_GROUP}"
    fi

    if [[ -f "$sudoers_pathfile" ]] && grep -q "%$AD_GROUP" "$sudoers_pathfile"; then
        echo "[✓]"
        ((PASSOS_OK++))
    else
        echo "[X] NÃO ENCONTRADA"
    fi
	sleep 0.5


    # 4. Testa consulta a usuário AD
    echo -n "    [4/9] Verificando consulta com 'id $AD_ACCOUNT'... "
    if id "$AD_ACCOUNT" &>/dev/null || getent passwd "$AD_ACCOUNT" &>/dev/null; then
        echo "[✓]"
        ((PASSOS_OK++))
    else
        echo "[X] FALHOU"
    fi


    # 5. Verifica sssd.conf domínio
    echo -n "    [5/9] Verificando entrada no sssd.conf... "
    if grep -q "domain/$AD_DOMAIN" /etc/sssd/sssd.conf; then
        echo "[✓]"
        ((PASSOS_OK++))
    else
        echo "[X] AUSENTE"
    fi
	sleep 0.5

    # 6. Serviços principais ativos
    for svc in realmd sssd chrony; do
        echo -n "    [6/9] Verificando serviço $svc... "
        if systemctl is-active --quiet "$svc"; then
            echo "[✓]"
            ((PASSOS_OK++))
        else
            echo "[X] INATIVO"
        fi
    done
	sleep 0.5

    # 7. Verifica sincronização NTP
    echo -n "    [7/9] Verificando status NTP (chronyc tracking)... "
    if chronyc tracking | grep -q "Reference ID"; then
        echo "[✓]"
        ((PASSOS_OK++))
    else
        echo "[X] FALHOU"
    fi
	sleep 0.5

    echo ""
    echo "    ========================================================================="
    echo "    CHECKLIST FINAL: $PASSOS_OK de $PASSOS_TOTAL itens validados com sucesso."
    echo "    ========================================================================="

    if [[ "$PASSOS_OK" -eq "$PASSOS_TOTAL" ]]; then
        echo "    [✓] Integração concluída com SUCESSO! O servidor está pronto para uso."
    else
        echo "    [X] Falhas detectadas. Recomenda-se revisar os módulos anteriores."
    fi
	sleep 0.5
    return 0
mod_next
}

# mod9_checklist

# sssctl user-checks -a acct -s sudo weverton

# -------------------------------------------------------------------------
# 2. FLUXO PRINCIPAL DO SCRIPT (main)
# -------------------------------------------------------------------------
main() {
    mod1_banner        || exit 1
    mod2_install       || exit 1
    mod3_adinfo        || exit 1
    mod4_timedrift     || exit 1
    mod5_adjoin        || exit 1
    mod6_sssdoptimal   || exit 1
    mod7_pam_homedir   || exit 1
    mod8_adsudo        || exit 1
    mod9_checklist     || exit 1
}

# -------------------------------------------------------------------------
# 3. EXECUÇÃO DO SCRIPT
# -------------------------------------------------------------------------
main
