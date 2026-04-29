# ==============================================================================
# Script: ActiveDirectory--Multiverso--FielAoDominio.ps1
# Funcao: Provisionamento Dinamico e Destruicao (Baseado no Dominio AJUBANK)
#
# IMPORTANTE: Ao realizar qualquer alteracao na logica ou compatibilidade, 
# atualize a variavel $ScriptVersion abaixo e a data do LOG de alteracoes.
#
# Versao Inicial: "6.1.0"
# Informar ultima alteracao: 2024-05-22 (Correcao de Idempotencia e Protecao de OU)
# ==============================================================================

# --- [0] METADADOS E VERSAO ---
$ScriptVersion = "6.1.0"

function Exibir-Banner {
    Clear-Host
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "|       Active Directory Ragnarok   [ DC & Marvel ]           |" -ForegroundColor White
    Write-Host "|       Versao: $ScriptVersion                                |" -ForegroundColor White
    Write-Host "===============================================================" -ForegroundColor Cyan
}

# --- [1] FUNCAO: CRIACAO ---
function Criar-Estrutura-Completa {
    try {
        $ADInfo = Get-ADDomain
        $DomainDN = $ADInfo.DistinguishedName
        $DomainDNS = $ADInfo.DNSRoot
        $Password = ConvertTo-SecureString "Senha@123" -AsPlainText -Force
    } catch {
        Write-Host "[ERRO] Sem conexao com o Dominio." -ForegroundColor Red ; return
    }

    $Multiverso = @{
        "Marvel.Comics" = @{
            "New.York"      = @{ "Herois" = "Peter.Parker","Steve.Rogers"; "Viloes" = "Otto.Octavius","Baron.Zemo" }
            "Hell.Kitchens" = @{ "Herois" = "Matt.Murdock","Luke.Cage"; "Viloes" = "Wilson.Fisk","Victor.Doom" }
            "Asgard"        = @{ "Herois" = "Thor","Valquiria"; "Viloes" = "Loki","Hela" }
        }
        "DC.Comics" = @{
            "Metropolis" = @{ "Herois" = "Clark.Kent","Lois.Lane"; "Viloes" = "Lex.Luthor","Max.Lord" }
            "Gotham"     = @{ "Herois" = "Bruce.Wayne","Barbara.Gordon"; "Viloes" = "Harvey.Dent","Pamela.Isley" }
            "Star.City"  = @{ "Herois" = "Oliver.Queen","Hal.Jordan"; "Viloes" = "Arthur.King","Thaal.Sinestro" }
        }
    }

    foreach ($Universo in $Multiverso.Keys) {
        $UniName = ".$Universo"
        $UniPath = "OU=$UniName,$DomainDN"

        # Validacao de existencia da OU Raiz
        $ExistingOU = Get-ADOrganizationalUnit -Filter "Name -eq '$UniName'" -ErrorAction SilentlyContinue
        if (-not $ExistingOU) {
            $OUParams = @{
                Name = $UniName
                Path = $DomainDN
                Description = "Realm $Universo"
                StreetAddress = "4000 Warner Blvd"
                City = "Burbank"
                State = "California"
                PostalCode = "91522"
                Country = "US"
            }
            New-ADOrganizationalUnit @OUParams
        }

        $GDLName = "$($Universo.Replace('.','-').ToUpper())_UNIVERSE"
        if (-not (Get-ADGroup -Filter "Name -eq '$GDLName'" -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $GDLName -GroupScope DomainLocal -Path $UniPath -Description "Grupo $Universo Universe"
            Set-ADGroup -Identity $GDLName -Replace @{ mail="hello@$($Universo.ToLower()).com"; info="Cidades do Multiverso" }
        }

        foreach ($Cidade in $Multiverso[$Universo].Keys) {
            $CityPath = "OU=$Cidade,$UniPath"
            if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$Cidade'" -SearchBase $UniPath -ErrorAction SilentlyContinue)) {
                New-ADOrganizationalUnit -Name $Cidade -Path $UniPath -Description "Cidade de $Cidade"
            }

            foreach ($Alinhamento in $Multiverso[$Universo][$Cidade].Keys) {
                $GroupName = "G.$($Cidade)_$($Alinhamento)"
                if (-not (Get-ADGroup -Filter "Name -eq '$GroupName'" -ErrorAction SilentlyContinue)) {
                    New-ADGroup -Name $GroupName -GroupScope Global -Path $CityPath -Description "$Cidade--$Alinhamento"
                    Add-ADGroupMember -Identity $GDLName -Members $GroupName
                }

                foreach ($Char in $Multiverso[$Universo][$Cidade][$Alinhamento]) {
                    if (-not (Get-ADUser -Filter "SamAccountName -eq '$Char'" -ErrorAction SilentlyContinue)) {
                        $Names = $Char -split "\."
                        $UP = @{
                            Name = $Char.Replace("."," "); SamAccountName = $Char; 
                            UserPrincipalName = "$Char@$DomainDNS"; Path = $CityPath;
                            AccountPassword = $Password; Enabled = $true;
                            Description = "codename: $Alinhamento";
                            Office = "Wayne Enterprises";
                            Title = "Personagem"; Department = "Multiverso"; Company = "Multiverso Corp";
                            EmailAddress = "$($Names[0].ToLower())@multiverso.tech";
                            StreetAddress = "Endereço Padrão"; City = "Houston"; State = "Texas"; PostalCode = "77066"; Country = "US"
                        }
                        New-ADUser @UP
                        Set-ADUser -Identity $Char -OfficePhone "+55 79 5555-0123"
                        Add-ADGroupMember -Identity $GroupName -Members $Char
                    }
                }
            }
        }
    }
    Write-Host "`nMultiverso provisionado com sucesso!" -ForegroundColor Green ; Pause
}

# --- [2] FUNCAO: DESTRUICAO RECURSIVA ---
function Destruir-Multiverso {
    Write-Host "[AVISO] Voce esta prestes a deletar estruturas do AD. Deseja continuar?" -ForegroundColor Yellow
    $Universos = @(".DC.Comics", ".Marvel.Comics")
    $DomainDN = (Get-ADDomain).DistinguishedName
    
    foreach ($Uni in $Universos) {
        $Target = "OU=$Uni,$DomainDN"
        if (Get-ADOrganizationalUnit -Identity $Target -ErrorAction SilentlyContinue) {
            # Idempotencia: Desativa protecao de todas as sub-OUs e da OU pai antes de deletar
            Get-ADOrganizationalUnit -Filter * -SearchBase $Target | Set-ADOrganizationalUnit -ProtectedFromAccidentalDeletion $false
            
            # Remove a arvore completa
            Remove-ADOrganizationalUnit -Identity $Target -Recursive -Confirm:$false
            Write-Host "[DESTRUIDO] $Uni" -ForegroundColor Red
        } else {
            Write-Host "[INFO] Estrutura $Uni nao encontrada. Nada a fazer." -ForegroundColor Gray
        }
    }
    Pause
}

# --- [3] MENU ---
do {
    Exibir-Banner
    Write-Host "1) Criar Multiverso (Fiel aos Prints)"
    Write-Host "2) Destruir Multiverso (Recursivo)"
    Write-Host "3) Sair"
    $Op = Read-Host "`nOpcao"
    switch ($Op) { 
        "1" { Criar-Estrutura-Completa } 
        "2" { Destruir-Multiverso } 
    }
} while ($Op -ne "3")