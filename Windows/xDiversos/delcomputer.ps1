# ==============================================================================
# Script: delcomputer.ps1
# Funcao: Remove conta de computador no AD com bypass de confirmacao e checagem de existencia
# 
# IMPORTANTE: Ao realizar qualquer alteracao na logica ou compatibilidade, 
# atualize a variavel $ScriptVersion abaixo e a data do LOG de alteracoes.
# O versionamento semantico deve estar ajustado para seguir a progressao.
#
# Versao: 1.2.1
# Informar ultima alteracao: 2026-05-26 (Correcao do Get-ADComputer usando -Filter)
# ==============================================================================

# --- [0] METADADOS E VERSAO ---
$ScriptVersion = "1.2.1"

function Remove-CustomADComputer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0, HelpMessage="Nome do computador a ser excluido.")]
        [string]$ComputerName,

        # [Switch]: Define um parametro do tipo chave (verdadeiro se presente, falso se ausente)
        [Alias("f", "y")]
        [switch]$Force
    )

    process {
        # Validacao Basica: Verifica se o modulo do Active Directory esta disponivel
        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            Write-Error "O modulo do ActiveDirectory nao esta instalado neste servidor/estacao."
            return
        }

        try {
            # --- [1] VALIDACAO DE EXISTENCIA (CORRIGIDA) ---
            # Usando -Filter, o AD nao gera erro se nao encontrar nada, apenas retorna vazio.
            # SamAccountName para computadores sempre termina com $, entao filtramos pelo nome exato ou com o sufixo.
            $ADComp = Get-ADComputer -Filter "SamAccountName -eq '$ComputerName' -or Name -eq '$ComputerName'" -ErrorAction Stop

            # Se a busca retornou vazia ($null), o computador nao existe no banco do AD
            if ($null -eq $ADComp) {
                Write-Host "[AVISO] O computador '$ComputerName' nao foi encontrado no Active Directory (DC=dexter,DC=labs). Nada a fazer." -ForegroundColor Yellow
                return
            }

            # --- [2] TRATAMENTO DE CONFIRMACAO (SE -FORCE NAO FOR USADO) ---
            if (-not $Force) {
                # --- AVISO DE RISCO ---
                Write-Warning "========================================================="
                Write-Warning "ATENCAO: Voce esta prestes a EXCLUIR o computador: $($ADComp.Name)"
                Write-Warning "Esta acao e DESTRUTIVA e invalida o acesso da maquina ao dominio."
                Write-Warning "========================================================="
                
                $Confirmacao = Read-Host "Tem certeza que deseja continuar? (S/N)"
                if ($Confirmacao -notmatch '^[Ss]$') {
                    Write-Host "Operacao cancelada pelo usuario." -ForegroundColor Yellow
                    return
                }
            } else {
                Write-Host "Parametro Force detectado. Pulando confirmacao manual..." -ForegroundColor DarkGray
            }

            # --- [3] EXECUCAO DA EXCLUSAO ---
            Write-Host "Removendo protecao contra exclusao acidental de: $($ADComp.Name)..." -ForegroundColor Cyan
            # Set-ADObject: Altera a flag de seguranca contra exclusao acidental
            $ADComp | Set-ADObject -ProtectedFromAccidentalDeletion $false -ErrorAction Stop

            Write-Host "Excluindo conta do computador..." -ForegroundColor Red
            # Remove-ADComputer: Deleta o objeto permanentemente usando o GUID
            Remove-ADComputer -Identity $ADComp.ObjectGUID -Confirm:$false -ErrorAction Stop

            Write-Host "Computador $($ADComp.Name) excluido com sucesso do Active Directory!" -ForegroundColor Green
        }
        catch {
            Write-Error "Erro inesperado ao processar a exclusao do computador. Detalhes: $_"
        }
    }
}

# --- PROCESSAMENTO DOS ARGUMENTOS DE LINHA DE COMANDO ---
if ($args.Count -gt 0) {
    $Parametros = @{
        ComputerName = $args[0]
    }
    
    if ($args.Count -gt 1 -and $args[1] -match '^-(y|f|Force)$') {
        $Parametros.Force = $true
    }

    Remove-CustomADComputer @Parametros
} else {
    $NomeInterativo = Read-Host "Digite o nome do computador que deseja excluir"
    if (-not [string]::IsNullOrEmpty($NomeInterativo)) {
        Remove-CustomADComputer -ComputerName $NomeInterativo
    }
}
