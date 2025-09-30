# /bash/bin
# exemplo de uso

# ============================================================
#
#  read -rp "Grupo a verificar: " grupo
#  read -rp "Conta UPN: " upn
#  echo -n "Senha: "
#  read -s senha
#  echo
#  
#  if verificar_grupo_ad "$grupo" "$upn" "$senha"; then
#      echo "Sucesso: o grupo existe no AD."
#  else
#      echo "Falha: o grupo não foi encontrado."
#  fi
#
# =============================================================


verificar_grupo_ad() {
    local grupo="$1"
    local upn="$2"
    local senha="$3"

    if [[ -z "$grupo" || -z "$upn" || -z "$senha" ]]; then
        echo "Uso: verificar_grupo_ad <grupo> <UPN> <senha>"
        return 2
    fi

    # Verifica se ldapsearch está disponível
    if ! command -v ldapsearch &> /dev/null; then
        echo "Erro: 'ldap-utils' não está instalado."
        return 3
    fi

    # Validação básica do grupo
    grupo=$(echo "$grupo" | tr -cd 'a-zA-Z0-9._-')
    if [[ -z "$grupo" ]]; then
        echo "Grupo inválido: apenas letras, números, '.', '-', '_' são permitidos."
        return 4
    fi

    # Validação do UPN
    if [[ ! "$upn" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        echo "UPN inválido."
        return 5
    fi

    local dominio="${upn#*@}"
    local base_dn
    base_dn=$(echo "$dominio" | awk -F. '{for (i=1;i<=NF;i++) printf "dc=%s%s", $i, (i==NF?"":",")}')
    local ldap_host="ldap://$dominio"

    echo "Buscando grupo '$grupo' no domínio '$dominio'..."

    local resultado
    resultado=$(ldapsearch -LLL -x -H "$ldap_host" \
        -D "$upn" -w "$senha" \
        -b "$base_dn" "(&(objectClass=group)(sAMAccountName=$grupo))" sAMAccountName 2>/dev/null)

    if echo "$resultado" | grep -q "^sAMAccountName: "; then
        echo "✅ Grupo encontrado: $grupo"
        return 0
    else
        echo "Grupo não encontrado."
        return 1
    fi
}
