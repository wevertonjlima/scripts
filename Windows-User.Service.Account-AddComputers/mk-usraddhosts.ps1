# ==============================================================================
# Script: Criacao de usuario de servico com delegacao (Win/Linux)
# Filename: mk-usraddhosts.ps1
# 
# [LOG DE ALTERACOES]
# Versao 1.1.2: Ajuste estetico de cores (White) e quebra de linha no Read-Host.
#
# Versao: 1.1.2
# Data: 2026-04-27
# ==============================================================================

# --- [0] METADADOS E VERSAO ---
$ScriptVersion = "1.1.2"

# --- [1] CONFIGURACOES DE LOG ---
$LogDate = Get-Date -Format "yyyy-MM-dd--HH-mm"
$LogFile = "report_$LogDate.log"

function Write-Log {
    param([string]$Message)
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$TimeStamp - $Message" | Out-File -FilePath $LogFile -Append
}

# --- [2] BANNER E CONFIRMACAO ---
Clear-Host
$CompName = $env:COMPUTERNAME
$DomainName = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name
$CurrDate = Get-Date -Format "dd/MM/yyyy HH:mm"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   AUTOMACAO DE CONTA DE SERVICO - AD DS"
Write-Host "   Versao: $ScriptVersion"
Write-Host "===================================================="
Write-Host " Servidor: $CompName"
Write-Host " Dominio:  $DomainName"
Write-Host " Data/Hora: $CurrDate"
Write-Host "===================================================="
Write-Host " AVISO: Este script realizara alteracoes de seguranca (ACLs)." -ForegroundColor Yellow

$Confirm = Read-Host " Deseja prosseguir com a operacao? (S/N)"
if ($Confirm -ne "S") { 
    Write-Host " Operacao cancelada pelo usuario." -ForegroundColor Red
    exit 
}

# --- [3] ENTRADA DE DADOS E VALIDACAO DE OUs ---

# [ETAPA 1] - Loop para OU de Destino (Computadores)
do {
    $TargetExists = $false
    Write-Host "`n[ETAPA 1] - Container dos Servidores" -ForegroundColor Yellow
    Write-Host "=============================================================" -ForegroundColor Yellow
    Write-Host "Exemplo de formato: OU=Servidores,OU=Recursos,DC=contoso,DC=local" -ForegroundColor White
    Write-Host " Informe o DN da OU que este usuario ira gerenciar (Computadores)" -ForegroundColor White
    $TargetOU = Read-Host " Digite"
    
    if (-not [string]::IsNullOrWhiteSpace($TargetOU)) {
        try {
            $TargetExists = [ADSI]::Exists("LDAP://$TargetOU")
        } catch { $TargetExists = $false }
    }

    if (-not $TargetExists) { 
        Write-Host " ERRO: Unidade Organizacional de destino nao encontrada. Verifique o DN." -ForegroundColor Red
        Write-Log "Erro: [ETAPA 1] OU de destino nao encontrada ou invalida: $TargetOU"
    }
} until ($TargetExists)

# [ETAPA 2] - Loop para OU do Usuario
do {
    $OUExists = $false
    Write-Host "`n[ETAPA 2] - Container da Conta de Servico" -ForegroundColor Yellow
    Write-Host "=============================================================" -ForegroundColor Yellow
    Write-Host " Exemplo de formato: OU=Usuarios Servico,DC=contoso,DC=local" -ForegroundColor White
    Write-Host " Informe o DistinguishedName (DN) da OU onde o USUARIO sera criado" -ForegroundColor White
    $UserOU = Read-Host " Digite"
    
    if (-not [string]::IsNullOrWhiteSpace($UserOU)) {
        try {
            $OUExists = [ADSI]::Exists("LDAP://$UserOU")
        } catch { $OUExists = $false }
    }

    if (-not $OUExists) { 
        Write-Host " ERRO: Unidade Organizacional nao encontrada. Verifique o DN." -ForegroundColor Red
        Write-Log "Erro: [ETAPA 2] OU de usuario nao encontrada ou invalida: $UserOU"
    }
} until ($OUExists)

# --- [4] CRIACAO DO USUARIO E REGRAS DE NOME ---
do {
    $ValidName = $true
    Write-Host "`n[ETAPA 3] - Nome da Conta de Servico" -ForegroundColor Yellow
    Write-Host "=============================================================" -ForegroundColor Yellow
    Write-Host " ATENCAO !!! - Maximo 20 caracteres, sem espacos ou simbolos (exceto _ ou - )." -ForegroundColor White
    Write-Host " Informe o nome da conta de servico (sAMAccountName)" -ForegroundColor White
    $UserName = Read-Host " Digite"

    if ([string]::IsNullOrWhiteSpace($UserName)) {
        Write-Host " ERRO: O nome do usuario nao pode ser vazio." -ForegroundColor Red
        $ValidName = $false
    }
    elseif ($UserName.Length -gt 20) {
        Write-Host " ERRO: O nome '$UserName' e muito longo." -ForegroundColor Red
        $ValidName = $false
    }
    elseif ($UserName -match '[^a-zA-Z0-9_\-]') {
        Write-Host " ERRO: O nome contem espacos ou caracteres invalidos." -ForegroundColor Red
        $ValidName = $false
    }
} while (-not $ValidName)

do {
    Write-Host "`n[DICA]: A senha deve atender aos requisitos de complexidade do seu dominio." -ForegroundColor White
    $Pass1 = Read-Host " Digite a senha para o usuario" -AsSecureString
    $Pass2 = Read-Host " Confirme a senha" -AsSecureString
    $Match = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Pass1)) -eq `
             [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Pass2))
    
    if (-not $Match) { Write-Host " As senhas nao conferem! Tente novamente." -ForegroundColor Red }
} until ($Match)

try {
    Write-Host "`n Criando usuario $UserName..." -ForegroundColor Yellow
    $NewUserObj = New-ADUser -Name $UserName -SamAccountName $UserName -Path $UserOU -AccountPassword $Pass1 -Enabled $true -PasswordNeverExpires $true -PassThru
    Write-Log "Sucesso: Usuario $UserName criado em $UserOU"
} catch {
    Write-Host " Falha ao criar usuario: $_" -ForegroundColor Red
    Write-Log "Erro fatal na criacao do usuario: $_"
    exit
}

# --- [5] DELEGACAO DE PERMISSOES ---
Write-Host " Aplicando delegacao de controle (Windows/Linux Support)..." -ForegroundColor Yellow

try {
    $UserSID = $NewUserObj.SID
    $ACL = Get-Acl -Path "AD:\$TargetOU"

    $ComputerClassGuid = [Guid]"bf967a86-0de6-11d0-a285-00aa003049e2"
    $WriteSPNGuid      = [Guid]"28630eb8-41d5-11d1-a9c1-0000f80367c1"
    $WriteDNSHostGuid  = [Guid]"72e111bd-d222-11d2-8a80-00c04fa31a28"
    
    $ACE1 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($UserSID, "CreateChild,DeleteChild", "Allow", $ComputerClassGuid)
    $ACE2 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($UserSID, "GenericAll", "Allow", "Descendents", $ComputerClassGuid)
    $ACE3 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($UserSID, "WriteProperty", "Allow", $WriteSPNGuid, "Descendents", $ComputerClassGuid)
    $ACE4 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($UserSID, "WriteProperty", "Allow", $WriteDNSHostGuid, "Descendents", $ComputerClassGuid)

    $ACL.AddAccessRule($ACE1)
    $ACL.AddAccessRule($ACE2)
    $ACL.AddAccessRule($ACE3)
    $ACL.AddAccessRule($ACE4)

    Set-Acl -Path "AD:\$TargetOU" -AclObject $ACL
    
    Write-Host " Sucesso! O usuario $UserName agora pode gerenciar computadores na OU informada." -ForegroundColor Green
    Write-Log "Sucesso: Delegacao completa aplicada para $UserName na OU $TargetOU"
} catch {
    Write-Host " Erro ao aplicar permissoes: $_" -ForegroundColor Red
    Write-Log "Erro na delegacao: $_"
}

Write-Host "`n Log gerado em: $LogFile"