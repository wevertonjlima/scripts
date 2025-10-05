#!/bin/bash
# --------------------------------------------------------------------------------------
# Nome do Script: AD-admins-sudoers.bash
# Criador: Weverton Lima < wevertonjlima@gmail.com >
# Powered IA: Gemini
# Data: 4 de Outubro de 2025
# --------------------------------------------------------------------------------------

# README: Configuração Segura de Permissões Sudo para Administradores
#
# PROPÓSITO:
# Esta função cria e configura de forma segura um arquivo de política sudoers
# (/etc/sudoers.d/domain-linux-admins.conf) para conceder privilégios sudo a todos os
# membros de um grupo específico (%domain-linux-admins).
#
# USO:
# Para executar, chame a função como root (ou com sudo):
# sudo bash -c "$(declare -f set_admin_sudoers); set_admin_sudoers"
# OU, se a função estiver carregada no seu shell:
# sudo set_admin_sudoers
# --------------------------------------------------------------------------------------

set_admin_sudoers() {
    local SUDOERS_FILE="/etc/sudoers.d/domain-linux-admins.conf"
    local ADMIN_GROUP="%domain-linux-admins"
    local SUDO_RULE="${ADMIN_GROUP} ALL=(ALL) ALL"

    echo "--- Iniciando Configuração de Sudoers para ${ADMIN_GROUP} ---"

    # Verificação de pré-requisito: Apenas root deve executar esta função.
    if [[ $EUID -ne 0 ]]; then
       echo "ERRO: Esta função deve ser executada com privilégios de root (sudo)."
       return 1
    fi
    
    # 1. Cria e insere a regra sudo.
    echo "1. Criando regra '${SUDO_RULE}' no arquivo: ${SUDOERS_FILE}"
    # Usamos tee para escrever no arquivo como root.
    if ! echo "${SUDO_RULE}" | tee "${SUDOERS_FILE}" > /dev/null; then
        echo "ERRO: Falha ao escrever no arquivo ${SUDOERS_FILE}."
        return 1
    fi

    # 2. Verifica a sintaxe do novo arquivo. CRÍTICO para evitar bloqueios de sudo!
    echo "2. Verificando sintaxe do arquivo de configuração..."
    if ! visudo -cf "${SUDOERS_FILE}"; then
        # Se a sintaxe falhar, o arquivo é perigoso. Removemos para evitar problemas.
        echo "ERRO: Falha na verificação de sintaxe! O arquivo ${SUDOERS_FILE} será removido para segurança."
        rm -f "${SUDOERS_FILE}"
        return 1
    fi

    # 3. Define as permissões seguras (0440: leitura apenas para root e grupo)
    echo "3. Aplicando permissões de segurança 0440..."
    if ! chmod 0440 "${SUDOERS_FILE}"; then
        echo "AVISO: Falha ao aplicar chmod 0440. O arquivo existe, mas as permissões podem não estar estritas."
    fi

    # 4. Define o proprietário e o grupo (root:root)
    echo "4. Aplicando propriedade root:root..."
    if ! chown root:root "${SUDOERS_FILE}"; then
        echo "AVISO: Falha ao aplicar chown root:root. O arquivo existe, mas a propriedade pode não estar correta."
    fi

    echo "--- Sucesso! ---"
    echo "O arquivo ${SUDOERS_FILE} foi criado, verificado e configurado com segurança."
    echo "Membros de ${ADMIN_GROUP} agora têm privilégios sudo."
    return 0
}
