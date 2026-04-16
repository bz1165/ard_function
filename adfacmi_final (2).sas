https://novartiscorp.service-now.com/onenovartisservices?id=nvs_ecp_cat_item&table=sc_cat_item&sys_id=11b94655dbcef058d6316008d496198f&recordUrl=com.glideapp.servicecatalog_cat_item_view.do%3Fv%3D1&sysparm_id=11b94655dbcef058d6316008d496198f/******************************************************************************* 
*            FILENAME : adfacmi.sas
*   PROGRAM DEVELOPER : Yijie Huang (huangy2e)                          
*                DATE : 2023-08-02                                                                                 
*  PROJECT/TRIAL CODE : CLNP023B1/CLNP023B12301
*  REPORTING ACTIVITY : CSR_4                                          
*         DESCRIPTION : To create adfacmi dataset                        
*            PLATFORM : GPSII and SAS 9.4                          
*          MACRO USED : N/A                         
*               INPUT : analysis.adsl, analysis.adfacit, analysis.adbs                       
*              OUTPUT : N/A                         
*               NOTES : N/A                         
*                                                                                                            
*  PROGRAMMING MODIFICATIONS HISTORY                                   
*  DATE        PROGRAMMER           DESCRIPTION                                                         
*  ---------   ----------------     ----------------------------------    
*  04Mar2024   huangy2e             modify data filtering for ANL01FL logic change
*  DDMonYYYY   XXXXXXXX            csr_4: use pre-dummy visits from ADFACIT; 
*                                  use EST/ICE/IMPREA variables; add IMPREAS
*******************************************************************************/


/************************************* Preparation section *************************************/
%macro check_autorun;
	%if %sysfunc(libref(data_a)) ne 0 %then %do; %autorun; %end;
%mend check_autorun;
%check_autorun;

proc datasets lib=work kill memtype=data;
run;


%let Path =/vob/CLNP023B1/CLNP023B12301/csr_1/pgm/stats;
%let Macro=/vob/CLNP023B1/CLNP023B12301/csr_1/pgm/stats;
%let MacroPath=/vob/CLNP023B1/CLNP023B12301/csr_1/pgm/stats;
/* 5macro to impute data based on continuous outcome and MMRM model*/
%include "&MacroPath/5macro_part1A_33.sas";
%include "&MacroPath/5macro_part1B_47.sas";
%include "&MacroPath/5macro_part2A_40.sas";
%include "&MacroPath/5macro_part2B_31.sas";
%include "&MacroPath/5macro_part3_55.sas";

/************************************* Section 2 facit scenario with MI *************************************/
/***2.1 Preparation step***/

/** Import the analysis dataset **/
/* Dummy visits are now pre-created in ADFACIT: use (ANL01FL="Y" or aval=.) to include them */
data dat_part;
      set analysis.adfacit;
      where paramcd="FACIT" and AVISIT in ("Baseline","Day 14","Day 30","Day 90","Day 180") 
            and (ANL01FL="Y" or aval=.) and ^missing(base);
      keep  USUBJID trt01pn avisit AVISITN _avisit PARAMCD PARAM base chg aval 
            EST01STP ICE01F IMPREA01 EST02STP ICE02F IMPREA02
            ANL05DT ANL06DT ANL07DT AEDCDT anl05fl anl06fl anl07fl aeflag;
	  _avisit = tranwrd(cats(avisit)," ","_");
run;

/* Add the stratification variable */
data dat_str;
	set analysis.adbs;
	where fasfl="Y";
	keep USUBJID systrcrf;
run;
proc sort data=dat_part;
	by USUBJID;
run;
proc sort data=dat_str;
	by USUBJID;
run;
data dat; 
	merge dat_part dat_str;
	by USUBJID;
run; 

data dat_ana;
	set dat;
	where trt01pn NE .; /* in case merge the stratification bring unlabeled data*/
	proc sort;
		by paramcd PARAM USUBJID;
run;

/* Separate baseline and post-baseline */
data dat_ana1;
	set dat_ana;
	where avisit ^= "Baseline";
run;
data dat_ana_base;
	set dat_ana;
	where avisit = "Baseline"; 
run;
proc sort data=dat_ana_base; by usubjid; run;
proc sort data=dat_ana1; by usubjid; run;

/* Ensure only subjects with baseline are included */
data dat_ana2;
  merge dat_ana1 dat_ana_base(in=b keep=usubjid);
  by usubjid;
  if b;
run;

/*set the order of visit*/
proc format;
 invalue avisit
 "Baseline"=99
 "Day 14"=202
 "Day 30"=203
 "Day 90"=204
 "Day 180"=205;

 value  avisitc 
 99 = "Baseline"
 202= "Day 14"
 203= "Day 30"
 204= "Day 90"
 205= "Day 180";
run;

proc sort data=dat_ana2;
	by USUBJID AVISITN;
run;


/** Mark the imputation methods according to SAP **/

/*secondary analysis — corresponds to EST01/IMPREA01 */
data dat_ana_mi_sec;
	set dat_ana2;
	length ACAT1 $50.;
	ACAT1="Secondary analysis 24";
	ACAT1N=1;
	ana_flag = "sec";
	IMPREAS=IMPREA01;
	if systrcrf="" then systrcrf="N";

	if imprea01='Missing data' or (EST01STP='Treatment policy' and aval=.) then imp_method='ALMCF';
	if trt01pn = 1 and EST01STP='Hypothetical strategy' then do; aval=.; chg=.; imp_method="J2R"; end;
	if trt01pn = 1 and AEDCDT NE . and imprea01='Missing data' then do; imp_method="J2R"; end;
 	if trt01pn = 2 and EST01STP='Hypothetical strategy' then do; aval=.; chg=.; imp_method="MAR"; end;
 	if trt01pn = 2 and AEDCDT NE . and imprea01='Missing data' then do; imp_method="MAR"; end;

	/* CRITICAL FALLBACK: 5macro requires ALL records to have a method assigned.
	   Any remaining aval=. without method gets ALMCF placeholder 
	   (will be recovered as truly missing later when imp_method="ALMCF" -> set aval=.) */
	if aval=. and missing(imp_method) then imp_method='ALMCF';
run;

/* CRITICAL: 5macro requires one record per USUBJID per AVISITN — enforce uniqueness */
proc sort data=dat_ana_mi_sec nodupkey dupout=_dup_sec;
	by USUBJID AVISITN;
run;


/*supplementary analysis — corresponds to EST02/IMPREA02 */
data dat_ana_mi_supp;
	set dat_ana2;
	length ACAT1 $50.;
	ACAT1="Supplementary analysis 24.1";
	ACAT1N=2;
	ana_flag = "supp";
	IMPREAS=IMPREA02;
	if systrcrf="" then systrcrf="N";

	if imprea02='Missing data' or (EST02STP='Treatment policy' and aval=.) then imp_method='ALMCF';
	if trt01pn = 1 and EST02STP='Hypothetical strategy' then do; aval=.; chg=.; imp_method="J2R"; end;
	if trt01pn = 1 and AEDCDT NE . and imprea02='Missing data' then do; imp_method="J2R"; end;
 	if trt01pn = 2 and EST02STP='Hypothetical strategy' then do; aval=.; chg=.; imp_method="MAR"; end;
 	if trt01pn = 2 and AEDCDT NE . and imprea02='Missing data' then do; imp_method="MAR"; end;

	/* CRITICAL FALLBACK */
	if aval=. and missing(imp_method) then imp_method='ALMCF';
run;

proc sort data=dat_ana_mi_supp nodupkey dupout=_dup_supp;
	by USUBJID AVISITN;
run;


/***2.2 Imputation step***/
/**imputation model: aval=trt*time+base+strfactor**/

%macro facit_mi(endpoint=);
	%part1A(Jobname=facit_mi
	,Data=dat_ana_mi_&endpoint.
	,Subject=USUBJID
	,Response=AVAL
	,Time=AVISITN
	,Treat=TRT01PN
	,Catcov=SYSTRCRF
	,Cov = BASE
	);

	%part1B(Jobname=facit_mi
	,Ndraws=200
	,thin=100
	,seed=999
	);
		
	%part2A(Jobname=facit_mi_&endpoint., INName= facit_mi, MethodV= imp_method, Ref= 2)
	%part2B(Jobname=facit_mi_&endpoint., seed=999)

	data dat_ana_info;
	   set dat_ana_mi_&endpoint.;
	   keep acat1 acat1n usubjid avisitn ana_flag imp_method;
	run;
	proc sort data=dat_ana_info;
	   by ACAT1 ACAT1N USUBJID AVISITN;
	run;

	/* Derive AVISIT from AVISITN in DataFull (5macro output only has AVISITN) */
	data facit_mi_&endpoint._DataFull;
		set facit_mi_&endpoint._DataFull;
		length AVISIT $60.;
		AVISIT=put(AVISITN, avisitc.);
	run;

	proc sql; 
	create table facit_mi_&endpoint._full as
	select x.*, y.ACAT1, y.ACAT1N, y.ana_flag, y.imp_method 
	from facit_mi_&endpoint._DataFull as x left join dat_ana_info as y
	on x.usubjid = y.usubjid & x.avisitn=y.avisitn;
	quit;

	/* Recover ALMCF records as truly missing */
	data facit_mi_&endpoint.;
	   set facit_mi_&endpoint._full;
	   CHG=AVAL-BASE;
	   if imp_method="ALMCF" then do; CHG=.; AVAL=.; imp_method=''; end;
	run;

	proc sort data=facit_mi_&endpoint.;
		by USUBJID TRT01PN AVISIT;
	run;

	proc sort data=analysis.adfacit out=adfacit1;
      where paramcd="FACIT" and ANL01FL="Y" and AVISIT in ("Baseline","Day 14","Day 30","Day 90","Day 180");
		by USUBJID TRT01PN AVISIT;
	run;
	
	data adfacmi_&endpoint.;
		length AVISIT $60.;
		merge facit_mi_&endpoint.(in=a) adfacit1(in=b drop=AVAL CHG BASE);
		by USUBJID TRT01PN AVISIT;
		if a;
		if nmiss(AVAL,BASE)=0 then CHG=AVAL-BASE;
		IMPNUM=draw;
		length DTYPE $20.;
		DTYPE=imp_method;
		* truncate the values larger than maximum and smaller than minimum;
		if ^missing(aval) and ^missing(DTYPE) then do;
			if aval>52 then aval=52;
			if aval<0 then aval=0;
		end;
		AVISITN=input(AVISIT,avisit.);
	run;
%mend;


%facit_mi(endpoint=sec);
%facit_mi(endpoint=supp);


/* Re-merge EST/ICE variables from source (lost during MI macro processing) */
proc sql;
	create table adfacmi_sec1 as 
	select distinct a.*, b.EST01STP, b.ICE01F, b.IMPREA01
	from adfacmi_sec(DROP=EST01STP ICE01F IMPREA01) as a
	left join dat_ana2(where=(^missing(EST01STP))) as b 
	on a.USUBJID=b.USUBJID and a.AVISIT=b.AVISIT
	order by a.USUBJID
	;
quit;

proc sql;
	create table adfacmi_supp1 as 
	select distinct a.*, b.EST02STP, b.ICE02F, b.IMPREA02
	from adfacmi_supp(DROP=EST02STP ICE02F IMPREA02) as a
	left join dat_ana2(where=(^missing(EST02STP))) as b 
	on a.USUBJID=b.USUBJID and a.AVISIT=b.AVISIT
	order by a.USUBJID
	;
quit;

data adfacmi_comb1;
	length ana_flag $10.;
	set adfacmi_sec1 adfacmi_supp1 
	analysis.adfacit(where=(AVISIT="Baseline" and paramcd='FACIT'));
	by USUBJID;	
	drop ANL05FL ANL06FL ANL07FL AEFLAG;
run;


proc sql noprint;
	select distinct name into: dropvar separated by " "
	from sashelp.vcolumn where find(libname,"WORK") and memname="ADFACMI_COMB1"
	and (name^="USUBJID" and name in 
		(select distinct name from sashelp.vcolumn where find(libname,"ANALYSIS") and memname="ADSL"))
	;
quit;

data adfacmi_final;
	length PROEVFL $1.;
	merge adfacmi_comb1(in=a drop=&dropvar SYSTRCRF) analysis.ADSL analysis.adbs(keep=USUBJID SYSTRCRF);
	by USUBJID;
	if a;
	if missing(param) and missing(paramcd) then do;
		param='FACIT Fatigue score';
		paramcd='FACIT';
	end;

	/* Re-derive ANL flags based on EST variables (following ADUPRMI pattern exactly) */
    if (EST01STP='Hypothetical strategy' or EST02STP='Hypothetical strategy') and ANL05DT ne . then do;
      ANL05FL="Y";
      ANL05DSC="Record after initiation or intensification of anti-proteinuric therapies";
	end;
    if (EST01STP='Hypothetical strategy' or EST02STP='Treatment policy') and ANL06DT ne . then do;
      ANL06FL="Y";
      ANL06DSC="Record after initiation of RRT";
	end;
    if EST01STP='Treatment policy' or EST02STP='Treatment policy' then do;
	  ANL07FL="Y";
      ANL07DSC="Record after treatment discontinuation for any other reason";
	end;
	if AEDCDT NE . then do; AEFLAG='Y'; end;

	/* Derive IMPREAS based on ACAT1 */
	if dtype ne '' then do;
	  if ana_flag='sec' then IMPREAS=IMPREA01;
	  if ana_flag='supp' then IMPREAS=IMPREA02;
    end;

	if ^missing(BASE) and FASFL='Y' then PROEVFL='Y'; else PROEVFL='N';
	if paramcd='FACIT';
run;

*----------------------------------------------------------------------;
*set the final dataset
*do sorting;
*select avariable and apply format from PDS;
*----------------------------------------------------------------------;

%_std_varpadding_submission( calledby =
,in_lib = work
,out_lib = work
,include_ds = adfacmi_final
,exclude_ds =
);

%opSetAttr(domain=adfacmi, inData=adfacmi_final, metaData  = RPRTDSM.study_adam_metadata);
