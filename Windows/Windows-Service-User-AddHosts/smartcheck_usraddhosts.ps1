# ==============================================================================
# Script: smartcheck_usraddhosts.ps1
# Funcao: Validar delegacoes de Contas de Servico (Criacao/Exclusao de Hosts)
#
# IMPORTANTE: Este script simula a criacao de 12 objetos de computador para
# validar se a Service Account possui permissoes de escrita/exclusao na OU.
# Os objetos seguem o padrao SRV-XXMMM_YYYYY (ex: SRV-01JAN_1A3F2)
# onde YYYYY e um sufixo hexadecimal aleatorio (00000 a FFFFF)
#
# Versao: 2.1.0
# Ultima Alteracao: 2024-05-23
# ==============================================================================

# --- [0] METADADOS E CONFIGURACAO ---
$ScriptVersion = "2.1.0"
$MesesAbrev = @("JAN","FEV","MAR","ABR","MAI","JUN","JUL","AGO","SET","OUT","NOV","DEZ")

# Variaveis para acumular resultados dos testes
$ResultadosCriacao = @()
$ResultadosExclusao = @()
$UltimaOUSelected = $null
$UltimaCredsUser = $null


# --- [1] CONFIGURACOES DE LOG ---
$HoraLog = Get-Date -Format "yyyy-MM-dd--HH-mm"
$DiretorioBase = $PSScriptRoot
$ArquivoLog = Join-Path $DiretorioBase "smartcheck-report_$HoraLog.log"
Start-Transcript -Path $ArquivoLog -Append -Force | Out-Null


# --- [2] BANNER E CONFIRMACAO INICIAL ---
Clear-Host
$CompName = $env:COMPUTERNAME
$DomainName = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name
$CurrDate = Get-Date -Format "dd/MM/yyyy HH:mm"

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "           VALIDADOR DE CONTA DE SERVICO ADDHOSTS - ADDS"
Write-Host "           Versao: $ScriptVersion"
Write-Host "======================================================================"
Write-Host "           Servidor: $CompName"
Write-Host "           Dominio:  $DomainName"
Write-Host "           Data/Hora: $CurrDate"
Write-Host "======================================================================"
Write-Host "    AVISO: Este script realizara a Criacao/Exclusao" -ForegroundColor Yellow
Write-Host "           de objetos Computador com nomes temporarios." -ForegroundColor Yellow
Write-Host "           Padrao: SRV-XXMMM_YYYYY (ex: SRV-01JAN_1A3F2)" -ForegroundColor Gray
Write-Host ""

$Confirm = Read-Host " Deseja prosseguir com a operacao? (S/N)"
if ($Confirm -ne "S") { 
    Write-Host " Operacao cancelada pelo usuario." -ForegroundColor Red
    Stop-Transcript
    exit 
}


# --- [3] FUNCOES AUXILIARES ---

# Funcao: Verificacao do Ambiente AD
function Test-ADEnvironment {
    try {
        $DomainInfo = Get-ADDomain
        $Global:DomainDNS = $DomainInfo.DNSRoot
        $Global:DomainDN = $DomainInfo.DistinguishedName
        return $true
    } catch {
        Write-Host "ERRO: Ambiente Active Directory nao detectado ou modulo indisponivel." -ForegroundColor Red
        return $false
    }
}

# Funcao: Exibicao do Banner Dinamico
function Show-Banner {
    param([string]$Titulo = "VALIDADOR DE CONTA DE SERVICO ADDHOSTS - ADDS")
    Clear-Host
    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Yellow
    Write-Host "       $Titulo - v$ScriptVersion" -ForegroundColor Yellow
    Write-Host "       Dominio: $DomainDNS" -ForegroundColor Yellow
    Write-Host "======================================================================" -ForegroundColor Yellow
    Write-Host ""
}

# Funcao: Validar e Corrigir Formato do DN
function Test-AndFix-DNFormat {
    param([string]$InputDN)
    
    # Se o DN ja começa com OU=, esta correto
    if ($InputDN -match "^OU=") {
        return $InputDN
    }
    
    # Verifica se o usuario digitou apenas o nome da OU (ex: "Core" ou "Core,OU=_ACMELABS,...")
    if ($InputDN -match "^[^,]+(,|$)") {
        # Extrai a primeira parte (possivel nome da OU)
        $firstPart = $InputDN -replace "\,.*$", ""
        
        # Se a primeira parte NAO comeca com OU=, assume que e o nome da OU
        if ($firstPart -notmatch "^OU=") {
            $suggestedDN = "OU=$InputDN"
            Write-Host ""
            Write-Host " [!] Detectado possivel erro de formato no DN." -ForegroundColor Yellow
            Write-Host "     Digitado: $InputDN" -ForegroundColor Gray
            Write-Host "     Sugestao: $suggestedDN" -ForegroundColor Cyan
            Write-Host ""
            Write-Host " Deseja usar a sugestao de correcao? (S/N)" -ForegroundColor White
            $useSuggestion = Read-Host
            if ($useSuggestion -eq "S") {
                return $suggestedDN
            }
        }
    }
    
    # Retorna o original se nao conseguiu corrigir
    return $InputDN
}

# Funcao: Validacao da Service Account
function Get-ServiceCredential {
    Write-Host "[ETAPA 1] - Validacao da Conta de Servico" -ForegroundColor Yellow
    Write-Host "======================================================================" -ForegroundColor Yellow
    $User = Read-Host " Por favor, digite apenas o nome da conta de servico"
    if ([string]::IsNullOrWhiteSpace($User)) { return $null }
    Write-Host ""
    
    $Pass = Read-Host " Digite a senha" -AsSecureString
    $UPN  = "$User@$DomainDNS"
    
    try {
        $AuthCred = New-Object System.Management.Automation.PSCredential($UPN, $Pass)
        Get-ADDomain -Credential $AuthCred | Out-Null
        Write-Host " [+] Credencial validada com autenticacao no dominio." -ForegroundColor Green
        Start-Sleep -Seconds 2
        return $AuthCred
    } catch {
        Write-Host " [!] ERRO: Falha de Logon para $UPN. Verifique conta/senha." -ForegroundColor Red
        Write-Host "     Detalhe: $($_.Exception.Message.Split('.')[0])" -ForegroundColor Gray
        Start-Sleep -Seconds 4
        return $null
    }
}

# Funcao: Validacao da OU (com correcao de formato)
function Get-ValidatedOU {
    param(
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.PSCredential]$Credential
    )
    
    Show-Banner "DEFINICAO DE ESCOPO"
    Write-Host " Informe o DistinguishedName (DN) da OU para o teste de escrita."
    Write-Host ""
    Write-Host " FORMATO CORRETO:" -ForegroundColor Cyan
    Write-Host "   OU=NomeDaOU,OU=Pai,DC=dominio,DC=com" -ForegroundColor White
    Write-Host ""
    Write-Host " EXEMPLOS:" -ForegroundColor Gray
    Write-Host "   OU=Servidores,DC=empresa,DC=com" -ForegroundColor Gray
    Write-Host "   OU=Workstations,OU=Matriz,DC=empresa,DC=com" -ForegroundColor Gray
    Write-Host ""
    
    $TargetOU = Read-Host " DN da OU"
    
    # Validar se esta vazio
    if ([string]::IsNullOrWhiteSpace($TargetOU)) {
        Write-Host " [!] ERRO: DN da OU nao pode estar vazio." -ForegroundColor Red
        Start-Sleep -Seconds 4
        return $null
    }
    
    # Tentar corrigir o formato do DN
    $OriginalOU = $TargetOU
    $TargetOU = Test-AndFix-DNFormat -InputDN $TargetOU
    
    if ($OriginalOU -ne $TargetOU) {
        Write-Host ""
        Write-Host " [+] Usando DN corrigido: $TargetOU" -ForegroundColor Green
        Start-Sleep -Seconds 2
    }
    
    # Validacao basica da OU (sintaxe e existencia)
    try {
        $ouExists = Get-ADOrganizationalUnit -Identity $TargetOU -ErrorAction Stop
        Write-Host " [+] OU validada com sucesso: $($ouExists.Name)" -ForegroundColor Green
        return $TargetOU
    } catch {
        Write-Host ""
        Write-Host " [!] ERRO: Nao foi possivel localizar a OU especificada." -ForegroundColor Red
        Write-Host "     DN informado: $TargetOU" -ForegroundColor Yellow
        Write-Host "     Erro: $($_.Exception.Message.Split('.')[0])" -ForegroundColor Gray
        Write-Host ""
        Write-Host "     Verifique:" -ForegroundColor Cyan
        Write-Host "     1. O DN comeca com 'OU=' ?" -ForegroundColor White
        Write-Host "     2. Os nomes das OUs estao corretos?" -ForegroundColor White
        Write-Host "     3. Os componentes DC= estao corretos?" -ForegroundColor White
        Write-Host ""
        
        Read-Host " Pressione Enter para tentar novamente"
        return $null
    }
}

# Funcao: Validacao de Acesso a OU com a Service Account
function Test-OUAccess {
    param(
        [Parameter(Mandatory=$true)]
        [string]$OUPath,
        [Parameter(Mandatory=$true)]
        [System.Management.Automation.PSCredential]$Credential
    )
    
    Write-Host "[ETAPA 2] - Validando Acesso da Service Account a OU" -ForegroundColor Yellow
    Write-Host "======================================================================" -ForegroundColor Yellow
    
    try {
        Get-ADOrganizationalUnit -Identity $OUPath -Credential $Credential -ErrorAction Stop | Out-Null
        Write-Host " [+] Service account tem acesso de LEITURA a OU." -ForegroundColor Green
        Write-Host "     Podera prosseguir com os testes de CRIACAO/EXCLUSAO." -ForegroundColor Gray
        Start-Sleep -Seconds 3
        return $true
    } catch {
        Write-Host " [!] ATENCAO: Service account NAO tem acesso de leitura a OU." -ForegroundColor Red
        Write-Host "     Caminho: $OUPath" -ForegroundColor Yellow
        Write-Host "     Erro: $($_.Exception.Message.Split('.')[0])" -ForegroundColor Gray
        Write-Host ""
        Write-Host "     Isso resultara em FALHA nos testes de criacao/exclusao." -ForegroundColor Yellow
        Write-Host "     Deseja continuar mesmo assim para confirmar a falha? (S/N)" -ForegroundColor Cyan
        
        $continuar = Read-Host
        if ($continuar -ne "S") { 
            Write-Host " Operacao cancelada. Tente outra OU ou verifique permissoes da conta." -ForegroundColor Red
            return $false
        }
        Write-Host " Continuando para demonstrar a falha de permissao..." -ForegroundColor Yellow
        return $null  # Retorna null para indicar que nao tem acesso mas continuara mesmo assim
    }
}

# Funcao: Gerar nome de computador no padrao SRV-XXMMM_YYYYY
function Generate-ComputerName {
    param(
        [Parameter(Mandatory=$true)]
        [int]$MonthNumber,
        [Parameter(Mandatory=$true)]
        [string]$MonthAbbrev
    )
    
    $SuffixoRandom = "{0:X5}" -f (Get-Random -Maximum 1048575)  # Range: 0x00000 a 0xFFFFF
    $ComputerName = "SRV-{0:D2}{1}_{2}" -f $MonthNumber, $MonthAbbrev, $SuffixoRandom
    return $ComputerName
}

# Funcao: Exibir Relatorio Detalhado
function Show-DetailedReport {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServiceAccount,
        [Parameter(Mandatory=$true)]
        [string]$TargetOU
    )
    
    Show-Banner "RELATORIO DETALHADO DA SESSAO"
    
    Write-Host " Conta testada: $ServiceAccount" -ForegroundColor Cyan
    Write-Host " OU testada: $TargetOU" -ForegroundColor Cyan
    Write-Host " Data/Hora: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "------------------------------------------------------------------------"
    
    # Relatorio de Criacao
    Write-Host "[TESTE DE CRIACAO]" -ForegroundColor Yellow
    if ($ResultadosCriacao.Count -eq 0) {
        Write-Host " Nenhum teste de criacao realizado nesta sessao." -ForegroundColor Gray
    } else {
        $sucessosCriacao = ($ResultadosCriacao | Where-Object { $_.Status -eq "SUCESSO" }).Count
        $falhasCriacao = ($ResultadosCriacao | Where-Object { $_.Status -eq "FALHA" }).Count
        
        Write-Host " Total tentativas: $($ResultadosCriacao.Count)" -ForegroundColor White
        Write-Host " Sucessos: $sucessosCriacao" -ForegroundColor Green
        Write-Host " Falhas: $falhasCriacao" -ForegroundColor Red
        
        if ($sucessosCriacao -eq 12) {
            Write-Host ""
            Write-Host " RESULTADO: ✅ Service account tem PERMISSAO TOTAL de CRIACAO na OU" -ForegroundColor Green
        } elseif ($sucessosCriacao -gt 0) {
            Write-Host ""
            Write-Host " RESULTADO: ⚠️ Service account tem PERMISSAO PARCIAL de CRIACAO na OU" -ForegroundColor Yellow
            Write-Host "            ($sucessosCriacao de 12 objetos criados com sucesso)" -ForegroundColor Gray
        } else {
            Write-Host ""
            Write-Host " RESULTADO: ❌ Service account NAO TEM permissao de CRIACAO na OU" -ForegroundColor Red
        }
        
        # Exibir detalhes das falhas se houver
        if ($falhasCriacao -gt 0) {
            Write-Host ""
            Write-Host " Detalhe das falhas de CRIACAO:" -ForegroundColor Yellow
            $ResultadosCriacao | Where-Object { $_.Status -eq "FALHA" } | ForEach-Object {
                Write-Host "   - $($_.Computador): $($_.Mensagem)" -ForegroundColor Gray
            }
        }
    }
    
    Write-Host ""
    Write-Host "------------------------------------------------------------------------"
    
    # Relatorio de Exclusao
    Write-Host "[TESTE DE EXCLUSAO]" -ForegroundColor Yellow
    if ($ResultadosExclusao.Count -eq 0) {
        Write-Host " Nenhum teste de exclusao realizado nesta sessao." -ForegroundColor Gray
    } else {
        $sucessosExclusao = ($ResultadosExclusao | Where-Object { $_.Status -eq "SUCESSO" }).Count
        $falhasExclusao = ($ResultadosExclusao | Where-Object { $_.Status -eq "FALHA" }).Count
        
        Write-Host " Total objetos encontrados: $($ResultadosExclusao.Count)" -ForegroundColor White
        Write-Host " Removidos com sucesso: $sucessosExclusao" -ForegroundColor Green
        Write-Host " Falhas na remocao: $falhasExclusao" -ForegroundColor Red
        
        if ($sucessosExclusao -eq $ResultadosExclusao.Count -and $ResultadosExclusao.Count -gt 0) {
            Write-Host ""
            Write-Host " RESULTADO: ✅ Service account tem PERMISSAO TOTAL de EXCLUSAO na OU" -ForegroundColor Green
        } elseif ($sucessosExclusao -gt 0) {
            Write-Host ""
            Write-Host " RESULTADO: ⚠️ Service account tem PERMISSAO PARCIAL de EXCLUSAO na OU" -ForegroundColor Yellow
            Write-Host "            ($sucessosExclusao de $($ResultadosExclusao.Count) objetos removidos)" -ForegroundColor Gray
        } else {
            Write-Host ""
            Write-Host " RESULTADO: ❌ Service account NAO TEM permissao de EXCLUSAO na OU" -ForegroundColor Red
        }
        
        # Exibir detalhes das falhas se houver
        if ($falhasExclusao -gt 0) {
            Write-Host ""
            Write-Host " Detalhe das falhas de EXCLUSAO:" -ForegroundColor Yellow
            $ResultadosExclusao | Where-Object { $_.Status -eq "FALHA" } | ForEach-Object {
                Write-Host "   - $($_.Computador): $($_.Mensagem)" -ForegroundColor Gray
            }
        }
    }
    
    Write-Host ""
    Write-Host "------------------------------------------------------------------------"
    Write-Host " NOTA: Para uso em IaC (Infraestrutura como Codigo), a conta deve" -ForegroundColor Cyan
    Write-Host "       apresentar PERMISSAO TOTAL tanto para CRIACAO quanto para" -ForegroundColor Cyan
    Write-Host "       EXCLUSAO de objetos computador na OU especificada." -ForegroundColor Cyan
    Write-Host "==========================================================================" -ForegroundColor Yellow
    
    Read-Host "`n Pressione Enter para voltar ao menu..."
}


# --- [4] VERIFICACAO INICIAL DO AMBIENTE ---
if (-not (Test-ADEnvironment)) {
    Write-Host "Script encerrado devido a falha no ambiente AD." -ForegroundColor Red
    Stop-Transcript
    exit
}


# --- [5] LOOP PRINCIPAL (LOGIN E SELECAO DE OU) ---
$GlobalExit = $false

while (-not $GlobalExit) {
    Show-Banner "LOGIN DO AGENTE DE TESTE"
    $Creds = Get-ServiceCredential
    
    if ($null -eq $Creds) { 
        Write-Host "`n Falha na autenticacao. Tente novamente." -ForegroundColor Red
        Start-Sleep -Seconds 4
        continue 
    }
    
    # Solicitacao e validacao da OU Alvo (agora com correcao de formato)
    $TargetOU = Get-ValidatedOU -Credential $Creds
    if ($null -eq $TargetOU) {
        continue  # Usuario erro na digitacao, volta ao inicio
    }
    
    # Validacao de acesso a OU com a Service Account
    $AccessResult = Test-OUAccess -OUPath $TargetOU -Credential $Creds
    if ($AccessResult -eq $false) {
        continue  # Usuario optou por cancelar
    }
    
    # Armazena informacoes da sessao atual
    $UltimaOUSelected = $TargetOU
    $UltimaCredsUser = $Creds.UserName
    $ResultadosCriacao = @()  # Reset dos resultados a cada nova OU/credencial
    $ResultadosExclusao = @()
    
    $InnerExit = $false


# --- [6] MENU DE OPERACOES ---
    do {
        Show-Banner "PAINEL DE CONTROLE - CONTA: $($Creds.UserName)"
        Write-Host " OU Alvo: $TargetOU" -ForegroundColor Cyan
        Write-Host " Objetos Criados nesta sessao: $($ResultadosCriacao.Count)/12" -ForegroundColor $(if ($ResultadosCriacao.Count -eq 12) { "Green" } else { "Gray" })
        Write-Host " Objetos Removidos nesta sessao: $($ResultadosExclusao.Count)" -ForegroundColor Gray
        Write-Host "------------------------------------------------------------------------"
        Write-Host " 1) Testar CRIACAO (12 objetos SRV-XXMMM_YYYYY)" -ForegroundColor White
        Write-Host " 2) Testar EXCLUSAO (Limpeza dos objetos criados na sessao)" -ForegroundColor White
        Write-Host " 3) Alterar OU" -ForegroundColor White
        Write-Host " 4) Alterar Credencial (Logoff)" -ForegroundColor White
        Write-Host " 5) Relatorio Detalhado (sessao atual)" -ForegroundColor White
        Write-Host " 6) Sair do Script" -ForegroundColor White
        
        $Opt = Read-Host "`n Selecione uma opcao"
        
        switch ($Opt) {
            "1" {
                Write-Host "`n[OPERACAO] - Iniciando criacao em lote de 12 objetos..." -ForegroundColor Yellow
                Write-Host "------------------------------------------------------------------------"
                
                for ($i=0; $i -lt 12; $i++) {
                    $MesNum = $i + 1
                    $MonthAbbrev = $MesesAbrev[$i]
                    $ComputerName = Generate-ComputerName -MonthNumber $MesNum -MonthAbbrev $MonthAbbrev
                    
                    try {
                        New-ADComputer -Name $ComputerName -Path $TargetOU -Credential $Creds -Enabled $false -ErrorAction Stop
                        Write-Host " [$($MesNum.ToString().PadLeft(2,'0'))/12] [+] OK: $ComputerName criado." -ForegroundColor Green
                        
                        $ResultadosCriacao += [PSCustomObject]@{
                            Computador = $ComputerName
                            Status = "SUCESSO"
                            Mensagem = "Criado com sucesso em $TargetOU"
                        }
                    } catch {
                        Write-Host " [$($MesNum.ToString().PadLeft(2,'0'))/12] [-] FALHA: $ComputerName" -ForegroundColor Red
                        Write-Host "            Erro: $($_.Exception.Message.Split('.')[0])" -ForegroundColor Gray
                        
                        $ResultadosCriacao += [PSCustomObject]@{
                            Computador = $ComputerName
                            Status = "FALHA"
                            Mensagem = $_.Exception.Message.Split('.')[0]
                        }
                    }
                    
                    Start-Sleep -Milliseconds 500
                }
                
                $sucessos = ($ResultadosCriacao | Where-Object { $_.Status -eq "SUCESSO" }).Count
                Write-Host "------------------------------------------------------------------------"
                Write-Host " RESUMO CRIACAO: $sucessos/12 objetos criados com sucesso." -ForegroundColor $(if ($sucessos -eq 12) { "Green" } elseif ($sucessos -gt 0) { "Yellow" } else { "Red" })
                
                if ($sucessos -eq 12) {
                    Write-Host " RESULTADO: Service account tem permissao TOTAL de CRIACAO na OU" -ForegroundColor Green
                } elseif ($sucessos -gt 0) {
                    Write-Host " RESULTADO: Service account tem permissao PARCIAL de CRIACAO na OU" -ForegroundColor Yellow
                } else {
                    Write-Host " RESULTADO: Service account NAO TEM permissao de CRIACAO na OU" -ForegroundColor Red
                }
                
                Read-Host "`n Pressione Enter para voltar ao menu..."
            }
            
            "2" {
                Write-Host "`n[OPERACAO] - Iniciando exclusao dos objetos de teste..." -ForegroundColor Yellow
                Write-Host "------------------------------------------------------------------------"
                
                if ($ResultadosCriacao.Count -eq 0) {
                    Write-Host " ATENCAO: Nenhum objeto de teste foi criado nesta sessao." -ForegroundColor Yellow
                    Write-Host " Execute primeiro a opcao 1 (Criacao) para gerar objetos." -ForegroundColor Gray
                    Read-Host "`n Pressione Enter para voltar ao menu..."
                    continue
                }
                
                $objetosParaRemover = $ResultadosCriacao | Where-Object { $_.Status -eq "SUCESSO" }
                
                if ($objetosParaRemover.Count -eq 0) {
                    Write-Host " ATENCAO: Nenhum objeto foi criado com sucesso para remocao." -ForegroundColor Yellow
                    Read-Host "`n Pressione Enter para voltar ao menu..."
                    continue
                }
                
                Write-Host " Encontrados $($objetosParaRemover.Count) objetos para remocao." -ForegroundColor Gray
                Write-Host ""
                
                foreach ($obj in $objetosParaRemover) {
                    try {
                        Remove-ADComputer -Identity $obj.Computador -Credential $Creds -Confirm:$false -ErrorAction Stop
                        Write-Host " [x] REMOVIDO: $($obj.Computador)" -ForegroundColor Green
                        
                        $ResultadosExclusao += [PSCustomObject]@{
                            Computador = $obj.Computador
                            Status = "SUCESSO"
                            Mensagem = "Removido com sucesso do AD"
                        }
                    } catch {
                        Write-Host " [!] FALHA: $($obj.Computador)" -ForegroundColor Red
                        Write-Host "        Erro: $($_.Exception.Message.Split('.')[0])" -ForegroundColor Gray
                        
                        $ResultadosExclusao += [PSCustomObject]@{
                            Computador = $obj.Computador
                            Status = "FALHA"
                            Mensagem = $_.Exception.Message.Split('.')[0]
                        }
                    }
                    
                    Start-Sleep -Milliseconds 300
                }
                
                $sucessos = ($ResultadosExclusao | Where-Object { $_.Status -eq "SUCESSO" }).Count
                $total = $objetosParaRemover.Count
                Write-Host "------------------------------------------------------------------------"
                Write-Host " RESUMO EXCLUSAO: $sucessos/$total objetos removidos com sucesso." -ForegroundColor $(if ($sucessos -eq $total) { "Green" } elseif ($sucessos -gt 0) { "Yellow" } else { "Red" })
                
                if ($sucessos -eq $total -and $total -gt 0) {
                    Write-Host " RESULTADO: Service account tem permissao TOTAL de EXCLUSAO na OU" -ForegroundColor Green
                } elseif ($sucessos -gt 0) {
                    Write-Host " RESULTADO: Service account tem permissao PARCIAL de EXCLUSAO na OU" -ForegroundColor Yellow
                } else {
                    Write-Host " RESULTADO: Service account NAO TEM permissao de EXCLUSAO na OU" -ForegroundColor Red
                }
                
                Read-Host "`n Pressione Enter para voltar ao menu..."
            }
            
            "3" { 
                Write-Host "`n Alterando OU de destino..." -ForegroundColor Yellow
                $TargetOU = Get-ValidatedOU -Credential $Creds
                if ($null -eq $TargetOU) {
                    Write-Host " Operacao cancelada. Mantendo OU anterior." -ForegroundColor Red
                    $TargetOU = $UltimaOUSelected
                } else {
                    $UltimaOUSelected = $TargetOU
                    Write-Host " [+] Nova OU definida: $TargetOU" -ForegroundColor Green
                    $ResultadosCriacao = @()
                    $ResultadosExclusao = @()
                }
                Start-Sleep -Seconds 2
            }
            
            "4" { 
                Write-Host "`n Realizando logoff e limpando sessao..." -ForegroundColor Yellow
                $ResultadosCriacao = @()
                $ResultadosExclusao = @()
                $InnerExit = $true
                Start-Sleep -Seconds 1
            }
            
            "5" {
                Show-DetailedReport -ServiceAccount $Creds.UserName -TargetOU $TargetOU
            }
            
            "6" { 
                Write-Host "`n Encerrando script conforme solicitado..." -ForegroundColor Yellow
                $InnerExit = $true
                $GlobalExit = $true
            }
            
            default {
                Write-Host " Opcao invalida! Digite 1, 2, 3, 4, 5 ou 6." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    } while (-not $InnerExit)


# --- [7] FINALIZACAO ---
Write-Host ""
Write-Host "==========================================================================" -ForegroundColor White
Write-Host " Finalizando sessao e gerando relatorio final..." -ForegroundColor Green
Write-Host "==========================================================================" -ForegroundColor White
Write-Host ""
Write-Host " Log de execucao disponivel em: $ArquivoLog" -ForegroundColor Gray
Write-Host ""

Stop-Transcript
Write-Host " Script encerrado com sucesso." -ForegroundColor Green