#!/bin/bash
# ==============================================================================
# Script: configurar-repo-local-ubuntu.sh
# Funcao: Automacao de Repositorio Local para Ubuntu (Ambiente Air-Gapped)
# Versao: 1.0.0 - Data: 2026-04-29
# ==============================================================================

# --- [1] VARIAVEIS ---
MNT_POINT="/media/cdrom"
SOURCES_FILE="/etc/apt/sources.list"
BACKUP_FILE="/etc/apt/sources.list.bak"

# --- [2] EXECUCAO ---
{
    # Criar ponto de montagem se nao existir
    mkdir -p $MNT_POINT

    # Montar o DVD (Ubuntu costuma usar /dev/sr0 ou /dev/cdrom)
    mount -t iso9660 /dev/sr0 $MNT_POINT 2>/dev/null

    # Backup do arquivo de fontes original (que aponta para internet)
    if [ ! -f "$BACKUP_FILE" ]; then
        cp $SOURCES_FILE $BACKUP_FILE
    fi

    # Sobreescrever o sources.list para apontar APENAS para o DVD
    # O Ubuntu precisa do prefixo [trusted=yes] para nao exigir chaves GPG na ISO local
    cat <<EOF > $SOURCES_FILE
deb [trusted=yes] file:$MNT_POINT $(lsb_release -cs) main restricted
EOF

    # Limpeza e atualizacao do indice
    apt-get clean
    apt-get update
} || {
    echo "ERRO: Falha na configuracao do repositorio local Ubuntu."
    exit 1
}

echo "CONFIGURACAO CONCLUIDA: APT configurado para usar apenas o DVD Local."