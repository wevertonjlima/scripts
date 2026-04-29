# ==============================================================================
# Script: ADO_Import_v7.1
# Funcao: Reconstrucao de objetos AD via CSV com Menu de Granularidade
# 
# IMPORTANTE: Ao realizar qualquer alteracao na logica ou compatibilidade, 
# atualize a variavel $ScriptVersion abaixo e a data do LOG de alteracoes.
#
# Versao: 7.1 Odometer
# Alteracao: 2024-05-23 (Inclusao de Submenu de Niveis de Importacao)
# ==============================================================================

Param(
    [Parameter(Mandatory=$false, Position=0, HelpMessage="Caminho da pasta CSV")]
    [String]$Path,
    [Parameter(Mandatory=$false)] [Switch]$i, # Chave para IMPORTACAO REAL (Red)
    [Parameter(Mandatory=$false)] [Switch]$s  # Chave para SIMULACAO (Yellow)
)

# --- [0] METADADOS E VERSAO ---
$ScriptVersion = "7.1"

# --- [03] VALIDACAO DE PRIVILEGIO ---
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] ERRO: Este script exige privilegios de Administrador." -ForegroundColor Red
    exit
}

# --- [04] CONFIGURACAO DE AMBIENTE E LOG (FROZEN) ---
$HoraLog = Get-Date -Format "yyyy-MM-dd--HH-mm"
$DiretorioBase = $PSScriptRoot
$ArquivoLog = Join-Path $DiretorioBase "Import_Event_$HoraLog.log"
Start-Transcript -Path $ArquivoLog -Append -Force | Out-Null

# --- [05] SYSTEM_INFO ENGINE (FROZEN) ---
try {
    $computername = $env:COMPUTERNAME
    $WindowsVersion = (Get-CimInstance Win32_OperatingSystem).Caption
    $ADInfo = Get-ADDomain
    $domain_name = $ADInfo.DNSRoot
    $domainDN = $ADInfo.DistinguishedName
    $User = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $date = Get-Date -Format "dd/MM/yyyy"
    $time = Get-Date -Format "HH:mm:ss"
} catch {
    Write-Host "[!] ERRO CRITICO: Active Directory inacessivel." -ForegroundColor Red
    Stop-Transcript ; exit
}

# --- [06] DEFINICAO DE MODO E CORES ---
$ModoStatus = "[ MODO DE OPERACAO - TUTORIAL ]"; $CorModo = "Green"
if ($s) { $ModoStatus = "[ MODO DE OPERACAO - SIMULACAO ]"; $CorModo = "Yellow" }
elseif ($i) { $ModoStatus = "[ MODO DE OPERACAO - IMPORTACAO ]"; $CorModo = "Red" }

# --- [07] EXIBICAO DO BANNER ---
Clear-Host
Write-Host "========================================================================================" -ForegroundColor White
Write-Host "                AD ODOMETER - SISTEMA DE IMPORTACAO DE OBJETOS AD                       " -ForegroundColor Green
Write-Host "                Versao: $ScriptVersion                                                  " -ForegroundColor Yellow
Write-Host "========================================================================================" -ForegroundColor White
Write-Host "    " -NoNewline; Write-Host $ModoStatus -ForegroundColor $CorModo
Write-Host ""
Write-Host "    Executado em ..........: " -NoNewline; Write-Host $computername -ForegroundColor Yellow
Write-Host "    Sistema Operacional ...: " -NoNewline; Write-Host $WindowsVersion -ForegroundColor Yellow
Write-Host "    Active Directory ......: " -NoNewline; Write-Host $domain_name -ForegroundColor Yellow
Write-Host "    User ..................: " -NoNewline; Write-Host $User -ForegroundColor Yellow
Write-Host "    Date & Time ...........: " -NoNewline; Write-Host "$date // $time" -ForegroundColor Yellow
Write-Host ""
Write-Host "========================================================================================" -ForegroundColor White

# --- [08] LOGICA DE FLUXO E TUTORIAL ---
if (!$i -and !$s) {
    Write-Host " [?] COMO UTILIZAR ESTE SCRIPT:" -ForegroundColor White 
    Write-Host " ------------------------------" -ForegroundColor White 
    Write-Host " .\ADO_Import_v6.1.ps1 -s <Pasta_CSV>  # Simula" -ForegroundColor Yellow
    Write-Host " .\ADO_Import_v6.1.ps1 -i <Pasta_CSV>  # Importa" -ForegroundColor Red
    Stop-Transcript; exit
}

if ([string]::IsNullOrWhiteSpace($Path) -or !(Test-Path $Path)) {
    Write-Host "[!] ERRO: Caminho de origem invalido." -ForegroundColor Red
    Stop-Transcript; exit
}

Write-Host "[!] ATENCAO: Voce esta prestes a injetar objetos no dominio $domain_name." -ForegroundColor Yellow
$Confirmacao = Read-Host " Deseja prosseguir? (S/N)"
if ($Confirmacao -notmatch "[Ss]") { Stop-Transcript; exit }

# --- [8.5] SUBMENU DE NIVEIS DE IMPORTACAO ---
Write-Host "`n SELECIONE O NIVEL DE IMPORTACAO:" -ForegroundColor Cyan
Write-Host " 1) Importar apenas OUs" -ForegroundColor White
Write-Host " 2) Importar OUs, Computadores e Grupos (Sem Membership)" -ForegroundColor White
Write-Host " 3) Importacao Completa (OUs, Comps, Grupos, Users e Members)" -ForegroundColor White
$NivelEscolha = Read-Host "`n Escolha uma opcao (1-3)"

switch ($NivelEscolha) {
    "1" { $ImportLevel = 1; Write-Host " -> Definido: Apenas OUs." -ForegroundColor Green }
    "2" { $ImportLevel = 2; Write-Host " -> Definido: OUs, Computadores e Grupos." -ForegroundColor Green }
    "3" { $ImportLevel = 3; Write-Host " -> Definido: Importacao Completa." -ForegroundColor Green }
    Default { Write-Host "[!] Opcao invalida. Abortando."; Stop-Transcript; exit }
}

# --- [09] MOTOR ODOMETER ---
function Set-Odometer {
    param($CurrentCount)
    Write-Host "`r====================>> [ " -NoNewline -ForegroundColor White
    Write-Host "$CurrentCount" -NoNewline -ForegroundColor Yellow
    Write-Host " ]" -NoNewline -ForegroundColor White
}

# --- [10] MOTOR DE IMPORTACAO ---
$OU_OK = 0; $OU_Err = 0; $CP_OK = 0; $CP_Err = 0; $GP_OK = 0; $GP_Err = 0; $US_OK = 0; $US_Err = 0; $Mem_OK = 0; $Mem_Err = 0
$ArquivoErroLog = Join-Path $DiretorioBase "ADO_Import_ErrorsEvent_$($HoraLog).log"
"--- LOG DE ERROS AD ODOMETER - $date $time ---" | Out-File $ArquivoErroLog

# 10.1 OUs
$CSV_OU = Join-Path $Path "01_OUs.csv"
if (Test-Path $CSV_OU) {
    $SourceDN = (Import-Csv $CSV_OU | Select-Object -First 1).DistinguishedName.Substring((Import-Csv $CSV_OU | Select-Object -First 1).DistinguishedName.IndexOf("DC="))
    Write-Host "`n[$(Get-Date -Format HH:mm:ss)] [1/5] Processando OUs ..." -ForegroundColor Green
    Import-Csv $CSV_OU | Sort-Object { $_.DistinguishedName.Split(',').Count } | ForEach-Object {
        $obj = $_; $OU_TotalCount++; Set-Odometer $OU_TotalCount
        $TargetOUDN = $obj.DistinguishedName -replace [regex]::Escape($SourceDN), $domainDN
        if (!(Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$TargetOUDN'" -ErrorAction SilentlyContinue)) {
            $ParentDN = if ($TargetOUDN.Contains(",")) { $TargetOUDN.Substring($TargetOUDN.IndexOf(",") + 1) } else { $domainDN }
            $ouProps = @{ Name=$obj.Name.Trim(); Path=$ParentDN; ProtectedFromAccidentalDeletion=($obj.ProtectedFromAccidentalDeletion -eq 'True'); Description=$obj.Description; StreetAddress=$obj.StreetAddress; City=$obj.City; State=$obj.State; PostalCode=$obj.PostalCode; Country=$obj.Country }
            if($i){ try { New-ADOrganizationalUnit @ouProps -ErrorAction Stop; $OU_OK++ } catch { $OU_Err++; "[OU] Erro $($obj.Name): $($_.Exception.Message)" | Out-File $ArquivoErroLog -Append } }
            elseif ($s) { $OU_OK++ }
        } else { $OU_OK++ }
    }
}

# 10.2 COMPUTADORES
if ($ImportLevel -ge 2) {
    $CSV_Comps = Join-Path $Path "02_Computadores.csv"
    if (Test-Path $CSV_Comps) {
        Write-Host "`n[$(Get-Date -Format HH:mm:ss)] [2/5] Processando Computadores ..." -ForegroundColor Green
        Import-Csv $CSV_Comps | ForEach-Object {
            $obj = $_; $CP_TotalCount++; Set-Odometer $CP_TotalCount
            if (!(Get-ADComputer -Filter "SamAccountName -eq '$($obj.Name.Trim())$'" -ErrorAction SilentlyContinue)) {
                $TargetPath = ($obj.DistinguishedName -replace [regex]::Escape($SourceDN), $domainDN).Substring($obj.DistinguishedName.IndexOf(",") + 1)
                $compProps = @{ Name=$obj.Name.Trim(); Path=$TargetPath; Enabled=($obj.Enabled -eq 'True'); Description=$obj.Description; Location=$obj.Location }
                if($i){ try { New-ADComputer @compProps -ErrorAction Stop; $CP_OK++ } catch { $CP_Err++; "[COMP] Erro $($obj.Name): $($_.Exception.Message)" | Out-File $ArquivoErroLog -Append } }
                elseif ($s) { $CP_OK++ }
            } else { $CP_OK++ }
        }
    }
}

# 10.3 GRUPOS
if ($ImportLevel -ge 2) {
    $CSV_Groups = Join-Path $Path "03_Grupos.csv"
    if (Test-Path $CSV_Groups) {
        Write-Host "`n[$(Get-Date -Format HH:mm:ss)] [3/5] Processando Grupos ..." -ForegroundColor Green
        Import-Csv $CSV_Groups | ForEach-Object {
            $obj = $_; $GP_TotalCount++; Set-Odometer $GP_TotalCount
            if (!(Get-ADGroup -Filter "SamAccountName -eq '$($obj.SamAccountName.Trim())'" -ErrorAction SilentlyContinue)) {
                $TargetPath = ($obj.DistinguishedName -replace [regex]::Escape($SourceDN), $domainDN).Substring($obj.DistinguishedName.IndexOf(",") + 1)
                $gpProps = @{ Name=$obj.Name.Trim(); SamAccountName=$obj.SamAccountName.Trim(); GroupCategory=$obj.GroupCategory; GroupScope=$obj.GroupScope; Path=$TargetPath; Description=$obj.Description }
                $Extras = @{}; if($obj.mail){$Extras.Add("mail",$obj.mail)}; if($obj.info){$Extras.Add("info",$obj.info)}
                if($Extras.Count -gt 0){$gpProps.Add("OtherAttributes", $Extras)}
                if($i){ try { New-ADGroup @gpProps -ErrorAction Stop; $GP_OK++ } catch { $GP_Err++; "[GRUPO] Erro $($obj.SamAccountName): $($_.Exception.Message)" | Out-File $ArquivoErroLog -Append } }
                elseif ($s) { $GP_OK++ }
            } else { $GP_OK++ }
        }
    }
}

# 10.4 USUARIOS
if ($ImportLevel -eq 3) {
    $CSV_Users = Join-Path $Path "04_Usuarios.csv"
    if (Test-Path $CSV_Users) {
        Write-Host "`n[$(Get-Date -Format HH:mm:ss)] [4/5] Processando Usuarios ..." -ForegroundColor Green
        $TempPass = ConvertTo-SecureString "SenhaTemp@123" -AsPlainText -Force
        Import-Csv $CSV_Users | ForEach-Object {
            $obj = $_; $US_TotalCount++; Set-Odometer $US_TotalCount
            if (!(Get-ADUser -Filter "SamAccountName -eq '$($obj.SamAccountName.Trim())'" -ErrorAction SilentlyContinue)) {
                $UserPath = ($obj.DistinguishedName -replace [regex]::Escape($SourceDN), $domainDN).Substring($obj.DistinguishedName.IndexOf(",") + 1)
                $userProps = @{ Name=$obj.Name.Trim(); SamAccountName=$obj.SamAccountName.Trim(); UserPrincipalName="$($obj.SamAccountName.Trim())@$domain_name"; AccountPassword=$TempPass; Enabled=($obj.Enabled -eq 'True'); Path=$UserPath; DisplayName=$obj.DisplayName; GivenName=$obj.GivenName; Surname=$obj.Surname; Description=$obj.Description; Office=$obj.Office; StreetAddress=$obj.StreetAddress; City=$obj.City; State=$obj.State; PostalCode=$obj.PostalCode; Country=$obj.Country; Title=$obj.Title; Department=$obj.Department; Company=$obj.Company; EmailAddress=$obj.EmailAddress; HomePage=$obj.HomePage; OfficePhone=$obj.OfficePhone; ChangePasswordAtLogon=$true }
                if($i){ try { New-ADUser @userProps -ErrorAction Stop; $US_OK++ } catch { $US_Err++; "[USER] Erro $($obj.SamAccountName): $($_.Exception.Message)" | Out-File $ArquivoErroLog -Append } }
                elseif ($s) { $US_OK++ }
            } else { $US_OK++ }
        }
    }
}

# 10.5 MEMBERSHIP
if ($ImportLevel -eq 3) {
    $CSV_Members = Join-Path $Path "05_Membros_Grupos.csv"
    if (Test-Path $CSV_Members) {
        Write-Host "`n[$(Get-Date -Format HH:mm:ss)] [5/5] Processando Membership ..." -ForegroundColor Green
        Import-Csv $CSV_Members | ForEach-Object {
            $obj = $_; $Mem_TotalCount++; Set-Odometer $Mem_TotalCount
            if($i){ try { Add-ADGroupMember -Identity $obj.GroupName -Members $obj.MemberSAM -ErrorAction Stop; $Mem_OK++ } catch { $Mem_Err++; "[MEMB] Erro $($obj.GroupName): $($_.Exception.Message)" | Out-File $ArquivoErroLog -Append } }
            elseif ($s) { $Mem_OK++ }
        }
    }
}

# --- [11] FINALIZACAO ---
Write-Host "`n`n********************************************************" -ForegroundColor White
Write-Host "          Resumo da Operacao (AD Odometer 6.1)"          -ForegroundColor White
Write-Host "********************************************************" -ForegroundColor White
Write-Host "Objeto          | Sucesso         | Falha"               -ForegroundColor White
$Report = @(@{N="OUs";O=$OU_OK;E=$OU_Err},@{N="Computers";O=$CP_OK;E=$CP_Err},@{N="Groups";O=$GP_OK;E=$GP_Err},@{N="Users";O=$US_OK;E=$US_Err},@{N="Members";O=$Mem_OK;E=$Mem_Err})
foreach($r in $Report){ 
    $SucessoDisplay = if($r.O -eq 0 -and $r.E -eq 0){ "N/A (Pulado)" } else { $r.O }
    "{0,-15} | {1,-15} | {2,-15}" -f $r.N, $SucessoDisplay, $r.E | Write-Host -ForegroundColor White 
}
Write-Host "********************************************************" -ForegroundColor White
Write-Host "`nLog de Erros: $ArquivoErroLog" -ForegroundColor Cyan
Stop-Transcript