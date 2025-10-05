#!/bin/bash

# =========================================================
# Script de integracao Ubuntu com Active Directory via SSSD
# =========================================================

LOGFILE="/var/log/join_ad.log"
exec > >(tee -a "$LOGFILE") 2>&1

PAM_COMMON_SESSION="/etc/pam.d/common-session"

backup_file() {
  local file="$1"
  if [[ -f "$file" && ! -f "$file.bkp" ]]; then
    sudo cp "$file" "$file.bkp"
  fi
}

LOG() {
  echo "[INFO] $1"
}

clear
echo "=============================================================================="
echo "                -----------------------------------------------"
echo "                Integracao Ubuntu com Active Directory via SSSD"
echo "                -----------------------------------------------"
echo ""
echo "           Em qualquer momento digite Ctrl+C , para abortar o script."
echo "=============================================================================="
read -rp "Deseja prosseguir ? (s/n): " PROSSEGUIR
[[ "$PROSSEGUIR" != "s" ]] && echo "Saindo..." && exit 1


echo ""
echo ""
# ========================================================="
# 1) Instalar pacotes"
# ========================================================="
LOG "Atualizando sistema e instalando pacotes necessarios..."
sudo apt update -q -y
sudo DEBIAN_FRONTEND=noninteractive apt install -y -q \
  realmd sssd sssd-tools libnss-sss libpam-sss adcli \
  samba-common-bin oddjob oddjob-mkhomedir packagekit chrony krb5-user

echo ""
echo ""
# ========================================================="
# 2) Credenciais  (ex: billgates@microsoft.com)"
# ========================================================="
echo " Insira as credenciais (ex: billgates@microsoft.com)"
echo ""
echo ""
read -e -p "Digite o dominio (ex: microsoft.com): " AD_DOMAIN
echo ""
read -e -p "Digite o usuario (ex: billgates)    : " AD_USER
echo ""

while true; do
  read -rsp "Digite a senha  : " AD_PASS1
  echo
  read -rsp "Confirme a senha: " AD_PASS2
  echo
  if [[ "$AD_PASS1" != "$AD_PASS2" ]]; then
    echo "[ERRO] As senhas nao conferem. Tente novamente."
  else
    break
  fi
done

# Converter dominio para maiusculas
AD_DOMAIN_CAPS=${AD_DOMAIN^^}

# =========================================================
# 3) Validacao de credenciais
# =========================================================
LOG "Validando credenciais do AD com kinit..."
echo "$AD_PASS1" | kinit "$AD_USER@$AD_DOMAIN_CAPS"
if [[ $? -ne 0 ]]; then
  echo ""
  echo "=============================================================================="
  echo "[ERRO] Nao foi possivel validar as credenciais fornecidas."
  echo "Por favor, insira um usuario e senha validos, ou tecle CTRL+C para encerrar."
  echo "=============================================================================="
  echo ""
  exit 1
fi
LOG "Credenciais validadas com sucesso!"
kdestroy

# =========================================================
# 4) Controladores de dominio para NTP
# =========================================================
echo ""
read -e -p "Digite o nome do controlador dominio Primario   : " AD_DC1
read -e -p "Digite o nome do controlador dominio Secundario : " AD_DC2
echo ""

LOG "Configurando NTP..."
backup_file "/etc/chrony/chrony.conf"
sudo sed -i 's/^pool/#pool/g' /etc/chrony/chrony.conf
echo "server $AD_DC1.$AD_DOMAIN iburst" | sudo tee -a /etc/chrony/chrony.conf
echo "server $AD_DC2.$AD_DOMAIN iburst" | sudo tee -a /etc/chrony/chrony.conf
sudo systemctl enable chrony
sudo systemctl restart chrony

# =========================================================
# 5) Garantir PAM mkhomedir
# =========================================================
ensure_pam_mkhomedir() {
  LOG "Verificando PAM para mkhomedir (criar /home automaticamente)..."
  backup_file "${PAM_COMMON_SESSION}"

  if ! grep -q 'pam_mkhomedir.so' "${PAM_COMMON_SESSION}"; then
    LOG "Adicionando pam_mkhomedir.so a ${PAM_COMMON_SESSION}"
    echo "session required pam_mkhomedir.so skel=/etc/skel umask=0022" | sudo tee -a "${PAM_COMMON_SESSION}"
  else
    LOG "pam_mkhomedir ja presente em ${PAM_COMMON_SESSION}"
  fi

  if ! grep -q 'pam_oddjob_mkhomedir.so' "${PAM_COMMON_SESSION}" && \
     grep -q 'oddjobd' /etc/services 2>/dev/null; then
    LOG "Adicionando pam_oddjob_mkhomedir.so a ${PAM_COMMON_SESSION}"
    echo "session optional pam_oddjob_mkhomedir.so skel=/etc/skel umask=0022" | sudo tee -a "${PAM_COMMON_SESSION}"
    sudo systemctl enable oddjobd
    sudo systemctl start oddjobd
  fi
}
ensure_pam_mkhomedir

# =========================================================
# 6) Garantir NSS sss
# =========================================================
LOG "Garantindo configuracao do NSS (sss em passwd e group)..."
backup_file "/etc/nsswitch.conf"
sudo sed -i 's/^passwd:.*/passwd:         compat sss/' /etc/nsswitch.conf
sudo sed -i 's/^group:.*/group:          compat sss/' /etc/nsswitch.conf

# =========================================================
# 7) Ingressar no dominio
# =========================================================
LOG "Descobrindo dominio..."
realm discover "$AD_DOMAIN"

LOG "Ingressando no dominio..."
echo "$AD_PASS1" | sudo realm join --user="$AD_USER" "$AD_DOMAIN_CAPS"

# =========================================================
# 8) Configuracao do SSSD
# =========================================================
LOG "Configurando SSSD..."
backup_file "/etc/sssd/sssd.conf"
sudo bash -c "cat > /etc/sssd/sssd.conf" <<EOF
[sssd]
domains = $AD_DOMAIN_CAPS
config_file_version = 2
services = nss, pam

[domain/$AD_DOMAIN_CAPS]
id_provider = ad
access_provider = ad
fallback_homedir = /home/%u
default_shell = /bin/bash
use_fully_qualified_names = False
cache_credentials = True
enumerate = False
EOF

sudo chown root:root /etc/sssd/sssd.conf
sudo chmod 600 /etc/sssd/sssd.conf
sudo systemctl restart sssd

# =========================================================
# Checklist final
# =========================================================
echo "=============================================================================="
echo " CHECKLIST FINAL"
echo " ----------------"
echo "[OK] Pacotes instalados"
echo "[OK] Credenciais validadas"
echo "[OK] NTP configurado com $AD_DC1 e $AD_DC2"
echo "[OK] PAM mkhomedir configurado"
echo "[OK] NSS configurado (sss habilitado)"
echo "[OK] Ingressou no dominio $AD_DOMAIN_CAPS"
echo "[OK] SSSD configurado"
echo "=============================================================================="

read -rp "Deseja reiniciar o servidor agora ? (s/n): " REBOOT
if [[ "$REBOOT" == "s" ]]; then
  sudo reboot
else
  echo "Script concluido. Reinicie manualmente se necessario."
fi
