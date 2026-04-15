/************************************************************************
*  PROJECT       : CLNP023B1
*  STUDY         : CLNP023B12301
*  RA            : csr_4
*  FILENAME      : adegfr.sas
*
*  DATE CREATED  : 07Jul2023
*  AUTHOR        : Dylan Hu
*
*  DESCRIPTION   : Create dataset ADEGFR
*  PLATFORM      : AIX 7.2 (AIX 64)
*  SAS VERSION   : 9.4
*
*  INPUT         : SDTM LB/SUPPLB, VS/SUPPVS, ADSL, ADLB
*  OUTPUT        : analysis.adegfr
*
*  MODIFICATIONS :
*    2025-04-02  : Add EST01STP, ICE01F, IMPREA01, EST02STP, ICE02F, IMPREA02,
*                 EST03STP, ICE03F, IMPREA03; move planned visit dummy to base dataset
************************************************************************/

/* Clean work library */
proc datasets lib=work kill;
run;

/* GPS environment setup macro */
data _null_;
  if libref('analysis') then call execute('%nrstr(%autorun;)');
run;

/* Visit remapping formats (existing) */
proc format;
  value $cbvisitn
    'Day 180'=99
    'Day 210'=203
    'Day 270'=204
    'Day 360'=205
    other = .
  ;
quit;

proc format;
  value cbvisit
    99='LNP023 Baseline'
    201='LNP023 Day 1'
    202='LNP023 Day 14'
    203='LNP023 Day 30'
    204='LNP023 Day 90'
    205='LNP023 Day 180'
    206='LNP023 Day 210'
    207='LNP023 Day 270'
    299='LNP023 Day 360'
    other=' '
  ;
quit;

/*---------------------------------------------------------------------*
 * Pull EGFRDER from ADLB excluding historical CRF pages
 *---------------------------------------------------------------------*/
data adegfr1;
  set analysis.adlb;
  where paramcd="EGFRDER"
    and fasfl="Y"
    and visit not in ("Lab results at the time of diagnosis for C3G Medical History",
                      "Renal Complement Pathway Hx");
run;

data adegfr2;
  merge adegfr1(in=a) analysis.adsl(drop=subjid);
  by usubjid;
  if a;
  obs=_n_;
run;

/*---------------------------------------------------------------------*
 * Historical eGFR from SDTM LB (Diagnosis history pages)
 *---------------------------------------------------------------------*/
%opMergeSupp(indata=derived.lb, outdata=dlb, insuppdata=derived.supplb);

data dlb1;
  set dlb;
  where not missing(usubjid)
    and lbparm in ("EGFR","CREAT")
    and upcase(lbstresc) not in ("","NOT DONE","ND","NA","NE","UNK","UNKNOWN")
    and lbstat=""
    and visit in ("Renal Complement Pathway Hx",
                  "Lab results at the time of diagnosis for C3G Medical History");
run;

/* Attach subject-level dates and treatment/period variables */
data egfrhis;
  merge dlb1(in=a) analysis.adsl(drop=subjid);
  by usubjid;
  if a;

  length dtype $10 aperiodc $100;
  format adt date9. atm time5. adtm datetime19.;

  if missing(lbdtc) then put "WARNING: " usubjid= visit= lbparm= "has missing LBDTC";

  if prxmatch("/\d{4}\-\d{2}\-\d{2}/", scan(lbdtc,1,"T")) then adt = input(scan(lbdtc,1,"T"), ?? yymmdd10.);
  else if prxmatch("/\d{4}\-\d{2}/", scan(lbdtc,1,"T")) then adt = input(cats(scan(lbdtc,1,"T"),"-15"), ?? yymmdd10.);
  else if prxmatch("/\d{4}/", scan(lbdtc,1,"T")) then adt = input(cats(scan(lbdtc,1,"T"),"-07-01"), ?? yymmdd10.);

  atm  = input(scan(lbdtc,2,"T"), ?? time5.);
  adtm = input(lbdtc, ?? e8601dt16.);

  if . < adt < trtsdt then ady = adt - trtsdt;
  else if trtsdt > . then ady = adt - trtsdt + 1;

  /* Keep SDTM ranges */
  anrlo = cats(lbstnrlo); anrlon = lbstnrlo;
  anrhi = cats(lbstnrhi); anrhin = lbstnrhi;
  anrind = lbnrind;
  parcat1 = lbcat; parcat2 = lbscat;

  /* Period assignment */
  if . < ap01sdt <= adt <= coalesce(ap02sdt, ap01edt) then do;
    aperiod = 1; aperiodc = "Double-blind";
    trta = trt01a; trtp = trt01p; trtan = trt01an; trtpn = trt01pn;
  end;
  else if . < ap02sdt <= adt <= ap02edt then do;
    aperiod = 2; aperiodc = "Open-label";
    trta = trt02a; trtp = trt02p; trtan = trt02an; trtpn = trt02pn;
  end;
run;

/* Historic creatinine (Scr) */
data creat_hist;
  set egfrhis;
  where upcase(lbparm)="CREAT" and not missing(lbstresn);

  length scr_mgdl 8;
  if upcase(strip(lbstresu)) in ("UMOL/L","UMO/L","UMOL/L ") then scr_mgdl = lbstresn / 88.4;
  else scr_mgdl = lbstresn;
run;

/* Historic measured eGFR */
data egfr_meas_hist;
  set egfrhis;
  where upcase(lbparm)="EGFR" and not missing(lbstresn);

  length aval_egfr_raw 8;
  aval_egfr_raw = lbstresn;
run;

/*---------------------------------------------------------------------*
 * Height extraction and matching (nearest within +/-90 days)
 *---------------------------------------------------------------------*/
%opMergeSupp(indata=derived.vs, outdata=dvs, insuppdata=derived.suppvs);

proc sql;
  create table vs_ht as
  select distinct
         usubjid,
         subjid,
         inputn(scan(vsdtc,1,'T'),'yymmdd10.') as vsdt format=date9.,
         coalesce(
           case
             when upcase(vsorresu) in ('CM','CENTIMETER','CENTIMETRE') then input(vsorres, best.)
             when upcase(vsorresu) in ('IN','INCH','INCHES') then input(vsorres, best.) * 2.54
             else .
           end,
           vsstresn
         ) as height_cm
  from dvs
  where upcase(vstestcd) in ('HEIGHT','HT')
    and not missing(vsdtc)
    and (not missing(vsorres) or not missing(vsstresn));
quit;

data creat_dt;
  set creat_hist;
  adt_dt = coalesce(adt, input(scan(lbdtc,1,'T'), ?? yymmdd10.));
  format adt_dt date9.;
run;

/* Exclude undated creatinine records from height matching */
data creat_dt_ok creat_dt_undated;
  set creat_dt;
  if missing(adt_dt) then do;
    output creat_dt_undated;
    put "WARNING: Drop undated historic CREAT record from height matching: " usubjid= subjid= visit= lbdtc=;
  end;
  else output creat_dt_ok;
run;

proc sort data=creat_dt_ok; by usubjid subjid adt_dt; run;
proc sort data=vs_ht;       by usubjid subjid vsdt;   run;

proc sql;
  create table ht_pairs as
  select
         c.usubjid, c.subjid, c.adt_dt,
         v.vsdt, v.height_cm,
         abs(v.vsdt - c.adt_dt) as delta,
         (v.vsdt <= c.adt_dt)   as before
  from creat_dt_ok as c
  left join vs_ht as v
    on  c.usubjid = v.usubjid
    and c.subjid  = v.subjid
    and abs(v.vsdt - c.adt_dt) <= 90
  ;
quit;

proc sort data=ht_pairs;
  where not missing(vsdt) and not missing(height_cm);
  by usubjid subjid adt_dt delta descending before vsdt;
run;

data ht_pick;
  set ht_pairs;
  by usubjid subjid adt_dt;
  if first.adt_dt;
  keep usubjid subjid adt_dt height_cm;
run;

proc sql;
  create table scr_ht as
  select a.*,
         p.height_cm
  from creat_dt_ok as a
  left join ht_pick as p
    on a.usubjid = p.usubjid
   and a.subjid  = p.subjid
   and a.adt_dt  = p.adt_dt
  ;
quit;

/* Schwartz derived EGFR from Scr + Height */
data lb_egfr_sch;
  set scr_ht;
  length paramcd $8 param $200;
  if not missing(scr_mgdl) and scr_mgdl>0 and not missing(height_cm) then do;
    aval    = 0.413 * height_cm / scr_mgdl;
    paramcd = "EGFRDER";
    param   = "Glomerular filtration rate (mL/min/1.73m2), Serum, Derived";
  end;
  else call missing(aval, paramcd, param);
run;

/* Measured eGFR per day (avoid duplicates) */
proc sql;
  create table egfr_meas_by_adt as
  select usubjid, subjid, adt,
         max(aval_egfr_raw) as aval_egfr_raw
  from egfr_meas_hist
  group by usubjid, subjid, adt;
quit;

/* Combine derived (Scr) first, fallback to measured */
proc sql;
  create table lb_egfr_final as
  select a.*,
         coalesce(a.aval, b.aval_egfr_raw) as aval_final
  from lb_egfr_sch as a
  left join egfr_meas_by_adt as b
    on a.usubjid=b.usubjid
   and a.subjid =b.subjid
   and a.adt    =b.adt
  ;
quit;

/* Build ADLB-like historical EGFRDER records */
data adlb_egfrder_hist;
  set lb_egfr_final;
  where not missing(aval_final);
  aval    = aval_final;
  lbparm  = "EGFR";
  paramcd = "EGFRDER";
  param   = "Glomerular filtration rate (mL/min/1.73m2), Serum, Derived";
  drop aval_final aval_egfr_raw;
run;

/* Bring EGFRCYC from ADLB */
data adlb_egfrcyc;
  set analysis.adlb;
  where paramcd="EGFRCYC";
run;

/* Combine base + historical + cystatin C */
data adegfr3;
  length crit1 crit2 race param $200 aperiodc $100 visit $60 subjid $50 dtype $10;
  set adegfr2
      adlb_egfrder_hist
      adlb_egfrcyc;
run;

/*---------------------------------------------------------------------*
 * Planned visit dummy moved to base dataset (for MI usage)
 *---------------------------------------------------------------------*/

/* Baseline templates per subject/parameter */
proc sort data=adegfr3 out=_base_egfr nodupkey;
  by usubjid paramcd;
  where paramcd in ("EGFRDER","EGFRCYC") and avisit="Baseline";
run;

/* Dummy planned visits */
data dummy_egfr;
  set _base_egfr(keep=usubjid param paramcd base);
  length avisit $20;
  do avisit="Baseline","Day 1","Day 14","Day 30","Day 90","Day 180","Day 210","Day 270","Day 360";
    output;
  end;
run;

/* Visit order for dummy */
proc format;
  invalue avisit_egfr
    "Baseline"=99
    "Day 1"   =201
    "Day 14"  =202
    "Day 30"  =203
    "Day 90"  =204
    "Day 180" =205
    "Day 210" =206
    "Day 270" =207
    "Day 360" =299
  ;
run;

data dummy_egfr;
  set dummy_egfr;
  avisitn = input(avisit, avisit_egfr.);
run;

/* Merge SV date, TV day, and TRTSDT to derive PADT */
proc sql;
  create table dummy_visit as
  select a.*,
         input(b.SVSTDTC,yymmdd10.) as SVSTDT format=date9.,
         c.VISITDY,
         d.*
  from dummy_egfr as a
  left join derived.sv as b
    on a.USUBJID=b.USUBJID and a.AVISIT=b.VISIT
  left join derived.tv as c
    on a.AVISIT=c.VISIT
  left join analysis.adsl as d
    on a.USUBJID=d.USUBJID
  ;
quit;

data dummy_final;
  format plandt padt date9.;
  set dummy_visit;
  if nmiss(trtsdt, visitdy)=0 then plandt = trtsdt + visitdy - 1;
  padt = coalesce(svstdt, plandt);
run;

proc sort data=dummy_final; by usubjid paramcd avisitn; run;
proc sort data=adegfr3;     by usubjid paramcd avisitn; run;

/* Merge dummy with observed data; observed overrides dummy on same keys */
data adegfr3;
  merge dummy_final(in=b) adegfr3;
  by usubjid paramcd avisitn;
run;

/* Ensure PADT exists for observed rows */
data adegfr3;
  set adegfr3;
  format padt date9.;
  if missing(padt) then padt = adt;
run;

/*---------------------------------------------------------------------*
 * Intercurrent events (subject-level dates)
 *---------------------------------------------------------------------*/

/* Anti-proteinuric therapies */
data ant_cm;
  merge derived.facm(where=(facat="ANTI-PROTEINURIC THERAPIES RELATED INTERCURRENT EVENTS" and faorres="Y"))
        analysis.adsl(keep=usubjid trtsdt fasfl);
  by usubjid;
  astdt = input(fadtc, ?? yymmdd10.);
  if astdt >= trtsdt > .;
  keep usubjid astdt;
run;

proc sql;
  create table cmdt as
  select distinct usubjid, astdt
  from ant_cm
  group by usubjid
  having astdt=min(astdt);

  create table adegfr4 as
  select a.*, b.astdt as astdt_cm
  from adegfr3 as a
  left join cmdt as b
    on a.usubjid=b.usubjid
  ;
quit;

/* RRT initiation */
data rrt;
  merge derived.facm(where=(facat="RENAL REPLACEMENT THERAPY RELATED INTERCURRENT EVENTS" and faorres="Y"))
        analysis.adsl(keep=usubjid trtsdt fasfl);
  by usubjid;
  astdt = input(fadtc, ?? yymmdd10.);
  if astdt >= trtsdt > .;
  keep usubjid astdt;
run;

proc sql;
  create table prdt as
  select distinct usubjid, astdt
  from rrt
  group by usubjid
  having astdt=min(astdt);

  create table adegfr5 as
  select a.*, b.astdt as astdt_pr
  from adegfr4 as a
  left join prdt as b
    on a.usubjid=b.usubjid
  ;
quit;

/* Treatment discontinuation for other reason (exclude COMPLETED/ADVERSE) */
data eot;
  merge derived.ds(where=(dsscat="BLINDED TREATMENT DISPOSITION"
                          and prxmatch("/COMPLETED|ADVERSE/", dsdecod)=0))
        analysis.adsl(keep=usubjid trtsdt fasfl);
  by usubjid;
  astdt = input(dsstdtc, ?? yymmdd10.);
  if astdt >= trtsdt > .;
  keep usubjid astdt;
run;

proc sql;
  create table eotdt as
  select distinct usubjid, astdt
  from eot
  group by usubjid
  having astdt=min(astdt);

  create table adegfr6 as
  select a.*, b.astdt as astdt_eot
  from adegfr5 as a
  left join eotdt as b
    on a.usubjid=b.usubjid
  ;
quit;

/* Study discontinuation due to AE or renal death (Period 1) */
data dsae;
  merge derived.ds(where=(dsscat="STUDY DISPOSITION" and find(dsdecod,"ADVERSE")))
        analysis.adsl(keep=usubjid ap01sdt ap01edt);
  by usubjid;
  astdt = input(dsstdtc, ?? yymmdd10.);
  if ap01sdt <= astdt <= ap01edt;
  keep usubjid astdt dsdecod;
run;

proc sql;
  create table adegfr7 as
  select a.*, b.astdt as astdt_ds
  from adegfr6 as a
  left join dsae as b
    on a.usubjid=b.usubjid
  ;
quit;

/*---------------------------------------------------------------------*
 * Final derivations: ICE flags/dates + estimand variables + criteria
 *---------------------------------------------------------------------*/
data adegfr_final;
  length crit1 crit2 $200 aperiodc $100 visit $60;
  length est01stp est02stp est03stp $50
         imprea01 imprea02 imprea03 $200
         ice01f ice02f ice03f $1;
  set adegfr7;

  /* Intercurrent event dates */
  anl05dt = astdt_cm;
  anl06dt = astdt_pr;
  anl07dt = astdt_eot;
  if not missing(astdt_ds) then aedcdt = astdt_ds;

  /* Analysis flags and descriptions (based on ADT only) */
  if adt > astdt_cm > . then do;
    anl05fl="Y";
    anl05dsc="Record after initiation or intensification of anti-proteinuric therapies";
  end;

  if adt > astdt_pr > . then do;
    anl06fl="Y";
    anl06dsc="Record after initiation of RRT";
  end;

  if adt > astdt_eot > . then do;
    anl07fl="Y";
    anl07dsc="Record after treatment discontinuation for any other reason";
  end;

  if not missing(astdt_ds) then aeflag="Y";

  /* Estimand handling / ICE flags / Imputation reason (PDS 20250402) */
  refdt = coalesce(adt, padt);

  ice01f="N"; ice02f="N"; ice03f="N";
  call missing(est01stp, est02stp, est03stp, imprea01, imprea02, imprea03);

  if paramcd="EGFRDER" then do;

    if refdt > astdt_cm > . then do;
      est01stp='Hypothetical strategy'; ice01f='Y'; imprea01='Post ICE';
      est02stp='Treatment policy'     ; ice02f='Y'; imprea02='Post ICE';
    end;
    else if refdt > astdt_pr > . then do;
      est01stp='Hypothetical strategy'; ice01f='Y'; imprea01='Post ICE';
      est02stp='Hypothetical strategy'; ice02f='Y'; imprea02='Post ICE';
    end;
    else if refdt > astdt_eot > . then do;
      est01stp='Treatment policy'; ice01f='Y'; imprea01='Post ICE';
      est02stp='Treatment policy'; ice02f='Y'; imprea02='Post ICE';
    end;

    if missing(aval) then do;
      if imprea01 ne 'Post ICE' then imprea01='Missing data';
      if imprea02 ne 'Post ICE' then imprea02='Missing data';
    end;

  end;

  if paramcd="EGFRCYC" then do;

    if refdt > astdt_cm > . then do;
      est03stp='Hypothetical strategy'; ice03f='Y'; imprea03='Post ICE';
    end;
    else if refdt > astdt_pr > . then do;
      est03stp='Hypothetical strategy'; ice03f='Y'; imprea03='Post ICE';
    end;
    else if refdt > astdt_eot > . then do;
      est03stp='Treatment policy'; ice03f='Y'; imprea03='Post ICE';
    end;

    if missing(aval) and imprea03 ne 'Post ICE' then imprea03='Missing data';

  end;

  drop refdt;

  /* Percent change */
  if nmiss(chg, base)=0 then pchg = chg/base*100;

  /* Criteria flags (existing) */
  if pchg >= -15 and avisitn > 99 then do;
    crit1   = "<= 15% reduction to baseline in eGFR";
    crit1fl = "Y";
  end;
  else call missing(crit1, crit1fl);

  if pchg >= -10 and avisitn > 99 then do;
    crit2   = "<= 10% reduction to baseline in eGFR";
    crit2fl = "Y";
  end;
  else call missing(crit2, crit2fl);
run;

proc sort data=adegfr_final;
  by studyid usubjid subjid adt;
run;

/* Standard var padding and set attributes */
%_std_varpadding_submission(
  calledby=
 ,in_lib=work
 ,out_lib=work
 ,include_ds=adegfr_final
 ,exclude_ds=
);

%opSetAttr(domain=adegfr, inData=adegfr_final, metaData=RPRTDSM.study_adam_metadata);
