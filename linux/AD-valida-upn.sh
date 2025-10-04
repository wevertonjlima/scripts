#!/bin/bash
# filename	: AD-valida-upn.sh
# created	: Weverton Lima < wevertonjlima@gmail.com >


# -------- Funções de UI --------
clear_screen() { clear; }

show_banner() {
   echo "    ============================================================="
   echo "    =    Validando credenciais do Dominio Active Directory      ="
   echo "    =     Use um formato UPN (exemplo: user@mydomain.dns)       ="
   echo "    ============================================================="
   echo ""
}

# -------- Validação do UPN --------
validate_upn() {
    local upn="$1"

    # Máx 255 chars
    if [[ ${#upn} -gt 255 ]]; then
        echo "ERROR - Formato de entrada invalido."
        return 1
    fi

    # Deve conter @
    if [[ "$upn" != *@* ]]; then
        echo "ERROR - Formato de entrada invalido."
        return 1
    fi

    local prefix="${upn%@*}"
    local suffix="${upn#*@}"

    # Prefixo: A-Z a-z 0-9 . - _
    if [[ ! "$prefix" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "ERROR - Formato de entrada invalido."
        return 1
    fi

    # Sufixo: A-Z a-z 0-9 . -  (não pode iniciar/terminar com . ou -)
    if [[ ! "$suffix" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])$ ]]; then
        echo "ERROR - Formato de entrada invalido."
        return 1
    fi

    return 0
}

# ===================== Programa Principal =====================

# Loop até UPN válido
while true; do
    clear_screen
    show_banner
    read -erp "Digite usuario (UPN): " USER_UPN
    if validate_upn "$USER_UPN"; then
        break
    else
        sleep 3
    fi
done

# Senha (silenciosa) e confirmação
clear_screen
show_banner
read -s -p "Digite a senha ....: " USER_PASS
echo ""
read -s -p "Confirme a senha ..: " USER_PASS_CONFIRM
echo ""
if [[ "$USER_PASS" != "$USER_PASS_CONFIRM" ]]; then
    echo "Erro: As senhas não coincidem!"
    exit 1
fi

# ---- Segmentação correta do UPN ----
ad_prefix="${USER_UPN%@*}"     # ex: bruce
ad_sufix="${USER_UPN#*@}"      # ex: acme.labs
REALM=$(echo "$ad_sufix" | tr '[:lower:]' '[:upper:]')  # ex: ACME.LABS

# Pré-visualização e confirmação
clear_screen
show_banner
echo "Olá, o seu usuario UPN inserido foi:"
echo "  $USER_UPN"
echo ""
echo "O comando de validação será:"
echo "  kinit ${ad_prefix}@${REALM}"
echo ""
read -erp "Posso prosseguir? (s/n): " CONFIRM
if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
    echo "Operação cancelada pelo usuário."
    exit 1
fi

# ---- Execução do kinit usando ad_prefix@REALM ----
printf "%s\n" "$USER_PASS" | kinit "${ad_prefix}@${REALM}" 2>/dev/null

if [[ $? -eq 0 ]]; then
    echo "Usuario validado no AD !!!"
else
    echo "Usuario não validado no AD XXX"
fi
