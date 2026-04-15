你这个判断是对的，而且这个修法比我上一版更对。

关键点就是你说的这句：

```sas
if b;
```

因为 `facit_dummy2` 只有 planned visits，不含 `Baseline`，所以一旦用它做主表 merge，再 `if b;`，就会把：

* `FACIT` baseline 记录
* 所有非 planned visit 的实际 `FACIT` 记录

一起丢掉。

这和 `ADUPCR` 的思路不一致。更合理的做法就是：

* **保留原始 `adfacit3` 全部实际记录**
* **只补那些 planned visit 上实际不存在的 dummy**
* 然后把 dummy append 回去

你给的思路是对的。我下面给你的是**按这个修正后的完整版本**，并且把前面你报错的 character/numeric 问题也一起处理掉了。

---

# 正确完整版本 `adfacit.sas`

```sas
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

proc datasets lib=work kill nolist;
quit;

/* GPS environment setup macro */
data _null_;
  if libref('analysis') then call execute('%nrstr(%autorun;)');
run;

/* ------------------------------- */
/* Formats                         */
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
/* Read QS + SUPPQS and pre-derive */
/* ------------------------------- */
%opMergeSupp(
  inData     = derived.qs,
  outData    = qs_raw,
  inSuppData = derived.suppqs,
  keepQnam   =
);

proc sort data=qs_raw nodupkey;
  by usubjid subjid qscat qstest qsscat visit qsdtc qsorres;
run;

/* Keep only FACIT-Fatigue 13 items */
data qs_items;
  set qs_raw(rename=(
        qstest   = param
        qstestcd = paramcd
        lg       = qslg
        qseval   = qseval
      ));
  where qscat = 'FACIT-FATIGUE 13-ITEM V4';

  length avalc $100;
  aval  = coalesce(qsstresn, input(upcase(qsorres), facit_val.));
  avalc = strip(upcase(qsorres));

  adt = input(scan(qsdtc,1,'T'), yymmdd10.);
  atm = input(scan(qsdtc,2,'T'), time8.);
  if length(qsdtc)=19 then adtm = input(qsdtc, e8601dt.);

  format adt yymmdd10. atm time5.;
run;

/* Map PARAMN from Analysis Parameters for item-level rows */
proc sql;
  create table qs_items_m as
  select a.*,
         b.paramcd as paramcd_,
         b.paramn
  from qs_items as a
  left join
       (
         select param, paramcd, paramn
         from rprtdsm.analysis_parameters
         where not missing(paramn)
       ) as b
    on a.param = b.param
  ;
quit;

proc sort data=qs_items_m;
  by usubjid subjid visit adt paramn;
run;

/* ------------------------------- */
/* Join ADSL and derive visit vars */
/* ------------------------------- */
data qs_items_j;
  merge qs_items_m(in=a)
        analysis.adsl(in=b drop=subjid rename=(siteid=siteid_adsl));
  by usubjid;
  if a;

  if adt>=trtsdt>. then ady = adt - trtsdt + 1;
  else if .<adt<trtsdt then ady = adt - trtsdt;

  length avisit $40;
  if visit = 'End of Study' then visit = 'Day 360';

  if visit in ('Day 1','Day 14','Day 30','Day 90','Day 180','Day 210','Day 270','Day 360') then avisit = visit;
  else avisit = '';

  avisitn = input(avisit, avisitn.);

  if missing(siteid) then siteid = siteid_adsl;
  drop siteid_adsl;
run;

/* ------------------------------- */
/* Derive FACIT/FACITEXP/FACITIMP  */
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

/*
  Compute scores:
  - reverse-keyed items where applicable
  - FAT_N = N(non-missing items)
  - if FAT_N/13 > 0.5 then prorated total FACIT
  - derived rows: FACIT, FACITEXP, FACITIMP
*/
data facit_der;
  length param $40 paramcd $8 paramtyp $7 avalc $100;
  set qs_wide;

  array item{13} FAC07001-FAC07013;
  array hi   HI7 HI12;
  array ana  AN1-AN5;
  array anb  AN7 AN8 AN12 AN14-AN16;

  do i=1 to 13;
    if item[i] in (8,9) then item[i]=.;
  end;

  if not missing(FAC07001) then HI7  = 4 - FAC07001;
  if not missing(FAC07002) then HI12 = 4 - FAC07002;
  if not missing(FAC07003) then AN1  = 4 - FAC07003;
  if not missing(FAC07004) then AN2  = 4 - FAC07004;
  if not missing(FAC07005) then AN3  = 4 - FAC07005;
  if not missing(FAC07006) then AN4  = 4 - FAC07006;
  if not missing(FAC07007) then AN5  = FAC07007;
  if not missing(FAC07008) then AN7  = FAC07008;
  if not missing(FAC07009) then AN8  = 4 - FAC07009;
  if not missing(FAC07010) then AN12 = 4 - FAC07010;
  if not missing(FAC07011) then AN14 = 4 - FAC07011;
  if not missing(FAC07012) then AN15 = 4 - FAC07012;
  if not missing(FAC07013) then AN16 = 4 - FAC07013;

  FAT_N = n(of HI7 HI12 AN1-AN5 AN7 AN8 AN12 AN14-AN16);

  if FAT_N/13 > .50 then do;
    aval  = sum(of HI7 HI12 AN1-AN5 AN7 AN8 AN12 AN14-AN16) * 13 / FAT_N;
    avalc = strip(put(aval, best.));
    param='FACIT Fatigue score';
    paramcd='FACIT';
    paramtyp='DERIVED';
    output;

    aval  = sum(of HI7 HI12 AN1 AN2 AN5);
    avalc = strip(put(aval, best.));
    param='FACIT Experience score';
    paramcd='FACITEXP';
    paramtyp='DERIVED';
    output;

    aval  = sum(of AN3 AN4 AN7 AN8 AN12 AN14-AN16);
    avalc = strip(put(aval, best.));
    param='FACIT Impact score';
    paramcd='FACITIMP';
    paramtyp='DERIVED';
    output;
  end;

  keep studyid usubjid subjid visit visitnum adt atm adtm qslg qseval
       param paramcd paramtyp aval avalc;
run;

/* Map PARAMN for derived rows */
proc sql;
  create table facit_der_m as
  select a.*, b.paramn
  from facit_der as a
  left join
       (
         select param, paramcd, paramn
         from rprtdsm.analysis_parameters
         where not missing(paramn)
       ) as b
    on a.param = b.param
   and a.paramcd = b.paramcd
  ;
quit;

/* ------------------------------- */
/* Union item-level + derived rows */
/* ------------------------------- */
data adfacit0;
  set qs_items_j(
        keep=studyid usubjid subjid siteid
             param paramcd paramn
             visit visitnum
             adt atm adtm
             qslg qseval qsstat qsreasnd
             aval avalc qsseq
             avisit avisitn
      )
      facit_der_m
  ;
run;

proc sort data=adfacit0;
  by usubjid paramcd adt atm adtm;
run;

data adfacit1;
  merge adfacit0(in=a)
        analysis.adsl(in=b drop=subjid rename=(siteid=siteid_adsl));
  by usubjid;
  if a;

  if adt>=trtsdt>. then ady = adt - trtsdt + 1;
  else if .<adt<trtsdt then ady = adt - trtsdt;

  if aperiod=. then do;
    if .<ap01sdt<=adt<=coalesce(ap02sdt, ap01edt) then aperiod=1;
    else if .<ap02sdt<adt<=ap02edt then aperiod=2;
  end;

  length aperiodc $30;
  if aperiod=1 then aperiodc='Double-blind';
  else if aperiod=2 then aperiodc='Open-label';

  if upcase(coalescec(paramtyp,''))='DERIVED' then do;
    qsstat   = '';
    qsreasnd = '';
    qslg     = '';
    qseval   = '';
  end;

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
  end;

  if missing(siteid) then siteid = siteid_adsl;
  drop siteid_adsl _v;

  length anl01dsc anl03dsc $100 crit1 crit2 $50;
run;

/* ------------------------------- */
/* Baseline                        */
/* ------------------------------- */
proc sort data=adfacit1;
  by usubjid paramcd adt atm adtm;
run;

data base_cand;
  set adfacit1;
  where adt <= trtsdt and not missing(aval);
  by usubjid paramcd adt atm adtm;
run;

data base_last;
  set base_cand;
  by usubjid paramcd adt atm adtm;
  if last.paramcd;
  keep usubjid paramcd adt aval;
  rename adt  = baseadt
         aval = base;
run;

proc sql;
  create table adfacit2 as
  select a.*, b.base, b.baseadt
  from adfacit1 as a
  left join base_last as b
    on a.usubjid=b.usubjid
   and a.paramcd=b.paramcd
  ;
quit;

data adfacit3;
  set adfacit2;

  length ablfl $1;

  if not missing(baseadt) and adt=baseadt then do;
    ablfl   = 'Y';
    avisit  = 'Baseline';
    avisitn = 99;
  end;

  if upcase(coalescec(paramtyp,''))='DERIVED' then do;
    if ablfl ne 'Y' and nmiss(aval, base)=0 then chg = aval - base;
  end;

  if not missing(chg) then do;
    if chg >= 5 then do;
      crit1fl='Y';
      crit1='5-point improvement';
    end;
    if chg >= 3 then do;
      crit2fl='Y';
      crit2='3-point improvement';
    end;
  end;

  if upcase(coalescec(paramtyp,''))='DERIVED' and (ablfl='Y' or not missing(aval)) then do;
    anl01fl='Y';
    anl01dsc='Unique record for each visit';
  end;

  if ablfl='Y' or (aperiod=1 and not missing(aval)) then do;
    anl03fl='Y';
    anl03dsc='Record for treatment randomized period analysis';
  end;
run;

/* Recompute TRTA/TRTP after ABLFL finalized */
data adfacit3;
  set adfacit3;
  if aperiod=1 or ablfl='Y' then do;
    trta  = trt01a;
    trtan = trt01an;
    trtp  = trt01p;
    trtpn = trt01pn;
  end;
  else if aperiod=2 then do;
    trta  = trt02a;
    trtan = trt02an;
    trtp  = trt02p;
    trtpn = trt02pn;
  end;
run;

/* ------------------------------- */
/* Add planned-visit dummy records */
/* only when actual FACIT visit    */
/* does not already exist          */
/* ------------------------------- */
proc sort data=adfacit3 out=facit_bl nodupkey;
  by usubjid paramcd;
  where paramcd='FACIT' and ablfl='Y';
run;

data facit_dummy0;
  set facit_bl(
    keep=studyid usubjid subjid siteid
         param paramcd paramn paramtyp
         trtsdt trt01a trt01an trt01p trt01pn
         trt02a trt02an trt02p trt02pn
         ap01sdt ap01edt ap02sdt ap02edt
         base
  );

  length avisit $40;
  do avisit='Day 1','Day 14','Day 30','Day 90','Day 180','Day 210','Day 270','Day 360';
    avisitn = input(avisit, avisitn.);
    output;
  end;
run;

proc sql;
  create table facit_dummy1 as
  select a.*,
         input(b.svstdtc, yymmdd10.) as svstdt format=date9.,
         c.visitdy
  from facit_dummy0 as a
  left join derived.sv as b
    on a.usubjid=b.usubjid
   and a.avisit=b.visit
  left join derived.tv as c
    on a.avisit=c.visit
  ;
quit;

data facit_dummy2;
  set facit_dummy1;
  format plandt padt date9.;

  if nmiss(trtsdt, visitdy)=0 then plandt = trtsdt + visitdy - 1;
  padt = coalesce(svstdt, plandt);

  if .<ap01sdt<=padt<=coalesce(ap02sdt, ap01edt) then aperiod=1;
  else if .<ap02sdt<padt<=ap02edt then aperiod=2;

  length aperiodc $30;
  if aperiod=1 then aperiodc='Double-blind';
  else if aperiod=2 then aperiodc='Open-label';

  if aperiod=1 then do;
    trta  = trt01a;
    trtan = trt01an;
    trtp  = trt01p;
    trtpn = trt01pn;
  end;
  else if aperiod=2 then do;
    trta  = trt02a;
    trtan = trt02an;
    trtp  = trt02p;
    trtpn = trt02pn;
  end;

  length
    visit    $40
    qsstat   $200
    qsreasnd $200
    qslg     $200
    qseval   $200
    avalc    $200
    crit1    $50
    crit2    $50
    crit1fl  $1
    crit2fl  $1
    anl01fl  $1
    anl03fl  $1
    ablfl    $1
    anl01dsc $100
    anl03dsc $100
    ice01f   $1
    ice02f   $1
    est01stp $200
    est02stp $200
    imprea01 $200
    imprea02 $200
  ;

  call missing(
    visit, qsstat, qsreasnd, qslg, qseval,
    adt, atm, adtm, ady, aval, avalc, chg,
    crit1, crit1fl, crit2, crit2fl,
    anl01fl, anl01dsc, anl03fl, anl03dsc,
    ablfl, qsseq,
    ice01f, ice02f, est01stp, est02stp, imprea01, imprea02
  );
run;

proc sort data=facit_dummy2;
  by usubjid paramcd avisitn;
run;

data existing_facit;
  set adfacit3;
  where paramcd='FACIT';
  keep usubjid paramcd avisitn;
run;

proc sort data=existing_facit nodupkey;
  by usubjid paramcd avisitn;
run;

data dummy_new;
  merge facit_dummy2(in=d) existing_facit(in=e);
  by usubjid paramcd avisitn;
  if d and not e;
run;

data adfacit3a;
  set adfacit3
      dummy_new;
run;

/* ------------------------------- */
/* ANL05/ANL06/ANL07 subject dates */
/* ------------------------------- */

/* ANL05: first anti-proteinuric therapy ICE */
data fa_ap;
  merge derived.facm(in=a)
        analysis.adsl(keep=usubjid trtsdt);
  by usubjid;
  if a
     and upcase(facat)='ANTI-PROTEINURIC THERAPIES RELATED INTERCURRENT EVENTS'
     and faorres='Y';

  fadt = input(fadtc, ??yymmdd10.);
  if fadt >= trtsdt > .;

  format fadt yymmdd10.;
run;

proc sort data=fa_ap;
  by usubjid fadt;
run;

data fa_ap1;
  set fa_ap;
  by usubjid fadt;
  if first.usubjid;
  keep usubjid fadt;
  rename fadt=anl05dt;
run;

/* ANL06: first RRT ICE */
data fa_rr;
  merge derived.facm(in=a)
        analysis.adsl(keep=usubjid trtsdt);
  by usubjid;
  if a
     and upcase(facat)='RENAL REPLACEMENT THERAPY RELATED INTERCURRENT EVENTS'
     and faorres='Y';

  fadt = input(fadtc, ??yymmdd10.);
  if fadt >= trtsdt > .;

  format fadt yymmdd10.;
run;

proc sort data=fa_rr;
  by usubjid fadt;
run;

data fa_rr1;
  set fa_rr;
  by usubjid fadt;
  if first.usubjid;
  keep usubjid fadt;
  rename fadt=anl06dt;
run;

/* ANL07: first treatment discontinuation for other reason */
data ds_oth;
  merge derived.ds(in=a)
        analysis.adsl(keep=usubjid trtsdt);
  by usubjid;
  if a
     and dsscat in ('BLINDED TREATMENT DISPOSITION','OPEN LABEL TREATMENT DISPOSITION')
     and prxmatch('/COMPLETED|ADVERSE/i', dsdecod)=0;

  anl07dt = input(dsstdtc, ??yymmdd10.);
  if anl07dt >= trtsdt > .;

  format anl07dt yymmdd10.;
run;

proc sort data=ds_oth;
  by usubjid anl07dt;
run;

data ds_oth1;
  set ds_oth;
  by usubjid anl07dt;
  if first.usubjid;
  keep usubjid anl07dt;
run;

/* Attach dates */
proc sql;
  create table adfacit4 as
  select a.*,
         b.anl05dt,
         c.anl06dt,
         d.anl07dt
  from adfacit3a as a
  left join fa_ap1  as b on a.usubjid=b.usubjid
  left join fa_rr1  as c on a.usubjid=c.usubjid
  left join ds_oth1 as d on a.usubjid=d.usubjid
  ;
quit;

/* Record-level post-ICE flags + new estimand vars */
data adfacit5;
  set adfacit4;
  length anl05fl anl06fl anl07fl ice01f ice02f $1
         anl05dsc anl06dsc anl07dsc $100
         est01stp est02stp imprea01 imprea02 $200;

  refdt = coalesce(adt, padt);
  format refdt date9.;

  if not missing(anl05dt) and refdt > anl05dt then do;
    anl05fl='Y';
    anl05dsc='Record after initiation or intensification of anti-proteinuric therapies';
  end;

  if not missing(anl06dt) and refdt > anl06dt then do;
    anl06fl='Y';
    anl06dsc='Record after initiation of RRT';
  end;

  if not missing(anl07dt) and refdt > anl07dt then do;
    anl07fl='Y';
    anl07dsc='Record after treatment discontinuation for any other reason';
  end;

  if paramcd='FACIT' then do;
    ice01f='N';
    ice02f='N';

    if refdt > anl05dt > . then do;
      est01stp='Hypothetical strategy';
      ice01f='Y';
      imprea01='Post ICE';

      est02stp='Treatment policy';
      ice02f='Y';
      imprea02='Post ICE';
    end;
    else if refdt > anl06dt > . then do;
      est01stp='Hypothetical strategy';
      ice01f='Y';
      imprea01='Post ICE';

      est02stp='Hypothetical strategy';
      ice02f='Y';
      imprea02='Post ICE';
    end;
    else if refdt > anl07dt > . then do;
      est01stp='Treatment policy';
      ice01f='Y';
      imprea01='Post ICE';

      est02stp='Treatment policy';
      ice02f='Y';
      imprea02='Post ICE';
    end;

    if missing(aval) then do;
      if missing(imprea01) then imprea01='Missing data';
      if missing(imprea02) then imprea02='Missing data';
    end;
  end;

  drop refdt;
run;

/* ------------------------------- */
/* AEFLAG / AEDCDT                 */
/* ------------------------------- */
data ds_ae_p1;
  merge derived.ds(in=a)
        analysis.adsl(keep=usubjid ap01sdt ap01edt);
  by usubjid;
  if a
     and dsscat='STUDY DISPOSITION'
     and index(upcase(dsdecod),'ADVERSE')>0;

  aedcdt = input(dsstdtc, ??yymmdd10.);
  if ap01sdt <= aedcdt <= ap01edt;

  format aedcdt yymmdd10.;
run;

proc sort data=ds_ae_p1;
  by usubjid aedcdt;
run;

data ds_ae_p1_1;
  set ds_ae_p1;
  by usubjid aedcdt;
  if first.usubjid;
  keep usubjid aedcdt;
run;

proc sql;
  create table adfacit6 as
  select a.*,
         e.aedcdt,
         case when not missing(e.aedcdt) then 'Y' else '' end as aeflag length=1
  from adfacit5 as a
  left join ds_ae_p1_1 as e
    on a.usubjid=e.usubjid
  ;
quit;

/* ------------------------------- */
/* Final dataset                   */
/* ------------------------------- */
data final;
  set adfacit6;

  if missing(aval) and missing(avalc)
     and not (
       paramcd='FACIT'
       and upcase(coalescec(paramtyp,''))='DERIVED'
       and missing(adt)
       and not missing(padt)
       and avisitn ne 99
     )
  then delete;

  drop plandt padt svstdt visitdy;
run;

proc sort data=final;
  by studyid usubjid subjid paramcd avisitn adt atm qsseq;
run;

/* Submission padding and attribute assignment */
%_std_varpadding_submission(
  calledby   =,
  in_lib     = work,
  out_lib    = work,
  include_ds = final,
  exclude_ds =
);

%opSetAttr(
  domain   = adfacit,
  inData   = final,
  metaData = RPRTDSM.study_adam_metadata
);
```

---

# 你这次修改为什么是正确的

你现在这个版本的 dummy 逻辑变成了：

```sas
data existing_facit;
  set adfacit3;
  where paramcd='FACIT';
  keep usubjid paramcd avisitn;
run;

data dummy_new;
  merge facit_dummy2(in=d) existing_facit(in=e);
  by usubjid paramcd avisitn;
  if d and not e;
run;

data adfacit3a;
  set adfacit3
      dummy_new;
run;
```

这个逻辑有 3 个优点：

### 1. Baseline FACIT 不会丢

因为 baseline 本来就在 `adfacit3` 里，现在 `adfacit3a` 是直接 `set adfacit3 dummy_new;`，所以 baseline 会保留。

### 2. 非 planned visit 的实际 FACIT 也不会丢

以前你是先 merge 到 dummy visit 框架上，所以非 planned visit 没有壳子，就被丢了。
现在所有实际记录都保留，再 append dummy，不会丢。

### 3. planned visits 只在缺失时补 dummy

这样最接近你给的 `ADUPCR` 思路：原始数据里先把 MI 需要的 planned visits 补齐，但不会覆盖已经存在的实际记录。

---

# 建议你现在一定跑的检查代码

下面这些 check 是为了验证这次修正是不是**真的把 baseline 和非 planned visit 保住了**。

---

## Check 1：确认 FACIT baseline 还在

```sas
proc freq data=final;
  tables paramcd*ablfl / list missing;
  where paramcd='FACIT';
run;

proc print data=final(obs=50);
  where paramcd='FACIT' and ablfl='Y';
  var usubjid paramcd adt avisit avisitn ablfl base aval chg;
run;
```

你要看：

* `FACIT` 是否还有 `ABLFL='Y'`
* baseline record 的 `AVISIT='Baseline'`，`AVISITN=99`

---

## Check 2：确认 dummy 只加在 planned visits 缺失处

```sas
proc print data=final(obs=100);
  where paramcd='FACIT'
    and missing(adt)
    and not missing(avisitn)
    and avisitn ne 99;
  var usubjid paramcd avisit avisitn padt base aval est01stp ice01f imprea01 est02stp ice02f imprea02;
run;
```

你要看：

* 这些应该是 dummy rows
* `ADT` 缺失
* `PADT` 应该有值
* `AVISIT/AVISITN` 是 planned visits

---

## Check 3：确认实际 FACIT 非 planned visit 还在

```sas
proc print data=final(obs=100);
  where paramcd='FACIT'
    and not missing(adt)
    and missing(avisitn);
  var usubjid paramcd visit adt avisit avisitn aval;
run;
```

你要看：

* 非 planned visit 的实际记录是否还存在
* 这正是上一版最容易被误删的部分

---

## Check 4：确认没有同一 subject/visit 重复 FACIT

```sas
proc sort data=final(where=(paramcd='FACIT'))
          out=chk_facit_dup dupout=dup_facit nodupkey;
  by usubjid paramcd avisitn adt atm;
run;

proc print data=dup_facit(obs=100);
run;
```

如果这里有很多重复，就说明 dummy append 可能和实际记录还存在重叠问题。

---

## Check 5：确认 planned visit 补齐是否完整

```sas
proc freq data=final;
  tables avisit / missing;
  where paramcd='FACIT';
run;

proc freq data=final;
  tables avisit*(missing(adt)) / list missing;
  where paramcd='FACIT' and avisit in ('Baseline','Day 1','Day 14','Day 30','Day 90','Day 180','Day 210','Day 270','Day 360');
run;
```

你要看：

* planned visits 都出现了
* 有实际记录的 visit 不应该全变成 dummy
* dummy 只应该出现在原本缺失的 visit

---

## Check 6：确认新增 estimand 变量在 FACIT 上有值

```sas
proc freq data=final;
  tables paramcd*ice01f paramcd*ice02f / list missing;
  where paramcd='FACIT';
run;

proc print data=final(obs=100);
  where paramcd='FACIT' and (ice01f='Y' or ice02f='Y' or imprea01='Missing data' or imprea02='Missing data');
  var usubjid avisit adt padt anl05dt anl06dt anl07dt est01stp ice01f imprea01 est02stp ice02f imprea02;
run;
```

---

## Check 7：直接确认 baseline 没有在 dummy step 后消失

这个 check 最直接。你可以在 `adfacit3` 和 `adfacit3a` 各跑一次：

```sas
proc sql;
  select count(*) as n_baseline_before
  from adfacit3
  where paramcd='FACIT' and ablfl='Y';

  select count(*) as n_baseline_after
  from adfacit3a
  where paramcd='FACIT' and ablfl='Y';
quit;
```

如果这两个数一样，说明你这次修正把 baseline 保住了。

---

# 我再帮你总结一下这次真正修对的点

你这次最重要的改正不是“语法”，而是**数据集构建策略**：

* 错误思路：用 dummy visit 框架去承载 FACIT，再 merge 实际记录
* 正确思路：保留所有实际 FACIT，再只补缺失的 planned visit dummy

这在 ADaM 里很关键，因为 baseline、unplanned visit、actual record 不能被 dummy 框架反客为主。

你把新 log 或者上面 check 的结果贴给我后，我可以继续帮你做下一轮确认，重点帮你看两件事：

1. `EST01/EST02` 的赋值是否完全符合你们 PDT
2. `final` 里最后那条 delete 规则是否还需要再微调，避免误删某些特殊 missing actual records




                                                   The FREQ Procedure                                                               
                                                                                                                                    
                                                                      Cumulative    Cumulative                                      
                         PARAMCD    ABLFL    Frequency     Percent     Frequency      Percent                                       
                         ---------------------------------------------------------------------                                      
                         FACIT                    175       89.29           175        89.29                                        
                         FACIT      Y              21       10.71           196       100.00                                        


      Obs           USUBJID           PARAMCD           ADT     AVISIT     AVISITN    ABLFL    BASE    AVAL    CHG                  
                                                                                                                                    
       79    CLNP023B12301_1001009     FACIT     2025-07-15    Baseline       99        Y       23      23                          
      138    CLNP023B12301_1001010     FACIT     2026-01-29    Baseline       99        Y       47      47                          
      191    CLNP023B12301_1002004     FACIT     2025-12-30    Baseline       99        Y       44      44                          
      257    CLNP023B12301_1005002     FACIT     2025-12-29    Baseline       99        Y       44      44                          
      424    CLNP023B12301_2054004     FACIT     2025-12-05    Baseline       99        Y       49      49                          
      529    CLNP023B12301_3311002     FACIT     2025-07-14    Baseline       99        Y       52      52                          
      590    CLNP023B12301_3311003     FACIT     2026-01-21    Baseline       99        Y       43      43                          
      756    CLNP023B12301_3404001     FACIT     2025-03-05    Baseline       99        Y       32      32                          
      885    CLNP023B12301_3502004     FACIT     2023-09-04    Baseline       99        Y       33      33                          
     1001    CLNP023B12301_3601011     FACIT     2025-07-01    Baseline       99        Y       49      49                          
     1127    CLNP023B12301_3602003     FACIT     2023-09-26    Baseline       99        Y       38      38                          
     1256    CLNP023B12301_3602004     FACIT     2023-09-19    Baseline       99        Y       48      48                          
     1346    CLNP023B12301_3902003     FACIT     2025-07-01    Baseline       99        Y       23      23                          
     1416    CLNP023B12301_4001007     FACIT     2025-12-10    Baseline       99        Y       47      47                          
     1568    CLNP023B12301_5002001     FACIT     2024-08-15    Baseline       99        Y       21      21                          
     1697    CLNP023B12301_5006015     FACIT     2024-12-04    Baseline       99        Y       40      40                          
     1800    CLNP023B12301_5006016     FACIT     2025-07-28    Baseline       99        Y       36      36                          
     1872    CLNP023B12301_5016001     FACIT     2024-08-13    Baseline       99        Y       52      52                          
     2053    CLNP023B12301_5211001     FACIT     2025-12-10    Baseline       99        Y       42      42                          
     2173    CLNP023B12301_6012001     FACIT     2024-08-22    Baseline       99        Y       49      49                          
     2302    CLNP023B12301_6013001     FACIT     2023-09-26    Baseline       99        Y       45      45                          


                                                   The FREQ Procedure                                                               
                                                                                                                                    
                                                                  Cumulative    Cumulative                                          
                             AVISIT      Frequency     Percent     Frequency      Percent                                           
                             -------------------------------------------------------------                                          
                             Baseline          21       10.71            21        10.71                                            
                             Day 1             23       11.73            44        22.45                                            
                             Day 14            25       12.76            69        35.20                                            
                             Day 180           23       11.73            92        46.94                                            
                             Day 210           23       11.73           115        58.67                                            
                             Day 270           23       11.73           138        70.41                                            
                             Day 30            25       12.76           163        83.16                                            
                             Day 360           10        5.10           173        88.27                                            
                             Day 90            23       11.73           196       100.00                                            


                                                   The FREQ Procedure                                                               
                                                                                                                                    
                                                                       Cumulative    Cumulative                                     
                         PARAMCD    ICE01F    Frequency     Percent     Frequency      Percent                                      
                         ----------------------------------------------------------------------                                     
                         FACIT      N              191       97.45           191        97.45                                       
                         FACIT      Y                5        2.55           196       100.00                                       
                                                                                                                                    
                                                                                                                                    
                                                                       Cumulative    Cumulative                                     
                         PARAMCD    ICE02F    Frequency     Percent     Frequency      Percent                                      
                         ----------------------------------------------------------------------                                     
                         FACIT      N              191       97.45           191        97.45                                       
                         FACIT      Y                5        2.55           196       100.00                                       


                                                       n_baseline_                                                                  
                                                            before                                                                  
                                                      ------------                                                                  
                                                                21                                                                  


                                                       n_baseline_                                                                  
                                                             after                                                                  
                                                      ------------                                                                  
                                                                21                                                                  

56226   
56227   proc print data=final(obs=100);
56228     where paramcd='FACIT'
56229       and missing(adt)
56230       and not missing(avisitn)
56231       and avisitn ne 99;
56232     var usubjid paramcd avisit avisitn padt base aval est01stp ice01f imprea01 est02stp ice02f imprea02;
ERROR: Variable PADT not found.
56233   run;

NOTE: The SAS System stopped processing this step because of errors.
NOTE: PROCEDURE PRINT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      
56234   


56235   proc print data=final(obs=100);
56236     where paramcd='FACIT'
56237       and not missing(adt)
56238       and missing(avisitn);
39                                                         The SAS System                            04:10 Wednesday, April 15, 2026

56239     var usubjid paramcd visit adt avisit avisitn aval;
56240   run;

NOTE: No observations were selected from data set WORK.FINAL.
NOTE: There were 0 observations read from the data set WORK.FINAL.
      WHERE (paramcd='FACIT') and (not MISSING(adt)) and MISSING(avisitn);
NOTE: PROCEDURE PRINT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

56241   
56242   proc sort data=final(where=(paramcd='FACIT'))
56243             out=chk_facit_dup dupout=dup_facit nodupkey;
56244     by usubjid paramcd avisitn adt atm;
56245   run;

NOTE: There were 196 observations read from the data set WORK.FINAL.
      WHERE paramcd='FACIT';
NOTE: 0 observations with duplicate key values were deleted.
NOTE: The data set WORK.CHK_FACIT_DUP has 196 observations and 133 variables.
NOTE: The data set WORK.DUP_FACIT has 0 observations and 133 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

56246   
56247   proc print data=dup_facit(obs=100);
56248   run;

NOTE: No observations in data set WORK.DUP_FACIT.
NOTE: PROCEDURE PRINT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

56249   
56250   proc freq data=final;
56251     tables avisit / missing;
56252     where paramcd='FACIT';
56253   run;

NOTE: There were 196 observations read from the data set WORK.FINAL.
      WHERE paramcd='FACIT';
NOTE: The PROCEDURE FREQ printed page 54.
NOTE: PROCEDURE FREQ used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

56254   
56255   proc freq data=final;
56256     tables avisit*(missing(adt)) / list missing;
                                -    -
                                79   22
                                     200
ERROR: Variable MISSING not found.
40                                                         The SAS System                            04:10 Wednesday, April 15, 2026

ERROR 79-322: Expecting a ).
ERROR 22-322: Syntax error, expecting one of the following: a name, ;, (, *, /, _ALL_, _CHARACTER_, _CHAR_, _NUMERIC_.  
ERROR 200-322: The symbol is not recognized and will be ignored.
56257     where paramcd='FACIT' and avisit in ('Baseline','Day 1','Day 14','Day 30','Day 90','Day 180','Day 210','Day
56257 ! 270','Day 360');
56258   run;

NOTE: The SAS System stopped processing this step because of errors.
NOTE: PROCEDURE FREQ used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      
56259   


56260   proc freq data=final;
56261     tables paramcd*ice01f paramcd*ice02f / list missing;
56262     where paramcd='FACIT';
56263   run;

NOTE: There were 196 observations read from the data set WORK.FINAL.
      WHERE paramcd='FACIT';
NOTE: The PROCEDURE FREQ printed page 55.
NOTE: PROCEDURE FREQ used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

56264   
56265   proc print data=final(obs=100);
56266     where paramcd='FACIT' and (ice01f='Y' or ice02f='Y' or imprea01='Missing data' or imprea02='Missing data');
56267     var usubjid avisit adt padt anl05dt anl06dt anl07dt est01stp ice01f imprea01 est02stp ice02f imprea02;
ERROR: Variable PADT not found.
56268   run;

NOTE: The SAS System stopped processing this step because of errors.
NOTE: PROCEDURE PRINT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      
56269   


56270   proc sql;
56271     select count(*) as n_baseline_before
56272     from adfacit3
56273     where paramcd='FACIT' and ablfl='Y';
56274   
56275     select count(*) as n_baseline_after
56276     from adfacit3a
56277     where paramcd='FACIT' and ablfl='Y';
56278   quit;
NOTE: The PROCEDURE SQL printed pages 56-57.
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.01 seconds
      cpu time            0.01 seconds

