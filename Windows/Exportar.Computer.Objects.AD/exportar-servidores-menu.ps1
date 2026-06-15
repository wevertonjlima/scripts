# ==============================================================================
# Script: exportar-servidores-menu.ps1
# Funcao: Exporta computadores do AD por tipos de filtro com odometro visual
# 
# IMPORTANTE: Ao realizar qualquer alteracao na logica ou compatibilidade, 
# atualize a variavel $ScriptVersion abaixo e a data do LOG de alteracoes.
# O versionamento semantico deve estar ajustado para seguir a progressao
# decimal definida ($1.0.x$ para correcoes/ajustes e $1.x.0$ para novas funcionalidades).
#
# Versao Inicial: 1.1.0
# Informar ultima alteracao: 2026-06-15 (Ajuste estrutural para menu de 4 opcoes)
# ==============================================================================

# --- [0] METADADOS E VERSAO ---
$ScriptVersion = "1.3.0"

function Export-ActiveDirectoryServersWithMenu {
    # Obtem a data e hora atual formatada para compor o nome do arquivo
    $DataHoraAtual = Get-Date -Format "yyyy-MM-dd_HH-mm"
    $NomeArquivo = "Relatorio_Windows_Servers_$DataHoraAtual.csv"

    # Determina o caminho do script para salvar o CSV no mesmo diretorio
    if ($PSScriptRoot) {
        $CaminhoSaida = Join-Path $PSScriptRoot $NomeArquivo
    } else {
        $CaminhoSaida = Join-Path $pwd $NomeArquivo
    }

    # --- 1. Limpar a tela ---
    Clear-Host

    # --- 2. Apresentar um menu inicial ---
    Write-Host "=======================================================================" -ForegroundColor Cyan
    Write-Host "             MENU DE EXPORTACAO DE SERVIDORES ACTIVE DIRECTORY         " -ForegroundColor Cyan
    Write-Host "=======================================================================" -ForegroundColor Cyan
    Write-Host " Este script ira buscar computadores no Active Directory e exportara para:"
    Write-Host " $CaminhoSaida" -ForegroundColor Yellow
    Write-Host "=======================================================================" -ForegroundColor Cyan
    Write-Host ""

    # --- 3. Perguntar se deseja continuar ---
    $Confirmacao = Read-Host "Deseja continuar com a exportacao? (S/N)"

    if ($Confirmacao -notmatch "^[sS]") {
        Write-Host ""
        Write-Host "Operacao cancelada pelo usuario. Encerrando o script." -ForegroundColor Orange
        return
    }

    # Valida se o modulo do AD esta instalado na maquina atual
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        Write-Error "O modulo ActiveDirectory nao foi encontrado. Execute em um DC ou maquina com RSAT."
        return
    }
    Import-Module ActiveDirectory

    # Controle do laco do menu de opcoes
    $ExecutandoMenu = $true

    while ($ExecutandoMenu) {
        Clear-Host
        Write-Host "=======================================================================" -ForegroundColor Cyan
        Write-Host "                         OPCOES DE EXPORTACAO                          " -ForegroundColor Cyan
        Write-Host "=======================================================================" -ForegroundColor Cyan
        Write-Host " 1) Exportar todos os computadores."
        Write-Host " 2) Exportar todos Windows Server."
        Write-Host " 3) Exportar por filtro de Sistema Operacional."
        Write-Host " 4) Encerrar."
        Write-Host "=======================================================================" -ForegroundColor Cyan
        Write-Host ""
        
        $Opcao = Read-Host "Escolha uma opcao (1-4)"

        switch ($Opcao) {
            "1" {
                # Filtro asterisco puro traz absolutamente todas as contas de computador do AD
                $FiltroSO = "*"
                $ExecutandoMenu = $false
            }
            "2" {
                # Filtro restrito a familia Windows Server
                $FiltroSO = "*Windows Server*"
                $ExecutandoMenu = $false
            }
            "3" {
                Write-Host ""
                Write-Host " Informe o tipo de sistema operacional a ser pesquisado." -ForegroundColor Yellow
                Write-Host " Exemplo ....: Windows Server 2022" -ForegroundColor Gray
                Write-Host ""
                $InputUsuario = Read-Host "Digite"
                
                if ([string]::IsNullOrEmpty($InputUsuario)) {
                    Write-Host "`nEntrada invalida. Retornando ao menu..." -ForegroundColor Orange
                    Start-Sleep -Seconds 2
                    break
                }
                # Sanitiza e prepara o filtro customizado
                $FiltroSO = "*{0}*" -f $InputUsuario.Trim()
                $ExecutandoMenu = $false
            }
            "4" {
                Write-Host "`nEncerrando o script." -ForegroundColor Orange
                return
            }
            Default {
                Write-Host "`nOpcao invalida! Escolha entre 1, 2, 3 ou 4." -ForegroundColor Red
                Start-Sleep -Seconds 2
            }
        }
    }

    # --- Processo de Busca e Exportacao ---
    try {
        Write-Host ""
        Write-Host "Consultando o Active Directory, aguarde..." -ForegroundColor Yellow
        
        # Realiza a busca com base no escopo definido pela opcao do menu
        $Servidores = Get-ADComputer -Filter "OperatingSystem -like '$FiltroSO'" -Properties DNSHostName, OperatingSystem, OperatingSystemVersion, OperatingSystemServicePack, Enabled

        # Se nenhum registro for encontrado, exibe alerta e reinicia a funcao do script (retorna ao banner)
        if ($null -eq $Servidores -or $Servidores.Count -eq 0) {
            Write-Host ""
            Write-Host "Nenhum registro encontrado" -ForegroundColor Red
            Write-Host "Pressione qualquer tecla para retornar ao menu..." -ForegroundColor Yellow
            $null = [Console]::ReadKey($true)
            
            # Chamada recursiva para retornar ao menu inicial
            Export-ActiveDirectoryServersWithMenu
            return
        }

        Write-Host ""
        Write-Host "Exportando lista de servidores..." -ForegroundColor Green

        # Cria/Limpa o arquivo CSV escrevendo o cabecalho estruturado
        $Cabecalho = "Name;DNSName;OperatingSystem;OperatingSystemVersion;OperatingSystemServicePack;DistinguishedName;Enabled"
        $Cabecalho | Out-File -FilePath $CaminhoSaida -Encoding utf8 -Force

        # --- Feedback Visual: Contador no formato de odometro ---
        $Contador = 0
        Write-Host ""
        
        foreach ($Servidor in $Servidores) {
            $Contador++

            # Formata a string de linha padrao CSV garantindo o tratamento de nulos nos campos
            $Linha = '"{0}";"{1}";"{2}";"{3}";"{4}";"{5}";"{6}"' -f $Servidor.Name, 
                                                                    $Servidor.DNSHostName, 
                                                                    $Servidor.OperatingSystem, 
                                                                    $Servidor.OperatingSystemVersion, 
                                                                    $Servidor.OperatingSystemServicePack, 
                                                                    $Servidor.DistinguishedName, 
                                                                    $Servidor.Enabled
            
            # Insere os dados de forma sequencial no arquivo
            $Linha | Out-File -FilePath $CaminhoSaida -Encoding utf8 -Append

            # Atualizacao em tempo real do odometro na tela
            Write-Host ("`rComputadores Exportados: {0}" -f $Contador) -NoNewline -ForegroundColor Cyan
            
            # Delay seguro de consistencia visual
            Start-Sleep -Milliseconds 15
        }

        # --- Finalizacao com Sucesso ---
        Write-Host "" 
        Write-Host ""
        Write-Host "Lista exportado com sucesso!" -ForegroundColor Green
        Write-Host "Arquivo salvo em: $CaminhoSaida" -ForegroundColor Yellow
    }
    catch {
        Write-Error "`nOcorreu um erro durante a execucao: $_"
    }
}

# Executa a funcao principal na sessao do terminal
Export-ActiveDirectoryServersWithMenu
