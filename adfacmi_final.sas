/************************************************************************
*  PROJECT       : CLNP023B1
*  STUDY         : CLNP023B12301
*  RA            : csr_4
*  FILENAME      : adfacit.sas
*  DESCRIPTION   : Create dataset ADFACIT (csr_4 PDS / VLM / METHOD compliant)
*  PLATFORM      : AIX 7.1 (AIX 64) (see SAS log file)
*  SAS VERSION   : 9.4 (see SAS log file)
*  INPUT         : SDTM QS (with SUPPQS), ADaM ADSL, SDTM DS/FACM
*  OUTPUT        : analysis.adfacit
*  MODIFICATIONS : Reworked from csr_3 to match csr_4 changes
*************************************************************************/

proc datasets lib=work kill nolist; quit;

/* GPS environment setup macro */
data _null_;
  if libref('analysis') then call execute('%nrstr(%autorun;)');
run;

/* ------------------------------- */
/* Formats for planned visit names */
/* ------------------------------- */
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

  /* Standardize AVISIT for planned visits only; EOS to Day 360 */
  length avisit $40;
  if visit = 'End of Study' then visit = 'Day 360';
if visit in ('Day 1','Day 14','Day 30','Day 90','Day 180','Day 210','Day 270','Day 360') then avisit = visit;  
else avisit = ''; 
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

  if missing(avisit) then do;
    length _v $40;
    _v = visit;
    if _v = 'End of Study' then _v = 'Day 360';
    if _v in ('Day 1','Day 14','Day 30','Day 180','Day 210','Day 270','Day 360') then do;
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


/* ------------------------------- */
/* ANL05/ANL06 from FACM; ANL07 from DS */
/* ------------------------------- */

/* ANL05: first ANTI-PROTEINURIC THERAPIES RELATED INTERCURRENT EVENTS (FAORRES='Y') on/after TRTSDT */
data fa_ap;
  merge derived.facm(in=a) analysis.adsl(keep=usubjid trtsdt);
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
  merge derived.facm(in=a) analysis.adsl(keep=usubjid trtsdt);
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
  merge derived.ds(in=a) analysis.adsl(keep=usubjid trtsdt);
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

/* Attach ANL05/06/07 subject-level dates, then set record-level flags when ADT > date >= TRTSDT */
proc sql;
  create table adfacit4 as
  select a.*,
         b.anl05dt,
         c.anl06dt,
         d.anl07dt
    from adfacit3 as a
    left join fa_ap1 as b on a.usubjid=b.usubjid
    left join fa_rr1 as c on a.usubjid=c.usubjid
    left join ds_oth1 as d on a.usubjid=d.usubjid
  ;
quit;

data adfacit5;
  set adfacit4;
  length anl05fl anl06fl anl07fl $1 anl05dsc anl06dsc anl07dsc $100;

  if not missing(anl05dt) and anl05dt >= trtsdt and adt > anl05dt then do;
    anl05fl='Y';
    anl05dsc='Record after initiation or intensification of anti-proteinuric therapies';
  end;

  if not missing(anl06dt) and anl06dt >= trtsdt and adt > anl06dt then do;
    anl06fl='Y';
    anl06dsc='Record after initiation of RRT';
  end;

  if not missing(anl07dt) and anl07dt >= trtsdt and adt > anl07dt then do;
    anl07fl='Y';
    anl07dsc='Record after treatment discontinuation for any other reason';
  end;
run;

/* ------------------------------- */
/* AEFLAG/AEDCDT  */
/* ------------------------------- */
data ds_ae_p1;
  merge derived.ds(in=a) analysis.adsl(keep=usubjid ap01sdt ap01edt);
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
data adfacit_est;
  set adfacit6;

  length EST01STP EST02STP $50
         ICE01F ICE02F $1
         IMPREA01 IMPREA02 $200;

  call missing(EST01STP, EST02STP, IMPREA01, IMPREA02);
  ICE01F='N'; ICE02F='N';

  if paramcd='FACIT' then do;

    /* Estimand 01 */
    if adt > anl05dt > . or adt > anl06dt > . then do;
      EST01STP='Hypothetical strategy';
      ICE01F='Y';
      IMPREA01='Post ICE';
    end;
    else if adt > anl07dt > . then do;
      EST01STP='Treatment policy';
      ICE01F='Y';
      IMPREA01='Post ICE';
    end;
    else if missing(aval) then IMPREA01='Missing data';

    /* Estimand 02 */
    if adt > anl06dt > . then do;
      EST02STP='Hypothetical strategy';
      ICE02F='Y';
      IMPREA02='Post ICE';
    end;
    else if adt > anl05dt > . or adt > anl07dt > . then do;
      EST02STP='Treatment policy';
      ICE02F='Y';
      IMPREA02='Post ICE';
    end;
    else if missing(aval) then IMPREA02='Missing data';

  end;
run;


proc sort data=adfacit_est out=_der;
  by usubjid paramcd avisitn adt atm adtm;
  where upcase(paramtyp)='DERIVED' and not missing(avisitn);
run;

data _keep;
  set _der;
  by usubjid paramcd avisitn;
  if avisitn=99 and ablfl='Y' then output;
  else if first.avisitn and not missing(aval) then output;
  keep usubjid paramcd avisitn adt atm adtm;
run;

proc sql;
  create table final as
  select a.*,
         case when k.usubjid is not null then 'Y' else '' end as anl01fl,
         case when k.usubjid is not null then 'Unique record for each visit' else '' end as anl01dsc
  from adfacit_est as a
  left join _keep as k
    on a.usubjid=k.usubjid
   and a.paramcd=k.paramcd
   and a.avisitn=k.avisitn
   and a.adt=k.adt
   and a.atm=k.atm
  ;
quit;

/* Submission padding and attribute assignment */
%_std_varpadding_submission(
  calledby   =,
  in_lib     = work,
  out_lib    = work,
  include_ds = final,
  exclude_ds =
);

%opSetAttr(domain=adfacit, inData=final, metaData=RPRTDSM.study_adam_metadata);



proc sql;
  select usubjid, avisitn, est01stp, ice01f
  from final
  where paramcd='FACIT'
    and ice01f='Y'
    and missing(est01stp);
quit;

proc sql;
  select usubjid, avisitn, est02stp, ice02f
  from final
  where paramcd='FACIT'
    and ice02f='Y'
    and missing(est02stp);
quit;

proc sql;
  select usubjid, avisitn, imprea01
  from final
  where paramcd='FACIT'
    and ice01f='Y'
    and imprea01 ne 'Post ICE';
quit;

proc sql;
  select usubjid, avisitn, imprea02
  from final
  where paramcd='FACIT'
    and ice02f='Y'
    and imprea02 ne 'Post ICE';
quit;

proc sql;
  select usubjid, avisitn, aval, ice01f, imprea01
  from final
  where paramcd='FACIT'
    and missing(aval)
    and ice01f ne 'Y'
    and imprea01 ne 'Missing data';
quit;
