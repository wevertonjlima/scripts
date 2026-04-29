# --- [01] DOCUMENTAÇÃO E DIRETRIZES ---
# ==============================================================================
# Author: Weverton Lima <wevertonjlima@gmail.com>
# Powered by: Gemini by Billy - The Microsoft Guru.
# Script: ADO_Export_v7.1.ps1
# Função: Extração massiva e inventário de objetos do AD para CSV com Odometer.
# Versão: 7.1 Odometer
# ------------------------------------------------------------------------------
# DIRETRIZES DE ARQUITETURA (PROTOCOL ODOMETER):
# 1. BLOCOS [04] (LOG) E [05] (SYSINFO) ESTÃO CONGELADOS (FROZEN).
# 2. SUB-BLOCOS DEVEM USAR NUMERAÇÃO DECIMAL (EX: 10.1, 10.2).
# 3. IDENTIDADE VISUAL, BANNER E ODOMETER SÃO IMUTÁVEIS PARA PADRONIZAÇÃO UX.
# 4. ATUALIZAÇÕES DEVEM SER SOLICITADAS VIA "MODO DELTA" SEMPRE QUE POSSÍVEL.
# ==============================================================================

# --- [02] VERSÃO ---
$ScriptVersion = "7.1"

# --- [03] VALIDAÇÃO DE PRIVILÉGIO ---
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] ERRO: Este script exige privilegios de Administrador." -ForegroundColor Red
    exit
}

# --- [04] CONFIGURAÇÃO DE AMBIENTE E LOG (FROZEN) ---
$HoraLog = Get-Date -Format "yyyy-MM-dd--HH-mm"
$PastaCSVName = "CSV_$(Get-Date -Format 'yyyy-MM-dd_HH-mm')"
$DiretorioBase = $PSScriptRoot
$CaminhoExport = Join-Path $DiretorioBase $PastaCSVName
$ArquivoLog = Join-Path $DiretorioBase "Export_Event_$HoraLog.log"
Start-Transcript -Path $ArquivoLog -Append -Force | Out-Null

# --- [05] SYSTEM_INFO ENGINE (FROZEN) ---
try {
    $computername = $env:COMPUTERNAME
    $WindowsVersion = (Get-CimInstance Win32_OperatingSystem).Caption
    $ADInfo = Get-ADDomain
    $domain_name = $ADInfo.DNSRoot
    $User = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $date = Get-Date -Format "dd/MM/yyyy"
    $time = Get-Date -Format "HH:mm:ss"
} catch {
    Write-Host "[!] ERRO CRÍTICO: Active Directory inacessível." -ForegroundColor Red
    Stop-Transcript ; exit
}

# --- [06] EXIBIÇÃO DO BANNER ---
Clear-Host
Write-Host "========================================================================================" -ForegroundColor White
Write-Host "                AD ODOMETER - SISTEMA DE INVENTARIO DE OBJETOS AD                       " -ForegroundColor Green
Write-Host "                Versao: $ScriptVersion | FOCO: PERFORMANCE                              " -ForegroundColor White
Write-Host "========================================================================================" -ForegroundColor White
Write-Host "    [ MODO DE OPERACAO - EXTRACAO ATIVA ]" -ForegroundColor Green
Write-Host ""
Write-Host "    Executado em ..........: " -NoNewline; Write-Host $computername -ForegroundColor Yellow
Write-Host "    Sistema Operacional ...: " -NoNewline; Write-Host $WindowsVersion -ForegroundColor Yellow
Write-Host "    Active Directory ......: " -NoNewline; Write-Host $domain_name -ForegroundColor Yellow
Write-Host "    User ..................: " -NoNewline; Write-Host $User -ForegroundColor Yellow
Write-Host "    Date & Time ...........: " -NoNewline; Write-Host "$date // $time" -ForegroundColor Yellow
Write-Host ""
Write-Host "========================================================================================" -ForegroundColor White

# --- [07] INTERATIVIDADE ---
Write-Host " Deseja iniciar a " -NoNewline; Write-Host " EXPORTACAO TOTAL " -ForegroundColor Green -NoNewline
$Confirmacao = Read-Host "dos objetos deste AD? (S/N)"
if ($Confirmacao -notmatch "[Ss]") { Stop-Transcript ; exit }
if (!(Test-Path $CaminhoExport)) { New-Item -ItemType Directory -Path $CaminhoExport | Out-Null }

# --- [08] MOTOR ODOMETER ---
function Set-Odometer {
    param($CurrentCount)
    Write-Host "`r====================>> [ " -NoNewline -ForegroundColor White
    Write-Host "$CurrentCount" -NoNewline -ForegroundColor Yellow
    Write-Host " ]" -NoNewline -ForegroundColor White
}

# --- [10] MOTOR DE EXPORTAÇÃO ---

# 10.1 - OUs
Write-Host "`n[$(Get-Date -Format HH:mm:ss)] [1/5] Exportando OUs ..." -ForegroundColor Green
$OUCount = 0
Get-ADOrganizationalUnit -Filter * -Properties Description, StreetAddress, City, State, PostalCode, Country | ForEach-Object {
    $OUCount++; Set-Odometer $OUCount; $_ 
} | Select-Object Name, DistinguishedName, ProtectedFromAccidentalDeletion, Description, StreetAddress, City, State, PostalCode, Country | Export-Csv -Path "$CaminhoExport\01_OUs.csv" -NoTypeInformation -Encoding UTF8

# 10.2 - Computadores
Write-Host "`n[$(Get-Date -Format HH:mm:ss)] [2/5] Exportando Computadores ..." -ForegroundColor Green
$CPCount = 0
Get-ADComputer -Filter * -Properties OperatingSystem, OperatingSystemVersion, IPv4Address, Enabled, Description, Location | ForEach-Object {
    $CPCount++; Set-Odometer $CPCount; $_
} | Select-Object Name, SamAccountName, OperatingSystem, OperatingSystemVersion, IPv4Address, Enabled, DistinguishedName, Description, Location | Export-Csv -Path "$CaminhoExport\02_Computadores.csv" -NoTypeInformation -Encoding UTF8

# 10.3 - Grupos
Write-Host "`n[$(Get-Date -Format HH:mm:ss)] [3/5] Exportando Grupos ..." -ForegroundColor Green
$GPCount = 0
Get-ADGroup -Filter * -Properties Description, mail, info | ForEach-Object {
    $GPCount++; Set-Odometer $GPCount; $_
} | Select-Object Name, SamAccountName, GroupCategory, GroupScope, Description, mail, info, DistinguishedName | Export-Csv -Path "$CaminhoExport\03_Grupos.csv" -NoTypeInformation -Encoding UTF8

# 10.4 - Usuários
Write-Host "`n[$(Get-Date -Format HH:mm:ss)] [4/5] Exportando Usuarios ..." -ForegroundColor Green
$USCount = 0
$UserProps = @("GivenName", "Surname", "DisplayName", "Description", "Office", "StreetAddress", "City", "State", "PostalCode", "Country", "Title", "Department", "Company", "EmailAddress", "HomePage", "OfficePhone", "Enabled")
Get-ADUser -Filter * -Properties $UserProps | ForEach-Object {
    $USCount++; Set-Odometer $USCount; $_
} | Select-Object Name, GivenName, Surname, DisplayName, Description, Office, StreetAddress, City, State, PostalCode, Country, Title, Department, Company, EmailAddress, HomePage, OfficePhone, SamAccountName, UserPrincipalName, Enabled, DistinguishedName | Export-Csv -Path "$CaminhoExport\04_Usuarios.csv" -NoTypeInformation -Encoding UTF8

# 10.5 - Membership (Resolução de SamAccountName)
Write-Host "`n[$(Get-Date -Format HH:mm:ss)] [5/5] Exportando Membros (Membership) ..." -ForegroundColor Green
$MemCount = 0
Get-ADGroup -Filter * -Properties Member | ForEach-Object {
    $Group = $_
    foreach ($MemberDN in $Group.Member) {
        $ObjReal = Get-ADObject -Identity $MemberDN -Properties SamAccountName -ErrorAction SilentlyContinue
        if ($ObjReal.SamAccountName) {
            $MemCount++; Set-Odometer $MemCount
            [PSCustomObject]@{ GroupName = $Group.SamAccountName; MemberSAM = $ObjReal.SamAccountName }
        }
    }
} | Export-Csv -Path "$CaminhoExport\05_Membros_Grupos.csv" -NoTypeInformation -Encoding UTF8

# --- [11] FINALIZAÇÃO ---
Write-Host "`n`n========================================================================================" -ForegroundColor White
Write-Host " EXPORTAÇÃO CONCLUÍDA: Arquivos em $CaminhoExport" -ForegroundColor Green
Write-Host "========================================================================================" -ForegroundColor White
Stop-Transcript