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
#!/bin/bash

# ============================================================
# Função: init_upn
# Descrição: Valida formato UPN e autentica via Kerberos (kinit)
# ============================================================

init_upn() {

    clear_screen() { clear; }
    
    show_banner() {
        echo "=============================================================="
        echo "=      Validando Credenciais de Usuário do Active Directory  ="
        echo "=        Use o formato UPN (exemplo: user@mydomain.dns)      ="
        echo "=============================================================="
        echo ""
    }

    validate_upn() {
        local upn="$1"
        
        if [[ ${#upn} -gt 255 || "$upn" != *@* ]]; then
            echo "ERROR - Formato inválido (tamanho ou falta de '@')."
            return 1
        fi

        local prefix="${upn%@*}"
        local suffix="${upn#*@}"

        if [[ ! "$prefix" =~ ^[A-Za-z0-9._-]+$ ]]; then
            echo "ERROR - Prefixo inválido (antes do '@')."
            return 1
        fi

        if [[ ! "$suffix" =~ ^([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$ ]]; then
            echo "ERROR - Sufixo inválido. Use formato DNS válido, ex: example.com"
            return 1
        fi

        return 0
    }

    # --- 1. Loop de entrada e validação --------------------------------------
    local user_upn=""
    while true; do
        clear_screen
        show_banner
        read -erp " Digite usuário (UPN): " user_upn
        if validate_upn "$user_upn"; then
            break
        else
            sleep 3
        fi
    done

    # --- 2. Senha e confirmação ----------------------------------------------
    local user_pass="" user_pass_confirm=""
    clear_screen
    show_banner
    read -s -p " Digite a senha ....: " user_pass; echo ""
    read -s -p " Confirme a senha ..: " user_pass_confirm; echo ""
    if [[ "$user_pass" != "$user_pass_confirm" ]]; then
        echo "Erro: As senhas não coincidem!"
        return 1
    fi

    # --- 3. Gera variáveis globais (exportadas) ------------------------------
    local ad_prefix="${user_upn%@*}"
    local ad_suffix="${user_upn#*@}"
    export AD_UPN="$user_upn"
    export AD_ACCOUNT="$ad_prefix"
    export AD_DOMAIN="$ad_suffix"
    export AD_REALM=$(echo "$ad_suffix" | tr '[:lower:]' '[:upper:]')
    export AD_PASS1="$user_pass"

    clear_screen
    show_banner
    echo "Usuário inserido: $AD_UPN"
    echo "Principal Kerberos: ${AD_ACCOUNT}@${AD_REALM}"
    echo ""
    read -erp "Posso prosseguir com a autenticação (kinit)? (s/n): " confirm_kinit
    if [[ "$confirm_kinit" != [sS] ]]; then
        echo "Operação cancelada."
        return 1
    fi

    printf "%s\n" "$AD_PASS1" | kinit "${AD_ACCOUNT}@${AD_REALM}" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        echo " Usuário autenticado com sucesso!"
        return 0
    else
        echo " Falha na autenticação Kerberos."
        return 1
    fi
}

# init_upn

