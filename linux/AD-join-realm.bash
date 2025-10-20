#!/bin/bash

# =============================================================================
# File       : AD-join-realm.bash
# Author     : Weverton Lima < wevertonjlima@gmail.com >
# Powered by : ChatGPT - BASH (Shell Script Programming Genius - IA)
# Descrição  : Realizar o procedimento de join de um servidor linux/ubuntu/debian em um Active Direcotry .
# =============================================================================
# README:
#
# Este script define uma função chamada `join_ad_domain` que:
#   - Descobre o domínio Active Directory informado
#   - Realiza o ingresso da máquina ao domínio
#   - Restringe o login apenas ao grupo AD especificado
#
# VARIAVEIS UTILIZADAS :
#   1. Defina as variáveis de ambiente antes de chamar a função:
#        - AD_DOMAIN   : Nome do AD DNS domínio ......................................................... (ex: empresa.local )
#        - AD_REALM    : Nome do AD KERBEROS domínio .................................................... (ex: EMPRESA.LOCAL )
#        - AD_ACCOUNT  : Conta usando apenas o prefixo UPN com permissão para ingressar a máquina ....... (ex: john )
#        - AD_PASS1    : Senha dessa conta (variável sensível)
#        - AD_GROUP    : Grupo AD que terá permissão de login ..................(ex: Domain-Linux-Admins )
#        - AD_UPN*     : Conta UPN com permissão para ingressar a máquina ............................... (ex: john@empresa.local )
#        * Apesar de mencionada como referência contextual, esta variavél não será utilizada nesse script.               
#
#   2. Execute com:
#        sudo ./AD-join-realm.bash
#
# REQUISITOS:
# - Pacote `realmd` com `realm` instalado
# - Privilégios sudo (para usar `realm join`, `permit`, `deny`)
# - O servidor deve conseguir resolver o Domínio e o DC via DNS.
# =============================================================================

# =============================================================================
# VARIÁVEIS DE SIMULAÇÃO PARA TESTE (APENAS PARA EXECUÇÃO INDIVIDUAL)
# =============================================================================
# IMPORTANTE: Para que este módulo funcione individualmente, o realmd deve estar instalado
# e o servidor deve conseguir resolver o Domínio e o DC via DNS.

# --- INCLUA SEUS VALORES AQUI PARA TESTAR O MODULO 5 INDIVIDUALMENTE ---
# Remova o '#' e insira o FQDN do seu Domínio e o UPN da conta que junta máquinas.
#
# AD_DOMAIN="acme.labs"
# AD_REALM="ACME.LABS"
# AD_ACCOUNT="bruce"
# AD_PASS1="wayne"
# AD_GROUP="Domain_Linux_Admins"

# ============================================================
# Função: join_ad_domain
# Descrição: Ingressa servidor no domínio AD via realmd/realm
# ============================================================

init_join_ad_realm() {
    echo " Descobrindo domínio..."
    sleep 0.5
    realm discover "$AD_DOMAIN"

    echo " Ingressando no domínio..."
    sleep 0.5
    echo "$AD_PASS1" | sudo realm join --user="$AD_UPN" "$AD_REALM"
    if [[ $? -ne 0 ]]; then
        echo " Falha ao ingressar no domínio."
        return 1
    fi
    echo " Ingressado no domínio com sucesso."

    echo " Configurando permissões de login..."
    sleep 0.5
    sudo realm deny --all
    sudo realm permit -g "$AD_GROUP"
    if [[ $? -ne 0 ]]; then
        echo " Falha ao configurar permissões de grupo."
        return 1
    fi
    echo " Apenas o grupo '$AD_GROUP' tem permissão de login."
}

#init_join_ad_realm
