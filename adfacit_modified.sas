/************************************************************************
*  PROJECT       : CLNP023B1
*  STUDY         : CLNP023B12301
*  RA            : csr_4
*  FILENAME      : adfacit.sas
*  DESCRIPTION   : Create dataset ADFACIT (csr_4 PDS / VLM / METHOD compliant)
*  PLATFORM      : AIX 7.1 (AIX 64) (see SAS log file)
*  SAS VERSION   : 9.4 (see SAS log file)
*  INPUT         : SDTM QS (with SUPPQS), ADaM ADSL, SDTM DS/FACM/SV/TV
*  OUTPUT        : analysis.adfacit
*  MODIFICATIONS : Add dummy visits for MI; Add EST01STP ICE01F IMPREA01 EST02STP ICE02F IMPREA02 per PDS update
*************************************************************************/

proc datasets lib=work kill nolist; quit;

/* GPS environment setup macro */
data _null_;
  if libref('analysis') then call execute('%nrstr(%autorun;)');
run;

/* ------------------------------- */
/* Formats for planned visit names */
/* ------------------------------- */
/* [CHANGE 1] Added 'Day 90' = 204 */
proc format;
  invalue avisitn
    'Baseline' = 99
    'Day 1'    = 201
    'Day 14'   = 202
    'Day 30'   = 203
    'Day 90'   = 204
    'Day 180'  = 205
    'Day 210'  = 206
    'Day 270'  = 207
    'Day 360'  = 299
  ;
quit;

/* 5-point verbal scale to numeric (fallback when QSSTRESN missing) */
proc format;
  invalue facit_val
    "NOT AT ALL"   = 0
    "A LITTLE BIT" = 1
    "SOMEWHAT"     = 2
    "QUITE A BIT"  = 3
    "VERY MUCH"    = 4
  ;
quit;

/* ------------------------------- */
/* Read QS  SUPPQS and pre-derive */
/* ------------------------------- */
%opMergeSupp(inData=derived.qs,
             outData=qs_raw,
             inSuppData=derived.suppqs,
             keepQnam=);

proc sort data=qs_raw nodupkey;
  by usubjid subjid qscat qstest qsscat visit qsdtc qsorres;
run;

/* Keep only FACIT-Fatigue 13 items */
data qs_items;
  set qs_raw(rename=(qstest=param qstestcd=paramcd lg=qslg QSEVAL   = qseval ));
  where qscat = 'FACIT-FATIGUE 13-ITEM V4';

  length avalc $100;
  /* Prefer QSSTRESN; if missing, translate QSORRES text */
  aval  = coalesce(qsstresn, input(upcase(qsorres), facit_val.));
  avalc = strip(upcase(qsorres));

  /* Datetime splits */
  adt = input(scan(qsdtc,1,'T'), yymmdd10.);
  atm = input(scan(qsdtc,2,'T'), time8.);
  if length(qsdtc)=19 then adtm = input(qsdtc, e8601dt.);
  format adt yymmdd10. atm time5.;
run;

/* Map PARAMN from Analysis Parameters (for item-level rows) */
proc sql;
  create table qs_items_m as
  select a.*
       , b.paramcd as paramcd_ 
       , b.paramn
  from qs_items as a
  left join
       (select param, paramcd, paramn
          from rprtdsm.analysis_parameters
         where not missing(paramn)) as b
    on a.param = b.param
  ;
quit;

proc sort data=qs_items_m;
  by usubjid subjid visit adt paramn;
run;

/* ------------------------------- */
/* Join ADSL and ADY/APERIOD base */
/* ------------------------------- */
data qs_items_j;
  merge qs_items_m(in=a)
        analysis.adsl(in=b drop=subjid);
  by usubjid;
  if a;

  /* ADY relative to first dose */
  if adt>=trtsdt> . then ady = adt - trtsdt + 1;
  else if .<adt<trtsdt then ady = adt - trtsdt;

  /* [CHANGE 2a] Added 'Day 90' to planned visit list */
  length avisit $40;
  if visit = 'End of Study' then visit = 'Day 360';
  if visit in ('Day 1','Day 14','Day 30','Day 90','Day 180','Day 210','Day 270','Day 360') then avisit = visit;
  else avisit = ''; /* non-planned set to null */
  avisitn = input(avisit, avisitn.);
run;

/* ------------------------------- */
/* Derive FACIT/FACITEXP/FACITIMP */
/* ------------------------------- */
proc sort data=qs_items_j;
  by studyid usubjid subjid visit visitnum adt atm adtm qslg qseval;
run;


proc transpose data=qs_items_j(where=(not missing(paramcd_)))
               out=qs_wide(drop=_name_);
  by studyid usubjid subjid visit visitnum adt atm adtm qslg qseval;
  var aval;
  id paramcd_;   
run;


/* Compute scores per METHOD:
   - reverse-keyed items to 4 - score where applicable
   - FAT_N = N(non-missing of 13 items)
   - if FAT_N/13  0.5 then prorated totals
   - derived rows: FACIT, FACITEXP, FACITIMP
*/
data facit_der;
  length param $40 paramcd $8 paramtyp $7 avalc $100;
  set qs_wide;

  array ITEM  {13} FAC07001-FAC07013;
  array HI    HI7 HI12;
  array ANa   AN1-AN5;  /* AN1 AN2 AN3 AN4 AN5 */
  array ANb   AN7 AN8 AN12 AN14-AN16;

  do i=1 to 13;
    if ITEM[i] in (8,9) then ITEM[i]=.;
  end;

  if not missing(FAC07001) then HI7  = 4 - FAC07001;
  if not missing(FAC07002) then HI12 = 4 - FAC07002;
  if not missing(FAC07003) then AN1  = 4 - FAC07003;
  if not missing(FAC07004) then AN2  = 4 - FAC07004;
  if not missing(FAC07005) then AN3  = 4 - FAC07005;
  if not missing(FAC07006) then AN4  = 4 - FAC07006;
  if not missing(FAC07007) then AN5  =      FAC07007; 
  if not missing(FAC07008) then AN7  =      FAC07008; 
  if not missing(FAC07009) then AN8  = 4 - FAC07009;
  if not missing(FAC07010) then AN12 = 4 - FAC07010;
  if not missing(FAC07011) then AN14 = 4 - FAC07011;
  if not missing(FAC07012) then AN15 = 4 - FAC07012;
  if not missing(FAC07013) then AN16 = 4 - FAC07013;

  FAT_N = n(of HI7 HI12 AN1-AN5 AN7 AN8 AN12 AN14-AN16);

  if FAT_N/13 > .50 then do;
    aval  = sum(of HI7 HI12 AN1-AN5 AN7 AN8 AN12 AN14-AN16) * 13 / FAT_N;
    avalc = strip(put(aval,best.));
    param='FACIT Fatigue score'; paramcd='FACIT'; paramtyp='DERIVED'; output;

    aval  = sum(of HI7 HI12 AN1 AN2 AN5);
    avalc = strip(put(aval,best.));
    param='FACIT Experience score'; paramcd='FACITEXP'; paramtyp='DERIVED'; output;

    aval  = sum(of AN3 AN4 AN7 AN8 AN12 AN14-AN16);
    avalc = strip(put(aval,best.));
    param='FACIT Impact score'; paramcd='FACITIMP'; paramtyp='DERIVED'; output;
  end;

  keep studyid usubjid subjid visit visitnum adt atm adtm qslg qseval param paramcd paramtyp aval avalc;
run;


/* Map PARAMN for derived rows from Analysis Parameters */
proc sql;
  create table facit_der_m as
  select a.*, b.paramn
  from facit_der as a
  left join
       (select param, paramcd, paramn
          from rprtdsm.analysis_parameters
         where not missing(paramn)) as b
    on a.param = b.param and a.paramcd = b.paramcd
  ;
quit;

/* ------------------------------- */
/* Union items  derived, join ADSL */
/* ------------------------------- */
data adfacit0;
  set qs_items_j(in=i keep=studyid usubjid subjid siteid param paramcd paramn
                        visit visitnum adt atm adtm qslg qseval aval avalc QSSEQ
						   avisit avisitn)
      facit_der_m;
run;

proc sort data=adfacit0; by usubjid paramcd adt atm adtm; run;

data adfacit1;
  merge adfacit0(in=a)
        analysis.adsl(in=b drop=subjid rename=(siteid=siteid_adsl));
  by usubjid;
  if a;

  /* Recompute ADY after union to be safe */
  if adt>=trtsdt>. then ady = adt - trtsdt + 1;
  else if .<adt<trtsdt then ady = adt - trtsdt;

  /* APERIOD per PDS */
  if aperiod = . then do;
    if .< ap01sdt <= adt <= coalesce(ap02sdt, ap01edt) then aperiod = 1;
    else if .< ap02sdt <  adt <= ap02edt                       then aperiod = 2;
  end;
  length aperiodc $30;
  if aperiod=1 then aperiodc='Double-blind';
  else if aperiod=2 then aperiodc='Open-label';

  /* Clean derived vs item-level text */
  if upcase(coalescec(paramtyp,'')) = 'DERIVED' then do;
    qsstat = ''; qsreasnd = ''; qslg=''; qseval='';
  end;

  /* [CHANGE 2b] Added 'Day 90' to planned visit list */
  if missing(avisit) then do;
    length _v $40;
    _v = visit;
    if _v = 'End of Study' then _v = 'Day 360';
    if _v in ('Day 1','Day 14','Day 30','Day 90','Day 180','Day 210','Day 270','Day 360') then do;
      avisit  = _v;
      avisitn = visitnum;
    end;
    else do;
      avisit  = '';
      avisitn = .;
    end;
    drop _v;
  end;

  if missing(siteid) then siteid = siteid_adsl;
  drop siteid_adsl;

  length anl01dsc anl03dsc $100 crit1 crit2 $50;
run;

/* ------------------------------- */
/* Baseline (last non-missing AVAL before/at TRTSDT), duplicated by paramcd */
/* ------------------------------- */
proc sort data=adfacit1; by usubjid paramcd adt atm adtm; run;


/* --- Baseline candidates: last non-missing AVAL with ADT <= TRTSDT --- */
data base_cand;
  set adfacit1;
  where adt <= trtsdt and not missing(aval);
  by usubjid paramcd adt atm adtm;
run;

data base_last;
  set base_cand;
  by usubjid paramcd adt atm adtm;
  if last.paramcd;                 /* last before/at first dose */
  keep usubjid paramcd adt aval;
  rename adt = baseadt
         aval= base;
run;

/* Merge BASE and BASEADT back */
proc sql;
  create table adfacit2 as
  select a.*, b.base, b.baseadt
  from adfacit1 as a
  left join base_last as b
    on a.usubjid=b.usubjid and a.paramcd=b.paramcd
  ;
quit;

/* CHG only for derived params and post-baseline */
data adfacit3;
  set adfacit2;

  /* Mark baseline row: last ADT <= TRTSDT, force AVISIT to Baseline */
  length ablfl $1;
  if not missing(baseadt) and adt = baseadt then do;
    ablfl  = 'Y';
    avisit = 'Baseline';
    avisitn= 99;
  end;

  /* CHG only for derived params and post-baseline records */
  if upcase(coalescec(paramtyp,''))='DERIVED' then do;
    if ablfl ne 'Y' and nmiss(aval, base)=0 then chg = aval - base;
  end;

  /* Criteria flags */
  if not missing(chg) then do;
    if chg >= 5 then do; crit1fl='Y'; crit1='5-point improvement'; end;
    if chg >= 3 then do; crit2fl='Y'; crit2='3-point improvement'; end;
  end;

  /* ANL01FL/ANL03FL for derived params only */
  if upcase(coalescec(paramtyp,''))='DERIVED' and (ablfl='Y' or aval ne .) then do;
    anl01fl='Y';
    anl01dsc='Unique record for each visit';
  end;
  if ablfl='Y' or aperiod=1 then do;
    anl03fl='Y';
    anl03dsc='Record for treatment randomized period analysis';
  end;
run;

/* Re-compute TRTA/TRTP after ABLFL is finalized (per PDS) */
data adfacit3;
  set adfacit3;  /* overwrite */
  if aperiod=1 or ablfl='Y' then do; trta=trt01a; trtan=trt01an; trtp=trt01p; trtpn=trt01pn; end;
  else if aperiod=2                then do; trta=trt02a; trtan=trt02an; trtp=trt02p; trtpn=trt02pn; end;
run;


/* ================================================================= */
/* [CHANGE 3] Create dummy visits for FACIT MI                       */
/* Following ADUPCR pattern: dummy planned visits with planned dates  */
/* ================================================================= */

/* Get subjects with baseline FACIT */
data facit_base_d;
  set adfacit3;
  where paramcd='FACIT' and ablfl='Y' and fasfl='Y';
  keep usubjid param paramcd base;
run;
proc sort data=facit_base_d nodupkey; by usubjid; run;

/* Create dummy visit shell for visits needed by MI */
data dummy_facit;
  set facit_base_d;
  do avisit="Day 14","Day 30","Day 90","Day 180";
    avisitn = input(avisit, avisitn.);
    output;
  end;
run;

/* Merge planned visit dates from SV and TV, plus ADSL variables */
proc sql;
  create table dummy_visit as 
  select a.*, 
         input(b.SVSTDTC, yymmdd10.) as SVSTDT format=date9., 
         c.VISITDY,
         d.*
  from dummy_facit as a 
  left join derived.sv as b 
    on a.USUBJID=b.USUBJID and a.AVISIT=b.VISIT 
  left join derived.tv as c 
    on a.AVISIT=c.VISIT
  left join analysis.adsl(drop=subjid) as d 
    on a.USUBJID=d.USUBJID
  ;
quit;

data dummy_final;
  format plandt padt date9.;
  set dummy_visit;
  /* Impute planned date: prefer SV scheduled date, then calculate from TRTSDT + VISITDY */
  if nmiss(TRTSDT, VISITDY)=0 then plandt = TRTSDT + VISITDY - 1;
  padt = coalesce(SVSTDT, plandt);
  paramtyp = 'DERIVED';
  /* Set treatment variables for period 1 */
  trta=trt01a; trtan=trt01an; trtp=trt01p; trtpn=trt01pn;
  /* APERIOD for dummy records */
  if aperiod = . then do;
    if .< ap01sdt <= padt <= coalesce(ap02sdt, ap01edt) then aperiod = 1;
    else if .< ap02sdt < padt <= ap02edt then aperiod = 2;
  end;
  length aperiodc $30;
  if aperiod=1 then aperiodc='Double-blind';
  else if aperiod=2 then aperiodc='Open-label';
run;

/* Only add dummies where no actual FACIT record exists for that visit */
proc sort data=dummy_final; by usubjid paramcd avisitn; run;

data existing_facit;
  set adfacit3;
  where paramcd='FACIT' and avisitn in (202, 203, 204, 205);
  keep usubjid paramcd avisitn;
run;
proc sort data=existing_facit nodupkey; by usubjid paramcd avisitn; run;

data dummy_new;
  merge dummy_final(in=d) existing_facit(in=e);
  by usubjid paramcd avisitn;
  if d and not e;
run;

/* Append dummy records to actual data */
data adfacit3a;
  set adfacit3 dummy_new;
run;
proc sort data=adfacit3a; by usubjid paramcd adt; run;

/* ================================================================= */
/* End of dummy visit creation                                        */
/* ================================================================= */


/* ------------------------------- */
/* ANL05/ANL06 from FACM; ANL07 from DS */
/* ------------------------------- */

/* ANL05: first ANTI-PROTEINURIC THERAPIES RELATED INTERCURRENT EVENTS (FAORRES='Y') on/after TRTSDT */
data fa_ap;
  merge data_a.facm(in=a) analysis.adsl(keep=usubjid trtsdt);
  by usubjid;
  if a and upcase(facat)='ANTI-PROTEINURIC THERAPIES RELATED INTERCURRENT EVENTS' and faorres='Y';
  if length(fadtc)=10 then fadt = input(fadtc, yymmdd10.);
  if fadt >= trtsdt;
  format fadt yymmdd10.;
run;
proc sort data=fa_ap; by usubjid fadt; run;
data fa_ap1; set fa_ap; by usubjid fadt; if first.usubjid; keep usubjid fadt; rename fadt=anl05dt; run;

/* ANL06: first RENAL REPLACEMENT THERAPY RELATED INTERCURRENT EVENTS (FAORRES='Y') on/after TRTSDT */
data fa_rr;
  merge data_a.facm(in=a) analysis.adsl(keep=usubjid trtsdt);
  by usubjid;
  if a and upcase(facat)='RENAL REPLACEMENT THERAPY RELATED INTERCURRENT EVENTS' and faorres='Y';
  if length(fadtc)=10 then fadt = input(fadtc, yymmdd10.);
  if fadt >= trtsdt;
  format fadt yymmdd10.;
run;
proc sort data=fa_rr; by usubjid fadt; run;
data fa_rr1; set fa_rr; by usubjid fadt; if first.usubjid; keep usubjid fadt; rename fadt=anl06dt; run;

/* ANL07: first treatment discontinuation for other reason (BLINDED only; exclude COMPLETED/ADVERSE), on/after TRTSDT */
data ds_oth;
  merge data_a.ds(in=a) analysis.adsl(keep=usubjid trtsdt);
  by usubjid;
  if a
     and dsscat = 'BLINDED TREATMENT DISPOSITION'
     and prxmatch('/COMPLETED|ADVERSE/i', dsdecod) = 0;
  if length(dsstdtc)=10 then anl07dt = input(dsstdtc, yymmdd10.);
  if anl07dt >= trtsdt;
  format anl07dt yymmdd10.;
run;
proc sort data=ds_oth; by usubjid anl07dt; run;
data ds_oth1; set ds_oth; by usubjid anl07dt; if first.usubjid; keep usubjid anl07dt; run;

/* [CHANGE 4] Attach ANL05/06/07 subject-level dates — read from adfacit3a instead of adfacit3 */
proc sql;
  create table adfacit4 as
  select a.*,
         b.anl05dt,
         c.anl06dt,
         d.anl07dt
    from adfacit3a as a
    left join fa_ap1 as b on a.usubjid=b.usubjid
    left join fa_rr1 as c on a.usubjid=c.usubjid
    left join ds_oth1 as d on a.usubjid=d.usubjid
  ;
quit;

/* [CHANGE 5] Set record-level flags; use coalesce(adt, padt) to handle dummy records */
data adfacit5;
  set adfacit4;
  length anl05fl anl06fl anl07fl $1 anl05dsc anl06dsc anl07dsc $100;

  _cmpdt = coalesce(adt, padt);

  if not missing(anl05dt) and anl05dt >= trtsdt and _cmpdt > anl05dt then do;
    anl05fl='Y';
    anl05dsc='Record after initiation or intensification of anti-proteinuric therapies';
  end;

  if not missing(anl06dt) and anl06dt >= trtsdt and _cmpdt > anl06dt then do;
    anl06fl='Y';
    anl06dsc='Record after initiation of RRT';
  end;

  if not missing(anl07dt) and anl07dt >= trtsdt and _cmpdt > anl07dt then do;
    anl07fl='Y';
    anl07dsc='Record after treatment discontinuation for any other reason';
  end;

  drop _cmpdt;
run;

/* ------------------------------- */
/* AEFLAG/AEDCDT  */
/* ------------------------------- */
data ds_ae_p1;
  merge data_a.ds(in=a) analysis.adsl(keep=usubjid ap01sdt ap01edt);
  by usubjid;
  if a and dsscat='STUDY DISPOSITION' and index(upcase(dsdecod),'ADVERSE')>0;
  if length(dsstdtc)=10 then aedcdt = input(dsstdtc, yymmdd10.);
  /* Period-1 window only */
  if ap01sdt <= aedcdt <= ap01edt;
  format aedcdt yymmdd10.;
run;
proc sort data=ds_ae_p1 nodupkey; by usubjid; run;

proc sql;
  create table adfacit6 as
  select a.*, e.aedcdt,
         case when not missing(e.aedcdt) then 'Y' else '' end as aeflag length=1
  from adfacit5 as a
  left join ds_ae_p1 as e
    on a.usubjid=e.usubjid
  ;
quit;


/* ================================================================= */
/* [CHANGE 6] Derive EST01STP ICE01F IMPREA01 EST02STP ICE02F IMPREA02 */
/* Per PDS:                                                            */
/*   EST01: Anti-proteinuric + RRT = Hypothetical; Disc other = Trt policy */
/*   EST02: RRT only = Hypothetical; Anti-proteinuric + Disc other = Trt policy */
/* Following ADUPCR pattern for ICE priority and padt fallback        */
/* ================================================================= */
data adfacit7;
  length EST01STP EST02STP $30 ICE01F ICE02F $1 IMPREA01 IMPREA02 $200;
  set adfacit6;

  if paramcd = 'FACIT' and avisitn not in (., 99) then do;
    _cmpdt = coalesce(adt, padt);

    /* Check ICE in priority order: anti-proteinuric -> RRT -> disc other */
    if _cmpdt > anl05dt > . then do;
      EST01STP = 'Hypothetical strategy'; ICE01F = 'Y'; IMPREA01 = 'Post ICE';
      EST02STP = 'Treatment policy';      ICE02F = 'Y'; IMPREA02 = 'Post ICE';
    end;
    else if _cmpdt > anl06dt > . then do;
      EST01STP = 'Hypothetical strategy'; ICE01F = 'Y'; IMPREA01 = 'Post ICE';
      EST02STP = 'Hypothetical strategy'; ICE02F = 'Y'; IMPREA02 = 'Post ICE';
    end;
    else if _cmpdt > anl07dt > . then do;
      EST01STP = 'Treatment policy'; ICE01F = 'Y'; IMPREA01 = 'Post ICE';
      EST02STP = 'Treatment policy'; ICE02F = 'Y'; IMPREA02 = 'Post ICE';
    end;

    /* If AVAL is missing (including dummy records), override IMPREA to 'Missing data' */
    if missing(aval) then do;
      IMPREA01 = 'Missing data';
      IMPREA02 = 'Missing data';
    end;
  end;

  drop _cmpdt;
run;


/* [CHANGE 7] Final cleanup — preserve dummy records (they have IMPREA populated) */
data final;
  set adfacit7;
  /* Delete truly empty records, but keep dummy FACIT records for MI */
  if missing(aval) and missing(avalc) and missing(IMPREA01) then delete;
run;

proc sort data=final;
  by studyid usubjid subjid param avisitn adt;
run;


/* Submission padding and attribute assignment */
%_std_varpadding_submission(
  calledby   =,
  in_lib     = work,
  out_lib    = work,
  include_ds = final,
  exclude_ds =
);

%opSetAttr(domain=adfacit, inData=final, metaData=RPRTDSM.study_adam_metadata);
