// Implementado por Eduardo Machado
// 2016

#include <iostream>
#include <string>
#include <fstream>
#include <map>
#include <cstdlib>
#include <cmath>
#include <vector>
#include <iomanip>

using namespace std;

int main(int argc, char *argv[]){
  // Arquivos de entrada e saída
  ifstream fileIn;
	ofstream fileOutBin, fileOutTxt;
  // Parâmetros de entrada
  string nameFileIn, nameFileOut;
  int nx, ny, nz, nt, txtOrBin;
  float undef, adder, cutLine, dataCutLine;
  // Demais variáveis do programa
  int i, j, k, l;       // Indices para trabalhar com as matrizes
  int undefCont, eventCont;        // Contador de valores indefinidos
  bool zeroSentinel, cutLineSentinel;    // booleano para dizer quando o gráfico passa pelo zero
  float ****inMatrix;   // matriz de entrada
  float ***outMatrix;   // matriz de saída

  // Leitura de parâmetros.
	if(argc != 11){
		cout << "Parâmetros errados!" << endl;
		return 0;
	}
	nameFileIn=argv[1];
	nx=atoi(argv[2]);
	ny=atoi(argv[3]);
  nz=atoi(argv[4]);
  nt=atoi(argv[5]);
  undef=atof(argv[6]);
  cutLine=atof(argv[7]);
  txtOrBin=atoi(argv[8]);
  nameFileOut=argv[9];
  dataCutLine=atof(argv[10]);
  // Alocação da matriz de entrada
  inMatrix = new float***[nx];
  outMatrix = new float**[nx];
  for(i=0;i<nx;i++){
    inMatrix[i] = new float**[ny];
    outMatrix[i] = new float*[ny];
    for(j=0;j<ny;j++){
      inMatrix[i][j] = new float*[nz];
      outMatrix[i][j] = new float[nz];
      for(k=0;k<nz;k++){
        inMatrix[i][j][k] = new float[nt];
      }
    }
  }
  // Abertura do arquivo de entrada.
	fileIn.open(nameFileIn.c_str(), ios::binary);
	fileIn.seekg (0);
  for(i=0;i<nt;i++){
    for(j=0;j<nz;j++){
      for(k=0;k<ny;k++){
        for(l=0;l<nx;l++){
          fileIn.read((char*)&inMatrix[l][k][j][i], sizeof(float));
          if(isnan(inMatrix[l][k][j][i])){
						inMatrix[l][k][j][i]=undef;
					}
        }
      }
    }
  }

  if(cutLine < 0){
    for(i=0;i<nx;i++){
      for(j=0;j<ny;j++){
        for(k=0;k<nz;k++){
          zeroSentinel=true;
          cutLineSentinel=false;
          outMatrix[i][j][k]=0;
          adder=0;
          eventCont=0;
          undefCont=0;
          outMatrix[i][j][k]=0;
          for(l=0;l<nt;l++){
            if((inMatrix[i][j][k][l] <= 0.0)&&(inMatrix[i][j][k][l] != undef)){
              if(zeroSentinel == true){
                zeroSentinel = false;
              }
              if((inMatrix[i][j][k][l] <= cutLine)&&(cutLineSentinel == false)){
                cutLineSentinel=true;
                eventCont++;
              }
              adder++;
            }
            if((inMatrix[i][j][k][l] >= 0.0)&&(zeroSentinel == false)&&(inMatrix[i][j][k][l] != undef)){
              zeroSentinel = true;
              if(cutLineSentinel == true){
                if(outMatrix[i][j][k] < adder){
                  outMatrix[i][j][k] = adder;
                }
                cutLineSentinel = false;
              }
              adder = 0;
            }
            if(inMatrix[i][j][k][l] != undef){
              undefCont++;
            }
            if((l == nt-1)&&(zeroSentinel == false)&&(cutLineSentinel == true)){ // Tratando de um caso expecífico, caso a série acabe com o último valor sendo negativo
              zeroSentinel = true;
              if(outMatrix[i][j][k] < adder){
                outMatrix[i][j][k] = adder;
              }
              adder = 0;
            }
          }
          if(undefCont <= (dataCutLine/100)*nt){
            outMatrix[i][j][k] = undef;
          }else if(eventCont == 0){
            outMatrix[i][j][k] = 0.0;
          }
        }
      }
    }
  } else if(cutLine > 0){
    for(i=0;i<nx;i++){
      for(j=0;j<ny;j++){
        for(k=0;k<nz;k++){
          zeroSentinel=true;
          cutLineSentinel=false;
          outMatrix[i][j][k]=0;
          adder=0;
          eventCont=0;
          undefCont=0;
          outMatrix[i][j][k]=0;
          for(l=0;l<nt;l++){
            if((inMatrix[i][j][k][l] >= 0.0)&&(inMatrix[i][j][k][l] != undef)){
              if(zeroSentinel == true){
                zeroSentinel = false;
              }
              if((inMatrix[i][j][k][l] >= cutLine)&&(cutLineSentinel == false)){
                cutLineSentinel=true;
                eventCont++;
              }
              adder++;
            }
            if((inMatrix[i][j][k][l] <= 0.0)&&(zeroSentinel == false)&&(inMatrix[i][j][k][l] != undef)){
              zeroSentinel = true;
              if(cutLineSentinel == true){
                if(outMatrix[i][j][k] < adder){
                  outMatrix[i][j][k] = adder;
                }
                cutLineSentinel = false;
              }
              adder = 0;
            }
            if(inMatrix[i][j][k][l] != undef){
              undefCont++;
            }
            if((l == nt-1)&&(zeroSentinel == false)&&(cutLineSentinel == true)){ // Tratando de um caso expecífico, caso a série acabe com o último valor sendo negativo
              zeroSentinel = true;
              if(outMatrix[i][j][k] < adder){
                outMatrix[i][j][k] = adder;
              }
              adder = 0;
            }
          }
          if(undefCont <= (dataCutLine/100)*nt){
            outMatrix[i][j][k] = undef;
          }else if(eventCont == 0){
            outMatrix[i][j][k] = 0.0;
          }
        }
      }
    }
  } else {
    cout << "A linha de corte não pode ser igual a zero." << endl;
  }

  // Escrita no arquivo de saída.
  if((txtOrBin == 0)||(txtOrBin == 2)){
		fileOutTxt.open((nameFileOut+".txt").c_str(), ios::out);
    for(i=0;i<nz;i++){
  		for(j=ny-1;j>=0;j--){
  			for(k=0;k<nx;k++){
          if(outMatrix[k][j][i] == undef){
            fileOutTxt << "----- ";
          }else if(outMatrix[k][j][i] < 10){
            fileOutTxt << "0" << setprecision(3) << outMatrix[k][j][i] << " ";
          }else{
            fileOutTxt << setprecision(3) << outMatrix[k][j][i] << " ";
          }
  			}
        fileOutTxt << endl;
  		}
    }
  }
  if((txtOrBin == 1)||(txtOrBin == 2)){
    fileOutBin.open((nameFileOut+".bin").c_str(), ios::binary);

    for(i=0;i<nz;i++){
  		for(j=0;j<ny;j++){
  			for(k=0;k<nx;k++){
          fileOutBin.write ((char*)&outMatrix[k][j][i], sizeof(float));
        }
      }
		}
  }

  fileOutTxt.close();
  fileOutBin.close();
  fileIn.close();
}
