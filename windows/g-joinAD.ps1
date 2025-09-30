<#
Script PowerShell: Delegação de Permissão para Ingressar Computadores no Domínio

Objetivo:
---------
Este script PowerShell automatiza a criação de um grupo de segurança no Active Directory e delega a ele a permissão de
**criar objetos de computador** no contêiner padrão do domínio (`CN=Computers,<domínio>`).

Funcionalidades:
----------------
- Cria um grupo de segurança chamado `G-JoinAD` no contêiner padrão de grupos (`CN=Users,<domínio>`).
- Detecta automaticamente o domínio atual (usando `Get-ADDomain`).
- Concede ao grupo `G-JoinAD` a permissão de **CreateChild** para objetos do tipo **computador** (`computer`) no contêiner padrão.
- Pode ser executado diretamente em um **Controlador de Domínio**.

Pré-requisitos:
---------------
- PowerShell executado com permissões administrativas.
- Executar o script em um **Controlador de Domínio**.
- O módulo `ActiveDirectory` precisa estar instalado (vem por padrão em DCs).

Uso:
----
Execute o script em um DC:

    .\Delegar-JoinAD.ps1

Após a execução:
- O grupo `G-JoinAD` será criado em `CN=Users,<domínio>`.
- Ele terá permissão para criar objetos de computador em `CN=Computers,<domínio>`.

Observações:
------------
- A permissão é apenas para criação de objetos `computer`.
- Pode ser adaptado para delegar em OUs personalizadas ou para conceder permissões adicionais.

Sugestão Adiconal:
------------------
- Faça uma copia da conta convidado do Active Directory e dê o nome de "usr_joinad" ;  mantenha ela no repositorio padrão (CN=Users,<domínio>).
- Forneça uma senha; configure a conta para nunca expirar; o mesmo vale para a senha - nunca expirar.
- Adicione a conta ao grupo G-JoinAD.
- Utilize-a para adiconar computadores ou servidores Linux.
#>

# Importa o módulo Active Directory
Import-Module ActiveDirectory

# Obtém o domínio e DN
$domain     = Get-ADDomain
$domainDN   = $domain.DistinguishedName

# Caminho padrão para grupos: CN=Users,<domínio>
$groupPath  = "CN=Users,$domainDN"

# Caminho padrão para novos computadores: CN=Computers,<domínio>
$computersPath = "CN=Computers,$domainDN"

# Parâmetros para criação do grupo
$groupParams = [ordered]@{
    Name           = 'G-JoinAD'
    SamAccountName = 'G-JoinAD'
    GroupScope     = 'Global'
    GroupCategory  = 'Security'
    Path           = $groupPath
    Description    = 'Grupo com permissão para ingressar computadores ao domínio'
}

# Cria o grupo se ele ainda não existir
if (-not (Get-ADGroup -Filter "Name -eq 'G-JoinAD'" -SearchBase $groupPath -ErrorAction SilentlyContinue)) {
    New-ADGroup @groupParams
}

# Obtém o SID do grupo
$group = Get-ADGroup -Identity 'G-JoinAD'
$groupSID = $group.SID

# GUID do objeto 'computer' no AD
$createComputerGUID = [GUID]'BF967A86-0DE6-11D0-A285-00AA003049E2'
$adRights  = [System.DirectoryServices.ActiveDirectoryRights]::CreateChild
$accessType = [System.Security.AccessControl.AccessControlType]::Allow

# Cria ACE para delegar permissão
$ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
    $groupSID, $adRights, $accessType, $createComputerGUID
)

# Aplica permissão no contêiner padrão CN=Computers
$ou = [ADSI]"LDAP://$computersPath"
$security = $ou.psbase.ObjectSecurity
$security.AddAccessRule($ace)
$ou.psbase.CommitChanges()
