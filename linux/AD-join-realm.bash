#!/bin/bash
# ============================================================
# File       : AD-join-realm.bash
# Author     : Weverton Lima < wevertonjlima@gmail.com >
# Powered by : ChatGPT - BASH (Shell Script Programming Genius - IA)
# ============================================================
# README:
#
# Este script define uma função chamada `join_ad_domain` que:
#   - Descobre o domínio Active Directory informado
#   - Realiza o ingresso da máquina ao domínio
#   - Restringe o login apenas ao grupo AD especificado
#
# USO:
#   1. Defina as variáveis de ambiente antes de chamar a função:
#        - AD_DOMAIN  : Nome do domínio (ex: empresa.local)
#        - AD_UPN     : Conta UPN com permissão para ingressar a máquina (ex: user@empresa.local)
#        - AD_PASS1   : Senha dessa conta (variável sensível)
#        - AD_GROUP   : Grupo AD que terá permissão de login.
#
#   2. Execute com:
#        source join_ad_domain.sh
#        join_ad_domain
#
# REQUISITOS:
# - Pacote `realmd` com `realm` instalado
# - Privilégios sudo (para usar `realm join`, `permit`, `deny`)
# ============================================================
# ============================================================
# Função: join_ad_domain
# Descrição: Ingressa servidor no domínio AD via realmd/realm
# ============================================================

join_ad_domain() {
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
