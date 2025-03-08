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
PERCENTAGES=(80)
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

# Function to determine CLEVS and CCOLORS based on INTERVALO, CUT_LINE and type
get_clevs() {
    local interval="$1"
    local cut_line="$2"
    local type="$3"  # "max" ou "med"

    # Define ranges for each cut line and interval combination for maximum duration
    declare -A ranges_max=(
        ["-2.0_1"]="0 30"      
        ["-2.0_3"]="0 100"      
        ["-2.0_6"]="0 100"        
        ["-2.0_9"]="0 100"       
        ["-2.0_12"]="0 100"      
        ["-2.0_24"]="0 200"      
        ["-2.0_48"]="0 300"      
        ["-2.0_60"]="0 300"      
        ["-1.5_1"]="0 30"     
        ["-1.5_3"]="0 100"     
        ["-1.5_6"]="0 100"      
        ["-1.5_9"]="0 100"      
        ["-1.5_12"]="0 100"     
        ["-1.5_24"]="0 200"      
        ["-1.5_48"]="0 300"      
        ["-1.5_60"]="0 300"      
        ["1.0_1"]="0 30"
        ["1.0_3"]="0 100"      
        ["1.0_6"]="0 100"      
        ["1.0_9"]="0 100"      
        ["1.0_12"]="0 100"      
        ["1.0_24"]="0 200"      
        ["1.0_48"]="0 300"      
        ["1.0_60"]="0 300"      
        ["2.0_1"]="0 30"       
        ["2.0_3"]="0 100"       
        ["2.0_6"]="0 100"       
        ["2.0_9"]="0 100"       
        ["2.0_12"]="0 100"      
        ["2.0_24"]="0 200"      
        ["2.0_48"]="0 300"      
        ["2.0_60"]="0 300"   
    )
    
    # Define ranges for each cut line and interval combination for mean duration
    declare -A ranges_med=(
        ["-2.0_1"]="0 20"      
        ["-2.0_3"]="0 30"      
        ["-2.0_6"]="0 100"        
        ["-2.0_9"]="0 100"       
        ["-2.0_12"]="0 100"      
        ["-2.0_24"]="0 200"      
        ["-2.0_48"]="0 300"      
        ["-2.0_60"]="0 300"      
        ["-1.5_1"]="0 30"     
        ["-1.5_3"]="0 100"     
        ["-1.5_6"]="0 100"      
        ["-1.5_9"]="0 100"      
        ["-1.5_12"]="0 100"     
        ["-1.5_24"]="0 200"      
        ["-1.5_48"]="0 300"      
        ["-1.5_60"]="0 300"      
        ["1.0_1"]="0 10"
        ["1.0_3"]="0 30"      
        ["1.0_6"]="0 60"      
        ["1.0_9"]="0 50"      
        ["1.0_12"]="0 80"      
        ["1.0_24"]="0 100"      
        ["1.0_48"]="0 200"      
        ["1.0_60"]="0 200"      
        ["2.0_1"]="0 30"       
        ["2.0_3"]="0 100"       
        ["2.0_6"]="0 100"       
        ["2.0_9"]="0 100"       
        ["2.0_12"]="0 100"      
        ["2.0_24"]="0 200"      
        ["2.0_48"]="0 300"      
        ["2.0_60"]="0 300"  
    )
    
    # Definir qual array usar com base no tipo
    local ranges
    if [[ "$type" == "max" ]]; then
        declare -n ranges=ranges_max
    else
        declare -n ranges=ranges_med
    fi

    local key="${cut_line}_${interval}"
    if [[ -n "${ranges[$key]}" ]]; then
        local min max
        read min max <<< "${ranges[$key]}"
        # Always keep start and end values, divide remaining range into 8 equal parts
        local step=$(( (max - min) / 8 ))
        echo -n "$min "
        for i in $(seq 1 7); do
            echo -n "$(( min + i * step )) "
        done
        echo "$max"
    else
        # Usar os valores padrão específicos para cada intervalo
        if [[ -n "${intervals[$interval]}" ]]; then
            echo "${intervals[$interval]}"
        else
            echo "3 15 30 45 60 75 90 105 120 130"  # valores padrão
        fi
    fi
}

get_colors() {
    echo "70 4 11 5 12 8 27 2"
}

# Define valores padrão para cada intervalo quando não há valores específicos
declare -A intervals=(
    [1]="3 6 9 12 15 18 21 24 27 30" 
    [2]="3 10 20 30 40 50 60 70 75 80"
    [3]="3 15 30 45 60 75 90 105 120 130"
    [6]="3 25 50 75 100 125 150 175 200 220"
    [9]="3 30 60 90 120 150 180 210 230 240"
    [12]="3 30 60 90 120 150 180 210 230 240"
    [24]="3 35 70 105 140 175 210 245 260 270"
    [48]="3 45 90 135 180 225 270 315 360 400"
    [60]="3 45 90 135 180 225 270 315 360 400"
)

# Cria diretórios para duracao_maxima e duracao_media
BASE_OUTPUT_DIR="output"

# Use basename to avoid full path in directory structure
INPUT_BASE=$(basename "$INPUT_PATH")
MAX_OUTPUT_DIR="$BASE_OUTPUT_DIR/durmax/$INPUT_BASE"
MEDIA_OUTPUT_DIR="$BASE_OUTPUT_DIR/durmed/$INPUT_BASE"

MAX_FIG_OUTPUT_DIR="$MAX_OUTPUT_DIR/figures"
MEDIA_FIG_OUTPUT_DIR="$MEDIA_OUTPUT_DIR/figures"
mkdir -p "$MAX_OUTPUT_DIR" "$MEDIA_OUTPUT_DIR" "$MAX_FIG_OUTPUT_DIR" "$MEDIA_FIG_OUTPUT_DIR"

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

    # Extrair coordenadas da grade
    XDEF_LINE="$(grep -i '^xdef ' "$CTL_FILE" | head -n1)"
    YDEF_LINE="$(grep -i '^ydef ' "$CTL_FILE" | head -n1)"

    LONI="$(echo "$XDEF_LINE" | awk '{print $4}')"
    LON_DELTA="$(echo "$XDEF_LINE" | awk '{print $5}')"
    NXDEF="$(echo "$XDEF_LINE" | awk '{print $2}')"
    LONF=$(awk -v start="$LONI" -v delta="$LON_DELTA" -v n="$NXDEF" 'BEGIN {print start + (n-1)*delta}')

    LATI="$(echo "$YDEF_LINE" | awk '{print $4}')"
    LAT_DELTA="$(echo "$YDEF_LINE" | awk '{print $5}')"
    NYDEF="$(echo "$YDEF_LINE" | awk '{print $2}')"
    LATF=$(awk -v start="$LATI" -v delta="$LAT_DELTA" -v n="$NYDEF" 'BEGIN {print start + (n-1)*delta}')

    # Ajustar ordem das latitudes se necessário
    if [ "$(echo "$LATI > $LATF" | bc -l)" -eq 1 ]; then
        TMP="$LATI"
        LATI="$LATF"
        LATF="$TMP"
    fi

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

            SPI=$(echo $CTL_FILE | grep -oP '(?<=spi)[0-9]+')
            VAR="spi${SPI}"

            CINT=$(get_clevs $SPI $CUT_LINE "max")
            CCOLORS=$(get_colors)
            BOTTOM=$(basename $CTL_FILE)
            
            echo -e "${GRAY}[INFO]${NC} Gerando gráficos..."
            echo -e "${BLUE}[CONFIG]${NC} LONI: $LONI, LONF: $LONF, LATI: $LATI, LATF: $LATF"
            echo -e "${BLUE}[CONFIG]${NC} SPI: $SPI, CINT: $CINT, CCOLORS: $CCOLORS"

            sed -e "s|<CTL>|$ARQ_CTL_OUT|g" \
                -e "s|<VAR>|$VAR|g" \
                -e "s|<TITULO>|Dur Max|g" \
                -e "s|<SPI>|$SPI|g" \
                -e "s|<PERCENTAGE>|$PERCENTAGE|g" \
                -e "s|<CUTLINE>|$CUT_LINE|g" \
                -e "s|<BOTTOM>|$BOTTOM|g" \
                -e "s|<CINT>|$CINT|g" \
                -e "s|<CCOL>|$CCOLORS|g" \
                -e "s|<LATI>|$LATI|g" \
                -e "s|<LATF>|$LATF|g" \
                -e "s|<LONI>|$LONI|g" \
                -e "s|<LONF>|$LONF|g" \
                -e "s|<NOME_FIG>|${ARQ_BIN_OUT}_perc${PERCENTAGE}_cut_${CUT_LINE/./_}_spi${SPI}|g" \
                "$SCRIPT_DIR/src/gs/gs" > "$TMP_GS"

            # echo -e "${BLUE}[PLOT]${NC} Plot for max"
            if ! grads -pbc "run $TMP_GS"; then
                echo -e "${RED}Erro ao gerar gráficos.${NC}"
                exit 1
            fi

            # copy figures to output directory
            mkdir -p "$MAX_FIG_OUTPUT_DIR/$PERCENTAGE/$CUT_LINE"
            cp ${ARQ_BIN_OUT}_perc${PERCENTAGE}_cut_${CUT_LINE/./_}_spi${SPI}.png $MAX_FIG_OUTPUT_DIR/$PERCENTAGE/$CUT_LINE

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

            CINT_MEDIA=$(get_clevs $SPI $CUT_LINE "med")

            sed -e "s|<CTL>|$ARQ_CTL_OUT_MEDIA|g" \
                -e "s|<VAR>|$VAR|g" \
                -e "s|<TITULO>|Dur Med|g" \
                -e "s|<SPI>|$SPI|g" \
                -e "s|<PERCENTAGE>|$PERCENTAGE|g" \
                -e "s|<CUTLINE>|$CUT_LINE|g" \
                -e "s|<BOTTOM>|$BOTTOM|g" \
                -e "s|<LATI>|$LATI|g" \
                -e "s|<LATF>|$LATF|g" \
                -e "s|<LONI>|$LONI|g" \
                -e "s|<LONF>|$LONF|g" \
                -e "s|<CINT>|$CINT_MEDIA|g" \
                -e "s|<CCOL>|$CCOLORS|g" \
                -e "s|<NOME_FIG>|${ARQ_BIN_OUT_MEDIA}_perc${PERCENTAGE}_cut_${CUT_LINE/./_}_spi${SPI}|g" \
                "$SCRIPT_DIR/src/gs/gs" > "$TMP_GS_MEDIA"

            #echo -e "${BLUE}[PLOT]${NC} Plot for media"
            if ! grads -pbc "run $TMP_GS_MEDIA"; then
                echo -e "${RED}Erro ao gerar gráficos.${NC}"
                exit 1
            fi

            # copy figures to output directory
            mkdir -p "$MEDIA_FIG_OUTPUT_DIR/$PERCENTAGE/$CUT_LINE"
            cp ${ARQ_BIN_OUT_MEDIA}_perc${PERCENTAGE}_cut_${CUT_LINE/./_}_spi${SPI}.png $MEDIA_FIG_OUTPUT_DIR/$PERCENTAGE/$CUT_LINE

            echo -e "${GRAY}─────────────────────────────────────────${NC}"
        done
    done
    echo -e "${GREEN}[CONCLUIDO]${NC} para $(basename "$CTL_FILE")\n"
done

echo -e "${GREEN}${BOLD}=== Operação completa! ===${NC}"
