      SUBROUTINE CALDIFF (ISTL_,M,CON1)  
C  
C CHANGE RECORD  
C **  SUBROUTINE CALDIFF CALCULATES THE HORIZONTAL DIFFUSIVE  
C **  TRANSPORT OF DISSOLVED OR SUSPENDED CONSITITUENT M LEADING TO  
C **  A REVISEDED VALUE AT TIME LEVEL (N+1). THE VALUE OF ISTL  
C **  INDICATES THE NUMBER OF TIME LEVELS IN THE STEP  
C  
      USE GLOBAL  
	IMPLICIT NONE
	INTEGER::K,L,LS,M,ISTL_
	REAL::CON1
      DIMENSION CON1(LCM,KCM)  
C  
C **  HORIZONTAL DIFFUSIVE FLUX CALCULATION  
C  
      DO K=1,KC  
        DO L=2,LA  
          LS=LSC(L)  
        FUHU(L,K)=FUHU(L,K)+0.5*SUB(L)*DYU(L)*HU(L)*(AH(L,K)+AH(LWEST(L),K))*
     &        (CON1(LWEST(L),K)-CON1(L,K))*DXIU(L)  
         FVHU(L,K)=FVHU(L,K)+0.5*SVB(L)*DXV(L)*HV(L)*(AH(L,K)+AH(LS,K))*
     &        (CON1(LS,K)-CON1(L,K))*DYIV(L)  
        ENDDO  
      ENDDO  
      RETURN  
      END  

