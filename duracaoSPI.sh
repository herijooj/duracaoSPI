#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

set_colors() {
    RED='\033[1;31m'
    GREEN='\033[1;32m'
    YELLOW='\033[1;93m'
    BLUE='\033[1;36m'
    PURPLE='\033[1;35m'
    CYAN='\033[0;36m'
    GRAY='\033[0;90m'
    BOLD='\033[1m'
    NC='\033[0m'
}

if [ -t 1 ] && ! grep -q -e '--no-color' <<<"$@"
then
    set_colors
fi

# Define arrays de estações, percentuais e linhas de corte
# SEASONS=("DJF" "MAM" "JJA" "SON" "ANO")
PERCENTAGES=(70 80)
CUT_LINES=(-2.0 -1.5 1.0 2.0)

# Ajuste dos parâmetros de entrada para permitir diretório ou arquivo
if [ "$#" -lt 1 ] || [ "$#" -gt 4 ]; then
    echo -e "${RED}ERRO! Parametros incorretos.${NC}"
    echo -e "${YELLOW}Uso: duracaoSPI.sh [DIRETORIO_OU_ARQUIVO_ENTRADA] [TXT_OU_BIN] [PERCENTAGES] [CUT_LINES]${NC}"
    exit 1
fi

INPUT_PATH="$1"
TXT_OR_BIN="${2:-1}"

# Sobrescreve percentuais e linhas de corte, se fornecidos
if [ "$#" -ge 3 ]; then
    IFS=',' read -ra PERCENTAGES <<< "$3"
fi
if [ "$#" -ge 4 ]; then
    IFS=',' read -ra CUT_LINES <<< "$4"
fi

# Cria diretórios para duracao_maxima e duracao_media
BASE_OUTPUT_DIR="output"
MAX_OUTPUT_DIR="$BASE_OUTPUT_DIR/max"
MEDIA_OUTPUT_DIR="$BASE_OUTPUT_DIR/med"
mkdir -p "$MAX_OUTPUT_DIR" "$MEDIA_OUTPUT_DIR"

# Verifica se é arquivo único ou vários arquivos .ctl
if [ -f "$INPUT_PATH" ] && [[ "$INPUT_PATH" == *.ctl ]]; then
    CTL_FILES=("$INPUT_PATH")
else
    CTL_FILES=("$INPUT_PATH"/*.ctl)
fi

for CTL_FILE in "${CTL_FILES[@]}"; do
    [ ! -f "$CTL_FILE" ] && echo -e "${RED}Nenhum arquivo .ctl encontrado.${NC}" && exit 1
    echo -e "\n${BOLD}${PURPLE}=== Processando: ${CYAN}$(basename "$CTL_FILE")${NC} ===\n"

    CTL_BASE=$(basename "$CTL_FILE" .ctl)
    FILE_MAX_OUTPUT_DIR="$MAX_OUTPUT_DIR/$CTL_BASE"
    FILE_MEDIA_OUTPUT_DIR="$MEDIA_OUTPUT_DIR/$CTL_BASE"
    mkdir -p "$FILE_MAX_OUTPUT_DIR" "$FILE_MEDIA_OUTPUT_DIR"

    for PERCENTAGE in "${PERCENTAGES[@]}"; do
        for CUT_LINE in "${CUT_LINES[@]}"; do
            echo -e "${BLUE}[CONFIG]${NC} $PERCENTAGE%, corte $CUT_LINE"
            
            # Process duracao_maxima
            CUT_DIR_MAX="$FILE_MAX_OUTPUT_DIR/${PERCENTAGE}/cut_${CUT_LINE/./_}"
            mkdir -p "$CUT_DIR_MAX"

            # Extrai parâmetros do .ctl
            ARQ_BIN_IN="$(dirname $CTL_FILE)/$(grep dset $CTL_FILE | tr -s " " | cut -d" " -f2 | sed -e s/\\^//g )"
            NX=$(cat ${CTL_FILE} | grep xdef | tr  "\t" " " | tr -s " " | cut -d" " -f2)
            NY=$(cat ${CTL_FILE} | grep ydef | tr  "\t" " " | tr -s " " | cut -d" " -f2)
            NZ=$(cat ${CTL_FILE} | grep zdef | tr  "\t" " " | tr -s " " | cut -d" " -f2)
            NT=$(cat ${CTL_FILE} | grep tdef | tr  "\t" " " | tr -s " " | cut -d" " -f2)
            UNDEF=$(cat ${CTL_FILE} | grep undef | tr  "\t" " " | tr -s " " | cut -d" " -f2)

            # Define saída
            ARQ_BIN_OUT="$CUT_DIR_MAX/$(basename $ARQ_BIN_IN .bin)_${CUT_LINE}"

            # echo -e "${BLUE}[EXEC]${NC} duracaoMaxima"
            if ! $SCRIPT_DIR/bin/duracaoMaxima $ARQ_BIN_IN $NX $NY $NZ $NT $UNDEF $CUT_LINE $TXT_OR_BIN $ARQ_BIN_OUT $PERCENTAGE; then
                echo -e "${RED}Erro ao executar duracaoMaxima.${NC}"
                exit 1
            fi

            # Ajuste dos arquivos de saída
            if [[ $TXT_OR_BIN -eq "1" || $TXT_OR_BIN -eq "2" ]]; then
                ARQ_CTL_OUT="$CUT_DIR_MAX/$(basename $CTL_FILE .ctl)_${CUT_LINE}.ctl"
                cp "$CTL_FILE" "$ARQ_CTL_OUT"
                sed  -i "s#$(basename $ARQ_BIN_IN .bin)#$(basename ${ARQ_BIN_OUT} .bin)#g;" ${ARQ_CTL_OUT}
                sed  -i "s#${NT}#1#g;" ${ARQ_CTL_OUT}
            fi
            if [[ $TXT_OR_BIN -eq "0" || $TXT_OR_BIN -eq "2" ]]; then
                mkdir -p "$CUT_DIR_MAX/txts"
                mv *.txt "$CUT_DIR_MAX/txts"
            fi

            # Plotting
            TMP_GS=$(mktemp)
            trap 'rm -f "$TMP_GS"' EXIT

            sed -e "s|<CTL>|$ARQ_CTL_OUT|g" \
                -e "s|<VAR>|SPI|g" \
                -e "s|<TITULO>|Duracao Max - $CUT_LINE - $PERCENTAGE%|g" \
                -e "s|<NOME_FIG>|${ARQ_BIN_OUT}|g" \
                "$SCRIPT_DIR/src/gs/gs" > "$TMP_GS"

            # echo -e "${BLUE}[PLOT]${NC} Plot for max"
            if ! grads -blc "run $TMP_GS"; then
                echo -e "${RED}Erro ao gerar gráficos.${NC}"
                exit 1
            fi

            # Process duracao_media
            CUT_DIR_MEDIA="$FILE_MEDIA_OUTPUT_DIR/${PERCENTAGE}/cut_${CUT_LINE/./_}"
            mkdir -p "$CUT_DIR_MEDIA"
            ARQ_BIN_OUT_MEDIA="$CUT_DIR_MEDIA/$(basename $ARQ_BIN_IN .bin)_${CUT_LINE}"

            # echo -e "${BLUE}[EXEC]${NC} duracaoMedia"
            if ! $SCRIPT_DIR/bin/duracaoMedia $ARQ_BIN_IN $NX $NY $NZ $NT $UNDEF $CUT_LINE $TXT_OR_BIN $ARQ_BIN_OUT_MEDIA $PERCENTAGE; then
                echo -e "${RED}Erro ao executar duracaoMedia.${NC}"
                exit 1
            fi

            # Ajuste dos arquivos de saída para duracao_media
            if [[ $TXT_OR_BIN -eq "1" || $TXT_OR_BIN -eq "2" ]]; then
                ARQ_CTL_OUT_MEDIA="$CUT_DIR_MEDIA/$(basename $CTL_FILE .ctl)_${CUT_LINE}.ctl"
                cp "$CTL_FILE" "$ARQ_CTL_OUT_MEDIA"
                sed  -i "s#$(basename $ARQ_BIN_IN .bin)#$(basename ${ARQ_BIN_OUT_MEDIA} .bin)#g;" ${ARQ_CTL_OUT_MEDIA}
                sed  -i "s#${NT}#1#g;" ${ARQ_CTL_OUT_MEDIA}
            fi
            if [[ $TXT_OR_BIN -eq "0" || $TXT_OR_BIN -eq "2" ]]; then
                mkdir -p "$CUT_DIR_MEDIA/txts"
                mv *.txt "$CUT_DIR_MEDIA/txts"
            fi

            # Plotting for duracao_media
            TMP_GS_MEDIA=$(mktemp)
            trap 'rm -f "$TMP_GS_MEDIA"' EXIT

            sed -e "s|<CTL>|$ARQ_CTL_OUT_MEDIA|g" \
                -e "s|<VAR>|SPI|g" \
                -e "s|<TITULO>|Duracao Med - $CUT_LINE - $PERCENTAGE%|g" \
                -e "s|<NOME_FIG>|${ARQ_BIN_OUT_MEDIA}|g" \
                "$SCRIPT_DIR/src/gs/gs" > "$TMP_GS_MEDIA"

            #echo -e "${BLUE}[PLOT]${NC} Plot for media"
            if ! grads -blc "run $TMP_GS_MEDIA"; then
                echo -e "${RED}Erro ao gerar gráficos.${NC}"
                exit 1
            fi

            echo -e "${GRAY}─────────────────────────────────────────${NC}"
        done
    done
    echo -e "${GREEN}[CONCLUIDO]${NC} para $(basename "$CTL_FILE")\n"
done

echo -e "${GREEN}${BOLD}=== Operação completa! ===${NC}"
