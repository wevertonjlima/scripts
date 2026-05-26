#!/usr/bin/env bash

# =====================================================================
# Filename: LinuxNinjaTweak.sh 
# Funcao: Script de ajustes no Oracle Linux Server (apenas para Laboratorio)
# Created by: Weverton Lima <wevertonjlima@gmail.com>
# Powered IA by: Morgana Linux Server Expert
# Date: 2025-10-06 14h23 America/Maceio
# Compatibilidade: Oracle Linux 9.7 (RHEL-based)
#
# LOG DE ALTERACOES:
# 2026-05-26 - Morgana: Ajuste estrutural, correcao do escopo de funcoes
#                      e implementacao da checagem para a familia Red Hat.
# =====================================================================

# --- [0] METADADOS E VERSAO ---
SCRIPT_VERSION="1.1.0"

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
       Versao RedHat Compativel
EOF
    printf "%s\n\n" "Carregando ..."
    sleep 2
}

# --- [4] FUNCAO DE VALIDACAO DE SISTEMA OPERACIONAL (RED HAT FAMILY) ---
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

    # Valida se o sistema e Oracle Linux, RHEL, CentOS, Rocky ou AlmaLinux
    if [[ "${os_id}" != "ol" && "${os_id}" != "rhel" && "${os_id}" != "centos" && "${os_id}" != "rocky" && "${os_id}" != "almalinux" && ! "${os_like}" =~ "rhel" && ! "${os_like}" =~ "centos" ]]; then
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
        echo "Este script precisa ser executado como root (sudo)."
        exit 1
    fi
}

# --- [7] AJUSTES E LOGICA DO LABORATORIO ---
main_tweak() {
    echo "Sistema operacional compativel da familia Red Hat / Oracle Linux detectado."
    echo "Dando inicio aos procedimentos de tweak do laboratortio..."
    echo ""
    
    # Insira seus comandos de ajuste de kernel, rede ou pacotes a partir daqui
    # Exemplo: sysctl -p, dnf update, etc.
}

# --- [8] EXECUCAO DO FLUXO PRINCIPAL ---
main() {
    main_banner
    check_root
    check_os_compatibility
    main_tweak
}

# Gatilho inicial do script passando argumentos se necessario
main "$@"
