#!/bin/bash

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
NC2BIN="/geral/programas/converte_nc_bin/converte_dados_nc_to_bin.sh"

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

print_bar() {
    local color=$1
    local text=$2
    local width=$(tput cols)
    local text_len=${#text}
    local pad_len=$(( (width - text_len - 2) / 2 ))
    local padding=$(printf '%*s' $pad_len '')
    echo -e "${color}${padding// /=} ${text} ${padding// /=}=${NC}"
}

# Função para detectar padrão de nomes e criar nome do ensemble
generate_ensemble_name() {
    local input_paths=("$@")
    local ensemble_name=""
    
    # Verifica se todas as pastas têm um padrão de nome similar (ex: EC-Earth3_ssp245_r1_gr_2027-2100)
    # Pega o primeiro diretório como referência
    local first_dir=$(basename "${input_paths[0]}")
    
    # Tenta encontrar padrão "rN" onde N é um número
    if [[ "$first_dir" =~ _r[0-9]+_ ]]; then
        # Extrai o prefixo e sufixo antes e depois do padrão rN
        local common_prefix="${first_dir%%_r[0-9]*}"
        local common_suffix="${first_dir#*_r[0-9]_}"
        ensemble_name="${common_prefix}_Ensemble_${common_suffix}"
    else
        # Se não encontrar o padrão, usa "Ensemble" como nome base
        ensemble_name="Ensemble_$(date +%Y%m%d)"
    fi
    
    echo "$ensemble_name"
}

# Função para calcular o ensemble mean
calculate_ensemble_mean() {
    local output_base_dir="$PWD/output"
    local input_paths=("$@")
    local ensemble_name=$(generate_ensemble_name "${input_paths[@]}")

    print_bar "${PURPLE}" "CALCULANDO ENSEMBLE MEAN"
    echo -e "${BLUE}[INFO]${NC} Nome do ensemble: ${ensemble_name}"

    # Para cada tipo de duração (max e med), percentual e linha de corte, calcular o ensemble
    for duration_type in "durmax" "durmed"; do
        # Cria diretório para o ensemble DENTRO do diretório do tipo de duração
        local ensemble_dir="${output_base_dir}/${duration_type}/${ensemble_name}"
        mkdir -p "${ensemble_dir}" || { echo -e "${RED}[ERRO]${NC} Falha ao criar diretório do ensemble ${ensemble_dir}"; return 1; }
        
        for PERCENTAGE in "${PERCENTAGES[@]}"; do
            for CUT_LINE in "${CUT_LINES[@]}"; do
                echo -e "\n${BOLD}${PURPLE}=== Processando Ensemble para ${YELLOW}${duration_type}${NC}, ${YELLOW}$PERCENTAGE%${NC}, ${YELLOW}Linha de Corte: $CUT_LINE${NC} ===${NC}"

                # Primeiro, identifica todos os SPIs disponíveis nos diretórios de entrada
                local available_spis=()
                local model_dirs=()
                
                # Listar diretórios de saída disponíveis para debugar
                echo -e "${GRAY}[DEBUG]${NC} Verificando diretórios de saída para ${duration_type}:"
                for input_path in "${input_paths[@]}"; do
                    local model_dir="${output_base_dir}/${duration_type}/$(basename ${input_path})"
                    echo -e "${GRAY}[DEBUG]${NC} Diretório: ${model_dir}"
                    if [ -d "$model_dir" ]; then
                        model_dirs+=("$model_dir")
                        
                        # Buscar mais amplamente por arquivos CTL que contêm "spi" no nome
                        local cut_dir="${model_dir}/*/${PERCENTAGE}/cut_${CUT_LINE/./_}"
                        
                        # Expressão de busca mais ampla para encontrar arquivos spi
                        local ctl_files=$(find "${model_dir}" -path "*/${PERCENTAGE}/cut_${CUT_LINE/./_}/*" -name "*.ctl" -type f 2>/dev/null)
                        
                        if [ -z "$ctl_files" ]; then
                            echo -e "${YELLOW}[AVISO]${NC} Nenhum arquivo .ctl encontrado em ${cut_dir}"
                            continue
                        else
                            while IFS= read -r ctl_file; do
                                
                                # Expressão regular mais flexível para extrair SPI
                                if [[ "$(basename "$ctl_file")" =~ spi([0-9]+) ]]; then
                                    local spi="${BASH_REMATCH[1]}"
                                    
                                    # Adiciona à lista se ainda não estiver lá
                                    if ! [[ " ${available_spis[@]} " =~ " ${spi} " ]]; then
                                        available_spis+=("$spi")
                                        echo -e "${BLUE}[INFO]${NC} SPI${spi} adicionado à lista de SPIs disponíveis"
                                    fi
                                fi
                            done <<< "$ctl_files"
                        fi
                    else
                        echo -e "${YELLOW}[AVISO]${NC} Diretório não encontrado: ${model_dir}"
                    fi
                done

                if [ ${#available_spis[@]} -eq 0 ]; then
                    echo -e "${YELLOW}[AVISO]${NC} Nenhum SPI identificado para ${duration_type}, percentual ${PERCENTAGE}% e linha de corte ${CUT_LINE}"
                    continue
                fi

                echo -e "${BLUE}[INFO]${NC} SPIs identificados: ${available_spis[@]}"
                
                # Resto da função permanece o mesmo...
                # Para cada SPI encontrado, cria um ensemble específico
                for spi_value in "${available_spis[@]}"; do
                    echo -e "\n${BOLD}${PURPLE}=== Calculando Ensemble para ${YELLOW}${duration_type}${NC}, SPI${spi_value}, ${YELLOW}$PERCENTAGE%${NC}, ${YELLOW}Linha de Corte: $CUT_LINE${NC} ===${NC}"

                    # Cria subdiretórios para o percentual, linha de corte e SPI atual
                    local perc_dir="${ensemble_dir}/${PERCENTAGE}"
                    local cut_dir="${perc_dir}/cut_${CUT_LINE/./_}"
                    local figures_dir="${ensemble_dir}/figures/${PERCENTAGE}/${CUT_LINE}"
                    mkdir -p "${cut_dir}" "${figures_dir}"

                    # Prepara lista de arquivos para o CDO ensmean, específicos para este SPI
                    local nc_files=()
                    local temp_dir=$(mktemp -d)
                    trap 'rm -rf "$temp_dir"' EXIT

                    # Encontra arquivos CTL específicos para este SPI
                    for input_path in "${input_paths[@]}"; do
                        local model_dir="${output_base_dir}/${duration_type}/$(basename ${input_path})"
                        echo -e "${BLUE}[INFO]${NC} Procurando arquivos para ${duration_type} em ${model_dir}"
                        
                        # Busca mais específica para localizar arquivos CTL do SPI atual
                        # Busca em múltiplos padrões possíveis
                        local found_files=0
                        
                        # Padrão 2: Busca arquivos com padrão *_spiN_*.ctl
                        for ctl_file in $(find "${model_dir}" -path "*/${PERCENTAGE}/cut_${CUT_LINE/./_}/*_spi${spi_value}_*.ctl" -type f 2>/dev/null); do
                            if [[ -f "$ctl_file" ]]; then
                                found_files=1
                                
                                # Converte de .ctl para .nc usando CDO
                                local nc_out="${temp_dir}/$(basename ${input_path})_$(basename ${ctl_file} .ctl).nc"

                                if cdo -f nc import_binary "${ctl_file}" "${nc_out}" 2>/dev/null; then
                                    nc_files+=("${nc_out}")
                                else
                                    echo -e "${YELLOW}[AVISO]${NC} Falha ao converter ${ctl_file} para NetCDF"
                                fi
                            fi
                        done
                        
                        if [ $found_files -eq 0 ]; then
                            echo -e "${YELLOW}[AVISO]${NC} Nenhum arquivo encontrado para SPI${spi_value} em ${model_dir}"
                        fi
                    done

                    # Verifica se encontrou arquivos para este SPI específico
                    if [ ${#nc_files[@]} -eq 0 ]; then
                        echo -e "${YELLOW}[AVISO]${NC} Nenhum arquivo encontrado para ${duration_type}, SPI${spi_value}, percentual ${PERCENTAGE}% e linha de corte ${CUT_LINE}"
                        continue
                    fi

                    echo -e "${BLUE}[INFO]${NC} Calculando ensemble mean para ${#nc_files[@]} arquivos de SPI${spi_value}"

                    # Determina o nome base para o arquivo de saída específico para este SPI
                    local base_name=""
                    if [[ -f "${nc_files[0]}" ]]; then
                        # Extrai o padrão comum do nome (removendo parte específica do run)
                        base_name=$(basename "${nc_files[0]}" .nc)
                        if [[ "$base_name" =~ _r[0-9]+_ ]]; then
                            # Remove apenas o padrão _rN_ e mantém o resto
                            local prefix="${base_name%%_r[0-9]*}"
                            local suffix="${base_name#*_r[0-9]+_}"
                            # Garantir que pegamos o resto completo após o padrão _rN_
                            if [[ "$base_name" =~ (_r[0-9]+_)(.*) ]]; then
                                suffix="${BASH_REMATCH[2]}"
                            fi
                            base_name="${prefix}_ensemble_${suffix}"
                        else
                            base_name="${base_name%%_*}_ensemble_spi${spi_value}_${CUT_LINE}_dur"
                        fi
                    else
                        base_name="ensemble_spi${spi_value}_${PERCENTAGE}_${CUT_LINE/./_}_dur"
                    fi

                    # Calcula o ensemble mean usando CDO
                    local temp_ensemble_nc="${temp_dir}/${base_name}.nc"
                    local ensemble_bin="${cut_dir}/${base_name}"
                    local ensemble_ctl="${cut_dir}/${base_name}.ctl"

                    # Constrói e executa comando CDO para ensemble mean
                    local cdo_cmd="cdo ensmean"
                    for nc_file in "${nc_files[@]}"; do
                        cdo_cmd+=" ${nc_file}"
                    done
                    cdo_cmd+=" ${temp_ensemble_nc}"

                    echo -e "${GRAY}[INFO]${NC} Executando: ${cdo_cmd}"
                    if eval ${cdo_cmd}; then
                        echo -e "${GREEN}[OK]${NC} Ensemble mean calculado com sucesso para SPI${spi_value}"

                        # Converte o resultado de volta para .ctl
                        if [ -f "${NC2BIN}" ]; then
                            echo -e "${GRAY}[INFO]${NC} Convertendo resultado para CTL/BIN"
                            if bash "${NC2BIN}" "${temp_ensemble_nc}" "${ensemble_ctl}"; then
                                echo -e "${GREEN}[OK]${NC} Convertido para CTL/BIN com sucesso"
                            else
                                echo -e "${RED}[ERRO]${NC} Falha ao converter ensemble NC para CTL/BIN"
                                continue
                            fi
                        else
                            echo -e "${YELLOW}[AVISO]${NC} Script de conversão NC2BIN não encontrado em ${NC2BIN}"
                            # Gera CTL usando CDO diretamente
                            cdo -f grads export_binary "${temp_ensemble_nc}" "${ensemble_bin}"
                        fi

                        # Plot do resultado com GrADS
                        local tmp_gs=$(mktemp)

                        # Extrai parâmetros da grade do NetCDF
                        local dimensions=$(cdo griddes "${temp_ensemble_nc}" | grep -E "xsize|ysize|xfirst|yfirst|xinc|yinc")
                        local nx=$(echo "$dimensions" | grep "xsize" | awk '{print $3}')
                        local ny=$(echo "$dimensions" | grep "ysize" | awk '{print $3}')
                        local loni=$(echo "$dimensions" | grep "xfirst" | awk '{print $3}')
                        local lati=$(echo "$dimensions" | grep "yfirst" | awk '{print $3}')
                        local lon_delta=$(echo "$dimensions" | grep "xinc" | awk '{print $3}')
                        local lat_delta=$(echo "$dimensions" | grep "yinc" | awk '{print $3}')

                        local lonf=$(awk -v start="$loni" -v delta="$lon_delta" -v n="$nx" 'BEGIN {print start + (n-1)*delta}')
                        local latf=$(awk -v start="$lati" -v delta="$lat_delta" -v n="$ny" 'BEGIN {print start + (n-1)*delta}')

                        # Garante que lati < latf
                        if (( $(echo "$lati > $latf" | bc -l) )); then
                            local tmp="$lati"
                            lati="$latf"
                            latf="$tmp"
                        fi

                        # Define CINT e CCOLORS para o plot
                        local cint=$(get_clevs $spi_value $CUT_LINE "max") # manter "max" aqui, pois é duracao
                        local ccolors=$(get_colors)

                        # Determina a variável do NetCDF
                        local var_name=$(cdo showname "${temp_ensemble_nc}" | head -1)

                        # Cria um BOTTOM mais consistente para o ensemble
                        # Extrai modelo e cenário do nome do ensemble
                        local model_scenario=""
                        
                        # Tenta extrair o padrão modelo_cenário mais adaptável
                        if [[ "${ensemble_name}" =~ ([A-Za-z0-9\+\-]+[A-Za-z0-9\+\-]*_[A-Za-z0-9\+\-]+) ]]; then
                            model_scenario="${BASH_REMATCH[1]}"
                        else
                            model_scenario="Ensemble"
                        fi

                        # Verifica se há informação de resolução no nome
                        local resolution=""
                        if [[ "${base_name}" =~ _([gr][0-9n]+)_ ]]; then
                            resolution="_${BASH_REMATCH[1]}"
                        fi

                        # Verifica se há informação de período no nome
                        local period=""
                        if [[ "${base_name}" =~ _([0-9]{4}-[0-9]{4}) ]]; then
                            period="_${BASH_REMATCH[1]}"
                        fi

                        # Construindo BOTTOM sem o padrão _rN_
                        local BOTTOM="${model_scenario}_ensemble${resolution}${period}"
                        
                        # Se o padrão _rN_ ainda estiver presente, remova-o
                        BOTTOM=$(echo "$BOTTOM" | sed -E 's/_r[0-9]+_/_/')
                        
                        echo -e "${BLUE}[INFO]${NC} BOTTOM: ${BOTTOM}"

                        if [[ "$duration_type" == "durmax" ]]; then
                            TITLE="Dur Max | SPI${spi_value} | ${CUT_LINE} | Ensemble Mean"
                        else
                            TITLE="Dur Med | SPI${spi_value} | ${CUT_LINE} | Ensemble Mean"
                        fi
                        
                        echo -e "${BLUE}[INFO]${NC} Gerando gráfico do ensemble para SPI${spi_value}"
                        echo -e "${BLUE}[INFO]${NC} LONI: $loni, LONF: $lonf, LATI: $lati, LATF: $latf"
                        echo -e "${BLUE}[INFO]${NC} SPI: $spi_value, CINT: $cint, CCOLORS: $ccolors"
                        echo -e "${BLUE}[INFO]${NC} BOTTOM: $BOTTOM"
                        echo -e "${BLUE}[INFO]${NC} TITLE: $TITLE"

                        # Prepara o script GrADS
                        sed -e "s|<CTL>|$ensemble_ctl|g" \
                            -e "s|<VAR>|$var_name|g" \
                            -e "s@<TITLE>@$TITLE@g" \
                            -e "s|<SPI>|$spi_value|g" \
                            -e "s|<PERCENTAGE>|$PERCENTAGE|g" \
                            -e "s|<CUTLINE>|$CUT_LINE|g" \
                            -e "s|<BOTTOM>|$BOTTOM|g" \
                            -e "s|<LATI>|$lati|g" \
                            -e "s|<LATF>|$latf|g" \
                            -e "s|<LONI>|$loni|g" \
                            -e "s|<LONF>|$lonf|g" \
                            -e "s|<CINT>|$cint|g" \
                            -e "s|<CCOL>|$ccolors|g" \
                            -e "s|<NOME_FIG>|${ensemble_bin}|g" \
                            "$SCRIPT_DIR/src/gs/gs" > "$tmp_gs"

                        echo -e "${GRAY}[INFO]${NC} Gerando gráfico do ensemble para SPI${spi_value}"
                        if grads -pbc "run $tmp_gs"; then
                            echo -e "${GREEN}[OK]${NC} Gráfico do ensemble gerado com sucesso para SPI${spi_value}"
                            cp ${ensemble_bin}.png ${figures_dir}/$(basename ${ensemble_bin}).png
                        else
                            echo -e "${RED}[ERRO]${NC} Falha na geração do gráfico do ensemble para SPI${spi_value}"
                        fi

                        rm -f "$tmp_gs"
                    else
                        echo -e "${RED}[ERRO]${NC} Falha ao calcular ensemble mean para SPI${spi_value}"
                    fi

                    echo -e "${GRAY}─────────────────────────────────────────${NC}"
                done # fim do loop para cada SPI
            done # fim do loop para cada linha de corte
        done # fim do loop para cada percentual
    done # fim do loop para cada tipo de duração

    print_bar "${GREEN}" "ENSEMBLE MEAN CONCLUÍDO"
}

# Define arrays de estações, percentuais e linhas de corte
# SEASONS=("DJF" "MAM" "JJA" "SON" "ANO")
PERCENTAGES=(80)
CUT_LINES=(-2.0 -1.5 1.0 2.0)

# Ajuste dos parâmetros de entrada para permitir múltiplos diretórios ou arquivos
if [ "$#" -lt 1 ]; then
    echo -e "${RED}ERRO! Parametros incorretos.${NC}"
    echo -e "${YELLOW}Uso: duracaoSPI.sh [DIRETORIOS_OU_ARQUIVOS_ENTRADA...] [TXT_OU_BIN] [PERCENTAGES] [CUT_LINES]${NC}"
    exit 1
fi

# Coletar todos os diretórios/arquivos até encontrarmos um parâmetro que não parece ser caminho
INPUT_PATHS=()
i=1
while [ $i -le $# ] && { [[ "${!i}" == /* ]] || [[ "${!i}" == ./* ]] || [[ -d "${!i}" ]] || [[ -f "${!i}" ]]; }; do
    INPUT_PATHS+=("${!i}")
    i=$((i+1))
done

# Processar os parâmetros restantes como opções
TXT_OR_BIN="${@:$i:1}"
TXT_OR_BIN="${TXT_OR_BIN:-1}"

PERC_ARG="${@:$((i+1)):1}"
if [ -n "$PERC_ARG" ]; then
    IFS=',' read -ra PERCENTAGES <<< "$PERC_ARG"
fi

CUTLINES_ARG="${@:$((i+2)):1}"
if [ -n "$CUTLINES_ARG" ]; then
    IFS=',' read -ra CUT_LINES <<< "$CUTLINES_ARG"
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

# Processa cada caminho de entrada
for INPUT_PATH in "${INPUT_PATHS[@]}"; do
    echo -e "\n${BOLD}${PURPLE}=== Processando caminho: ${CYAN}$INPUT_PATH${NC} ===\n"
    
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
        [ ! -f "$CTL_FILE" ] && echo -e "${RED}Nenhum arquivo .ctl encontrado em $INPUT_PATH.${NC}" && continue
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
                    continue
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
                TITLE="| SPI${SPI} | ${CUT_LINE}"

                echo -e "${GRAY}[INFO]${NC} Gerando gráficos..."
                echo -e "${BLUE}[CONFIG]${NC} LONI: $LONI, LONF: $LONF, LATI: $LATI, LATF: $LATF"
                echo -e "${BLUE}[CONFIG]${NC} SPI: $SPI, CINT: $CINT, CCOLORS: $CCOLORS"

                sed -e "s|<CTL>|$ARQ_CTL_OUT|g" \
                    -e "s|<VAR>|$VAR|g" \
                    -e "s@<TITLE>@Dur Max $TITLE@g" \
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
                    continue
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
                    continue
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
                    -e "s@<TITLE>@Dur Med $TITLE@g" \
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
                    continue
                fi

                # copy figures to output directory
                mkdir -p "$MEDIA_FIG_OUTPUT_DIR/$PERCENTAGE/$CUT_LINE"
                cp ${ARQ_BIN_OUT_MEDIA}_perc${PERCENTAGE}_cut_${CUT_LINE/./_}_spi${SPI}.png $MEDIA_FIG_OUTPUT_DIR/$PERCENTAGE/$CUT_LINE

                echo -e "${GRAY}─────────────────────────────────────────${NC}"
            done
        done
        echo -e "${GREEN}[CONCLUIDO]${NC} para $(basename "$CTL_FILE")\n"
    done
    echo -e "${GREEN}${BOLD}=== Processamento concluído para ${CYAN}$INPUT_PATH${GREEN} ===${NC}\n"
done

echo -e "${GREEN}${BOLD}=== Operação completa para todos os diretórios! ===${NC}"

# Verifica se há mais de uma entrada para calcular o ensemble
if [ ${#INPUT_PATHS[@]} -gt 1 ]; then
    echo -e "\n${BOLD}${GREEN}=== Calculando ensemble para múltiplas entradas ===${NC}"
    calculate_ensemble_mean "${INPUT_PATHS[@]}"
else
    echo -e "\n${YELLOW}[INFO]${NC} Apenas uma entrada fornecida - ensemble mean não será calculado."
fi
