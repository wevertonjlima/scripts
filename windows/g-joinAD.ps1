# Importa o módulo Active Directory
Import-Module ActiveDirectory

# Obtém o domínio e o DN
$domain = Get-ADDomain
$domainDN = $domain.DistinguishedName

# Define o caminho padrão para grupos: CN=Users,<domínio>
$defaultGroupContainer = "CN=Users,$domainDN"

# Define o caminho padrão para novos computadores: CN=Computers,<domínio>
$defaultComputerContainer = "CN=Computers,$domainDN"

# Parâmetros para criação do grupo
$groupParams = [ordered]@{
    Name           = 'G-JoinAD'
    SamAccountName = 'G-JoinAD'
    GroupScope     = 'Global'
    GroupCategory  = 'Security'
    Path           = $defaultGroupContainer
    Description    = 'Grupo com permissão para ingressar computadores ao domínio'
}

# Cria o grupo se não existir
if (-not (Get-ADGroup -Filter "Name -eq 'G-JoinAD'" -SearchBase $defaultGroupContainer -ErrorAction SilentlyContinue)) {
    New-ADGroup @groupParams
}

# Obtém o SID do grupo
$group = Get-ADGroup -Identity 'G-JoinAD'
$groupSID = $group.SID

# GUID do objeto computador
$createComputerGUID = [GUID]'BF967A86-0DE6-11D0-A285-00AA003049E2'
$adRights  = [System.DirectoryServices.ActiveDirectoryRights]::CreateChild
$accessType = [System.Security.AccessControl.AccessControlType]::Allow

# Cria ACE
$ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
    $groupSID, $adRights, $accessType, $createComputerGUID
)

# Aplica a permissão na CN=Computers
$ou = [ADSI]"LDAP://$defaultComputerContainer"
$security = $ou.psbase.ObjectSecurity
$security.AddAccessRule($ace)
$ou.psbase.CommitChanges()
