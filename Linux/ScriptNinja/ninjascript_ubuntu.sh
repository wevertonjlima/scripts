!/bin/bash

# =====================================================================
# Filename: LinuxNinjaTweak.sh 
# Funcao: Script de ajustes no Ubuntu Server (apenas para Laboratorio)
# Created by: Weverton Lima <wevertonjlima@gmail.com>
# Powered IA by: ChatGPT IA Agent Linux Server Expert
# Date: 2025-10-06 14h23 America/Maceio
# Compatibilidade: Ubuntu 22.04 / 24.04 / 24.10
# =====================================================================

main_banner() {
    clear
    cat <<'EOF'

    ===============================================
         NINJA SCRIPT LINUX
    ===============================================
	
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
    
    echo "${YELLOW}[1/6] Verificando dependencias...${RESET}"
    if ! command -v ss >/dev/null; then
        apt-get update -qq && apt-get install -y -qq iproute2
    fi
    
    echo "${YELLOW}[2/6] Criando aliases globais...${RESET}"
    ALIASES_FILE="/etc/bash.bashrc"
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
    
    echo "${YELLOW}[3/6] Ajustando timeout do sudo para 120 minutos...${RESET}"
    SUDOERS_TIMEOUT_FILE="/etc/sudoers.d/timeout"
    if [[ ! -f "$SUDOERS_TIMEOUT_FILE" ]]; then
        echo "Defaults timestamp_timeout=120" > "$SUDOERS_TIMEOUT_FILE"
        chmod 440 "$SUDOERS_TIMEOUT_FILE"
    fi
    
    echo "${YELLOW}[4/6] Permitindo nomes de usuario com ponto...${RESET}"
    sed -i 's/^NAME_REGEX.*/NAME_REGEX="^[a-z][-a-z0-9_.]*$"/' /etc/adduser.conf
    
    echo "${YELLOW}[5/6] Desativando IPv6 via GRUB...${RESET}"
    GRUB_FILE="/etc/default/grub"
    if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_FILE"; then
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash ipv6.disable=1"/' "$GRUB_FILE"
        update-grub
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
