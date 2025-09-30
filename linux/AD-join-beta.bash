#!/bin/bash
# filename: AD-join-v2.bash



# __________________________________________
# Blocos interativos
# __________________________________________


# --------------------- banner inicial ---------------------
clear_screen() { clear; }

show_banner() {
   echo "    ============================================================="
   echo "    =    Validando credenciais do Dominio Active Directory      ="
   echo "    =     Use um formato UPN (exemplo: user@mydomain.dns)       ="
   echo "    ============================================================="
   echo ""
}
# ---/ end /--- #

# --------------------- bloco valida UPN ---------------------
validate_upn() {
    local upn="$1"

    if [[ ${#upn} -gt 255 ]]; then
        echo "ERROR - Formato de entrada invalido."
        return 1
    fi

    if [[ "$upn" != *@* ]]; then
        echo "ERROR - Formato de entrada invalido."
        return 1
    fi

    local prefix="${upn%@*}"
    local suffix="${upn#*@}"

    if [[ ! "$prefix" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "ERROR - Formato de entrada invalido."
        return 1
    fi

    if [[ ! "$suffix" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])$ ]]; then
        echo "ERROR - Formato de entrada invalido."
        return 1
    fi
    
	return 0
}
# ---/ end /--- #


# --------------------- bloco valida AD ---------------------
obter_AD() {

while true; do
    clear_screen
    show_banner
    read -erp "Digite usuario (UPN): " USER_UPN
    if validate_upn "$USER_UPN"; then
        break
    else
        sleep 3
    fi
done

clear_screen
show_banner
read -s -p "Digite a senha ....: " USER_PASS
echo ""
read -s -p "Confirme a senha ..: " USER_PASS_CONFIRM
echo ""
if [[ "$USER_PASS" != "$USER_PASS_CONFIRM" ]]; then
    echo "Erro: As senhas não coincidem!"
    exit 1
fi

# .............. Segmentação do UPN ...............................
ad_prefix="${USER_UPN%@*}"      # exemplo: bruce
ad_sufix="${USER_UPN#*@}"       # exemplo: acme.labs
REALM=$(echo "$ad_sufix" | tr '[:lower:]' '[:upper:]')  # ACME.LABS


# .............. Exibir comando antes de executar .................
clear_screen
show_banner
echo "Olá, o seu usuario UPN inserido foi:"
echo "  $USER_UPN"
echo ""
echo "O comando de validação será:"
echo "  kinit ${ad_prefix}@${REALM}"
echo ""
read -p "Posso prosseguir? (s/n): " CONFIRM
if [[ "$CONFIRM" != "s" && "$CONFIRM" != "S" ]]; then
    echo "Operação cancelada pelo usuário."
    exit 1
fi

# .............. Executa validação .................................
printf "%s\n" "$USER_PASS" | kinit "${ad_prefix}@${REALM}" 2>/dev/null

if [[ $? -eq 0 ]]; then
    echo "Usuario validado no AD !!!"
else
    echo "Usuario não validado no AD XXX"
fi

}
# ---/ end /--- #


# ------------ bloco SUDO Domain-Admins-Group ---------------
obter_Domain-Admins-Group() {
    echo ""
    echo " --------------------------------------------------------------"
    echo " Por favor insira o nome do grupo \"Domain Linux Admins\":"
    echo " observação: o nome do grupo não pode ter espaços!"
    echo " exemplo: domain-linux-admins"
    echo " --------------------------------------------------------------"
    echo ""

    while true; do
        read -erp " Digite o nome do grupo: " Domain-Admins-Group

        # Verifica se há espaços ou entrada vazia
        if [[ "$Domain-Admins-Group" =~ \  ]]; then
            echo " [ERRO] O nome do grupo não pode conter espaços. Tente novamente."
			sleep 2
        elif [[ -z "$Domain-Admins-Group" ]]; then
            echo " [ERRO] O nome do grupo não pode estar vazio. Tente novamente."
			sleep 2
        else
            break
        fi
    done

	echo "%Domain-Admins-Group ALL=(ALL) ALL" | sudo tee /etc/sudoers.d/Domain-Admins-Group.conf > /dev/null && \
	sudo visudo -cf /etc/sudoers.d/Domain-Admins-Group.conf && \
	sudo chmod 0440 /etc/sudoers.d/Domain-Admins-Group.conf && \
	sudo chown root:root /etc/sudoers.d/Domain-Admins-Group.conf

}
# ---/ end /--- #



# ------------------------------------------
# FLUXO PRINCIPAL
# ------------------------------------------
main() {
    [[ "$1" == "?" ]] && ajuda

    clear
    if [[ $# -eq 4 ]]; then
        entra_upn             "$1" &&
        entra_realm           "$2" &&
        entra_ntp1            "$3" &&
        entra_ad-linux-admins "$4"
    else
        obter_AD
		# Comando de pausa
		echo "Pressione [Enter] para continuar..."
		read 
        clear
#		obter_Domain-Admins-Group
    fi
}

main "$@"
