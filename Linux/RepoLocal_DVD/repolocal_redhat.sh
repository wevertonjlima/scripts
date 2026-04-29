#!/bin/bash
# ==============================================================================
# Script: configurar-repo-local.sh
# Funcao: Automacao de Repositorio Local para Oracle Linux 9 (Air-Gapped)
# Versao: 1.1.0 - Data: 2026-04-29
# ==============================================================================

# --- [1] VARIAVEIS E METADADOS ---
MNT_POINT="/media/dvdrom"
REPO_CONF="/etc/yum.repos.d/local-media.repo"
BACKUP_DIR="/etc/yum.repos.d/backup_original"
GPG_KEY="/etc/pki/rpm-gpg/RPM-GPG-KEY-oracle"

# --- [2] EXECUCAO SILENCIOSA ---
{
    # Criar ponto de montagem
    mkdir -p $MNT_POINT

    # Montar DVD (Redireciona erros para o limbo)
    mount -t iso9660 /dev/sr0 $MNT_POINT 2>/dev/null

    # Backup de repositorios que tentam usar internet
    mkdir -p $BACKUP_DIR
    mv /etc/yum.repos.d/oracle-linux-ol9.repo $BACKUP_DIR/ 2>/dev/null
    mv /etc/yum.repos.d/uek-ol9.repo $BACKUP_DIR/ 2>/dev/null

    # Criacao do arquivo de repositorio local (Escrita direta)
    cat <<EOF > $REPO_CONF
[local-baseos]
name=Oracle Linux 9 BaseOS - Local
baseurl=file://$MNT_POINT/BaseOS
gpgcheck=1
enabled=1
gpgkey=file://$GPG_KEY

[local-appstream]
name=Oracle Linux 9 AppStream - Local
baseurl=file://$MNT_POINT/AppStream
gpgcheck=1
enabled=1
gpgkey=file://$GPG_KEY
EOF

    # Limpeza e reindexacao
    dnf clean all > /dev/null
    dnf repolist
} || {
    echo "ERRO: Falha na configuracao do repositorio local."
    exit 1
}

echo "CONFIGURACAO CONCLUIDA: Repositorio local ativo e pronto para uso."
