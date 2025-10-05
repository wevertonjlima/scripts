#!/bin/bash

# ============================================================
# File       : AD-joinlinux.bash
# Author     : Weverton Lima  < wevertonjlima@gmail.com >
# Powered by : BASH (Shell Script Programming Genius - IA)
# ============================================================
# README:
#
# Este script define uma função chamada `join_ad_domain` que permite
# descobrir um domínio Active Directory e ingressar o sistema local
# nesse domínio usando o utilitário `realm`.
#
# USO:
#   1. Defina as seguintes variáveis de ambiente antes de chamar a função:
#      - AD_DOMAIN  : Nome do domínio (ex: empresa.local)
#      - AD_ACCOUNT : Conta de usuário com permissão para ingressar máquinas no domínio
#      - AD_PASS1   : Senha dessa conta (atenção: variável sensível)
#
#   2. Execute o script no shell atual com `source`:
#      source join_ad_domain.sh
#
#   3. Chame a função:
#      join_ad_domain
#
# IMPORTANTE:
# - Requer privilégios sudo (para executar `realm join`)
# - Certifique-se de que o utilitário `realm` esteja instalado (`realmd`)
# ============================================================

join_ad_domain() {
    echo "🔍 Descobrindo domínio..."
    sleep 0.5
    realm discover "$AD_DOMAIN"

    echo "🔐 Ingressando no domínio..."
    sleep 0.5
    echo "$AD_PASS1" | sudo realm join --user="$AD_ACCOUNT" "${AD_DOMAIN^^}"
    if [[ $? -ne 0 ]]; then
        echo "❌ Falha ao ingressar no domínio."
        return 1
    fi
    echo "✅ Ingressado no domínio com sucesso."
}
