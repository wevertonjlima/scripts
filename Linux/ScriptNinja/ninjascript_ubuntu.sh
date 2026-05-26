#!/usr/bin/env bash

# =====================================================================
# Filename: LinuxNinjaTweak.sh 
# Funcao: Script de ajustes no Ubuntu Server (apenas para Laboratorio)
# Created by: Weverton Lima <wevertonjlima@gmail.com>
# Powered IA by: Morgana Linux Server Expert
# Date: 2025-10-06 14h23 America/Maceio
# Compatibilidade: Ubuntu 22.04 / 24.04 / 24.10
#
# LOG DE ALTERACOES:
# 2026-05-26 - Morgana: Padronizacao do fluxo principal, tratamento de 
#                      excecoes de ambiente e integracao do novo banner.
# =====================================================================

# --- [0] METADADOS E VERSAO ---
SCRIPT_VERSION="1.2.0"

# --- [1] CONFIGURACOES DE SEGURANCA ---
set -euo pipefail

# --- [2] CORES E ARTIFACTS VISUAIS (TTY COMPATIBLE) ---
# \e[1;31m -> Vermelho Light/Bold | \e[0m -> Reset
RED_LIGHT="\e[1;31m"
NC="\e[0m"

# --- [3] BANNER DE APRESENTACAO ---
main_banner() {
    clear
    cat <<'EOF'

    ===============================================================                  
          _   _ _       _         _      _                 
         | \ | (_)     (_)       | |    (_)                 
         |  \| |_ _ __  _  __ _  | |     _ _ __  _   ___  __
         | . ` | | '_ \| |/ _` | | |    | | '_ \| | | \ \/ /
         | |\  | | | | | | (_| | | |____| | | | | |_| |>  < 
         |_|_\_|_|_| |_| |\__,_| |______|_|_| |_|\__,_/_/\_\
          / ____|     _/ |(_)     | |                       
         | (___   ___|__/_ _ _ __ | |_                      
          \___ \ / __| '__| | '_ \| __|                     
          ____) | (__| |  | | |_) | |_                      
         |_____/ \___|_|  |_| .__/ \__|                     
                            | |                             
                            |_|                                                                     
    ===============================================================
       Versao Ubuntu Linux Compativel
EOF
    printf "%s\n\n" "Carregando ..."
    sleep 2
}

# --- [4] FUNCAO DE VALIDACAO DE SISTEMA OPERACIONAL (DEBIAN/UBUNTU) ---
check_os_compatibility() {
    # Verifica a existencia do arquivo de identificacao padrao POSIX
    if [ ! -f /etc/os-release ]; then
        show_error_and_exit
    fi

    # Extrai o ID e os IDs de derivacao (ID_LIKE) do arquivo
    local os_id
    local os_like
    os_id=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    os_like=$(grep -E '^ID_LIKE=' /etc/os-release | cut -d= -f2 | tr -d '"' || echo "")

    # Valida se o sistema e Ubuntu, Debian ou derivado direto deles
    if [[ "${os_id}" != "ubuntu" && "${os_id}" != "debian" && ! "${os_like}" =~ "ubuntu" && ! "${os_like}" =~ "debian" ]]; then
        show_error_and_exit
    fi
}

# --- [5] FUNCAO DE EXIBICAO DE ERRO (DIRETRIZ 5 - SEM ACENTOS) ---
show_error_and_exit() {
    echo -e "${RED_LIGHT}"
    echo "==========================================================="
    echo "                                  ERROR !                  "
    echo "                                                           "
    echo "                  Voce esta executando este script         "
    echo "          em um sistema operacional incompativel.          "
    echo "==========================================================="
    echo -e "${NC}"
    exit 1
}

# --- [6] VALIDACAO DE PRIVILEGIOS ---
check_root() {
    if [ "${EUID}" -ne 0 ]; then
        # Variavel local fallback caso o tput falhe ou nao possua TTY
        echo -e "${RED_LIGHT}[ERRO] Este script deve ser executado com sudo/root.${NC}"
        exit 1
    fi
}

# --- [7] LOGICA DE AJUSTES (TWEAKS) ---
main_tweak() {
    # Inicializacao de variaveis de cor locais via tput para o escopo interno
    local GREEN
    local RED
    local YELLOW
    local RESET
    
    GREEN=$(tput setaf 2)
    RED=$(tput setaf 1)
    YELLOW=$(tput setaf 3)
    RESET=$(tput sgr0)
    
    echo "${YELLOW}[1/6] Verificando dependencias...${RESET}"
    if ! command -v ss >/dev/null; then
        apt-get update -qq && apt-get install -y -qq iproute2
    fi
    
    echo "${YELLOW}[2/6] Criando aliases globais...${RESET}"
    local ALIASES_FILE="/etc/bash.bashrc"
    
    # Declaracao explicita do mapa de aliases
    declare -A ALIASES=(
        [cls]="clear"
        [dirr]="ls -lsha"
        [services]="systemctl list-units --type=service --all --no-pager"
        [firewall-listen]="sudo ss -tuln state listening"
    )
    
    local alias
    for alias in "${!ALIASES[@]}"; do
        if ! grep -Eq "^[[:space:]]*alias[[:space:]]+$alias=" "$ALIASES_FILE"; then
            echo "alias $alias='${ALIASES[$alias]}'" >> "$ALIASES_FILE"
        fi
    done
    
    echo "${YELLOW}[3/6] Ajustando timeout do sudo para 120 minutos...${RESET}"
    local SUDOERS_TIMEOUT_FILE="/etc/sudoers.d/timeout"
    if [[ ! -f "$SUDOERS_TIMEOUT_FILE" ]]; then
        echo "Defaults timestamp_timeout=120" > "$SUDOERS_TIMEOUT_FILE"
        chmod 440 "$SUDOERS_TIMEOUT_FILE"
    fi
    
    echo "${YELLOW}[4/6] Permitindo nomes de usuario com ponto...${RESET}"
    if [ -f /etc/adduser.conf ]; then
        sed -i 's/^NAME_REGEX.*/NAME_REGEX="^[a-z][-a-z0-9_.]*$"/' /etc/adduser.conf
    fi
    
    echo "${YELLOW}[5/6] Desativando IPv6 via GRUB...${RESET}"
    local GRUB_FILE="/etc/default/grub"
    if [ -f "$GRUB_FILE" ]; then
        if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE"; then
            sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash ipv6.disable=1"/' "$GRUB_FILE"
            update-grub
        fi
    fi
    
    echo "${YELLOW}[6/6] Limpando cache de comandos...${RESET}"
    hash -r
    
    echo "-----------------------------------------------------------"
    echo "Script Finalizado:"
    echo "-----------------------------------------------------------"
    sleep 0.5; echo "${GREEN}[OK]${RESET} - Aliases criados: cls, dirr, firewall-listen, services."
    sleep 0.5; echo "${GREEN}[OK]${RESET} - Timeout do sudo ajustado para 120 minutos."
    sleep 0.5; echo "${GREEN}[OK]${RESET} - Permitido nomes de usuarios com ponto."
    sleep 0.5; echo "${GREEN}[OK]${RESET} - IPv6 desativado via GRUB."
    sleep 0.5; echo "${GREEN}[OK]${RESET} - Dependencias verificadas e satisfeitas."
    echo "-----------------------------------------------------------"
    
    # Interacao do usuario estruturada sem acentuacao (Diretriz 5)
    local resposta
    read -rp "Deseja reiniciar o servidor agora? [S/N]: " resposta
    resposta=${resposta^^}
    
    if [[ "$resposta" == "S" ]]; then
        echo "${YELLOW}[INFO] Reiniciando o sistema...${RESET}"
        reboot
    else
        echo "${YELLOW}[INFO] Por favor, reinicie o sistema manualmente.${RESET}"
    fi
}

# --- [8] EXECUCAO DO FLUXO PRINCIPAL ---
main() {
    main_banner
    check_root
    check_os_compatibility
    main_tweak "$@"
}

main "$@"
