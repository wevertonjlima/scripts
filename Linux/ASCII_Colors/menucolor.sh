#!/usr/bin/env bash
# ==============================================================================
# Script: funcoes_cores_dinamicas.sh
# Funcao: Cria funcoes de eco coloridas dinamicamente (ex: echo-yellow)
#
# IMPORTANTE: Ao realizar qualquer alteracao na logica ou compatibilidade,
# atualize a variavel SCRIPT_VERSION abaixo e a data do LOG de alteracoes.
# O versionamento semantico deve seguir a progressao decimal (1.0.x para
# correcoes/ajustes e 1.x.0 para novas funcionalidades).
#
# Versao Inicial: 1.0.0
# Informar ultima alteracao: 2026-05-21 (Ajuste no escape do reset de cor)
# ==============================================================================

# --- [0] METADADOS E VERSAO ---
SCRIPT_VERSION="1.0.0"

# --- [1] CONFIGURACOES DE SEGURANCA ---
set -euo pipefail

# --- [2] GERADOR DINAMICO DE FUNCOES DE COR ---
# Declaramos uma matriz (array) associativa com o sufixo e o codigo ANSI
declare -A CORES_MAP=(
    # --- Cores Padrao (Escuras/Sobrias) ---
    ["black"]="\e[30m"
    ["red"]="\e[31m"
    ["green"]="\e[32m"
    ["yellow"]="\e[33m"
    ["blue"]="\e[34m"
    ["purple"]="\e[35m"
    ["cyan"]="\e[36m"
    ["white"]="\e[37m"

    # --- Cores Claras (Light / Alta Intensidade) ---
    ["lblack"]="\e[90m"     # Conhecido como Cinza Escuro
    ["lred"]="\e[91m"       # Vermelho Claro
    ["lgreen"]="\e[92m"     # Verde Claro
    ["lyellow"]="\e[93m"    # Amarelo Claro (Light Yellow)
    ["lblue"]="\e[94m"      # Azul Claro
    ["lpurple"]="\e[95m"    # Roxo Claro / Magenta
    ["lcyan"]="\e[96m"      # Ciano Claro
    ["lwhite"]="\e[97m"     # Branco de Alto Brilho
)

# Reseta o terminal (Variavel Global)
CLR_RESET="\e[0m"

# Laco que percorre o mapa e injeta as funcoes em memoria usando 'eval'
for nome_cor in "${!CORES_MAP[@]}"; do
    codigo_ansi="${CORES_MAP[$nome_cor]}"

    # O \$* e o \$CLR_RESET garantem que os valores sejam avaliados 
    # apenas no momento em que a funcao for de fato executada.
    eval "
    echo-${nome_cor}() {
        echo -e \"${codigo_ansi}\$*\$CLR_RESET\"
    }
    "
done

# --- [3] EXECUCAO / EXEMPLO DE USO ---
main() {
    clear

    # --- Exemplos Solicitados de Validacao do Reset ---
    echo-black      "Hello World! - Em Preto"
    echo-lblack     "Hello World! - Em Cinza Escuro (Light Black)"
    
    echo-red        "Hello World! - Em Vermelho"
    echo-lred       "Hello World! - Em Vermelho Light"
    
    echo-green      "Hello World! - Em Verde"
    echo-lgreen     "Hello World! - Em Verde Light"
    
    echo-yellow     "Hello World! - Em Amarelo"
    echo-lyellow    "Hello World! - Em Amarelo Light"
    
    echo-blue       "Hello World! - Em Azul"
    echo-lblue      "Hello World! - Em Azul Light"
    
    echo-purple     "Hello World! - Em Roxo"
    echo-lpurple    "Hello World! - Em Roxo Light"
    
    echo-cyan       "Hello World! - Em Ciano"
    echo-lcyan      "Hello World! - Em Ciano Light"
    
    echo-white      "Hello World! - Em Branco"
    echo-lwhite     "Hello World! - Em Branco Light"

    echo ""
    echo-lyellow    "Instrucao: O processo de integracao com o Active Directory requer atencao."
    echo "Texto de teste sem funcao para comprovar que o reset funcionou e o padrao do terminal voltou."
}

main
