#!/bin/bash

# =================================================================
# BIBLIOTECA DE FUNÇÕES DE CORES PARA SCRIPTS BASH
# =================================================================

# 1. DEFINIÇÃO DAS CORES (Negrito por padrão para destaque)
# ---------------------------------------------------------
# exemplo tradicional = echo -e "\e[31m Atenção! Cuidado ao usar o comando rm -r \e[0m"
# exemplo c/ alias    = echo-red "Atenção! Cuidado ao usar o comando rm -r"

# \e[1;31m -> Negrito (1) + Vermelho (31)
# \e[31m -> Vermelho (31)
# \e[33m -> Amarelo (33)
# \e[32m -> Verde (32)
# \e[0m   -> Reset (Volta para a cor e formatação padrão)

readonly RED='\e[31m'    # Vermelho: Para Erros, Alertas Críticos.
readonly YLW='\e[33m'    # Amarelo: Para Avisos, Informações importantes.
readonly GRN='\e[32m'    # Verde: Para Sucesso, Conclusão de Tarefas.
readonly NC='\e[0m'        # No Color (Reset): Essencial para terminar a cor.


# 2. DEFINIÇÃO DAS FUNÇÕES
# ------------------------

# Função: Imprime em Vermelho
echo-red () {
    echo -e "${RED}$*${NC}"
}

# Função: Imprime em Amarelo
echo-ylw () {
    echo -e "${YLW}$*${NC}"
}

# Função: Imprime em Verde
echo-grn () {
    echo -e "${GRN}$*${NC}"
}

# --- EXEMPLOS DE USO ABAIXO ---
# echo-red "ERRO: O arquivo não foi encontrado!"
# echo-ylw "AVISO: Verifique a conexão com a rede."
# echo-grn "SUCESSO: Script concluído com êxito!"

# =================================================================
# FIM DA BIBLIOTECA
# =================================================================
