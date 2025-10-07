# Função 4: init_ad_group - Seleção e Validação do Grupo AD
# =============================================================================
init_ad_group() {

    # Funções aninhadas para manter a consistência visual
    clear_screen() { clear; }
    
	show_banner() {
        echo-ylw
        echo-ylw "  =============================================================="
        echo-ylw "  =  Definindo Grupo do Active Directory para Acesso ao Linux  ="
        echo-ylw "  =     O grupo deve existir no AD e será usado para SSSD.     ="
        echo-ylw "  =============================================================="
        
        # Novo bloco de instrução sobre espaços
        echo-ylw "  Atenção! O nome do grupo não deve conter espaços:"
        echo-grn "  [ OK ] = Grupo-Linux"
        echo-red "  [ERRO] = Grupo Linux"
        echo-ylw "  --------------------------------------------------------------"

        # Novo bloco de credenciais em uso
        echo-wht "  Credenciais em uso >>>"
        echo-wht "    Domínio AD .......... : $AD_DOMAIN"
        echo-wht "    Usuário Autenticado .. : $AD_UPN"
        echo-ylw "  =============================================================="
        echo-ylw "  "
    }

    # Validação do nome do grupo (Adaptação da sua lógica de sanitização)
    validate_group_name() {
        local input="$1"
        # Permite letras, números, '.', '-', '_' e remove espaços iniciais/finais
        local sanitized_group=$(echo "$input" | tr -d '\n\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Verifica se sobrou algo após a sanitização
        if [[ -z "$sanitized_group" ]]; then
            echo-red "  ERRO: O nome do grupo não pode ser vazio."
            return 1
        fi
        
        # Sua validação de caracteres (Garantindo que não há chars proibidos)
        if ! [[ "$sanitized_group" =~ ^[a-zA-Z0-9._-]+$ ]]; then
            echo-red "  ERRO: Grupo contém caracteres inválidos. Perm.: letras, números, '.', '-', '_'."
            return 1
        fi

        echo "$sanitized_group"
        return 0
    }

    # --- LOOP PRINCIPAL DE ENTRADA E VALIDAÇÃO DO GRUPO ------------------------
    local group_name=""
    local check_result=1 # Inicializa com falha

    while true; do
        clear_screen; show_banner
        
        # 1. Solicita o nome do grupo
        read -erp " Digite o nome do Grupo AD: " input_group_name
        
        # 2. Valida o formato (sanitiza e verifica caracteres)
        local validated_group=$(validate_group_name "$input_group_name")
        
        if [[ $? -eq 0 ]]; then
            group_name="$validated_group" # Armazena o nome validado
            
            echo-wht "  Verificando se o grupo '$group_name' existe no AD..."
            
            # 3. Tenta buscar o grupo no AD via ldapsearch
            # --------------------------------------------------------------------
            # OTIMIZAÇÃO: Usando as variáveis globais AD_*
            local ldap_result
            
            # Converte o domínio DNS para BASE DN (DC=example,DC=com)
            local base_dn=$(echo "$AD_DOMAIN" | awk -F. '{for (i=1;i<=NF;i++) printf "dc=%s%s", $i, (i==NF?"":",")}')
            local ldap_host="ldap://$AD_DOMAIN"
            
            # Verifica se ldapsearch está disponível
            if ! command -v ldapsearch &> /dev/null; then
                echo-red "  ERRO: O utilitário 'ldapsearch' (ldap-utils) não está instalado."
                return 3 # Sai da função, pois o ldapsearch é mandatório
            fi

            ldap_result=$(ldapsearch -LLL -x -H "$ldap_host" \
                -D "$AD_UPN" -w "$AD_PASS1" \
                -b "$base_dn" "(&(objectClass=group)(sAMAccountName=$group_name))" sAMAccountName 2>/dev/null)
            # --------------------------------------------------------------------

            if echo "$ldap_result" | grep -q "^sAMAccountName: "; then
                echo-grn " [!] Grupo '$group_name' encontrado e credenciais verificadas com sucesso!"
                
                # Armazena o nome do grupo como variável global para a próxima função
                export AD_LINUX_GROUP="$group_name"
                sleep 2
                break # SUCESSO! Sai do LOOP PRINCIPAL
            else
                echo-red " [X] ERRO: Grupo '$group_name' não encontrado no AD ou credenciais expiradas."
                echo-red " Tente novamente ou verifique se o grupo existe."
                sleep 3
            fi
        else
            # Erro de formato (já exibido por validate_group_name)
            sleep 3
        fi
        
    done # Fim do LOOP PRINCIPAL

    return 0
}
