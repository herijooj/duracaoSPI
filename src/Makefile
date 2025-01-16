# Compilador e flags
CXX = g++
CXXFLAGS = -Wall -O2

# Diretórios e arquivos
SRC_DIR = src
BIN_DIR = ../bin
TARGET = duracaoMaxima duracaoMedia

# Arquivos fonte
SRCS = duracaoMaxima.cpp duracaoMedia.cpp
OBJS = $(SRCS:.cpp=.o)

# Regra principal
all: $(BIN_DIR) $(TARGET)

# Criar diretório bin se não existir
$(BIN_DIR):
	mkdir -p $(BIN_DIR)

duracaoMaxima: duracaoMaxima.o
	$(CXX) $(CXXFLAGS) duracaoMaxima.o -o $(BIN_DIR)/duracaoMaxima

duracaoMedia: duracaoMedia.o
	$(CXX) $(CXXFLAGS) duracaoMedia.o -o $(BIN_DIR)/duracaoMedia
# Regra para arquivos objeto
%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

# Limpar arquivos compilados
clean:
	rm -f $(OBJS) $(TARGET)
	rm -rf $(BIN_DIR)
	rm -f *.o

.PHONY: all clean
