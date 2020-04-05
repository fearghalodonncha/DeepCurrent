      SUBROUTINE CALTRAN (ISTL_,IS2TL_,MVAR,MO,CON,CON1)  
C  
C CHANGE RECORD  
C  ADDED TRANSPORT BYPASS MASK, IMASKDRY FOR DRY CELLS  
C **  SUBROUTINE CALTRAN CALCULATES THE ADVECTIVE  
C **  TRANSPORT OF DISSOLVED OR SUSPENDED CONSITITUENT M LEADING TO  
C **  A NEW VALUE AT TIME LEVEL (N+1). THE VALUE OF ISTL INDICATES  
C **  THE NUMBER OF TIME LEVELS IN THE STEP  
C  
      USE GLOBAL
      USE OMP_LIB

      DIMENSION CON(LCM,KCM),CON1(LCM,KCM)  
      REAL,SAVE,ALLOCATABLE,DIMENSION(:,:)::CONTMN  
      REAL,SAVE,ALLOCATABLE,DIMENSION(:,:)::CONTMX  
      REAL,SAVE,ALLOCATABLE,DIMENSION(:,:)::FQCPAD  
      REAL,SAVE,ALLOCATABLE,DIMENSION(:,:)::QSUMNAD  
      REAL,SAVE,ALLOCATABLE,DIMENSION(:,:)::QSUMPAD  
      REAL,SAVE,ALLOCATABLE,DIMENSION(:,:)::POS

      REAL,SAVE,ALLOCATABLE,DIMENSION(:,:)::WQBCCON

      IF(.NOT.ALLOCATED(CONTMN))THEN
        ALLOCATE(CONTMN(LCM,KCM))  
        ALLOCATE(CONTMX(LCM,KCM))  
        ALLOCATE(FQCPAD(LCM,KCM))  
        ALLOCATE(QSUMNAD(LCM,KCM))  
        ALLOCATE(QSUMPAD(LCM,KCM))  
        ALLOCATE(POS(LCM,KCM))  
        ALLOCATE(WQBCCON(LCM,KCM))  

        DO L=1,LC  
          FWU(L,0)=0.  
          FWU(L,KC)=0.  
        ENDDO  
        CONTMN=0.0
        CONTMX=0.0
        FQCPAD=0.0
        QSUMNAD=0.0  ! *** NOT USED
        QSUMPAD=0.0
        POS=0.0
        WQBCCON=0.0
      ENDIF

C  
      BSMALL=1.0E-6  
      ISUD=1  
      IF(ISDYNSTP.EQ.0)THEN  
        DELT=DT2  
        DELTA=DT2  
        IF(ISCDCA(MVAR).EQ.2) DELTA=DT  
        DELTD2=DT  
        IF(ISTL_.NE.3)THEN  
          DELT=DT  
          DELTA=DT  
          DELTD2=0.5*DT  
          IF(IS2TIM.EQ.0)ISUD=0  ! *** PMC SINGLE LINE CHANGE
        ENDIF  
      ELSE  
        DELT=DTDYN  
        DELTA=DTDYN  
        DELTD2=0.5*DTDYN  
      END IF  
      DELTA4=0.25*DELTA 

      ! *** DSLLC BEGIN
      M=MO
      IF(IS2TL_.EQ.1)THEN  
        ISUD=1  
        IF(MVAR.NE.8)THEN
          CON1=CON    ! *** ARRAYS
        ENDIF            
      ENDIF  
      
      ! *** SAVE OLD WQ CONCENTRATIONS FOR OPEN BOUNDARY CELLS
      IF(MVAR.EQ.8)THEN
        DO IOBC=1,NBCSOP  
          L=LOBCS(IOBC)  
          DO K=1,KC
            WQBCCON(L,K)=CON(L,K)  
          ENDDO  
        ENDDO  
      ENDIF
      ! *** DSLLC END
C  
C **  CALCULATED EXTERNAL SOURCES AND SINKS  
C  
      CALL CALFQC (ISTL_,IS2TL_,MVAR,M,CON,CON1,FQCPAD,QSUMPAD,QSUMNAD)
C  
C **  SELECT TRANSPORT OPTION, ISPLIT=1 FOR HORIZONTAL-VERTICAL  
C **  OPERATOR SPLITTING  
C **  BEGIN COMBINED ADVECTION SCHEME  
C **  ADVECTIVE FLUX CALCULATION  
C  
      IF(ISTL_.EQ.2) GOTO 300  
      IF(ISCDCA(MVAR).EQ.0) GOTO 300  
      IF(ISCDCA(MVAR).EQ.1) GOTO 400  
      IF(ISCDCA(MVAR).EQ.2) GOTO 350  
C  
C **  CALCULATE ADVECTIVE FLUXES BY UPWIND DIFFERENCE WITH ADVECTION  
C **  AVERAGED BETWEEN (N) AND (N+1) OR (N-1) AND (N+1) AND ADVECTED  
C **  AT (N) OR (N-1) IF ISTL EQUALS 2 OR 3 RESPECTIVELY  
C  
  300 CONTINUE  
      IF(IDRYTBP.EQ.0)THEN  
!$OMP PARALLEL SHARED(DEFAULT)  
        DO K=1,KS  
!$OMP DO  schedule(static,chunksize) 
          DO L=2,LA  
              FUHU(L,K)=UHDY2(L,K)*CON1(LUPU(L,K),K)  
              FVHU(L,K)=VHDX2(L,K)*CON1(LUPV(L,K),K)  
              FWU(L,K)=W2(L,K)*CON1(L,KUPW(L,K))
          ENDDO  
        ENDDO
        DO L=2,LA  
          FUHU(L,KC)=UHDY2(L,KC)*CON1(LUPU(L,KC),KC)  
          FVHU(L,KC)=VHDX2(L,KC)*CON1(LUPV(L,KC),KC)  
        ENDDO 
!$OMP END PARALLEL 
      ELSE  
        DO K=1,KC  
          DO L=2,LA  
            IF(LMASKDRY(L))THEN  
              FUHU(L,K)=UHDY2(L,K)*CON1(LUPU(L,K),K)  
              FVHU(L,K)=VHDX2(L,K)*CON1(LUPV(L,K),K)  
            ELSE
              FUHU(L,K)=0.  
              FVHU(L,K)=0.  
            ENDIF  
          ENDDO  
        ENDDO
        IF(KC.GT.1)THEN
          DO K=1,KS  
            DO L=2,LA  
              IF(LMASKDRY(L))THEN  
                FWU(L,K)=W2(L,K)*CON1(L,KUPW(L,K))  
              ELSE
                FWU(L,K)=0.
              ENDIF  
            ENDDO 
          ENDDO  
        ENDIF  

      ENDIF  

      GOTO 500  
C  
C **  CALCULATE ADVECTIVE FLUXES BY UPWIND DIFFERENCE WITH ADVECTION  
C **  AVERAGED BETWEEN  (N-1) AND (N+1) AND ADVECTED FIELD AVERAGED  
C **  BETWEEN AT (N-1) AND (N) IF ISTL 3 ONLY  
C  
  350 CONTINUE  
!$OMP PARALLEL SHARED(DEFAULT)
      DO K=1,KC  
!$OMP DO SCHEDULE(STATIC,CHUNKSIZE)
        DO L=2,LA  
          CONT(L,K)=0.5*(CON(L,K)+CON1(L,K))  
     &        +DELT*0.5*FQC(L,K)*DXYIP(L)/H2P(L)  
        ENDDO  
!$OMP END DO
      ENDDO  
      DO K=1,KC  
!$OMP DO SCHEDULE(STATIC,CHUNKSIZE)
        DO L=2,LA  
          FUHU(L,K)=UHDY2(L,K)*CONT(LUPU(L,K),K)  
          FVHU(L,K)=VHDX2(L,K)*CONT(LUPV(L,K),K)  
          FWU(L,K)=W2(L,K)*CONT(L,KUPW(L,K))  
        ENDDO  
      ENDDO 
!$OMP END PARALLEL
      GOTO 500  
C  
C **  CALCULATE ADVECTIVE FLUXES BY CENTRAL DIFFERENCE WITH TRANSPORT  
C **  AVERAGED BETWEEN (N+1) AND (N-1) AND TRANSPORTED FIELD AT (N)  
C  
  400 CONTINUE  
C PMC      DO K=1,KC  
C PMC        DO L=2,LA  
C PMC          CONT(L,K)=CON1(L,K)  
C PMC        ENDDO  
C PMC      ENDDO  
      DO K=1,KC  
        DO L=2,LA  
          LS=LSC(L)  
          FUHU(L,K)=0.5*UHDY2(L,K)*(CON(L,K)+CON(LWEST(L),K))  
          FVHU(L,K)=0.5*VHDX2(L,K)*(CON(L,K)+CON(LS,K))  
        ENDDO  
      ENDDO  
      DO K=1,KC  
        DO LL=1,NCBS  
          L=LCBS(LL)  
          LN=LNC(L)  
          IF(VHDX2(LN,K).LT.0.) FVHU(LN,K)=VHDX2(LN,K)*CON1(LN,K)  
        ENDDO  
        DO LL=1,NCBW  
          L=LCBW(LL)
          LE=LEAST(L)
          IF(UHDY2(LE,K).LT.0.) FUHU(LE,K)=UHDY2(LE,K)*CON1(LE,K)  
        ENDDO  
        DO LL=1,NCBE  
          L=LCBE(LL)  
          IF(UHDY2(L,K).GT.0.) FUHU(L,K)=UHDY2(L,K)*CON1(LWEST(L),K)  
        ENDDO  
        DO LL=1,NCBN  
          L=LCBN(LL)  
          LS =LSC(L)  
          IF(VHDX2(L,K).GT.0.) FVHU(L,K)=VHDX2(L,K)*CON1(LS,K)  
        ENDDO  
      ENDDO  
      DO K=1,KS  
        DO L=2,LA  
          FWU(L,K)=0.5*W2(L,K)*(CON(L,K+1)+CON(L,K))  
        ENDDO  
      ENDDO  
C  
C **  STANDARD ADVECTION CALCULATION  
C  
  500 CONTINUE  
C  
C BEGIN IF ON TRANSPORT OPTION CHOICE  
C  
      ! *** CALCULATE AND ADD HORIZONTAL DIFFUSION FLUX (PMC MOVED)
      IF(ISHDMF.EQ.2) CALL CALDIFF (ISTL_,M,CON1)

      ! *** IF ISACAC EQ 0 INCLUDE FQC MASS SOURCES IN UPDATE  
      IF(ISCDCA(MVAR).EQ.0)THEN  
        IF(ISTL_.EQ.2)THEN  
          IF(IDRYTBP.EQ.0)THEN  
!$OMP PARALLEL SHARED(DEFAULT) PRIVATE(RDZIC) 
            DO K=1,KC  
              RDZIC=DZIC(K)  
!$OMP DO schedule(static,chunksize)
              DO L=2,LA
                LN=LNC(L)
                LE=LEAST(L)
                CH(L,K)=CON1(L,K)*H1P(L)  
     &              +DELT*( ( RDZIC*FQC(L,K)  
     &              +FUHU(L,K)-FUHU(LE,K)  
     &              +FVHU(L,K)-FVHU(LN,K))*DXYIP(L)  
     &              +(FWU(L,K-1)-FWU(L,K))*RDZIC )  
             ENDDO  
            ENDDO  
!$OMP END PARALLEL


          ELSE  
            DO K=1,KC  
              RDZIC=DZIC(K)  
              DO L=2,LA
                IF(IMASKDRY(L).EQ.0)THEN  
                  LN=LNC(L)
                  LE=LEAST(L)
                  CH(L,K)=CON1(L,K)*H1P(L)  
     &              +DELT*( ( RDZIC*FQC(L,K)+FUHU(L,K)-FUHU(LE,K)  
     &              +FVHU(L,K)-FVHU(LN,K))*DXYIP(L)  
     &              +(FWU(L,K-1)-FWU(L,K))*RDZIC )  
                ELSEIF(IMASKDRY(L).EQ.1)THEN
                  CH(L,K)=CON1(L,K)*H1P(L)  
     &              +DELT*( ( FQC(L,K) )*DXYIP(L) )  
                ELSEIF(IMASKDRY(L).EQ.2)THEN
                  CH(L,K)=CON1(L,K)*H1P(L)
                ENDIF
              ENDDO  
            ENDDO 
          ENDIF    ! END IF IDRYTBP
          IF(ISFCT(MVAR).GE.1.AND.ISADAC(MVAR).GT.0)THEN  ! *** DSLLC SINGLE LINE
            DO K=1,KC  
              DO L=2,LA  
                CON2(L,K)=CON1(L,K)  
              ENDDO  
            ENDDO  

          ENDIF  

C  
C ELSE ON TIME LEVEL CHOICE FOR ISCDCA=0   (i.e. ISTL_ == 2) 
C  
        ELSE
!$OMP PARALLEL SHARED(DEFAULT) PRIVATE(RDZIC)
          DO K=1,KC  
            RDZIC=DZIC(K)  
!$OMP DO schedule(static,chunksize)
            DO L=2,LA
              LE=LEAST(L)
              LN=LNC(L)
              CH(L,K)=CON1(L,K)*H2P(L)  
     &            +DELT*( ( RDZIC*FQC(L,K)  
     &            +FUHU(L,K)-FUHU(LE,K)  
     &            +FVHU(L,K)-FVHU(LN,K))*DXYIP(L)  
     &            +(FWU(L,K-1)-FWU(L,K))*RDZIC )  
            ENDDO  
          ENDDO  
!$OMP END PARALLEL
          IF(ISFCT(MVAR).GE.1.AND.ISADAC(MVAR).GT.0)THEN  ! *** DSLLC SINGLE LINE
            DO K=1,KC  
              DO L=2,LA  
                CON2(L,K)=CON(L,K)  
              ENDDO  
            ENDDO  
          ENDIF
        ENDIF  
C  
C ENDIF ON TIME LEVEL CHOICE FOR ISCDCA=0  
C  
        IF(ISUD.EQ.1.AND.IS2TL_.EQ.0.AND.MVAR.NE.8)THEN
          DO K=1,KC
            DO IOBC=1,NBCSOP  
              L=LOBCS(IOBC)  
              CON(L,K)=CON1(L,K)  
            ENDDO  

            DO L=2,LA
              CON1(L,K)=CON(L,K)
            ENDDO  
          ENDDO  
        ENDIF
    

        ! *** UPDATE NEW CONCENTRATIONS        
        DO K=1,KC  
 !         DO L=2,LA  
            CON(2:LA,K)=CH(2:LA,K)*HPI(2:LA)  
 !         ENDDO  
        ENDDO 

C  
C *** ELSE ON TRANSPORT OPTION CHOICE  
C *** IF ISACAC NE 0 DO NOT INCLUDE FQC MASS SOURCES IN UPDATE  
C
      ELSE  
C  
C BEGIN IF ON TIME LEVEL CHOICE FOR ISCDCA.NE.0  
C  
        IF(ISTL_.EQ.2)THEN  
          IF(IDRYTBP.EQ.0)THEN
!$OMP PARALLEL SHARED(DEFAULT) PRIVATE(RDZIC)
            DO K=1,KC  
              RDZIC=DZIC(K)  
!$OMP DO SCHEDULE(static,chunksize)
              DO L=2,LA
                LE=LEAST(L)
                LN=LNC(L)
                CH(L,K)=CON1(L,K)*H1P(L)  
     &              +DELT*( ( RDZIC*FQC(L,K)
     &              +FUHU(L,K)-FUHU(LE,K)  
     &              +FVHU(L,K)-FVHU(LN,K))*DXYIP(L)  
     &              +(FWU(L,K-1)-FWU(L,K))*RDZIC )  
              ENDDO  
            ENDDO  
!$OMP END PARALLEL
          ELSE  
            DO K=1,KC  
              RDZIC=DZIC(K)  
              DO L=2,LA  
                IF(IMASKDRY(L).EQ.0)THEN
                    LE=LEAST(L)
                    LN=LNC(L)
                    CH(L,K)=CON1(L,K)*H1P(L)  
     &              +DELT*( ( RDZIC*FQC(L,K)
     &              +FUHU(L,K)-FUHU(LE,K)  
     &              +FVHU(L,K)-FVHU(LN,K))*DXYIP(L)  
     &              +(FWU(L,K-1)-FWU(L,K))*RDZIC )  
                ELSEIF(IMASKDRY(L).EQ.1)THEN
                    CH(L,K)=CON1(L,K)*H1P(L)  
     &              +DELT*( ( FQC(L,K) )*DXYIP(L) )  
                ELSEIF(IMASKDRY(L).EQ.2)THEN  
                    CH(L,K)=CON1(L,K)*H1P(L)
                ENDIF
              ENDDO  
            ENDDO  
          ENDIF  
          IF(ISFCT(MVAR).GE.1)THEN  
            CON2=CON1   ! *** ARRAYS
          ENDIF  
C  
C ELSE ON TIME LEVEL CHOICE FOR ISCDCA.NE.0 AND ISTL.EQ.3
C  
        ELSE  
!$OMP PARALLEL SHARED(DEFAULT) PRIVATE(RDZIC)
          DO K=1,KC  
            RDZIC=DZIC(K)  
!$OMP DO schedule(static,chunksize)
            DO L=2,LA
              LE=LEAST(L)
              LN=LNC(L)
              CH(L,K)=CON1(L,K)*H2P(L)  
     &            +DELT*( ( RDZIC*FQC(L,K)+FUHU(L,K)-FUHU(LEA,K)  
     &            +FVHU(L,K)-FVHU(LN,K))*DXYIP(L)  
     &            +(FWU(L,K-1)-FWU(L,K))*RDZIC )  
            ENDDO  
          ENDDO  
!$OMP END PARALLEL
          IF(ISFCT(MVAR).GE.1)THEN  
            CON2=CON    ! *** ARRAYS
          ENDIF  
        ENDIF  
C  
C ENDIF ON TIME LEVEL CHOICE FOR ISCDCA.NE.0  
C  
        IF(ISUD.EQ.1.AND.MVAR.NE.8)THEN  
          DO K=1,KC
            DO IOBC=1,NBCSOP  
              L=LOBCS(IOBC)  
              CON(L,K)=CON1(L,K)  
            ENDDO  

            DO L=2,LA
              CON1(L,K)=CON(L,K)
            ENDDO  
          ENDDO  
        ENDIF
        ! *** PMC-BOUNDARY CONDITIONS APPLIED BELOW
        DO K=1,KC  
          DO L=2,LA  
            CON(L,K)=CH(L,K)*HPI(L)  
          ENDDO  
        ENDDO  

      ENDIF  

C  
C ENDIF ON TRANSPORT OPTION CHOICE  
C
C *** APPLY OPEN BOUNDARY CONDITIONS, BASED ON DIRECTION OF FLOW
C  
      ! *** ALL OTHER WATER CONSTITUENTS 
      IF(MVAR.EQ.8)THEN   !.AND.IWQPSL.EQ.2)THEN
        M=4+NTOX+NSED+NSND+MO

        ! *** RESTORE ORIGINAL CONCENTRATIONS PRIOR TO APPLYING OPEN BC'S
        DO K=1,KC
          DO IOBC=1,NBCSOP  
            L=LOBCS(IOBC)  
            CON1(L,K)=WQBCCON(L,K)  
          ENDDO  
        ENDDO  
      ENDIF
      ! *** SOUTH OPEN B


      DO K=1,KC  
        DO LL=1,NCBS  
          NSID=NCSERS(LL,M)  
          L=LCBS(LL)  
          LN=LNC(L)  
          IF(VHDX2(LN,K).LE.0.)THEN
            ! *** FLOWING OUT OF DOMAIN
            IF(ISTL_.EQ.2)THEN  
              CTMP=CON1(L,K)+DELT*(VHDX2(LN,K)*CON1(L,K)  
     &            -FVHU(LN,K))*DXYIP(L)*HPI(L)  
            ELSE  
              IF(ISCDCA(MVAR).NE.2)CTMP=CON1(L,K)+DELT*(VHDX2(LN,K)
     &            *CON1(L,K)-FVHU(LN,K))*DXYIP(L)*HPI(L)  
              IF(ISCDCA(MVAR).EQ.2) CTMP=0.5*(CON1(L,K)+CON(L,K))  
     &            +0.5*(CON1(L,K)-CON(L,K))*H2P(L)*HPI(L)  
     &            +DELT*(0.5*VHDX2(LN,K)*(CON1(L,K)+CON(L,K))  
     &            -FVHU(LN,K))*DXYIP(L)*HPI(L)  
              CON1(L,K)=CON(L,K)  
            ENDIF  
            CON(L,K)=CTMP  
            CBSTMP=CBS(LL,1,M)+CSERT(1,NSID,M)  
            IF(M.EQ.1.AND.CON(L,K).GT.CBSTMP)THEN
              CON(L,K)=CBSTMP  
            ENDIF
            CLOS(LL,K,M)=CON(L,K)  
            NLOS(LL,K,M)=N  
          ELSE  
            ! *** FLOWING INTO DOMAIN
            IF(ISUD.EQ.1) CON1(L,K)=CON(L,K)  
            CBT=WTCI(K,1)*CBS(LL,1,M)+WTCI(K,2)*CBS(LL,2,M)+CSERT(
     &          K,NSID,M)  
            NMNLO=N-NLOS(LL,K,M)  
            IF(NMNLO.GE.NTSCRS(LL))THEN  
              CON(L,K)=CBT  
            ELSE  
              CON(L,K)=CLOS(LL,K,M)  
     &            +(CBT-CLOS(LL,K,M))*FLOAT(NMNLO)/FLOAT(NTSCRS(LL))  
            ENDIF  
          ENDIF  
        ENDDO  
      ENDDO  
      VSW_BOUNDARY = 0
      SAL_CELL = 0
      ! *** WEST OPEN BC
        DO LL=1,NCBW  
              DO K=1,KC

          NSID=NCSERW(LL,M)  
          L=LCBW(LL)
          LE=LEAST(L)
          IF(UHDY2(LE,K).LE.0.)THEN  
            ! *** FLOWING OUT OF DOMAIN
            IF(ISTL_.EQ.2)THEN  
              CTMP=CON1(L,K)+DELT*(UHDY2(LE,K)*CON1(L,K)  
     &            -FUHU(LE,K))*DXYIP(L)*HPI(L)  
            ELSE  
              IF(ISCDCA(MVAR).NE.2) CTMP=CON1(L,K)  
     &            +DELT*(UHDY2(LE,K)*CON1(L,K)-FUHU(LE,K))*DXYIP(L)
     &            *HPI(L)  
              IF(ISCDCA(MVAR).EQ.2) CTMP=0.5*(CON1(L,K)+CON(L,K))  
     &            +0.5*(CON1(L,K)-CON(L,K))*H2P(L)*HPI(L)  
     &            +DELT*(0.5*UHDY2(LE,K)*(CON1(L,K)+CON(L,K))  
     &            -FUHU(LE,K))*DXYIP(L)*HPI(L)  
              CON1(L,K)=CON(L,K)  
            ENDIF  
            CON(L,K)=CTMP  
            CBWTMP=CBW(LL,1,M)+CSERT(1,NSID,M)  
            IF(M.EQ.1.AND.CON(L,K).GT.CBWTMP) CON(L,K)=CBWTMP  
            CLOW(LL,K,M)=CON(L,K)  
            NLOW(LL,K,M)=N  
            SAL_CELL = SAL_CELL + (CTMP*(-1.)/KC)

          ELSE  
            ! *** FLOWING INTO DOMAIN
            IF(ISUD.EQ.1) CON1(L,K)=CON(L,K)  
            CBT=WTCI(K,1)*CBW(LL,1,M)+WTCI(K,2)*CBW(LL,2,M)+CSERT(
     &          K,NSID,M)  
            NMNLO=N-NLOW(LL,K,M)  
            IF(NMNLO.GE.NTSCRW(LL))THEN  
              CON(L,K)=CBT  
            ELSE  
              CON(L,K)=CLOW(LL,K,M)  
     &            +(CBT-CLOW(LL,K,M))*FLOAT(NMNLO)/FLOAT(NTSCRW(LL))

            ENDIF  
            SAL_CELL = SAL_CELL + CON(L,K)/KC
          ENDIF  
        ENDDO  
        VSW_BOUNDARY= VSW_BOUNDARY+((.5*( HU(L) + HV(L)))*DXYP(L)*(1 - (SAL_CELL/35)))
        SAL_CELL = 0
      ENDDO
      
      ! *** EAST OPEN BC
      DO K=1,KC  
        DO LL=1,NCBE  
          NSID=NCSERE(LL,M)  
          L=LCBE(LL)  
          IF(UHDY2(L,K).GE.0.)THEN  
            ! *** FLOWING OUT OF DOMAIN
            IF(ISTL_.EQ.2)THEN  
              CTMP=CON1(L,K)+DELT*(FUHU(L,K)  
     &            -UHDY2(L,K)*CON1(L,K))*DXYIP(L)*HPI(L)  
            ELSE  
              IF(ISCDCA(MVAR).NE.2) CTMP=CON1(L,K)+DELT*(FUHU(L,K)  
     &            -UHDY2(L,K)*CON1(L,K))*DXYIP(L)*HPI(L)  
              IF(ISCDCA(MVAR).EQ.2) CTMP=0.5*(CON1(L,K)+CON(L,K))  
     &           +0.5*(CON1(L,K)-CON(L,K))*H2P(L)*HPI(L)+DELT*(FUHU(L,K)  
     &            -0.5*UHDY2(L,K)*(CON1(L,K)+CON(L,K)))*DXYIP(L)*HPI(L)  
              CON1(L,K)=CON(L,K)  
            ENDIF  
            CON(L,K)=CTMP  
            CBETMP=CBE(LL,1,M)+CSERT(1,NSID,M)  
            IF(M.EQ.1.AND.CON(L,K).GT.CBETMP) CON(L,K)=CBETMP  
            CLOE(LL,K,M)=CON(L,K)  
            NLOE(LL,K,M)=N  
          ELSE  
            ! *** FLOWING INTO DOMAIN
            IF(ISUD.EQ.1) CON1(L,K)=CON(L,K)  
            CBT=WTCI(K,1)*CBE(LL,1,M)+WTCI(K,2)*CBE(LL,2,M)+CSERT(
     &          K,NSID,M)  
            NMNLO=N-NLOE(LL,K,M)  
            IF(NMNLO.GE.NTSCRE(LL))THEN  
              CON(L,K)=CBT  
            ELSE  
              CON(L,K)=CLOE(LL,K,M)  
     &            +(CBT-CLOE(LL,K,M))*FLOAT(NMNLO)/FLOAT(NTSCRE(LL))  
            ENDIF  
          ENDIF  
        ENDDO  
      ENDDO  
      
      ! *** NORTH OPEN BC
      DO K=1,KC  
        DO LL=1,NCBN  
          NSID=NCSERN(LL,M)  
          L=LCBN(LL)  
          LS=LSC(L)  
          IF(VHDX2(L,K).GE.0.)THEN  
            ! *** FLOWING OUT OF DOMAIN
            IF(ISTL_.EQ.2)THEN  
              CTMP=CON1(L,K)+DELT*(FVHU(L,K)  
     &            -VHDX2(L,K)*CON1(L,K))*DXYIP(L)*HPI(L)  
            ELSE  
              IF(ISCDCA(MVAR).NE.2) CTMP=CON1(L,K)+DELT*(FVHU(L,K)  
     &            -VHDX2(L,K)*CON1(L,K))*DXYIP(L)*HPI(L)  
              IF(ISCDCA(MVAR).EQ.2) CTMP=0.5*(CON1(L,K)+CON(L,K))  
     &           +0.5*(CON1(L,K)-CON(L,K))*H2P(L)*HPI(L)+DELT*(FVHU(L,K)  
     &            -0.5*VHDX2(L,K)*(CON1(L,K)+CON(L,K)))*DXYIP(L)*HPI(L)  
              CON1(L,K)=CON(L,K)  
            ENDIF  
            CON(L,K)=CTMP  
            CBNTMP=CBN(LL,1,M)+CSERT(1,NSID,M)  
            IF(M.EQ.1.AND.CON(L,K).GT.CBNTMP) CON(L,K)=CBNTMP  
            CLON(LL,K,M)=CON(L,K)  
            NLON(LL,K,M)=N  
          ELSE  
            ! *** FLOWING INTO DOMAIN
            IF(ISUD.EQ.1) CON1(L,K)=CON(L,K)  
            CBT=WTCI(K,1)*CBN(LL,1,M)+WTCI(K,2)*CBN(LL,2,M)+CSERT(
     &          K,NSID,M)  
            NMNLO=N-NLON(LL,K,M)  
            IF(NMNLO.GE.NTSCRN(LL))THEN  
              CON(L,K)=CBT  
            ELSE  
              CON(L,K)=CLON(LL,K,M)  
     &            +(CBT-CLON(LL,K,M))*FLOAT(NMNLO)/FLOAT(NTSCRN(LL))  
            ENDIF  
          ENDIF  
        ENDDO  
      ENDDO  

C  
C **  ANTI-DIFFUSIVE ADVECTIVE FLUX CALCULATION  
C  
      IF(ISADAC(MVAR).EQ.0) GOTO 2000  
      IF(ISCDCA(MVAR).EQ.1) GOTO 2000
      
      IF(ISFCT(MVAR).GT.0)THEN
        ! *** DU & DV are used as a temporary array in this sub
        DO K=1,KC  
          DU(1,K)=0.  
          DV(1,K)=0.  
          DU(LC,K)=0. 
          DV(LC,K)=0.  
        ENDDO  
      ENDIF
C  
C **  STANDARD ANTI-DIFFUSIVE ADVECTIVE FLUX CALCULATION  
C  

      ! *** PMC BEGIN BLOCK
      ! *** GET ONLY POSITIVE CONCENTRATIONS
!      DO L=2,LA
!        DO K=1,KC
!          POS(L,K)=MAX(CON(L,K),0.)
!        ENDDO
!      ENDDO
      POS(2:LA,1:KC)=MAX(CON(2:LA,1:KC),0.0)
      ! *** PMC END BLOCK

      IF(IDRYTBP.EQ.0)THEN  
        DO K=1,KC  
          UUU(LC,K)=0.0  
          VVV(LC,K)=0.0  
          UUU(1,K)=0.0  
          VVV(1,K)=0.0  
        ENDDO  
        DO L=1,LC  
          WWW(L,0)=0.0  
          WWW(L,KC)=0.0  
        ENDDO  
C
!$         LST = omp_get_wtime()
!$OMP PARALLEL SHARED(DEFAULT) PRIVATE(UTERM,VTERM,UHU,VHV,SSCORUE,SSCORUW,SSCORVN,
!$OMP& SSCORVS,SSCORU,SSCORV,LW,LE,LN,LS,LNW,LSE,RDZIC,RDZIG,AUHU,AVHV,AWW,WTERM,
!$OMP& SSCORWA,SSCORWB,SSCORW,WW)
        DO K=1,KC  
          RDZIG=DZIG(K)  
!$OMP DO SCHEDULE(STATIC,CHUNKSIZE) 
          DO L=2,LA  
            LS=LSC(L)
            LW=LWEST(L)
            UUU(L,K)=U2(L,K)*(POS(L,K)-POS(LW,K))*DXIU(L)  
            VVV(L,K)=V2(L,K)*(POS(L,K)-POS(LS,K))*DYIV(L)  
 !           WWW(L,K)=W2(L,K)*(POS(L,K+1)-POS(L,K))*HPI(L)*RDZIG  
          ENDDO  
!$OMP END DO
          WWW(2:LA,K)=W2(2:LA,K)*(POS(2:LA,K+1)-POS(2:LA,K))*HPI(2:LA)*RDZIG
        ENDDO 
        DO K=1,KC  
          RDZIC=DZIC(K) 
!$OMP DO SCHEDULE(STATIC,CHUNKSIZE)     !This loop has dependencies on UUU,VVV above 
          DO L=2,LA  
            LN=LNC(L)  
            LS=LSC(L)  
            LW=LWEST(L)
            LE=LEAST(L)
            LNW=LNWC(L)  
            LSE=LSEC(L)  
            AUHU=ABS(UHDY2(L,K))  
            AVHV=ABS(VHDX2(L,K))  
            UTERM=AUHU*(POS(L,K)-POS(LW,K))  
            VTERM=AVHV*(POS(L,K)-POS(LS,K))  
            IF(ISADAC(MVAR).GE.2)THEN  
              SSCORUE=DELTA*RDZIC*DXYIP(L  )*HPI(L  )*(FQCPAD(L  ,K)  
     &            -QSUMPAD(L  ,K)*CON(L  ,K))  
              SSCORUW=DELTA*RDZIC*DXYIP(LW)*HPI(LW)*(FQCPAD(LW,K)  
     &            -QSUMPAD(LW,K)*CON(LW,K))  
              SSCORVN=DELTA*RDZIC*DXYIP(L  )*HPI(L  )*(FQCPAD(L  ,K)  
     &            -QSUMPAD(L  ,K)*CON(L  ,K))  
              SSCORVS=DELTA*RDZIC*DXYIP(LS )*HPI(LS )*(FQCPAD(LS ,K)  
     &            -QSUMPAD(LS ,K)*CON(LS ,K))  
              SSCORU=MAX(UHDY2(L,K),0.0)*SSCORUW+MIN(UHDY2(L,K),0.0)
     &            *SSCORUE  
              SSCORV=MAX(VHDX2(L,K),0.0)*SSCORVS+MIN(VHDX2(L,K),0.0)
     &            *SSCORVN  
              UTERM=UTERM+SSCORU  
              VTERM=VTERM+SSCORV  
            ENDIF  
            IF(UHDY2(L,K).GE.0.0)THEN  
              UTERM=UTERM-0.5*DELTA*UHDY2(L,K)*  
     &            (VVV(LNW,K)+VVV(LW,K)+WWW(LW,K)+WWW(LW,K-1)  
     &            +UUU(L,K)+UUU(LW,K))  
            ELSE  
              UTERM=UTERM-0.5*DELTA*UHDY2(L,K)*  
     &            (VVV(LN,K)+VVV(L,K)+WWW(L,K)+WWW(L,K-1)  
     &            +UUU(L,K)+UUU(LE,K))  
            ENDIF  
            IF(VHDX2(L,K).GE.0.0)THEN  
              VTERM=VTERM-0.5*DELTA*VHDX2(L,K)*  
     &            (UUU(LS,K)+UUU(LSE,K)+WWW(LS,K)+WWW(LS,K-1)  
     &            +VVV(LS,K)+VVV(L,K))  
            ELSE  
              VTERM=VTERM-0.5*DELTA*VHDX2(L,K)*  
     &            (UUU(L,K)+UUU(LE,K)+WWW(L,K)+WWW(L,K-1)  
     &            +VVV(LN,K)+VVV(L,K))  
            ENDIF  
            IF(ISFCT(MVAR).GE.2)THEN  
              FUHU(L,K)=0.5*UTERM  
              FVHU(L,K)=0.5*VTERM  
              IF(ISFCT(MVAR).EQ.3)THEN  
                FUHU(L,K)=UTERM  
                FVHU(L,K)=VTERM  
              ENDIF  
            ELSE  
              UHU=UTERM/(POS(L,K)+POS(LW,K)+BSMALL)  
              VHV=VTERM/(POS(L,K)+POS(LS,K)+BSMALL)  
              FUHU(L,K)=MAX(UHU,0.)*POS(LW,K)  
     &            +MIN(UHU,0.)*POS(L,K)  
              FVHU(L,K)=MAX(VHV,0.)*POS(LS,K)  
     &            +MIN(VHV,0.)*POS(L,K)  
            ENDIF  
          ENDDO  
!$OMP END DO NOWAIT
        ENDDO  
        DO K=1,KS  
!$OMP DO SCHEDULE(STATIC,CHUNKSIZE)
          DO L=2,LA  
            LN=LNC(L)
            LE=LEAST(L)
            AWW=ABS(W2(L,K))  
            WTERM=AWW*(POS(L,K+1)-POS(L,K))  
            IF(ISADAC(MVAR).GE.2)THEN  
              SSCORWA=DELTA*DZIG(K+1)*HPI(L)*DXYIP(L)  
     &            *(FQCPAD(L,K+1)-QSUMPAD(L,K+1)*POS(L,K+1))  
              SSCORWB=DELTA*DZIG(K)*HPI(L)*DXYIP(L)  
     &            *(FQCPAD(L,K  )-QSUMPAD(L,K  )*POS(L,K  ))  
              SSCORW=MAX(W2(L,K),0.0)*SSCORWB+MIN(W2(L,K),0.0)*SSCORWA  
              WTERM=WTERM+SSCORW  
            ENDIF  
            IF(W2(L,K).GE.0.0)THEN  
              WTERM=WTERM-0.5*DELTA*W2(L,K)*  
     &            (UUU(L,K)+UUU(LE,K)+VVV(L,K)+VVV(LN,K)  
     &            +WWW(L,K)+WWW(L,K-1))  
            ELSE  
              WTERM=WTERM-0.5*DELTA*W2(L,K)*  
     &            (UUU(LE,K+1)+UUU(L,K+1)+VVV(LN,K+1)+VVV(L,K+1)  
     &            +WWW(L,K)+WWW(L,K+1))  
            ENDIF  
            IF(ISFCT(MVAR).GE.2)THEN  
              FWU(L,K)=0.5*WTERM  
              IF(ISFCT(MVAR).EQ.3)THEN  
                FWU(L,K)=WTERM  
              ENDIF  
            ELSE  
              WW=WTERM/(POS(L,K+1)+POS(L,K)+BSMALL)  
              FWU(L,K)=MAX(WW,0.)*POS(L,K)  
     &            +MIN(WW,0.)*POS(L,K+1)  
            ENDIF  
          ENDDO  
        ENDDO  
!$OMP END PARALLEL

C ** SET ANTIDIFFUSIVE FLUXES TO ZERO FOR SOURCE CELLS
C  
        IF(ISADAC(MVAR).EQ.1)THEN  
          ! *** ANTIDIFFUSION TURNED OFF FOR SOURCE CELLS  
          DO K=1,KC  
            DO L=2,LA  
              IF(QSUMPAD(L,K).GT.0.0)THEN  
                LN=LNC(L)
                LE=LEAST(L)
                FUHU(L  ,K)=0.  
                FUHU(LE,K)=0.  
                FVHU(L  ,K)=0.  
                FVHU(LN ,K)=0.  
                FWU(L,K  )=0.  
                FWU(L,K-1)=0.  
              ENDIF  
            ENDDO  
          ENDDO  
        ENDIF  
C  
C ** SET ANTIDIFFUSIVE FLUXES TO ZERO FOR OPEN BOUNDARY CELLS  
C  
        DO K=1,KC  
          DO LL=1,NCBS  
            L=LCBS(LL)  
            LN=LNC(L)  
            FVHU(LN,K)=0.0  
          ENDDO  
          DO LL=1,NCBW  
            L=LCBW(LL)
            LE=LEAST(L)
            FUHU(LE,K)=0.0  
          ENDDO  
          DO LL=1,NCBE  
            L=LCBE(LL)  
            FUHU(L,K)=0.0  
          ENDDO  
          DO LL=1,NCBN  
            L=LCBN(LL)  
            FVHU(L,K)=0.0  
          ENDDO  
        ENDDO  
C  
C **  CALCULATE AND APPLY FLUX CORRECTED TRANSPORT LIMITERS  
C  
        IF(ISFCT(MVAR).EQ.0) GOTO 1100  
C  
C **  DETERMINE MAX AND MIN CONCENTRATIONS  
C  
!        DO K=1,KC  
!          DO L=1,LC  
!            CONTMX(L,K)=0.0  
!            CONTMN(L,K)=0.0  
!          ENDDO  
!        ENDDO
!        DO K=1,KC  
!          DO L=2,LA  
!            CONTMX(L,K)=MAX(CON(L,K),CON2(L,K))  
!            CONTMN(L,K)=MIN(CON(L,K),CON2(L,K))  
!          ENDDO  
!        ENDDO
        CONTMX(2:LA,1:KC)=MAX(CON(2:LA,1:KC),CON2(2:LA,1:KC))
        CONTMN(2:LA,1:KC)=MIN(CON(2:LA,1:KC),CON2(2:LA,1:KC))
!        DO L=2,LA  
!          CMAX(L,1)=MAX(CONTMX(L,1),CONTMX(L,2))  
!          CMAX(L,KC)=MAX(CONTMX(L,KS),CONTMX(L,KC))  
!          CMIN(L,1)=MIN(CONTMN(L,1),CONTMN(L,2))  
!          CMIN(L,KC)=MIN(CONTMN(L,KS),CONTMN(L,KC))  
!        ENDDO
        CMAX(2:LA,1)=MAX(CONTMX(2:LA,1),CONTMX(2:LA,2))  
        CMAX(2:LA,KC)=MAX(CONTMX(2:LA,KS),CONTMX(2:LA,KC))  
        CMIN(2:LA,1)=MIN(CONTMN(2:LA,1),CONTMN(2:LA,2))  
        CMIN(2:LA,KC)=MIN(CONTMN(2:LA,KS),CONTMN(2:LA,KC)) 
        DO K=2,KS  
!          DO L=2,LA  
!            CMAXT=MAX(CONTMX(L,K-1),CONTMX(L,K+1))  
!            CMAX(L,K)=MAX(CONTMX(L,K),CMAXT)  
!            CMINT=MIN(CONTMN(L,K-1),CONTMN(L,K+1))  
!            CMIN(L,K)=MIN(CONTMN(L,K),CMINT)  
!          ENDDO
          CMAX(2:LA,K)=MAX(CONTMX(2:LA,K-1),CONTMX(2:LA,K),CONTMX(2:LA,K+1))
          CMIN(2:LA,K)=MIN(CONTMN(2:LA,K-1),CONTMN(2:LA,K),CONTMN(2:LA,K+1))
        ENDDO  
!$OMP PARALLEL SHARED(DEFAULT) PRIVATE(CMAXT,CMINT,LS,LN,LW,LE,
!$OMP& CWMAX,CEMAX,CSMAX,CNMAX,CWMIN,CEMIN,CSMIN,CNMIN,RDZIC) 
        DO K=1,KC  
!$OMP DO schedule(static,chunksize)
          DO L=2,LA  
            LS=LSC(L)  
            LN=LNC(L)
            LE=LEAST(L)
            CWMAX=SUB(L)*CONTMX(LWEST(L),K)  
            CEMAX=SUB(LE)*CONTMX(LE,K)  
            CSMAX=SVB(L)*CONTMX(LS,K)  
            CNMAX=SVB(LN)*CONTMX(LN,K)  
            CMAXT=MAX(CNMAX,CEMAX)  
            CMAXT=MAX(CMAXT,CSMAX)  
            CMAXT=MAX(CMAXT,CWMAX)  
            CMAX(L,K)=MAX(CMAX(L,K),CMAXT)  
            CWMIN=SUB(L)*CONTMN(LWEST(L),K)+1.E+6*(1.-SUB(L))  
            CEMIN=SUB(LE)*CONTMN(LE,K)+1.E+6*(1.-SUB(LE))  
            CSMIN=SVB(L)*CONTMN(LS,K)+1.E+6*(1.-SVB(L))  
            CNMIN=SVB(LN)*CONTMN(LN,K)+1.E+6*(1.-SVB(LN))  
            CMINT=MIN(CNMIN,CEMIN)  
            CMINT=MIN(CMINT,CSMIN)  
            CMINT=MIN(CMINT,CWMIN)  
            CMIN(L,K)=MIN(CMIN(L,K),CMINT)  
C  
C **  SEPARATE POSITIVE AND NEGATIVE FLUXES PUTTING NEGATIVE FLUXES  
C **  INTO FUHV, FVHV, AND FWV  
C  
            FUHV(L,K)=MIN(FUHU(L,K),0.)  
            FUHU(L,K)=MAX(FUHU(L,K),0.)  
            FVHV(L,K)=MIN(FVHU(L,K),0.)  
            FVHU(L,K)=MAX(FVHU(L,K),0.)  

            FWV(L,K)=MIN(FWU(L,K),0.)  
            FWU(L,K)=MAX(FWU(L,K),0.)  
          ENDDO  
!$OMP END DO
        ENDDO  
C  
C **  CALCULATE INFLUX AND OUTFLUX IN CONCENTRATION UNITS AND LOAD  
C **  INTO DU AND DV, THEN ADJUCT VALUES AT BOUNDARIES  
C  
        DO K=1,KC  
          RDZIC=DZIC(K)  
!$OMP DO SCHEDULE(STATIC,CHUNKSIZE)
          DO L=2,LA  
            LN=LNC(L)
            LE=LEAST(L)
            DU(L,K)=DELT*(DXYIP(L)*(FUHU(L,K)-FUHV(LE,K)  
     &          +FVHU(L,K)-FVHV(LN,K))  
     &          +RDZIC*(FWU(L,K-1)-FWV(L,K)) )*HPI(L)  
            DV(L,K)=DELT*(DXYIP(L)*(FUHU(LE,K)-FUHV(L,K)  
     &          +FVHU(LN,K)-FVHV(L,K))  
     &          +RDZIC*(FWU(L,K)-FWV(L,K-1)) )*HPI(L)  

C **  CALCULATE BETA COEFFICIENTS WITH BETAUP AND BETADOWN IN DU AND DV  
C  
          IF(DU(L,K).GT.0.)DU(L,K)=MIN(1.0,(CMAX(L,K)-POS(L,K))/(DU(L,K)+BSMALL))
            !DU(L,K)=MIN(DU(L,K),1.)
          IF(DV(L,K).GT.0.)DV(L,K)=MIN(1.0,(CON(L,K)-CMIN(L,K))/(DV(L,K)+BSMALL))
            !DV(L,K)=MIN(DV(L,K),1.)  
          ENDDO  
        ENDDO  
!$OMP END PARALLEL
        DO K=1,KC
          DO IOBC=1,NBCSOP  
            L=LOBCS(IOBC)  
            DU(L,K)=0.  
            DV(L,K)=0.  
          ENDDO  
        END DO
        DO K=1,KC  
          DO LL=1,NCBS  
            L=LCBS(LL)  
            LN=LNC(L)  
            DU(LN,K)=0.  
            DV(LN,K)=0.  
          ENDDO  
          DO LL=1,NCBW  
            L=LCBW(LL)
            LE=LEAST(L)
            DU(LE,K)=0.  
            DV(LE,K)=0.  
          ENDDO  
          DO LL=1,NCBE  
            L=LCBE(LL)  
            DU(LWEST(L),K)=0.  
            DV(LWEST(L),K)=0.  
          ENDDO  
          DO LL=1,NCBN  
            L=LCBN(LL)  
            LS=LSC(L)  
            DU(LS,K)=0.  
            DV(LS,K)=0.  
          ENDDO  
        ENDDO  
C  
C  
C **  LIMIT FLUXES  
C  

!$OMP PARALLEL SHARED(DEFAULT) PRIVATE(LS,LW) 
        DO K=1,KC
!$OMP DO SCHEDULE(STATIC,CHUNKSIZE)  
          DO L=2,LA  
            LS=LSC(L)
            LW=LWEST(L)  
            FUHU(L,K)=MIN(DV(LW,K),DU(L,K))*FUHU(L,K)  
     &          +MIN(DU(LW,K),DV(L,K))*FUHV(L,K)  
            FVHU(L,K)=MIN(DV(LS,K),DU(L,K))*FVHU(L,K)  
     &          +MIN(DU(LS,K),DV(L,K))*FVHV(L,K)  
          ENDDO  
        ENDDO  
!$OMP END PARALLEL
        DO K=1,KS  
          DO L=2,LA  
            FWU(L,K)=MIN(DV(L,K),DU(L,K+1))*FWU(L,K)  
     &          +MIN(DU(L,K),DV(L,K+1))*FWV(L,K)  
          ENDDO  
        ENDDO  
C  
C **  ANTI-DIFFUSIVE ADVECTION CALCULATION  
C  
 1100   CONTINUE  
C    
!$OMP PARALLEL SHARED(DEFAULT) PRIVATE(RDZIC) 
        DO K=1,KC
          RDZIC=DZIC(K)  
!$OMP DO SCHEDULE(STATIC,CHUNKSIZE)  
          DO L=2,LA
            LE=LEAST(L)
            LN=LNC(L)
            CH(L,K)=CON(L,K)*HP(L)  
     &          +DELT*( (FUHU(L,K)-FUHU(LE,K)  
     &          +FVHU(L,K)-FVHU(LN,K))*DXYIP(L)  
     &          +(FWU(L,K-1)-FWU(L,K))*RDZIC )  
            CON(L,K)=SCB(L)*CH(L,K)*HPI(L)+(1.-SCB(L))*CON(L,K)  
          ENDDO  
        ENDDO  
!$OMP END PARALLEL
C  
C **  ADD REMAINING SEDIMENT SETTLING AND FLUX  
C  
      ENDIF  
C  
C **  ANTI-DIFFUSIVE ADVECTIVE FLUX CALCULATION WITH DRY BYPASS  
C  
      IF(IDRYTBP.GT.0)THEN     ! (i.e. if ISDRY < 0) 
        ! *** DSLLC BEGIN 
        DO L=1,LC  
          WWW(L,0)=0.0 
          WWW(L,KC)=0.0 
        ENDDO  
        DO K=1,KC  
          UUU(LC,K)=0.0  
          VVV(LC,K)=0.0  
          UUU(1,K)=0.0  
          VVV(1,K)=0.0  
        ENDDO

        DO K=1,KC  
          DO L=2,LA  
            IF(LMASKDRY(L))THEN  
              LS=LSC(L)
              LW=LWEST(L)
              UUU(L,K)=U2(L,K)*(POS(L,K)-POS(LW,K))*DXIU(L)  
              VVV(L,K)=V2(L,K)*(POS(L,K)-POS(LS,K))*DYIV(L)
            ELSE  
              UUU(L,K)=0.  
              VVV(L,K)=0.  
            ENDIF
          ENDDO  
        ENDDO  

        DO K=1,KS  
          RDZIG=DZIG(K)  
          DO L=2,LA  
            IF(LMASKDRY(L))THEN  
              WWW(L,K)=W2(L,K)*(POS(L,K+1)-POS(L,K))*HPI(L)*RDZIG  
            ELSE
              WWW(L,K)=0.0
            ENDIF
          ENDDO  
        ENDDO  
C
        DO K=1,KC  
          RDZIC=DZIC(K)  
          DO L=2,LA  
            IF(LMASKDRY(L))THEN  
              LN=LNC(L)  
              LS=LSC(L)  
              LNW=LNWC(L)  
              LSE=LSEC(L)
              LW=LWEST(L)
              AUHU=ABS(UHDY2(L,K))  
              AVHV=ABS(VHDX2(L,K))  
              UTERM=AUHU*(POS(L,K)-POS(LW,K))
              VTERM=AVHV*(POS(L,K)-POS(LS,K)) 
              IF(ISADAC(MVAR).GE.2)THEN  
                SSCORUE=DELTA*RDZIC*DXYIP(L  )*HPI(L  )*(FQCPAD(L  ,K)  
     &            -QSUMPAD(L  ,K)*CON(L  ,K))  
                SSCORUW=DELTA*RDZIC*DXYIP(LW)*HPI(LW)*(FQCPAD(LW,K)  
     &            -QSUMPAD(LW,K)*CON(LW,K))  
                SSCORVN=DELTA*RDZIC*DXYIP(L  )*HPI(L  )*(FQCPAD(L  ,K)  
     &            -QSUMPAD(L  ,K)*CON(L  ,K))  
                SSCORVS=DELTA*RDZIC*DXYIP(LS )*HPI(LS )*(FQCPAD(LS ,K)  
     &            -QSUMPAD(LS ,K)*CON(LS ,K))  
                SSCORU=MAX(UHDY2(L,K),0.0)*SSCORUW+MIN(UHDY2(L,K),0.0)
     &            *SSCORUE  
                SSCORV=MAX(VHDX2(L,K),0.0)*SSCORVS+MIN(VHDX2(L,K),0.0)
     &            *SSCORVN  
                UTERM=UTERM+SSCORU  
                VTERM=VTERM+SSCORV  
              ENDIF  
              IF(UHDY2(L,K).GE.0.0)THEN  
                UTERM=UTERM-0.5*DELTA*UHDY2(L,K)*  
     &            (VVV(LNW,K)+VVV(LW,K)+WWW(LW,K)+WWW(LW,K-1)  
     &            +UUU(L,K)+UUU(LW,K))  
              ELSE  
                UTERM=UTERM-0.5*DELTA*UHDY2(L,K)*  
     &            (VVV(LN,K)+VVV(L,K)+WWW(L,K)+WWW(L,K-1)  
     &            +UUU(L,K)+UUU(LE,K))  
              ENDIF  
              IF(VHDX2(L,K).GE.0.0)THEN  
                VTERM=VTERM-0.5*DELTA*VHDX2(L,K)*  
     &            (UUU(LS,K)+UUU(LSE,K)+WWW(LS,K)+WWW(LS,K-1)  
     &            +VVV(LS,K)+VVV(L,K))  
              ELSE  
                VTERM=VTERM-0.5*DELTA*VHDX2(L,K)*  
     &            (UUU(L,K)+UUU(LE,K)+WWW(L,K)+WWW(L,K-1)  
     &            +VVV(LN,K)+VVV(L,K))  
              ENDIF  
              IF(ISFCT(MVAR).GE.2)THEN  
                FUHU(L,K)=0.5*UTERM  
                FVHU(L,K)=0.5*VTERM  
                IF(ISFCT(MVAR).EQ.3)THEN  
                  FUHU(L,K)=UTERM  
                  FVHU(L,K)=VTERM  
                ENDIF  
              ELSE  
                UHU=UTERM/(POS(L,K)+POS(LW,K)+BSMALL)  
                VHV=VTERM/(POS(L,K)+POS(LS,K)+BSMALL)  
                FUHU(L,K)=MAX(UHU,0.)*POS(LWE,K)  
     &            +MIN(UHU,0.)*POS(L,K)  
                FVHU(L,K)=MAX(VHV,0.)*POS(LS,K)  
     &            +MIN(VHV,0.)*POS(L,K)  
              ENDIF  
            ELSE
              FUHU(L,K)=0.  
              FVHU(L,K)=0.  
            ENDIF
          ENDDO  
        ENDDO  
C
        DO K=1,KS  
          DO L=2,LA  
            IF(LMASKDRY(L))THEN  
              LN=LNC(L)
              LE=LEAST(L)
              AWW=ABS(W2(L,K))  
              WTERM=AWW*(POS(L,K+1)-POS(L,K))  
              IF(ISADAC(MVAR).GE.2)THEN  
                SSCORWA=DELTA*DZIG(K+1)*HPI(L)*DXYIP(L)  
     &            *(FQCPAD(L,K+1)-QSUMPAD(L,K+1)*CON(L,K+1))  
                SSCORWB=DELTA*DZIG(K)*HPI(L)*DXYIP(L)  
     &            *(FQCPAD(L,K  )-QSUMPAD(L,K  )*CON(L,K  ))  
                SSCORW=MAX(W2(L,K),0.0)*SSCORWB+MIN(W2(L,K),0.0)*SSCORWA
                WTERM=WTERM+SSCORW  
              ENDIF  
              IF(W2(L,K).GE.0.0)THEN  
                WTERM=WTERM-0.5*DELTA*W2(L,K)*  
     &            (UUU(L,K)+UUU(LE,K)+VVV(L,K)+VVV(LN,K)  
     &            +WWW(L,K)+WWW(L,K-1))  
              ELSE  
                WTERM=WTERM-0.5*DELTA*W2(L,K)*  
     &            (UUU(LE,K+1)+UUU(L,K+1)+VVV(LN,K+1)+VVV(L,K+1)  
     &            +WWW(L,K)+WWW(L,K+1))  
              ENDIF  
              IF(ISFCT(MVAR).GE.2)THEN  
                FWU(L,K)=0.5*WTERM  
                IF(ISFCT(MVAR).EQ.3)THEN  
                  FWU(L,K)=WTERM  
                ENDIF  
              ELSE  
                WW=WTERM/(POS(L,K+1)+POS(L,K)+BSMALL)  
                FWU(L,K)=MAX(WW,0.)*POS(L,K)  
     &            +MIN(WW,0.)*POS(L,K+1)  
              ENDIF  
            ELSE
              FWU(L,K)=0.  
            ENDIF
          ENDDO  
        
        ENDDO  
C  
C ** SET ANTIDIFFUSIVE FLUXES TO ZERO FOR SOURCE CELLS
C  
        if(n.gt.2400.AND..FALSE.)then   ! PMC PMC
          L = 6795
          k = 1
          write(*,9999)n,con(LWEST(L),k),con(l,k),con(LEAST(L),k),
     1                 fuhu(LWEST(L),k),fuhu(l,k),fuhu(LEAST(L),k),
     1                 UHDY2(LWEST(L),k),UHDY2(l,k),UHDY2(LEAST(L),k),
     1                 VHDX2(LWEST(L),k),VHDX2(l,k),VHDX2(LEAST(L),k)
    ! 1                 fwu(LWEST(L),k),fwu(l,k),fwu(LEAST(L),k)
 9999 format(i5,6f12.2/5x,6f12.2)
        endif

        IF(ISADAC(MVAR).EQ.1)THEN  
          DO K=1,KC  
            DO L=2,LA
              IF(LMASKDRY(L))THEN  
                IF(ABS(QSUM(L,K)).GT.1.E-12)THEN  
                  LN=LNC(L)
                  LE=LEAST(L)
                  FUHU(L  ,K)=0.  
                  FUHU(LE,K)=0.  
                  FVHU(L  ,K)=0.  
                  FVHU(LN ,K)=0.  
                  FWU(L,K  )=0.  
                  FWU(L,K-1)=0.  
                ENDIF  
              ENDIF  
            ENDDO  
          ENDDO  
        ENDIF
C  
C ** SET ANTIDIFFUSIVE FLUXES TO ZERO FOR OPEN BOUNDARY CELLS  
C  
        DO K=1,KC  
          DO LL=1,NCBS  
            L=LCBS(LL)  
            LN=LNC(L)  
            FVHU(LN,K)=0.0  
          ENDDO  
          DO LL=1,NCBW  
            L=LCBW(LL)
            LE=LEAST(L)
            FUHU(LE,K)=0.0  
          ENDDO  
          DO LL=1,NCBE  
            L=LCBE(LL)  
            FUHU(L,K)=0.0  
          ENDDO  
          DO LL=1,NCBN  
            L=LCBN(LL)  
            FVHU(L,K)=0.0  
          ENDDO  
        ENDDO  
C  
C **  CALCULATE AND APPLY FLUX CORRECTED TRANSPORT LIMITERS  
C  
        IF(ISFCT(MVAR).EQ.0) GOTO 1101  
C  
C **  DETERMINE MAX AND MIN CONCENTRATIONS  
C  
        DO K=1,KC  
          DO L=2,LA  
            CMIN(L,K)=0.  
            CMAX(L,K)=0.  
          ENDDO  
        ENDDO  
        DO K=1,KC  
          DO L=2,LA  
            IF(LMASKDRY(L))THEN  
              CONTMX(L,K)=MAX(CON(L,K),CON2(L,K))  
              CONTMN(L,K)=MIN(CON(L,K),CON2(L,K))  
            ENDIF  
          ENDDO  
        ENDDO  
        DO L=2,LA  
          IF(LMASKDRY(L))THEN  
            CMAX(L,1)=MAX(CONTMX(L,1),CONTMX(L,2))  
            CMAX(L,KC)=MAX(CONTMX(L,KS),CONTMX(L,KC))  
            CMIN(L,1)=MIN(CONTMN(L,1),CONTMN(L,2))  
            CMIN(L,KC)=MIN(CONTMN(L,KS),CONTMN(L,KC))  
          ENDIF  
        ENDDO  
        DO K=2,KS  
          DO L=2,LA  
            IF(LMASKDRY(L))THEN  
              CMAXT=MAX(CONTMX(L,K-1),CONTMX(L,K+1))  
              CMAX(L,K)=MAX(CONTMX(L,K),CMAXT)  
              CMINT=MIN(CONTMN(L,K-1),CONTMN(L,K+1))  
              CMIN(L,K)=MIN(CONTMN(L,K),CMINT)  
            ENDIF  
          ENDDO  
        ENDDO  
        DO K=1,KC  
          DO L=2,LA  
            IF(LMASKDRY(L))THEN  
              LS=LSC(L)  
              LN=LNC(L)
              LE=LEAST(L)
              CWMAX=SUB(L)*CONTMX(LWEST(L),K)  
              CEMAX=SUB(LE)*CONTMX(LE,K)  
              CSMAX=SVB(L)*CONTMX(LS,K)  
              CNMAX=SVB(LN)*CONTMX(LN,K)  
              CMAXT=MAX(CNMAX,CEMAX)  
              CMAXT=MAX(CMAXT,CSMAX)  
              CMAXT=MAX(CMAXT,CWMAX)  
              CMAX(L,K)=MAX(CMAX(L,K),CMAXT)  
              CWMIN=SUB(L)*CONTMN(LWEST(L),K)+1.E+6*(1.-SUB(L))  
              CEMIN=SUB(LE)*CONTMN(LE,K)+1.E+6*(1.-SUB(LE))  
              CSMIN=SVB(L)*CONTMN(LS,K)+1.E+6*(1.-SVB(L))  
              CNMIN=SVB(LN)*CONTMN(LN,K)+1.E+6*(1.-SVB(LN))  
              CMINT=MIN(CNMIN,CEMIN)  
              CMINT=MIN(CMINT,CSMIN)  
              CMINT=MIN(CMINT,CWMIN)  
              CMIN(L,K)=MIN(CMIN(L,K),CMINT)  
            ENDIF  
          ENDDO  
        ENDDO  
C  
C **  SEPARATE POSITIVE AND NEGATIVE FLUXES PUTTING NEGATIVE FLUXES  
C **  INTO FUHV, FVHV, AND FWV  
C  
        DO K=1,KC  
          DO L=2,LA  
            IF(LMASKDRY(L))THEN  
              FUHV(L,K)=MIN(FUHU(L,K),0.)  
              FUHU(L,K)=MAX(FUHU(L,K),0.)  
              FVHV(L,K)=MIN(FVHU(L,K),0.)  
              FVHU(L,K)=MAX(FVHU(L,K),0.)  
            ELSE
              FUHV(L,K)=0.  
              FVHV(L,K)=0.  
            ENDIF  
          ENDDO  
        ENDDO  
        DO K=1,KS  
          DO L=2,LA  
            IF(LMASKDRY(L))THEN  
              FWV(L,K)=MIN(FWU(L,K),0.)  
              FWU(L,K)=MAX(FWU(L,K),0.)  
            ELSE
              FWV(L,K)=0.  
            ENDIF  
          ENDDO  
        ENDDO  
C  
C **  CALCULATE INFLUX AND OUTFLUX IN CONCENTRATION UNITS AND LOAD  
C **  INTO DU AND DV, THEN ADJUCT VALUES AT BOUNDARIES  
C  
        DO K=1,KC  
          RDZIC=DZIC(K)  
          DO L=2,LA  
            IF(LMASKDRY(L))THEN  
              LN=LNC(L)
              LE=LEAST(L)
              DU(L,K)=DELT*SCB(L)*( DXYIP(L)*(FUHU(L,K)-FUHV(LE,K)  
     &            +FVHU(L,K)-FVHV(LN,K))  
     &            +RDZIC*(FWU(L,K-1)-FWV(L,K)) )*HPI(L)  
              DV(L,K)=DELT*SCB(L)*( DXYIP(L)*(FUHU(LE,K)-FUHV(L,K)  
     &            +FVHU(LN,K)-FVHV(L,K))  
     &            +RDZIC*(FWU(L,K)-FWV(L,K-1)) )*HPI(L)  
            ELSE
              DU(L,K)=0.  
              DV(L,K)=0.  
            ENDIF  
          ENDDO  
        ENDDO  
        DO K=1,KC  
          DO LL=1,NCBS  
            L=LCBS(LL)  
            LN=LNC(L)  
            DU(LN,K)=0.  
            DV(LN,K)=0.  
          ENDDO  
          DO LL=1,NCBW  
            L=LCBW(LL)
            LE=LEAST(L)
            DU(LE,K)=0.  
            DV(LE,K)=0.  
          ENDDO  
          DO LL=1,NCBE  
            L=LCBE(LL)  
            DU(LWEST(L),K)=0.  
            DV(LWEST(L),K)=0.  
          ENDDO  
          DO LL=1,NCBN  
            L=LCBN(LL)  
            LS=LSC(L)  
            DU(LS,K)=0.  
            DV(LS,K)=0.  
          ENDDO  
        ENDDO  
C  
C **  CALCULATE BETA COEFFICIENTS WITH BETAUP AND BETADOWN IN DU AND DV  
C  
        DO K=1,KC  
          DO L=2,LA  
            IF(LMASKDRY(L))THEN  
              IF(DU(L,K).GT.0.)DU(L,K)=(CMAX(L,K)-POS(L,K))/(DU(L,K)
     &            +BSMALL)  
              DU(L,K)=MIN(DU(L,K),1.)  
              IF(DV(L,K).GT.0.)DV(L,K)=(CON(L,K)-CMIN(L,K))/(DV(L,K)
     &            +BSMALL)  
              DV(L,K)=MIN(DV(L,K),1.)  
            ENDIF  
          ENDDO  
        ENDDO  
C  
C **  LIMIT FLUXES  
C  
        DO K=1,KC  
          DO L=2,LA  
            IF(LMASKDRY(L))THEN  
              LS=LSC(L)  
              FUHU(L,K)=MIN(DV(LWEST(L),K),DU(L,K))*FUHU(L,K)  
     &            +MIN(DU(LWEST(L),K),DV(L,K))*FUHV(L,K)  
              FVHU(L,K)=MIN(DV(LS,K),DU(L,K))*FVHU(L,K)  
     &            +MIN(DU(LS,K),DV(L,K))*FVHV(L,K)  
            ENDIF  
          ENDDO  
        ENDDO  
        DO K=1,KS  
          DO L=2,LA  
            IF(LMASKDRY(L))THEN  
              FWU(L,K)=MIN(DV(L,K),DU(L,K+1))*FWU(L,K)  
     &            +MIN(DU(L,K),DV(L,K+1))*FWV(L,K)  
            ENDIF  
          ENDDO  
        ENDDO  
C  
C **  END OF ANTI-DIFFUSIVE ADVECTION CALCULATION
C  
 1101   CONTINUE  
C  
        DO K=1,KC  
          RDZIC=DZIC(K)  
          DO L=2,LA  
            IF(LMASKDRY(L))THEN
              LE=LEAST(L)
              CH(L,K)=CON(L,K)*HP(L)  
     &            +DELT*( (FUHU(L,K)-FUHU(LE,K)  
     &            +FVHU(L,K)-FVHU(LNC(L),K))*DXYIP(L)  
     &            +(FWU(L,K-1)-FWU(L,K))*RDZIC )  
              CON(L,K)=SCB(L)*CH(L,K)*HPI(L)+(1.-SCB(L))*CON(L,K)
            ENDIF  
          ENDDO  
        ENDDO  
C  
C **  ADD REMAINING SEDIMENT SETTLING AND FLUX  
C  
      ENDIF  
C  
C **  DIAGNOSE FCT SCHEME  
C  
      IF(ISFCT(MVAR).EQ.99)THEN  
        WRITE(6,6110)N  
        DO K=1,KC  
          DO L=2,LA  
            CCMAX=SCB(L)*(CON(L,K)-CMAX(L,K))  
            IF(CCMAX.GT.0.)THEN  
              WRITE(6,6111)CON(L,K),CMAX(L,K),IL(L),JL(L),K  
            ENDIF  
            CCMIN=SCB(L)*(CMIN(L,K)-CON(L,K))  
            IF(CCMIN.GT.0.)THEN  
              WRITE(6,6112)CMIN(L,K),CON(L,K),IL(L),JL(L),K  
            ENDIF  
          ENDDO  
        ENDDO  
      ENDIF  
 6110 FORMAT('  FCT DIAGNOSTICS AT N = ',I5)  
 6111 FORMAT('  CON = ',E12.4,3X,'CMAX = ',E12.4,3X,'I,J,K=',(3I10))  
 6112 FORMAT('  CMIN = ',E12.4,3X,'CON = ',E12.4,3X,'I,J,K=',(3I10)) 
 
      ! *** ZERO HEAT FLUXES
 2000 IF(MVAR.EQ.2)THEN        
        ! *** ZERO EVAP/RAINFALL
        DO L=1,LC  
          FQC(L,KC)=0.  
        ENDDO  
        IF(ISADAC(MVAR).GE.2)THEN
          DO L=1,LC  
            FQCPAD(L,KC)=0.  
          ENDDO  
        ENDIF
        IF(ISADAC(MVAR).GT.0)THEN
          DO L=1,LC  
            QSUMPAD(L,KC)=0.  
          ENDDO  
        ENDIF
      ENDIF
      
      RETURN  
      END  
