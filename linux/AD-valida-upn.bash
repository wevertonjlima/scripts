#!/bin/bash
# filename    : AD-valida-upn.bash
# author      : Weverton Lima <wevertonjlima@gmail.com>
# revised by  : BASH (Shell Script Programming Genius)
#
# =============================================================
# README:
#
# Este script tem como objetivo validar credenciais de um
# usuário no Active Directory (AD), utilizando um formato UPN
# (User Principal Name), como por exemplo: usuario@dominio.com.
#
# O script realiza:
#   - Validação do formato UPN
#   - Solicitação e confirmação de senha
#   - Geração do comando `kinit` para autenticação no AD
#
# Uso:
#   1. Torne o script executável:
#      chmod +x AD-valida-upn.sh
#   2. Execute:
#      ./AD-valida-upn.sh
#
# Dependência:
#   - kinit (Kerberos)
#
# =============================================================

clear_screen() { clear; }

show_banner() {
    echo "    ============================================================="
    echo "    =    Validando credenciais do Dominio Active Directory      ="
    echo "    =     Use um formato UPN (exemplo: user@mydomain.dns)       ="
    echo "    ============================================================="
    echo ""
}

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

    # Sufixo: A-Z a-z 0-9 . -
    if [[ ! "$suffix" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])$ ]]; then
        echo "ERROR - Formato de entrada invalido."
        return 1
    fi

    return 0
}

main() {
    local USER_UPN USER_PASS USER_PASS_CONFIRM
    local ad_prefix ad_sufix REALM CONFIRM

    while true; do
        clear_screen
        show_banner
        read -p "Digite usuario (UPN): " USER_UPN
        if validate_upn "$USER_UPN"; then
            break
        else
            sleep 3
        fi
    done

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

    ad_prefix="${USER_UPN%@*}"
    ad_sufix="${USER_UPN#*@}"
    REALM=$(echo "$ad_sufix" | tr '[:lower:]' '[:upper:]')

    clear_screen
    show_banner
    echo "Olá, o seu usuario UPN inserido foi:"
    echo "  $USER_UPN"
    echo ""
    echo "O comando de validação será:"
    echo "  kinit ${ad_prefix}@${REALM}"
    echo ""
    read -p "Posso prosseguir? (s/n): " CONFIRM
    if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
        echo "Operação cancelada pelo usuário."
        exit 1
    fi

    printf "%s\n" "$USER_PASS" | kinit "${ad_prefix}@${REALM}" 2>/dev/null

    if [[ $? -eq 0 ]]; then
        echo "Usuario validado no AD !!!"
    else
        echo "Usuario não validado no AD XXX"
    fi
}

main "$@"
