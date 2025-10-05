#!/bin/bash

# ==============================================================================
# Nome do Script : AD-configure_sssd.bash
# Criador        : Weverton Lima < wevertonjlima@gmail.com >
# Powered by     : IA - ChatGPT (GPT-4o) | openai.com
#
# Descrição:
# Este script configura o SSSD (System Security Services Daemon) em sistemas
# Linux para permitir autenticação de usuários de um domínio Active Directory.
#
# Ele cria (ou sobrescreve) de forma segura o arquivo de configuração
# /etc/sssd/sssd.conf com os parâmetros necessários para integrar ao domínio AD,
# definindo shell padrão, diretório home, permissões seguras e reiniciando o SSSD.
#
# Uso:
#   1. Exporte a variável de ambiente AD_DOMAIN com o nome do domínio:
#        export AD_DOMAIN=meudominio.local
#
#   2. Execute o script com permissões de sudo:
#        sudo ./configure_sssd_ad.sh
#
# OBS:
#   - O script faz backup do sssd.conf original, se existir.
#   - É necessário ter o pacote `sssd` instalado e o domínio resolvido via DNS.
# ==============================================================================

configure_sssd_ad() {
    if [[ -z "$AD_DOMAIN" ]]; then
        echo "Erro: A variável AD_DOMAIN não está definida."
        echo "Defina com: export AD_DOMAIN=meudominio.local"
        return 1
    fi

    echo "Configurando SSSD para o domínio '${AD_DOMAIN^^}'..."
    sleep 0.8

    # Backup do sssd.conf atual (se existir)
    sudo cp /etc/sssd/sssd.conf /etc/sssd/sssd.conf.bkp 2>/dev/null || true

    # Criação do novo arquivo de configuração
    sudo bash -c "cat > /etc/sssd/sssd.conf" <<EOF
[sssd]
domains = ${AD_DOMAIN^^}
config_file_version = 2
services = nss, pam

[domain/${AD_DOMAIN^^}]
id_provider = ad
access_provider = ad
fallback_homedir = /home/%u
default_shell = /bin/bash
use_fully_qualified_names = False
cache_credentials = True
enumerate = False
EOF

    # Permissões seguras
    sudo chown root:root /etc/sssd/sssd.conf
    sudo chmod 600 /etc/sssd/sssd.conf

    # Reinício do serviço
    sudo systemctl restart sssd

    echo "SSSD configurado com sucesso para o domínio '${AD_DOMAIN^^}'."
}

# Executa a função se o script for chamado diretamente
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    configure_sssd_ad
fi
