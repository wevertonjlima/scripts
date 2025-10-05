#!/bin/bash
#
# ============================================================================
# Nome do Arquivo: AD-pam-makehomedir.bash
# IA Generated: Sim (ChatGPT - OpenAI)
# Data de Geração: 03/10/2025
# ============================================================================
#
# README:
# --------
# Este script garante que o módulo PAM `pam_mkhomedir.so` esteja configurado
# no arquivo `/etc/pam.d/common-session`, permitindo que diretórios home dos
# usuários sejam criados automaticamente no primeiro login (ex: SSH).
#
# Também adiciona suporte opcional ao `oddjobd` (se disponível no sistema),
# ativando-o e iniciando-o automaticamente.
#
# Uso:
# ----
# 1. Salve este script como `garantir_pam_mkhomedir.sh`
# 2. Torne-o executável:
#       chmod +x garantir_pam_mkhomedir.sh
# 3. Execute:
#       ./garantir_pam_mkhomedir.sh
#
# ============================================================================
# Script
# ============================================================================

garantir_pam_mkhomedir() {
  local PAM_COMMON_SESSION="/etc/pam.d/common-session"

  echo "[*] Garantindo pam_mkhomedir no $PAM_COMMON_SESSION..."

  # Adiciona pam_mkhomedir.so se não existir
  if ! grep -q 'pam_mkhomedir\.so' "$PAM_COMMON_SESSION"; then
    echo "session required pam_mkhomedir.so skel=/etc/skel umask=0022" | sudo tee -a "$PAM_COMMON_SESSION" >/dev/null
    echo "[*] Linha pam_mkhomedir.so adicionada."
  else
    echo "[*] pam_mkhomedir.so já está configurado."
  fi

  # Se oddjobd estiver presente, adiciona suporte opcional
  if grep -q 'oddjobd' /etc/services 2>/dev/null; then
    if ! grep -q 'pam_oddjob_mkhomedir\.so' "$PAM_COMMON_SESSION"; then
      echo "session optional pam_oddjob_mkhomedir.so skel=/etc/skel umask=0022" | sudo tee -a "$PAM_COMMON_SESSION" >/dev/null
      echo "[*] Linha pam_oddjob_mkhomedir.so adicionada (opcional)."
    fi
    sudo systemctl enable oddjobd >/dev/null 2>&1 || true
    sudo systemctl start oddjobd  >/dev/null 2>&1 || true
  fi

  echo "[*] Configuração concluída."
}

# Executa automaticamente a função ao chamar o script
garantir_pam_mkhomedir
