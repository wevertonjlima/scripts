#!/bin/bash

# =====================================================================
# Filename: LinuxNinjaTweak.sh 
# Funcao: Script de ajustes no Oracle Linux Server (apenas para Laboratorio)
# Created by: Weverton Lima <wevertonjlima@gmail.com>
# Powered IA by: ChatGPT IA Agent Linux Server Expert
# Date: 2025-10-06 14h23 America/Maceio
# Compatibilidade: Oracle Linux 9.7 (RHEL-based)
# =====================================================================

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
EOF
    printf "%s\n\n" "Carregando ..."
    sleep 2
}

main_tweak() {
    set -euo pipefail
    
    GREEN=$(tput setaf 2)
    RED=$(tput setaf 1)
    YELLOW=$(tput setaf 3)
    RESET=$(tput sgr0)
    
    if [[ "$(id -u)" -ne 0 ]]; then
        echo "${RED}[ERRO] Este script deve ser executado com sudo/root.${RESET}"
        exit 1
    fi
    
    echo "${YELLOW}[1/5] Verificando dependencias...${RESET}"
    if ! command -v ss >/dev/null; then
        dnf install -y -q iproute
    fi
    
    echo "${YELLOW}[2/5] Criando aliases globais...${RESET}"
    ALIASES_FILE="/etc/bashrc"
    declare -A ALIASES=(
        [cls]="clear"
        [dirr]="ls -lsha"
        [services]="systemctl list-units --type=service --all --no-pager"
        [firewall-listen]="sudo ss -tuln state listening"
    )
    for alias in "${!ALIASES[@]}"; do
        if ! grep -Eq "^[[:space:]]*alias[[:space:]]+$alias=" "$ALIASES_FILE"; then
            echo "alias $alias='${ALIASES[$alias]}'" >> "$ALIASES_FILE"
        fi
    done
    
    echo "${YELLOW}[3/5] Ajustando timeout do sudo para 120 minutos...${RESET}"
    SUDOERS_TIMEOUT_FILE="/etc/sudoers.d/timeout"
    if [[ ! -f "$SUDOERS_TIMEOUT_FILE" ]]; then
        echo "Defaults timestamp_timeout=120" > "$SUDOERS_TIMEOUT_FILE"
        chmod 440 "$SUDOERS_TIMEOUT_FILE"
    fi
    
    echo "${YELLOW}[4/5] Desativando IPv6 via GRUB...${RESET}"
    GRUB_FILE="/etc/default/grub"
    if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE"; then
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash ipv6.disable=1"/' "$GRUB_FILE"
        grub2-mkconfig -o /boot/grub2/grub.cfg
    fi
    
    echo "${YELLOW}[5/5] Limpando cache de comandos...${RESET}"
    hash -r
    
    echo "-----------------------------------------------------------"
    echo "Script Finalizado:"
    echo "-----------------------------------------------------------"
    sleep 0.5; echo "${GREEN}[OK]${RESET} - Aliases criados: cls, dirr, firewall-listen, services."
    sleep 0.5; echo "${GREEN}[OK]${RESET} - Timeout do sudo ajustado para 120 minutos."
    sleep 0.5; echo "${GREEN}[OK]${RESET} - IPv6 desativado via GRUB."
    sleep 0.5; echo "${GREEN}[OK]${RESET} - Dependencias verificadas e satisfeitas."
    echo "-----------------------------------------------------------"
    
    read -rp "Deseja reiniciar o servidor agora? [S/N]: " resposta
    resposta=${resposta^^}
    
    if [[ "$resposta" == "S" ]]; then
        echo "${YELLOW}[INFO] Reiniciando o sistema...${RESET}"
        reboot
    else
        echo "${YELLOW}[INFO] Por favor, reinicie o sistema manualmente.${RESET}"
    fi
}

main_banner
main_tweak "$@"