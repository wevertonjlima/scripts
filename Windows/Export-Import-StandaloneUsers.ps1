# ==============================================================================
# Script: Export-Import-StandaloneUsers.ps1
# Funcao: Exportar usuarios locais (Standalone) e importar no Active Directory
# 
# IMPORTANTE: Ao realizar qualquer alteracao na logica ou compatibilidade, 
# atualize a variavel $ScriptVersion abaixo e a data do LOG de alteracoes.
# O versionamento semantico deve estar ajustado para seguir a progressao 
# decimal definida ($1.0.x$ para correcoes/ajustes e $1.x.0$ para novas funcionalidades).
#
# Versao Inicial: 1.0.0
# Ultima alteracao: 2026-06-19 (Versao 2.2.1 - VERSAO MATRIZ GOLD - ULTRA FAST V2)
# ==============================================================================

Param(
    [Parameter(Mandatory=$false, ParameterSetName="Exportar")][switch]$e,
    [Parameter(Mandatory=$false, ParameterSetName="Importar")][string]$i
)

# --- [0] METADADOS E VERSAO ---
$ScriptVersion = "2.2.1"
$ErrorActionPreference = "Stop"

# --- [1] FUNCOES AUXILIARES E FORMATACAO ---
function Get-Timestamp {
    Return (Get-Date -Format "yyyy-MM-dd_HH'h'mm")
}

function Write-Log {
    Param (
        [string]$Message,
        [string]$Level = "INFO",
        [string]$LogPath
    )
    $FormatDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Text = "[$FormatDate] [$Level] $Message"
    Write-Host $Text
    if ($LogPath) {
        Out-File -FilePath $LogPath -InputObject $Text -Append -Encoding UTF8
    }
}

function Show-Banner {
    $ADInfo   = Get-ADDomain
    $Dominio  = $ADInfo.NetBIOSName
    $Hostname = $env:COMPUTERNAME
    $Usuario  = $env:USERNAME

    Clear-Host
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host "       AUTOMACAO DE CLONAGEM DE USUARIOS - AD       " -ForegroundColor Cyan
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host " Versao do Script : $ScriptVersion"
    Write-Host " Dominio AD        : $Dominio ($($ADInfo.DNSRoot))"
    Write-Host " Executado em      : $Hostname"
    Write-Host " Operador Atual    : $Usuario"
    Write-Host " Data e Hora       : $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
    Write-Host "====================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Show-WarningBanner {
    Param([string]$Modo)
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Yellow
    Write-Host " AVISO DE RISCO: O SCRIPT SERA EXECUTADO EM MODO DE $Modo" -ForegroundColor Yellow
    Write-Host " Esta operacao exige privilegios administrativos elevados." -ForegroundColor Yellow
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Yellow
    Write-Host ""
}


# --- [2] MODO TUTORIAL ---
function Show-Tutorial {
    Show-Banner
    Write-Host "MODO TUTORIAL DE OPERACAO" -ForegroundColor Green
    Write-Host "------------------------------------------------------------------------"
    Write-Host "Este script extrai contas locais de um servidor Standalone e as"
    Write-Host "importa em uma Unidade Organizacional (OU) no Active Directory."
    Write-Host ""
    Write-Host "Sintaxe para Execucao:"
    Write-Host "  Para Exportar: .\\Export-Import-StandaloneUsers.ps1 -e"
    Write-Host "  Para Importar: .\\Export-Import-StandaloneUsers.ps1 -i <caminho_do_arquivo_csv>"
    Write-Host ""
    Write-Host "Exemplo de Importacao:"
    Write-Host "  .\\Export-Import-StandaloneUsers.ps1 -i .\\SRV01-standalone-users_2026-06-18_12h30.csv"
    Write-Host "------------------------------------------------------------------------"
    Write-Host ""
}


# --- [3] MODO EXPORTACAO (CONGELADO) ---
function Export-Users {
    Show-Banner
    Show-WarningBanner -Modo "EXPORTACAO"
    
    $Confirmacao = Read-Host "Deseja prosseguir com a exportacao de usuarios locais? (S/N)"
    if ($Confirmacao -notmatch "^[sS]") {
        Write-Host "Operacao cancelada pelo operador." -ForegroundColor Red
        Exit
    }

    $Hostname = $env:COMPUTERNAME
    $Timestamp = Get-Timestamp
    
    $ScriptDir = $PSScriptRoot
    if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = "." }
    
    $CsvFilename = "$Hostname-standalone-users_$Timestamp.csv"
    $CsvPath = Join-Path $ScriptDir $CsvFilename
    $LogFilename = "report_$Hostname-standalone-users_$Timestamp.log"
    $LogPath = Join-Path $ScriptDir $LogFilename

    Write-Log -Message "Iniciando processo de exportacao no host local: $Hostname" -Level "INFO" -LogPath $LogPath

    Write-Log -Message "Coletando contas de usuarios locais ativos..." -Level "INFO" -LogPath $LogPath
    $LocalUsers = Get-LocalUser | Where-Object { $_.Enabled -eq $true -and $_.Name -notmatch "Administrator|Guest|DefaultAccount|WDAGUtilityAccount" }

    $ExportData = @()
    foreach ($User in $LocalUsers) {
        $FirstName = ""
        $LastName = ""
        if ($User.FullName) {
            $NameSplit = $User.FullName -split ' ', 2
            $FirstName = $NameSplit[0]
            if ($NameSplit.Count -gt 1) { $LastName = $NameSplit[1] }
        } else {
            $FirstName = $User.Name
        }

        $Obj = [PSCustomObject]@{
            Username    = $User.Name
            FirstName   = $FirstName
            LastName    = $LastName
            Description = $User.Description
        }
        $ExportData += $Obj
    }

    if ($ExportData.Count -eq 0) {
        Write-Log -Message "Nenhum usuario local customizado foi detectado para exportacao." -Level "WARN" -LogPath $LogPath
    } else {
        $ExportData | Export-Csv -Path $CsvPath -NoTypeInformation -Delimiter "," -Encoding UTF8
        Write-Log -Message "Exportacao concluida. Arquivo gerado em: $CsvPath" -Level "SUCCESS" -LogPath $LogPath
    }

    Write-Host ""
    Write-Log -Message "Processo finalizado. Arquivo de Log gerado: $LogPath" -Level "INFO" -LogPath $LogPath
}


# --- [4] MODO IMPORTACAO (MATRIZ GOLD - ULTRA FAST V2) ---
function Import-Users {
    Param ([string]$PathCsv)

    Show-Banner
    Show-WarningBanner -Modo "IMPORTACAO NO ACTIVE DIRECTORY"

    $Hostname = $env:COMPUTERNAME
    $Timestamp = Get-Timestamp
    
    $ScriptDir = $PSScriptRoot
    if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = "." }
    
    $LogFilename = "report_$Hostname-standalone-users_$Timestamp.log"
    $LogPath = Join-Path $ScriptDir $LogFilename

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Host "ERRO CRITICO: O modulo ActiveDirectory nao esta instalado ou disponivel via RSAT." -ForegroundColor Red
        Exit
    }
    Import-Module ActiveDirectory

    try {
        $DomainObj = Get-ADDomain
        $DomainUPNSuffix = $DomainObj.DNSRoot
    } catch {
        Write-Host "ERRO CRITICO: Nao foi possivel obter o sufixo UPN do dominio. Verifique a conectividade com o AD." -ForegroundColor Red
        Exit
    }

    if (-not (Test-Path -Path $PathCsv)) {
        Write-Host "ERRO: O arquivo CSV de origem nao foi localizado: $PathCsv" -ForegroundColor Red
        Exit
    }

    $Confirmacao = Read-Host "Confirma o processamento e a leitura do arquivo CSV de entrada? (S/N)"
    if ($Confirmacao -notmatch "^[sS]") {
        Write-Host "Operacao cancelada pelo operador." -ForegroundColor Red
        Exit
    }

    # ==============================================================================
    # VALIDACAO DA CONTA MODELO (TEMPLATE)
    # ==============================================================================
    $TemplateObj = $null
    while ($true) {
        Write-Host ""
        $TemplateInput = Read-Host "Informe por favor a conta template no formato SamAccount (ex.: usr_template)"
        if ([string]::IsNullOrEmpty($TemplateInput)) {
            Write-Host "ERRO: O nome do usuario template nao pode ser nulo ou vazio." -ForegroundColor Red
            Start-Sleep -Seconds 3
            Continue
        }
        
        $TemplateObj = Get-ADUser -Filter "SamAccountName -eq '$TemplateInput'" -Properties primaryGroupID -ErrorAction SilentlyContinue
        
        if ($TemplateObj) {
            $TemplateUser = $TemplateInput
            Write-Host "[OK] Conta template '$TemplateUser' localizada com sucesso!" -ForegroundColor Green
            break
        } else {
            Write-Host "[ERRO] A conta template '$TemplateInput' nao existe no AD. Tente novamente em 3 segundos..." -ForegroundColor Red
            Start-Sleep -Seconds 3
        }
    }

    # LOOP DE VALIDACAO DA OU / CONTAINER
    $TargetOU = ""
    while ($true) {
        Write-Host ""
        $OUInput = Read-Host "Informe por favor a OU onde as contas de usuarios serao criadas (Pressione ENTER para usar o container padrao Users)"
        
        if ([string]::IsNullOrEmpty($OUInput)) {
            $TargetOU = $DomainObj.UsersContainer
            Write-Host "Container padrao Users selecionado automaticamente: $TargetOU" -ForegroundColor Green
            break
        } else {
            try {
                $OUCheck = Get-ADOrganizationalUnit -Identity $OUInput -ErrorAction SilentlyContinue
                if (-not $OUCheck) {
                    $OUCheck = Get-ADObject -Identity $OUInput -ErrorAction Stop
                }
                $TargetOU = $OUInput
                Write-Host "Destino da OU/Container validado com sucesso: $TargetOU" -ForegroundColor Green
                break
            } catch {
                Write-Host "ERRO: O Distinguished Name (DN) informado nao existe ou e invalido: $OUInput" -ForegroundColor Red
                Start-Sleep -Seconds 3
            }
        }
    }

    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Yellow
    Write-Host "            RESUMO DOS PARAMETROS DE IMPORTACAO" -ForegroundColor Yellow
    Write-Host "==================================================" -ForegroundColor Yellow
    Write-Host " Arquivo CSV de Origem  : $PathCsv"
    Write-Host " Conta de Usuario Base  : $TemplateUser"
    Write-Host " Caminho DN do Destino  : $TargetOU"
    Write-Host "==================================================" -ForegroundColor Yellow
    $Prosseguir = Read-Host "Deseja iniciar a criacao em lote das contas de usuarios? (S/N)"
    if ($Prosseguir -notmatch "^[sS]") {
        Write-Host "Operacao abortada." -ForegroundColor Red
        Exit
    }

    $FormatDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$FormatDate] [INFO] Iniciando processamento em lote do arquivo: $PathCsv" | Out-File -FilePath $LogPath -Append -Encoding UTF8
    
    $CsvUsers = @(Import-Csv -Path $PathCsv -Delimiter ",")
    $TotalUsuarios = $CsvUsers.Count
    $Contador = 0

    Write-Host ""
    Write-Host "--------------------------------------------------" -ForegroundColor Gray
    Write-Host " [ PROGRESSO DE INJECAO DE IDENTIDADES NO AD ]" -ForegroundColor Green
    Write-Host "--------------------------------------------------" -ForegroundColor Gray

    # ==============================================================================
    # PRE-PROCESSAMENTO EM MEMORIA (CACHE DO TEMPLATE OUTSIDE THE LOOP)
    # ==============================================================================
    $TemplateRID = $TemplateObj.primaryGroupID
    $TemplateGruposCompleto = Get-ADPrincipalGroupMembership -Identity $TemplateUser | Get-ADGroup -Properties PrimaryGroupToken
    $GrupoPrimarioTemplate = $TemplateGruposCompleto | Where-Object { $_.PrimaryGroupToken -eq $TemplateRID }
    
    # Verifica em memoria se o grupo padrao Domain Users (RID 513) esta na lista do template
    $DomainUsersNaLista = $TemplateGruposCompleto | Where-Object { $_.PrimaryGroupToken -eq 513 }

    # Define a senha segura hardcoded solicitada
    $SenhaSegura = ConvertTo-SecureString "Senha#Complexa!2026" -AsPlainText -Force

    foreach ($UserRow in $CsvUsers) {
        $Contador++
        
        $TextoOdometro = "`r[ODOMETRO] Processando: [$Contador/$TotalUsuarios] ===> Conta: $($UserRow.Username)                     "
        Write-Host -NoNewline $TextoOdometro -ForegroundColor Cyan
        
        try {
            $UserExists = Get-ADUser -Filter "SamAccountName -eq '$($UserRow.Username)'"
            if ($UserExists) {
                $FormatDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                "[$FormatDate] [WARN] Usuario [$($UserRow.Username)] ja existe no Active Directory. Ignorando criacao." | Out-File -FilePath $LogPath -Append -Encoding UTF8
                Continue
            }

            $NomeCompleto = "$($UserRow.FirstName) $($UserRow.LastName)".Trim()
            if ([string]::IsNullOrEmpty($NomeCompleto)) {
                $NomeCompleto = $UserRow.Username
            }

            $DinamicoUPN = "$($UserRow.Username)@$DomainUPNSuffix"

            # Criacao limpa e direta
            New-ADUser -Name $NomeCompleto `
                       -SamAccountName $UserRow.Username `
                       -UserPrincipalName $DinamicoUPN `
                       -GivenName $UserRow.FirstName `
                       -Surname $UserRow.LastName `
                       -Description $UserRow.Description `
                       -Path $TargetOU `
                       -AccountPassword $SenhaSegura `
                       -Enabled $true `
                       -PasswordNeverExpires $true `
                       -CannotChangePassword $true `
                       -ErrorAction Stop

            # ==============================================================================
            # ENGENHARIA DE GRUPOS GOLD 1:1 - OTIMIZACAO IN-MEMORY + PROTECAO DE REPLICACAO
            # ==============================================================================
            
            # 1. Injeta o novo usuario em todos os grupos do template (incluindo o que se tornara o primario)
            foreach ($Grupo in $TemplateGruposCompleto) {
                Add-ADGroupMember -Identity $Grupo.DistinguishedName -Members $UserRow.Username -ErrorAction Stop
            }

            # Pequena pausa tática (100ms) em memória para o AD consolidar a associação antes da herança
            [System.Threading.Thread]::Sleep(100)

            # 2. Transfere a heranca do Grupo Primario para o ID correto do Template
            Set-ADUser -Identity $UserRow.Username -Replace @{primaryGroupID = $GrupoPrimarioTemplate.PrimaryGroupToken} -ErrorAction Stop

            # 3. Elimina o "Domain Users" apenas se ele NAO estiver explicitamente mapeado no template
            if (-not $DomainUsersNaLista -and $TemplateRID -ne 513) {
                Remove-ADGroupMember -Identity "Domain Users" -Members $UserRow.Username -Confirm:$false -ErrorAction SilentlyContinue
            }
            
            $FormatDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            "[$FormatDate] [SUCCESS] Usuario [$($UserRow.Username)] gerado com sucesso em conformidade 1:1 com o template." | Out-File -FilePath $LogPath -Append -Encoding UTF8

        } catch {
            $FormatDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            "[$FormatDate] [ERROR] Falha critica ao provisionar conta [$($UserRow.Username)]. Detalhes: $($_.Exception.Message)" | Out-File -FilePath $LogPath -Append -Encoding UTF8
        }
    }

    Write-Host ""
    Write-Host "--------------------------------------------------" -ForegroundColor Gray
    Write-Host " Carga concluida com sucesso!" -ForegroundColor Green
    Write-Host "--------------------------------------------------" -ForegroundColor Gray
    Write-Host ""
    
    $FormatDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$FormatDate] [INFO] Processamento de importacao finalizado." | Out-File -FilePath $LogPath -Append -Encoding UTF8
    
    Write-Host "Processamento de importacao finalizado em conformidade 1:1 (Modo de Alta Performance)."
    Write-Host ""
    Write-Host "Nome do arquivo de log detalhado gerado para auditoria:" -ForegroundColor Green
    Write-Host "$LogPath" -ForegroundColor Yellow
}


# --- [5] CONTROLADOR DO FLUXO PRINCIPAL ---
if ($PsCmdlet.ParameterSetName -eq "Exportar" -or $e) {
    Export-Users
} elseif ($PsCmdlet.ParameterSetName -eq "Importar" -or (-not [string]::IsNullOrEmpty($i))) {
    Import-Users -PathCsv $i
} else {
    Show-Tutorial
}
