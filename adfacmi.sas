/******************************************************************************* 
*            FILENAME : adfacmi.sas
*   PROGRAM DEVELOPER : Yijie Huang (huangy2e)                          
*                DATE : 2023-08-02                                                                                 
*  PROJECT/TRIAL CODE : CLNP023B1/CLNP023B12301
*  REPORTING ACTIVITY : CSR_1                                          
*         DESCRIPTION : To create adfacmi dataset                        
*            PLATFORM : GPSII and SAS 9.4                          
*          MACRO USED : N/A                         
*               INPUT : analysis.adsl, analysis.adfacit                       
*              OUTPUT : N/A                         
*               NOTES : N/A                         
*                                                                                                            
*  PROGRAMMING MODIFICATIONS HISTORY                                   
*  DATE        PROGRAMMER           DESCRIPTION                                                         
*  ---------   ----------------     ----------------------------------    
*  04Mar2024	huangy2e			modify data filtering for ANL01FL logic change
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
/*Import the analysis dataset*/
/*libname  analysis '/vob/CLNP023B1/CLNP023B12301/csr_1/analysis_data';*/
data dat_part;
      set analysis.adfacit;
      where ANL01FL="Y" and ^missing(base) and paramcd="FACIT" and AVISIT in ("Baseline","Day 14","Day 30","Day 90","Day 180");
      keep  usubjid trt01p trt01pn avisit _avisit avisitn paramcd param base chg aval 
		anl05fl anl05dsc anl05dt anl06fl anl06dsc anl06dt anl07fl anl07dsc anl07dt aeflag aedcdt adt ady; /*Keeping only variables which are needed*/
	  _avisit = tranwrd(cats(avisit)," ","_");
run;

/* Add the stratification variable */
data dat_str;
	set analysis.adbs;
	where fasfl="Y";
	keep usubjid systrcrf;
run;
proc sort data=dat_part;
	by usubjid;
run;
proc sort data=dat_str;
	by usubjid;
run;
data dat; 
	merge dat_part dat_str;
	by usubjid;
run; 

/* in case merge the stratification bring unlabeled data*/
data dat_ana;
	set dat;
	where trt01p NE ''; 
	nomisfl='Y';
	proc sort;
		by usubjid avisitn;
run;

/**************** As per SAP 5.2.1, impute the missing scheduled visits and visit date*****************/
proc sql;	
	create table usubjid as select distinct usubjid from dat_ana order by usubjid;
quit;

data full_visit;
	set usubjid;
	length avisit $50.;
	AVISIT='Baseline';output;
	AVISIT='Day 14';output;
	AVISIT='Day 30';output;
	AVISIT='Day 90';output;
	AVISIT='Day 180';output;
run;

proc sql;
	create table dat_ana1 as
	select b.* from dat_ana a right join full_visit b on a.usubjid=b.usubjid and a.avisit=b.avisit;

	* remerge common variables;
	create table dat_ana1_1 as
	select a.*, b.trt01p,b.trt01pn,b.paramcd,b.param,b.base,b.systrcrf from dat_ana1 a left join (
	select * from dat_ana(rename=(usubjid=usubjid_ avisit=avisit_)) where avisit_='Baseline') b
	on a.usubjid=b.usubjid_;

	create table dat_ana1_2 as
	select a.*, b.* from dat_ana1_1 a left join dat_ana(rename=(usubjid=usubjid_ avisit=avisit_) drop=trt01p trt01pn paramcd param base systrcrf) b on
	a.usubjid=b.usubjid_ and a.avisit=b.avisit_;
	* merge TR01SDT from adsl;

	create table dat_ana1_3 as
	select a.*,b.TR01SDT from dat_ana1_2 a left join analysis.adsl b on a.usubjid=b.usubjid;

quit;

* merge planned visit from SV;
data sv;
	set data_a.sv;
	format svdt date9.;
	svdt=input(svstdtc,yymmdd10.);
run;

proc sql;
	create table dat_ana1_4 as
	select a.*,b.svdt,b.svstdy from dat_ana1_3 a left join sv b on a.usubjid=b.usubjid and a.avisit=b.visit;
quit;

data dat_ana1_5;
	set dat_ana1_4;
	if missing(nomisfl) and missing(adt) and avisit ^= 'Baseline' then do;
		* impute date;
		if ^missing(svdt) then do;ady=svstdy;adt=svdt;end;
		if missing(svdt) then do; ady=input(scan(avisit,2),best.);adt=tr01sdt+ady;end;

		* impute flag;
		ANL05FL='';
		ANL05DSC='';
		ANL06FL='';
		ANL06DSC='';
		ANL07FL='';
		ANL07DSC='';

		if ^missing(ANL05DT) and ADT>ANL05DT then do; 
			ANL05FL='Y';
			ANL05DSC='Record after initiation or intensification of anti-proteinuric therapies';
		end;
		if ^missing(ANL06DT) and ADT>ANL06DT then do; 
			ANL06FL='Y';
			ANL06DSC='Record after initiation of RRT';
		end;
		if ^missing(ANL07DT) and ADT>ANL07DT then do; 
			ANL07FL='Y';
			ANL07DSC='Record after treatment discontinuation for any other reason';
		end;
	end;
run;


/*set the order of visit*/
proc format;
 invalue avisit
 "Day 14"=202
 "Day 30"=203
 "Day 90"=204
 "Day 180"=205;

 value  avisitc 
 202= "Day 14"
 203= "Day 30"
 204= "Day 90"
 205= "Day 180";
run;

/*remove baseline records*/
data dat_ana4;
	set dat_ana1_5;
	where avisit ^= "Baseline"; 
		AVISITN=input(AVISIT,avisit.);
run;



/**Mark the imputation methods according to SAP**/
/*anl05fl, RECORD LEVEL, IAT
anl06fl, RECORD LEVEL,RRT
aeflag, PATIENT LEVEL,DC due to AE/Death*/
/*secondary analysis*/
data dat_ana_mi_sec;
	set dat_ana4;
	length ACAT1 $50.;
	ACAT1="Secondary analysis 24";
	ACAT1N=1;
	ana_flag = "sec";
	if systrcrf="" then systrcrf="N";
	if aval=. then do imp_method="ALMCF"; end;
	/* the reason why doing this: 5macro will impute all missing data, otherwise error*/
	/* we will use one method for those no need for imputation, then set it to missing manually later*/
	if trt01p = "LNP023 200mg b.i.d." and (anl05fl="Y" OR anl06fl="Y")  then do aval=.; imp_method="J2R"; end;
	if trt01p = "LNP023 200mg b.i.d."  and aeflag="Y" and aval=. then do imp_method="J2R";end;
 	if trt01p = "Placebo" and  (anl05fl="Y" OR anl06fl="Y") then do aval=.; imp_method="MAR";end;
 	if trt01p = "Placebo" and aeflag="Y" and aval=. then do imp_method="MAR";end;
run;


/*supplementary analysis*/
data dat_ana_mi_supp;
	set dat_ana4;
	length ACAT1 $50.;
	ACAT1="Supplementary analysis 24.1";
	ACAT1N=2;
	ana_flag = "supp";
	if systrcrf="" then systrcrf="N";
	if aval=. then do imp_method="ALMCF"; end;/*we don't use it, but just for missing*/
	if trt01p = "LNP023 200mg b.i.d." and (anl06fl="Y")  then do aval=.; imp_method="J2R"; end;
	if trt01p = "LNP023 200mg b.i.d."  and aeflag="Y" and aval=. then do imp_method="J2R";end;
 	if trt01p = "Placebo" and  (anl06fl="Y") then do aval=.; imp_method="MAR";end;
 	if trt01p = "Placebo" and aeflag="Y" and aval=. then do imp_method="MAR";end;
run;

/***2.2Imputation step***/
/**imputation model: aval=trt*time+base+strfactor**/
/*secondary analysis*/

%macro facit_mi(endpoint=);
	%part1A(Jobname=facit_mi
	,Data=dat_ana_mi_&endpoint.
	,Subject=USUBJID
	,Response=AVAL
	,Time=AVISITN
	,Treat=TRT01PN
	,Catcov=SYSTRCRF
	,Cov = BASE
	/*,Covgroup=TRT01P corresponding to seperate variance-covaraince matrix for different arms*/
	);

	/*Ndraws=200 repsents the number of draws from the posterior distribution with a thining of 100 iterations;*/
	%part1B(Jobname=facit_mi
	,Ndraws=200 /*usually 200*/
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

	proc sql; 
	create table facit_mi_&endpoint._full as
	select x.*, y.ACAT1, y.ACAT1N, y.ana_flag, y.imp_method 
	from facit_mi_&endpoint._DataFull as x left join dat_ana_info as y
	on x.usubjid = y.usubjid & x.avisitn=y.avisitn;
	quit;

	/*recover missing due to administrative reasons as missing status*/
	data facit_mi_&endpoint.;
	   set facit_mi_&endpoint._full;
	   chg=aval-base;
	   if imp_method="ALMCF" then do chg=.; aval=.; imp_method=''; end;
	run;

	
	proc sort data=facit_mi_&endpoint.;
		by USUBJID TRT01PN AVISITN draw;
	run;

	proc sort data=analysis.adfacit out=adfacit1;
      where ANL01FL="Y" and paramcd="FACIT" and AVISIT in ("Baseline","Day 14","Day 30","Day 90","Day 180");
		by USUBJID TRT01PN AVISITN;
	run;
	
	data adfacmi_&endpoint.;
		
		merge facit_mi_&endpoint.(in=a) adfacit1(in=b drop=AVAL CHG BASE);
		by USUBJID TRT01PN AVISITN;
		if a;
		length DTYPE $20.;
		DTYPE=imp_method;
		* truncate the values larger than maximum and smaller than minimum;
		if ^missing(aval) and ^missing(DTYPE) then do;
			if aval>52 then aval=52;
			if aval<0 then aval=0;
		end;
		if nmiss(AVAL,BASE)=0 then CHG=AVAL-BASE;
		IMPNUM=draw;

		avisit=put(avisitn,avisitc.);
	run;
%mend;


%facit_mi(endpoint=sec);
%facit_mi(endpoint=supp);

data adfacmi_comb1;
	length ana_flag $10.;
	set adfacmi_sec adfacmi_supp 
	analysis.adfacit(where=(AVISIT="Baseline" and paramcd='FACIT'));
	by USUBJID;	

run;


/*Remerge ANL05/ANL06/AEFLAG*/
/*proc sql;*/
/*	create table adfacmi_comb1 as */
/*	select distinct a.*, b.ANL05FL, c.ANL06FL, d.AEFLAG*/
/*	from adfacmi_comb as a*/
/*	left join dat_ana1(where=(^missing(ANL05FL))) as b */
/*	on a.USUBJID=b.USUBJID and a.AVISIT=b.AVISIT*/
/*	left join dat_ana1(where=(^missing(ANL06FL))) as c */
/*	on a.USUBJID=c.USUBJID and a.AVISIT=c.AVISIT*/
/*	left join dat_ana1(where=(^missing(AEFLAG))) as d */
/*	on a.USUBJID=d.USUBJID*/
/*	order by a.USUBJID*/
/*	;*/
/*quit;*/

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


 请参考 /************************************************************************
*  PROJECT       : CLNP023B1
*  STUDY         : CLNP023B12301
*  RA            : csr_4
*  FILENAME      : aduprmi.sas

*  DATE CREATED  : 16Mar2026
*  AUTHOR        : Huiyu Luo

*  DESCRIPTION   : Create dataset aduprmi
*  PLATFORM      : AIX 7.2 (AIX 64) (see SAS log file)
*  SAS VERSION   : 9.4 (see SAS log file)

*  MACROS CALLED : None
*  INPUT         : ADUPCR, ADSL, ADBS
*  OUTPUT        : analysis.aduprmi

*  MODIFICATIONS : [x.xx] dd-mmm-yy, 5-2-1 id, brief description  
20231023 hudy1 to include handling I/C for missing assessment based on visit date or scheduled visit date
*************************************************************************/
/*Clean work library*/
proc datasets lib=work kill;
run;

/* GPS environment setup macro */;
data _null_;
    if libref('analysis') then call execute('%nrstr(%autorun;)');
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

/** Import the analysis dataset **/
data dat_part;
      set analysis.adupcr;
      where (PARAMCD="LGUPCR24" and AVISIT in ("Baseline","Day 90","Day 180") and (ANL01FL="Y" or aval=.))
      or (PARAMCD="LGUPCRFV" and AVISIT in ("Baseline","Day 14","Day 30","Day 90","Day 180") and (ANL01FL="Y" or aval=.));
      keep  USUBJID trt01pn avisit AVISITN _avisit PARAMCD PARAM base chg aval EST0: ICE0: IMPREA0: ANL05DT ANL06DT ANL07DT AEDCDT anl05fl anl06fl anl07fl aeflag; /*Keeping only variables which are needed*/
	  _avisit = tranwrd(cats(avisit)," ","_");
run;

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

/**************** simulation: create simulated dataset with the need for imputation *****************/
data dat_ana1;
	set dat_ana;
	where avisit ^= "Baseline"; /*remove baseline records*/
run;
data dat_ana_base;
	set dat_ana;
	where avisit = "Baseline"; 
run;
proc sort data=dat_ana_base;by usubjid;run;
proc sort data=dat_ana1;by usubjid;run;

data dat_ana2;
  merge dat_ana1 dat_ana_base(in=b keep=usubjid);
  by usubjid;
  if b;
run;


/**************** simulation: create simulated dataset with the need for imputation *****************/

/*set the order of visit*/
proc format;
 invalue avisit
 "Baseline"=99
 "Day 14"=202
 "Day 30"=203
 "Day 90"=204
 "Day 180"=205;
 value visit
 99="Baseline"
 202="Day 14"
 203="Day 30"
 204="Day 90"
 205="Day 180";
run;

proc sort data=dat_ana2;
	by USUBJID AVISITN;
run;


/* Mark the imputation methods according to SAP*/
/*primary analysis*/
data dat_ana_mi_pri;
	set dat_ana2;
	where PARAMCD="LGUPCR24";
	length ACAT1 $50.;
	ACAT1="Primary analysis";
	ACAT1N=1;
	ana_flag = "pri";
	IMPREAS=IMPREA01;
	if systrcrf="" then systrcrf="N";
	if imprea01='Missing data' or (EST01STP='Treatment policy' and aval=.) then imp_method='ALMCF';
	if trt01pn = 1 and EST01STP='Hypothetical strategy' then do;aval=.;chg=.; imp_method="J2R"; end;
	if trt01pn = 1 and AEDCDT NE . and imprea01='Missing data' then do;imp_method="J2R";end;
 	if trt01pn = 2 and EST01STP='Hypothetical strategy'  then do;aval=.;chg=.;  imp_method="MAR";end;
 	if trt01pn = 2 and AEDCDT NE . and imprea01='Missing data' then do;imp_method="MAR";end;
/*	if aval=. then do;imp_method="ALMCF"; end;*/
	/*we don't use it, but just for missing due to administrative reasons*/
/*	if trt01pn = 1 and (anl05fl="Y" OR anl06fl="Y")  then do;aval=.;aval=.; chg=.; imp_method="J2R"; end;*/
/*	if trt01pn = 1  and aeflag="Y" and aval=. then do;imp_method="J2R";end;*/
/* 	if trt01pn = 2 and  (anl05fl="Y" OR anl06fl="Y") then do;aval=.;aval=.;  chg=.;  imp_method="MAR";end;*/
/* 	if trt01pn = 2 and aeflag="Y" and aval=. then do;imp_method="MAR";end;*/
run;

/*Sensitivity analysis 1 */
/*data dat_ana_mi_sens1;*/
/*	set dat_ana4;*/
/*	where PARAMCD="LGUPCR24";*/
/*	length ACAT1 $50.;*/
/*	ACAT1="Sensitivity analysis 1";*/
/*	ACAT1N=2;*/
/*	ana_flag = "sec1";*/
/*	if systrcrf="" then systrcrf="N";*/
/*	if aval=. then do;imp_method="ALMCF"; end;*/
	/*we don't use it, but just for missing due to administrative reasons*/
/*	if trt01pn = 1 and anl05fl="Y" then do;aval=.;aval=.; chg=.; imp_method="MAR"; end;*/
/*	if trt01pn = 1 and anl06fl="Y" then do;aval=.;aval=.; chg=.; imp_method="J2R"; end;*/
/*	if trt01pn = 1  and aeflag="Y" and aval=. then do;imp_method="J2R";end;*/
/* 	if trt01pn = 2 and anl05fl="Y" then do;aval=.;aval=.;  chg=.;  imp_method="MAR";end;*/
/* 	if trt01pn = 2 and anl06fl="Y" then do;aval=.;aval=.;  chg=.;  imp_method="MAR";end;*/
/* 	if trt01pn = 2 and aeflag="Y" and aval=. then do;imp_method="MAR";end;*/
/*run;*/

/*Sensitivity analysis 2 */
/*data dat_ana_mi_sens2;*/
/*	set dat_ana4;*/
/*	where PARAMCD="LGUPCR24";*/
/*	length ACAT1 $50.;*/
/*	ACAT1="Sensitivity analysis 2";*/
/*	ACAT1N=3;*/
/*	ana_flag = "sec2";*/
/*	if systrcrf="" then systrcrf="N";*/
/*	if aval=. then do;imp_method="ALMCF"; end;*/
	/*we don't use it, but just for missing due to administrative reasons*/
/*	if trt01pn = 1 and anl05fl="Y" then do;aval=.;aval=.; chg=.; imp_method="CR"; end;*/
/*	if trt01pn = 1 and anl06fl="Y" then do;aval=.;aval=.; chg=.; imp_method="J2R"; end;*/
/*	if trt01pn = 1  and aeflag="Y" and aval=. then do;imp_method="J2R";end;*/
/* 	if trt01pn = 2 and anl05fl="Y" then do;aval=.;aval=.;  chg=.;  imp_method="MAR";end;*/
/* 	if trt01pn = 2 and anl06fl="Y" then do;aval=.;aval=.;  chg=.;  imp_method="MAR";end;*/
/* 	if trt01pn = 2 and aeflag="Y" and aval=. then do;imp_method="MAR";end;*/
/*run;*/

/*supplementary analysis 1*/
data dat_ana_mi_supp1;
	set dat_ana2;
	where PARAMCD="LGUPCR24";
	length ACAT1 $50.;
	ACAT1="Supplementary analysis 1";
	ACAT1N=2;
	ana_flag = "supp1";
	IMPREAS=IMPREA02;
	if systrcrf="" then systrcrf="N";
	if imprea02='Missing data' or (EST02STP='Treatment policy' and aval=.) then imp_method='ALMCF';
	if trt01pn = 1 and EST02STP='Hypothetical strategy' then do;aval=.;chg=.; imp_method="J2R"; end;
	if trt01pn = 1  and AEDCDT NE . and imprea02='Missing data' then do;imp_method="J2R";end;
 	if trt01pn = 2 and EST02STP='Hypothetical strategy' then do;aval=.;chg=.; imp_method="MAR"; end;
 	if trt01pn = 2 and AEDCDT NE . and imprea02='Missing data' then do;imp_method="MAR";end;
/*	if aval=. then do;imp_method="ALMCF"; end;*/
	/*we don't use it, but just for missing*/
/*	if trt01pn = 1 and (anl06fl="Y")  then do;aval=.;aval=.; chg=.; imp_method="J2R"; end;*/
/*	if trt01pn = 1  and aeflag="Y" and aval=. then do;imp_method="J2R";end;*/
/* 	if trt01pn = 2 and  (anl06fl="Y") then do;aval=.;aval=.;  chg=.; imp_method="MAR"; end;*/
/* 	if trt01pn = 2 and aeflag="Y" and aval=. then do;imp_method="MAR";end;*/
run;

/*Supplementary  analysis 2*/
data dat_ana_mi_supp2;
	set dat_ana2;
	where PARAMCD="LGUPCRFV";
	length ACAT1 $50.;
	ACAT1="Supplementary analysis 2";
	ACAT1N=3;
	ana_flag = "supp2";
	IMPREAS=IMPREA03;
	if systrcrf="" then systrcrf="N";
	if imprea03='Missing data' or (EST03STP='Treatment policy' and aval=.) then imp_method='ALMCF';
	if trt01pn = 1 and EST03STP='Hypothetical strategy' then do;aval=.;chg=.; imp_method="J2R"; end;
	if trt01pn = 1 and AEDCDT NE . and imprea03='Missing data' then do;imp_method="J2R";end;
 	if trt01pn = 2 and EST03STP='Hypothetical strategy'  then do;aval=.;chg=.;  imp_method="MAR";end;
 	if trt01pn = 2 and AEDCDT NE . and imprea03='Missing data' then do;imp_method="MAR";end;
/*	if aval=. then do;imp_method="ALMCF"; end;*/
	/*we don't use it, but just for missing due to administrative reasons*/
/*	if trt01pn = 1 and (anl05fl="Y" OR anl06fl="Y")  then do;aval=.;aval=.; chg=.; imp_method="J2R"; end;*/
/*	if trt01pn = 1  and aeflag="Y" and aval=. then do;imp_method="J2R";end;*/
/* 	if trt01pn = 2 and  (anl05fl="Y" OR anl06fl="Y") then do;aval=.;aval=.;  chg=.;  imp_method="MAR";end;*/
/* 	if trt01pn = 2 and aeflag="Y" and aval=. then do;imp_method="MAR";end;*/
run;

/************************************* Imputation section *************************************/
/**imputation model: log(UPCR)=trt*time+log(base)+stratification factor(not crossing with time)**/
/*secondary analysis*/

%macro upcr_mi(endpoint= );
	%part1A(Jobname=upcr_mi
	,Data=dat_ana_mi_&endpoint.
	,Subject=USUBJID
	,Response=AVAL
	,Time=AVISITN
	,Treat=TRT01PN
	,Catcov=SYSTRCRF
	,Cov = BASE
	/*,Covgroup=TRT01P corresponding to seperate variance-covaraince matrix for different arms*/
	);
	
	/*Ndraws repsents the number of draws from the posterior distribution with a thining of 100 iterations;*/
	%part1B(Jobname=upcr_mi
	,Ndraws=200 /*usually 200, for simple test run, 20 is used here*/
	,thin=100
	,seed=999
	);
		
	%part2A(Jobname=upcr_mi_&endpoint., INName= upcr_mi, MethodV= imp_method, Ref= 2)
	%part2B(Jobname=upcr_mi_&endpoint., seed=999)
	
	data dat_ana_info;
	   set dat_ana_mi_&endpoint.;
	   keep ACAT1 ACAT1N PARAMCD PARAM USUBJID avisit ana_flag imp_method /* ANL05FL ANL06FL AEFLAG */;
	run;
	proc sort data=dat_ana_info;
	   by ACAT1 ACAT1N PARAMCD PARAM USUBJID AVISIT;
	run;

	data upcr_mi_&endpoint._DataFull;
		set upcr_mi_&endpoint._DataFull;
		length AVISIT $60.;
		AVISIT=put(AVISITN, visit.);
	run;

	proc sql; 
	create table upcr_mi_&endpoint._full as
	select x.*, y.ACAT1, y.ACAT1N, y.PARAMCD, y. PARAM, y.ana_flag, y.imp_method/* , y.ANL05FL, y.ANL06FL, y.AEFLAG */
	from upcr_mi_&endpoint._DataFull as x left join dat_ana_info as y
	on x.USUBJID = y.USUBJID & x.avisit=y.avisit;
	quit;
	
	data upcr_mi_&endpoint.;
	   set upcr_mi_&endpoint._full;
	   CHG=AVAL-BASE;
	   if imp_method="ALMCF" then do;CHG=.;AVAL=.; imp_method=''; end;/*recover missing due to administrative reasons as missing status*/
	run;
	
	proc sort data=upcr_mi_&endpoint.;
		by USUBJID TRT01PN AVISIT;
	run;
	
	%if &endpoint^=supp2 %then %do;
	proc sort data=analysis.adupcr out=adupcr1;
      where PARAMCD="LGUPCR24" and ANL01FL="Y" and AVISIT in ("Baseline","Day 90","Day 180");
		by USUBJID TRT01PN AVISIT;
	run;
	%end;
	%else %do;
	proc sort data=analysis.adupcr out=adupcr1;
      where PARAMCD="LGUPCRFV" and ANL01FL="Y" and AVISIT in ("Baseline","Day 14","Day 30","Day 90","Day 180");
		by USUBJID TRT01PN AVISIT;
	run;
	%end;
	
	data aduprmi_&endpoint.;
		length AVISIT $60.;
		merge upcr_mi_&endpoint.(in=a) adupcr1(in=b drop=AVAL CHG BASE);
		by USUBJID TRT01PN AVISIT;
		if a;
		if nmiss(AVAL,BASE)=0 then CHG=AVAL-BASE;
		IMPNUM=draw;
		length DTYPE $20.;
		DTYPE=imp_method;
		AVISITN=input(AVISIT,avisit.);
	run;
	
%mend;

%upcr_mi(endpoint=pri);
/*%upcr_mi(endpoint=sens1);*/
/*%upcr_mi(endpoint=sens2);*/
%upcr_mi(endpoint=supp1);
%upcr_mi(endpoint=supp2);

/*Remerge ANL05/ANL06/AEFLAG*/
/*proc sql;*/
/*	create table aduprmi_comb1 as */
/*	select distinct a.*, b.ANL05FL,  c.ANL06FL,  e.ANL07FL,  d.AEFLAG */
/*	from aduprmi_comb as a*/
/*	left join dat_ana4(where=(^missing(ANL05FL))) as b */
/*	on a.USUBJID=b.USUBJID and a.AVISIT=b.AVISIT and a.PARAMCD=b.PARAMCD*/
/*	left join dat_ana4(where=(^missing(ANL06FL))) as c */
/*	on a.USUBJID=c.USUBJID and a.AVISIT=c.AVISIT and a.PARAMCD=c.PARAMCD*/
/*	left join dat_ana4(where=(^missing(ANL07FL))) as e */
/*	on a.USUBJID=e.USUBJID and a.AVISIT=e.AVISIT and a.PARAMCD=e.PARAMCD*/
/*	left join dat_ana4(where=(^missing(AEFLAG))) as d */
/*	on a.USUBJID=d.USUBJID and a.PARAMCD=d.PARAMCD*/
/*	order by a.USUBJID*/
/*	;*/
/*quit;*/
proc sql;
	create table aduprmi_pri1 as 
	select distinct a.*, b.EST01STP, b.ICE01F, b.IMPREA01
	from aduprmi_pri(DROP=EST01STP ICE01F IMPREA01) as a
	left join dat_ana2(where=(^missing(EST01STP))) as b 
	on a.USUBJID=b.USUBJID and a.AVISIT=b.AVISIT and a.PARAMCD=b.PARAMCD
	order by a.USUBJID
	;
quit;

proc sql;
	create table aduprmi_supp11 as 
	select distinct a.*, b.EST02STP, b.ICE02F, b.IMPREA02
	from aduprmi_supp1(DROP=EST02STP ICE02F IMPREA02)  as a
	left join dat_ana2(where=(^missing(EST02STP))) as b 
	on a.USUBJID=b.USUBJID and a.AVISIT=b.AVISIT and a.PARAMCD=b.PARAMCD
	order by a.USUBJID
	;
quit;

proc sql;
	create table aduprmi_supp21 as 
	select distinct a.*, b.EST03STP, b.ICE03F, b.IMPREA03
	from aduprmi_supp2(DROP=EST03STP ICE03F IMPREA03)  as a
	left join dat_ana2(where=(^missing(EST03STP))) as b 
	on a.USUBJID=b.USUBJID and a.AVISIT=b.AVISIT and a.PARAMCD=b.PARAMCD
	order by a.USUBJID
	;
quit;

data aduprmi_comb;
	length ana_flag $10.;
	set aduprmi_pri1 /*aduprmi_sens1 aduprmi_sens2*/ aduprmi_supp11 aduprmi_supp21 
	analysis.adupcr(where=(PARAMCD in ("LGUPCR24","LGUPCRFV") and AVISIT="Baseline"));
	by USUBJID;	
	drop ANL05FL ANL06FL ANL07FL AEFLAG;
run;

/*proc sql;*/
/*	create table aduprmi_comb1 as */
/*	select distinct a.*, b.ANL05FL,  c.ANL06FL,  e.ANL07FL,  d.AEFLAG */
/*	from aduprmi_comb as a*/
/*	left join dat_ana2(where=(^missing(ANL05FL))) as b */
/*	on a.USUBJID=b.USUBJID and a.AVISIT=b.AVISIT and a.PARAMCD=b.PARAMCD*/
/*	left join dat_ana2(where=(^missing(ANL06FL))) as c */
/*	on a.USUBJID=c.USUBJID and a.AVISIT=c.AVISIT and a.PARAMCD=c.PARAMCD*/
/*	left join dat_ana2(where=(^missing(ANL07FL))) as e */
/*	on a.USUBJID=e.USUBJID and a.AVISIT=e.AVISIT and a.PARAMCD=e.PARAMCD*/
/*	left join dat_ana2(where=(^missing(AEFLAG))) as d */
/*	on a.USUBJID=d.USUBJID and a.PARAMCD=d.PARAMCD*/
/*	order by a.USUBJID*/
/*	;*/
/*quit;*/
proc sql noprint;
	select distinct name into: dropvar separated by " "
	from sashelp.vcolumn where find(libname,"WORK") and memname="ADUPRMI_COMB1"
	and (name^="USUBJID" and name in 
		(select distinct name from sashelp.vcolumn where find(libname,"ANALYSIS") and memname="ADSL"))
	;
quit;

data aduprmi_final;
	merge aduprmi_comb(in=a drop=&dropvar SYSTRCRF) analysis.ADSL analysis.adbs(keep=USUBJID SYSTRCRF);
	by USUBJID;
	if a;
    if (EST01STP='Hypothetical strategy' or EST02STP='Hypothetical strategy' or EST03STP='Hypothetical strategy') and ANL05DT ne . then do;
      ANL05FL="Y";
      ANL05DSC="Record after initiation or intensification of anti-proteinuric therapies";
	end;
    if (EST01STP='Hypothetical strategy' or EST02STP='Treatment policy' or EST03STP='Hypothetical strategy') and ANL06DT ne .  then do;
      ANL06FL="Y";
      ANL06DSC="Record after initiation of RRT";
	end;
    if EST01STP='Treatment policy' or EST02STP='Treatment policy' or EST03STP='Treatment policy' then do;
	  ANL07FL="Y";
      ANL07DSC="Record after treatment discontinuation for any other reason";
	end;
	if AEDCDT NE . then do;AEFLAG='Y';end;
	if dtype ne '' then do;
	  if ana_flag='pri' then IMPREAS=IMPREA01;
	  if ana_flag='supp1' then IMPREAS=IMPREA02;
	  if ana_flag='supp2' then IMPREAS=IMPREA03;
    end;
/*    if ANL05FL="Y" then ANL05DSC="Record after initiation or intensification of anti-proteinuric therapies";*/
/*    if ANL06FL="Y" then ANL06DSC="Record after initiation of RRT";*/
/*    if ANL07FL="Y" then ANL07DSC="Record after treatment discontinuation for any other reason";*/
run;

*----------------------------------------------------------------------;
*set the final dataset
*do sorting;
*select avariable and apply format from PDS;
*----------------------------------------------------------------------;
/*proc sort data=analysis.aduprmi out=dev; by USUBJID SUBJID ACAT1N  PARAMCD AVISITN IMPNUM;run;*/
/*proc sort data=aduprmi_final; by USUBJID SUBJID ACAT1N  PARAMCD AVISITN IMPNUM;run;*/
/**/
/*PROC COMPARE BASE=dev COMPARE=aduprmi_final LISTALL;*/
/*RUN;*/

%_std_varpadding_submission( calledby =
,in_lib = work
,out_lib = work
,include_ds = aduprmi_final
,exclude_ds =
);


%opSetAttr(domain=aduprmi, inData=aduprmi_final, metaData  = RPRTDSM.study_adam_metadata);
PDS更新了，然后ADUPCR， ADUPRMI也先出了一版，你可以参考，大概的逻辑就是我们之前是在MI里面dummy了planed的visit，现在给换成在原始的数据集里给先dummy好，这样MI里就可以直接用 然后53	20250402	Huiyu Luo	ADEGRMI	IMPREAS	Add variable IMPREAS	
ADEGRMI	IMPREAS	Imputation Rason	C					15				Predecessor		Set to IMPREA01, IMPREA02, IMPREA03 based on  ACAT1																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																																							
请仔细思考 提供修改补丁

The SAS System

1        
                                                   The FREQ Procedure                                                               
                                                                        Cumulative    Cumulative                                    
                        PARAMCD    AVISIT      Frequency     Percent     Frequency      Percent                                     
                        ------------------------------------------------------------------------                                    
                        FACIT      Baseline          21       14.29            21        14.29                                      
                        FACIT      Day 1              2        1.36            23        15.65                                      
                        FACIT      Day 14            25       17.01            48        32.65                                      
                        FACIT      Day 180           14        9.52            62        42.18                                      
                        FACIT      Day 210           15       10.20            77        52.38                                      
                        FACIT      Day 270           12        8.16            89        60.54                                      
                        FACIT      Day 30            25       17.01           114        77.55                                      
                        FACIT      Day 360           10        6.80           124        84.35                                      
                        FACIT      Day 90            23       15.65           147       100.00                                      
 
 
                                                           E                I              E                I                       
                    U             P           A            S                M              S                M                       
                    S             A     A     V            T         I      P              T         I      P                       
                    U             R     V     I            0         C      R              0         C      R                       
                    B             A     I     S   B        1         E      E              2         E      E                       
       O            J             M     S     I   A        S         0      A              S         0      A                       
       b            I             C     I     T   S        T         1      0              T         2      0                       
       s            D             D     T     N   E        P         F      1              P         F      2                       
       97 CLNP023B12301_1001010 FACIT Day 90 204 47                    Missing data                    Missing data                 
      146 CLNP023B12301_1002004 FACIT Day 90 204 44                    Missing data                    Missing data                 
      371 CLNP023B12301_2054004 FACIT Day 30 203 49                    Missing data                    Missing data                 
      532 CLNP023B12301_3311003 FACIT Day 90 204 43                    Missing data                    Missing data                 
     1781 CLNP023B12301_5016001 FACIT Day 90 204 52 Treatment policy Y Missing data Treatment policy Y Missing data                 
 
 
                                                   The FREQ Procedure                                                               
                                                                       Cumulative    Cumulative                                     
                         PARAMCD    ICE01F    Frequency     Percent     Frequency      Percent                                      
                         ----------------------------------------------------------------------                                     
                         FACIT                     145       98.64           145        98.64                                       
                         FACIT      Y                2        1.36           147       100.00                                       

                                                                       Cumulative    Cumulative                                     
                         PARAMCD    ICE02F    Frequency     Percent     Frequency      Percent                                      
                         ----------------------------------------------------------------------                                     
                         FACIT                     145       98.64           145        98.64                                       
                         FACIT      Y                2        1.36           147       100.00                                       
 
 
   Obs         USUBJID         PARAMCD    AVISIT          ADT     ANL07DT  ANL07FL      EST01STP          EST02STP                  
  1781  CLNP023B12301_5016001  FACIT     Day 90                2024-11-04     Y     Treatment policy  Treatment policy              
  1782  CLNP023B12301_5016001  FAC07008  Baseline  2024-08-13  2024-11-04                                                           
  1783  CLNP023B12301_5016001  FAC07008  Day 14    2024-08-27  2024-11-04                                                           
  1784  CLNP023B12301_5016001  FAC07008  Day 30    2024-09-12  2024-11-04                                                           
  1785  CLNP023B12301_5016001  FAC07008  Day 360   2024-11-26  2024-11-04     Y                                                     
  1786  CLNP023B12301_5016001  FAC07012  Baseline  2024-08-13  2024-11-04                                                           
  1787  CLNP023B12301_5016001  FAC07012  Day 14    2024-08-27  2024-11-04                                                           
  1788  CLNP023B12301_5016001  FAC07012  Day 30    2024-09-12  2024-11-04                                                           
  1789  CLNP023B12301_5016001  FAC07012  Day 360   2024-11-26  2024-11-04     Y                                                     
  1790  CLNP023B12301_5016001  FAC07010  Baseline  2024-08-13  2024-11-04                                                           
  1791  CLNP023B12301_5016001  FAC07010  Day 14    2024-08-27  2024-11-04                                                           
  1792  CLNP023B12301_5016001  FAC07010  Day 30    2024-09-12  2024-11-04                                                           
  1793  CLNP023B12301_5016001  FAC07010  Day 360   2024-11-26  2024-11-04     Y                                                     
  1794  CLNP023B12301_5016001  FAC07001  Baseline  2024-08-13  2024-11-04                                                           
  1795  CLNP023B12301_5016001  FAC07001  Day 14    2024-08-27  2024-11-04                                                           
  1796  CLNP023B12301_5016001  FAC07001  Day 30    2024-09-12  2024-11-04                                                           
  1797  CLNP023B12301_5016001  FAC07001  Day 360   2024-11-26  2024-11-04     Y                                                     
  1798  CLNP023B12301_5016001  FAC07003  Baseline  2024-08-13  2024-11-04                                                           
  1799  CLNP023B12301_5016001  FAC07003  Day 14    2024-08-27  2024-11-04                                                           
  1800  CLNP023B12301_5016001  FAC07003  Day 30    2024-09-12  2024-11-04                                                           
  1801  CLNP023B12301_5016001  FAC07003  Day 360   2024-11-26  2024-11-04     Y                                                     
  1802  CLNP023B12301_5016001  FAC07004  Baseline  2024-08-13  2024-11-04                                                           
  1803  CLNP023B12301_5016001  FAC07004  Day 14    2024-08-27  2024-11-04                                                           
  1804  CLNP023B12301_5016001  FAC07004  Day 30    2024-09-12  2024-11-04                                                           
  1805  CLNP023B12301_5016001  FAC07004  Day 360   2024-11-26  2024-11-04     Y                                                     
  1806  CLNP023B12301_5016001  FAC07002  Baseline  2024-08-13  2024-11-04                                                           
  1807  CLNP023B12301_5016001  FAC07002  Day 14    2024-08-27  2024-11-04                                                           
  1808  CLNP023B12301_5016001  FAC07002  Day 30    2024-09-12  2024-11-04                                                           
  1809  CLNP023B12301_5016001  FAC07002  Day 360   2024-11-26  2024-11-04     Y                                                     
  1810  CLNP023B12301_5016001  FAC07007  Baseline  2024-08-13  2024-11-04                                                           
  1811  CLNP023B12301_5016001  FAC07007  Day 14    2024-08-27  2024-11-04                                                           
  1812  CLNP023B12301_5016001  FAC07007  Day 30    2024-09-12  2024-11-04                                                           
  1813  CLNP023B12301_5016001  FAC07007  Day 360   2024-11-26  2024-11-04     Y                                                     
  1814  CLNP023B12301_5016001  FAC07009  Baseline  2024-08-13  2024-11-04                                                           
  1815  CLNP023B12301_5016001  FAC07009  Day 14    2024-08-27  2024-11-04                                                           
  1816  CLNP023B12301_5016001  FAC07009  Day 30    2024-09-12  2024-11-04                                                           
  1817  CLNP023B12301_5016001  FAC07009  Day 360   2024-11-26  2024-11-04     Y                                                     
  1818  CLNP023B12301_5016001  FAC07013  Baseline  2024-08-13  2024-11-04                                                           
  1819  CLNP023B12301_5016001  FAC07013  Day 14    2024-08-27  2024-11-04                                                           
  1820  CLNP023B12301_5016001  FAC07013  Day 30    2024-09-12  2024-11-04                                                           
   ;*';*";*/;quit;run;
2          OPTIONS PAGENO=MIN;
3          %LET _CLIENTTASKLABEL='adfacmi.sas';
4          %LET _CLIENTPROCESSFLOWNAME='Process Flow';
5          %LET _CLIENTPROJECTPATH='Y:\clnp023b_adam.egp';
6          %LET _CLIENTPROJECTPATHHOST='GLCHBS-TP320196';
7          %LET _CLIENTPROJECTNAME='clnp023b_adam.egp';
8          %LET _SASPROGRAMFILE='V:\zhaibe1_view\CLNP023B1\CLNP023B12301\csr_4\pgm\data\adfacmi.sas';
9          %LET _SASPROGRAMFILEHOST='GLCHBS-TP320196';
10         
11         ODS _ALL_ CLOSE;
12         OPTIONS DEV=SVG;
13         GOPTIONS XPIXELS=0 YPIXELS=0;
14         %macro HTML5AccessibleGraphSupported;
15             %if %_SAS_VERCOMP_FV(9,4,4, 0,0,0) >= 0 %then ACCESSIBLE_GRAPH;
16         %mend;
17         FILENAME EGHTML TEMP;
18         ODS HTML5(ID=EGHTML) FILE=EGHTML
19             OPTIONS(BITMAP_MODE='INLINE')
20             %HTML5AccessibleGraphSupported
21             ENCODING='utf-8'
22             STYLE=HTMLBlue
23             NOGTITLE
24             NOGFOOTNOTE
25             GPATH=&sasworklocation
26         ;
NOTE: Writing HTML5(EGHTML) Body file: EGHTML
27         
28         %macro __before();
29         
30         %if %upcase(&_clientprocessflowname.)^='AUTOEXEC' and %upcase(&sysscp.)=WIN %then %do;
31         
32         %unquote(%str(rsubm)%str(it));
33         
34         %end;
35         
36         %mend __before;
37         
38         %__before;
NOTE: Remote submit to T1 commencing.
21770   /*******************************************************************************
21771  *            FILENAME : adfacmi.sas
21772  *   PROGRAM DEVELOPER : Yijie Huang (huangy2e)
21773  *                DATE : 2023-08-02
21774  *  PROJECT/TRIAL CODE : CLNP023B1/CLNP023B12301
21775  *  REPORTING ACTIVITY : CSR_1
21776  *         DESCRIPTION : To create adfacmi dataset
21777  *            PLATFORM : GPSII and SAS 9.4
21778  *          MACRO USED : N/A
21779  *               INPUT : analysis.adsl, analysis.adfacit
21780  *              OUTPUT : N/A
21781  *               NOTES : N/A
21782  *
21783  *  PROGRAMMING MODIFICATIONS HISTORY
21784  *  DATE        PROGRAMMER           DESCRIPTION
21785  *  ---------   ----------------     ----------------------------------
21786  *  04Mar2024 huangy2e   modify data filtering for ANL01FL logic change
21787  *  DDMonYYYY XXXXXXXX   Update to use pre-dummy visits from ADFACIT; use EST/ICE/IMPREA variables; add IMPREAS
21788  *******************************************************************************/
21789  
21790  
21791  /************************************* Preparation section *************************************/
21792  %macro check_autorun;
21793   %if %sysfunc(libref(data_a)) ne 0 %then %do; %autorun; %end;
21794  %mend check_autorun;
2                                                          The SAS System                            04:10 Wednesday, April 15, 2026

21795  %check_autorun;
21796  
21797  proc datasets lib=work kill memtype=data;
 
                                                       Directory

                       Libref             WORK                                                   
                       Engine             V9                                                     
                       Physical Name      /saswork/SAS_work079C01A00128_CHBS-SPAPP03.novartis.net
                       Filename           /saswork/SAS_work079C01A00128_CHBS-SPAPP03.novartis.net
                       Inode Number       467124                                                 
                       Access Permission  rwx------                                              
                       Owner Name         zhaibe1                                                
                       File Size          4KB                                                    
                       File Size (bytes)  4096                                                   


                                                 Member
                      #  Name                    Type       File Size  Last Modified

                      1  ADFACIT1                DATA           216KB  04/15/2026 05:08:55        
                      2  ADFACMI_COMB1           DATA           144KB  04/15/2026 05:08:55        
                      3  ADFACMI_FINAL           DATA           128KB  04/15/2026 05:08:55        
                      4  ADFACMI_SEC             DATA           144KB  04/15/2026 05:08:46        
                      5  ADFACMI_SEC1            DATA           144KB  04/15/2026 05:08:55        
                      6  ADFACMI_SUPP            DATA           144KB  04/15/2026 05:08:55        
                      7  ADFACMI_SUPP1           DATA           144KB  04/15/2026 05:08:55        
                      8  DAT                     DATA           128KB  04/15/2026 05:08:38        
                      9  DAT_ANA                 DATA           128KB  04/15/2026 05:08:38        
                     10  DAT_ANA4                DATA           128KB  04/15/2026 05:08:38        
                     11  DAT_ANA_BASE            DATA           128KB  04/15/2026 05:08:38        
                     12  DAT_ANA_INFO            DATA           128KB  04/15/2026 05:08:55        
                     13  DAT_ANA_MI_SEC          DATA           128KB  04/15/2026 05:08:38        
                     14  DAT_ANA_MI_SUPP         DATA           128KB  04/15/2026 05:08:38        
                     15  DAT_PART                DATA           128KB  04/15/2026 05:08:38        
                     16  DAT_STR                 DATA           128KB  04/15/2026 05:08:38        
                     17  FACIT_MI_DATAP          DATA           128KB  04/15/2026 05:08:47        
                     18  FACIT_MI_DATAV          DATA           128KB  04/15/2026 05:08:46        
                     19  FACIT_MI_MASTER         DATA           128KB  04/15/2026 05:08:55        
                     20  FACIT_MI_PATTERNS       DATA           128KB  04/15/2026 05:08:46        
                     21  FACIT_MI_POSTCVP        DATA           128KB  04/15/2026 05:08:55        
                     22  FACIT_MI_POSTLP         DATA           256KB  04/15/2026 05:08:55        
                     23  FACIT_MI_SEC            DATA           128KB  04/15/2026 05:08:46        
                     24  FACIT_MI_SEC_DATAFULL   DATA           128KB  04/15/2026 05:08:46        
                     25  FACIT_MI_SEC_DATAPM     DATA           128KB  04/15/2026 05:08:46        
                     26  FACIT_MI_SEC_MASTER     DATA           128KB  04/15/2026 05:08:46        
                     27  FACIT_MI_SEC_NEWBITS    DATA           128KB  04/15/2026 05:08:46        
                     28  FACIT_MI_SEC_TEMP39     DATA           128KB  04/15/2026 05:08:46        
                                                 Member
                      #  Name                    Type       File Size  Last Modified

                     29  FACIT_MI_SEC_TEMP40     DATA           128KB  04/15/2026 05:08:46        
                     30  FACIT_MI_SEC_TEMP41     DATA           128KB  04/15/2026 05:08:46        
                     31  FACIT_MI_SEC_TEMP42     DATA           128KB  04/15/2026 05:08:46        
                     32  FACIT_MI_SEC_TEMP51     DATA           128KB  04/15/2026 05:08:46        
                     33  FACIT_MI_SUPP           DATA           128KB  04/15/2026 05:08:55        
                     34  FACIT_MI_SUPP_DATAFULL  DATA           128KB  04/15/2026 05:08:55        
                     35  FACIT_MI_SUPP_DATAPM    DATA           128KB  04/15/2026 05:08:55        
3                                                          The SAS System                            04:10 Wednesday, April 15, 2026

                     36  FACIT_MI_SUPP_MASTER    DATA           128KB  04/15/2026 05:08:55        
                     37  FACIT_MI_SUPP_NEWBITS   DATA           128KB  04/15/2026 05:08:55        
                     38  FACIT_MI_SUPP_TEMP39    DATA           128KB  04/15/2026 05:08:55        
                     39  FACIT_MI_SUPP_TEMP40    DATA           128KB  04/15/2026 05:08:55        
                     40  FACIT_MI_SUPP_TEMP41    DATA           128KB  04/15/2026 05:08:55        
                     41  FACIT_MI_SUPP_TEMP42    DATA           128KB  04/15/2026 05:08:55        
                     42  FACIT_MI_SUPP_TEMP51    DATA           128KB  04/15/2026 05:08:55        
                     43  FUNCS                   DATA           320KB  04/15/2026 05:08:38        
                         FUNCS                   INDEX           24KB  04/15/2026 05:08:38        
NOTE: Deleting WORK.ADFACIT1 (memtype=DATA).
NOTE: Deleting WORK.ADFACMI_COMB1 (memtype=DATA).
NOTE: Deleting WORK.ADFACMI_FINAL (memtype=DATA).
NOTE: Deleting WORK.ADFACMI_SEC (memtype=DATA).
NOTE: Deleting WORK.ADFACMI_SEC1 (memtype=DATA).
NOTE: Deleting WORK.ADFACMI_SUPP (memtype=DATA).
NOTE: Deleting WORK.ADFACMI_SUPP1 (memtype=DATA).
NOTE: Deleting WORK.DAT (memtype=DATA).
NOTE: Deleting WORK.DAT_ANA (memtype=DATA).
NOTE: Deleting WORK.DAT_ANA4 (memtype=DATA).
NOTE: Deleting WORK.DAT_ANA_BASE (memtype=DATA).
NOTE: Deleting WORK.DAT_ANA_INFO (memtype=DATA).
NOTE: Deleting WORK.DAT_ANA_MI_SEC (memtype=DATA).
NOTE: Deleting WORK.DAT_ANA_MI_SUPP (memtype=DATA).
NOTE: Deleting WORK.DAT_PART (memtype=DATA).
NOTE: Deleting WORK.DAT_STR (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_DATAP (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_DATAV (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_MASTER (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_PATTERNS (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_POSTCVP (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_POSTLP (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SEC (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SEC_DATAFULL (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SEC_DATAPM (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SEC_MASTER (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SEC_NEWBITS (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SEC_TEMP39 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SEC_TEMP40 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SEC_TEMP41 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SEC_TEMP42 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SEC_TEMP51 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SUPP (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SUPP_DATAFULL (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SUPP_DATAPM (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SUPP_MASTER (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SUPP_NEWBITS (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SUPP_TEMP39 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SUPP_TEMP40 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SUPP_TEMP41 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SUPP_TEMP42 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SUPP_TEMP51 (memtype=DATA).
NOTE: Deleting WORK.FUNCS (memtype=DATA).
21798  run;

21799  
21800  
21801  %let Path =/vob/CLNP023B1/CLNP023B12301/csr_1/pgm/stats;
21802  %let Macro=/vob/CLNP023B1/CLNP023B12301/csr_1/pgm/stats;
4                                                          The SAS System                            04:10 Wednesday, April 15, 2026

21803  %let MacroPath=/vob/CLNP023B1/CLNP023B12301/csr_1/pgm/stats;
21804  /* 5macro to impute data based on continuous outcome and MMRM model*/
21805  %include "&MacroPath/5macro_part1A_33.sas";


NOTE: PROCEDURE DATASETS used (Total process time):
      real time           0.03 seconds
      cpu time            0.00 seconds
      

22722  %include "&MacroPath/5macro_part1B_47.sas";
24310  %include "&MacroPath/5macro_part2A_40.sas";
NOTE: No CMP or C functions found in library work.funcs.

NOTE: Function CAUSAL saved to work.funcs.trial.
NOTE: Function AFCMCF saved to work.funcs.trial.
NOTE: Function OFCMCF saved to work.funcs.trial.
NOTE: Function ALMCF saved to work.funcs.trial.
NOTE: Function OLMCF saved to work.funcs.trial.
NOTE: Function CR saved to work.funcs.trial.
NOTE: Function J2R saved to work.funcs.trial.
NOTE: Function CIR saved to work.funcs.trial.
NOTE: Function MAR saved to work.funcs.trial.
NOTE: PROCEDURE FCMP used (Total process time):
      real time           0.02 seconds
      cpu time            0.00 seconds
      

25388  %include "&MacroPath/5macro_part2B_31.sas";

NOTE: Function simulate saved to work.funcs.trial.
NOTE: Function mytranspose saved to work.funcs.trial.
NOTE: Function mysubtract saved to work.funcs.trial.
NOTE: Function mymult saved to work.funcs.trial.
NOTE: Function myinv saved to work.funcs.trial.
NOTE: PROCEDURE FCMP used (Total process time):
      real time           0.02 seconds
      cpu time            0.01 seconds
      

26335  %include "&MacroPath/5macro_part3_55.sas";
27645   
27646   /************************************* Section 2 facit scenario with MI *************************************/
27647   /***2.1 Preparation step***/
27648   /*Import the analysis dataset - include pre-dummy visits (aval=.) from updated ADFACIT*/
27649   data dat_part;
27650         set analysis.adfacit;
27651         where paramcd="FACIT" and AVISIT in ("Baseline","Day 14","Day 30","Day 90","Day 180")
27652               and (ANL01FL="Y" or aval=.) and ^missing(base);
27653         keep  usubjid trt01p trt01pn avisit _avisit avisitn paramcd param base chg aval
27654     anl05fl anl05dsc anl05dt anl06fl anl06dsc anl06dt anl07fl anl07dsc anl07dt aeflag aedcdt adt ady
27655     EST01STP ICE01F IMPREA01 EST02STP ICE02F IMPREA02;
27656      _avisit = tranwrd(cats(avisit)," ","_");
27657   run;

NOTE: There were 96 observations read from the data set ANALYSIS.ADFACIT.
      WHERE (paramcd='FACIT') and AVISIT in ('Baseline', 'Day 14', 'Day 180', 'Day 30', 'Day 90') and ((ANL01FL='Y') or 
      (aval=.)) and (not MISSING(base));
5                                                          The SAS System                            04:10 Wednesday, April 15, 2026

NOTE: The data set WORK.DAT_PART has 96 observations and 30 variables.
NOTE: DATA statement used (Total process time):
      real time           0.01 seconds
      cpu time            0.01 seconds
      

27658   
27659   /* Add the stratification variable */
27660   data dat_str;
27661    set analysis.adbs;
27662    where fasfl="Y";
27663    keep usubjid systrcrf;
27664   run;

NOTE: There were 21 observations read from the data set ANALYSIS.ADBS.
      WHERE fasfl='Y';
NOTE: The data set WORK.DAT_STR has 21 observations and 2 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

27665   proc sort data=dat_part;
27666    by usubjid;
27667   run;

NOTE: There were 96 observations read from the data set WORK.DAT_PART.
NOTE: The data set WORK.DAT_PART has 96 observations and 30 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

27668   proc sort data=dat_str;
27669    by usubjid;
27670   run;

NOTE: There were 21 observations read from the data set WORK.DAT_STR.
NOTE: The data set WORK.DAT_STR has 21 observations and 2 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

27671   data dat;
27672    merge dat_part dat_str;
27673    by usubjid;
27674   run;

NOTE: There were 96 observations read from the data set WORK.DAT_PART.
NOTE: There were 21 observations read from the data set WORK.DAT_STR.
NOTE: The data set WORK.DAT has 98 observations and 31 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

27675   
6                                                          The SAS System                            04:10 Wednesday, April 15, 2026

27676   /* in case merge the stratification bring unlabeled data*/
27677   data dat_ana;
27678    set dat;
27679    where trt01pn NE .;

NOTE: There were 96 observations read from the data set WORK.DAT.
      WHERE trt01pn not = .;
NOTE: The data set WORK.DAT_ANA has 96 observations and 31 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

27680    proc sort;
27681     by paramcd param usubjid;
27682   run;

NOTE: There were 96 observations read from the data set WORK.DAT_ANA.
NOTE: The data set WORK.DAT_ANA has 96 observations and 31 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

27683   
27684   /*set the order of visit*/
27685   proc format;
27686    invalue avisit
27687    "Day 14"=202
27688    "Day 30"=203
27689    "Day 90"=204
27690    "Day 180"=205;
NOTE: Informat AVISIT is already on the library WORK.FORMATS.
NOTE: Informat AVISIT has been output.
27691   
27692    value  avisitc
27693    202= "Day 14"
27694    203= "Day 30"
27695    204= "Day 90"
27696    205= "Day 180";
NOTE: Format AVISITC is already on the library WORK.FORMATS.
NOTE: Format AVISITC has been output.
27697   run;

NOTE: PROCEDURE FORMAT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

27698   
27699   /*remove baseline records*/
27700   data dat_ana4;
27701    set dat_ana;
27702    where avisit ^= "Baseline";
27703    AVISITN=input(AVISIT,avisit.);
27704   run;

NOTE: There were 75 observations read from the data set WORK.DAT_ANA.
7                                                          The SAS System                            04:10 Wednesday, April 15, 2026

      WHERE avisit not = 'Baseline';
NOTE: The data set WORK.DAT_ANA4 has 75 observations and 31 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

27705   
27706   /* keep baseline for subject filtering */
27707   data dat_ana_base;
27708    set dat_ana;
27709    where avisit = "Baseline";
27710   run;

NOTE: There were 21 observations read from the data set WORK.DAT_ANA.
      WHERE avisit='Baseline';
NOTE: The data set WORK.DAT_ANA_BASE has 21 observations and 31 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

27711   proc sort data=dat_ana_base; by usubjid; run;

NOTE: There were 21 observations read from the data set WORK.DAT_ANA_BASE.
NOTE: The data set WORK.DAT_ANA_BASE has 21 observations and 31 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

27712   proc sort data=dat_ana4; by usubjid; run;

NOTE: There were 75 observations read from the data set WORK.DAT_ANA4.
NOTE: The data set WORK.DAT_ANA4 has 75 observations and 31 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

27713   
27714   /* ensure only subjects with baseline are included */
27715   data dat_ana4;
27716    merge dat_ana4 dat_ana_base(in=b keep=usubjid);
27717    by usubjid;
27718    if b;
27719   run;

NOTE: There were 75 observations read from the data set WORK.DAT_ANA4.
NOTE: There were 21 observations read from the data set WORK.DAT_ANA_BASE.
NOTE: The data set WORK.DAT_ANA4 has 75 observations and 31 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

27720   
27721   proc sort data=dat_ana4;
8                                                          The SAS System                            04:10 Wednesday, April 15, 2026

27722    by usubjid avisitn;
27723   run;

NOTE: There were 75 observations read from the data set WORK.DAT_ANA4.
NOTE: The data set WORK.DAT_ANA4 has 75 observations and 31 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

27724   
27725   
27726   /**Mark the imputation methods according to SAP**/
27727   /*secondary analysis*/
27728   data dat_ana_mi_sec;
27729    set dat_ana4;
27730    length ACAT1 $50.;
27731    ACAT1="Secondary analysis 24";
27732    ACAT1N=1;
27733    ana_flag = "sec";
27734    IMPREAS=IMPREA01;
27735    if systrcrf="" then systrcrf="N";
27736    if imprea01='Missing data' or (EST01STP='Treatment policy' and aval=.) then imp_method='ALMCF';
27737    if trt01pn = 1 and EST01STP='Hypothetical strategy' then do; aval=.; chg=.; imp_method="J2R"; end;
27738    if trt01pn = 1 and AEDCDT NE . and imprea01='Missing data' then do; imp_method="J2R"; end;
27739     if trt01pn = 2 and EST01STP='Hypothetical strategy' then do; aval=.; chg=.; imp_method="MAR"; end;
27740     if trt01pn = 2 and AEDCDT NE . and imprea01='Missing data' then do; imp_method="MAR"; end;
27741   run;

NOTE: There were 75 observations read from the data set WORK.DAT_ANA4.
NOTE: The data set WORK.DAT_ANA_MI_SEC has 75 observations and 36 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

27742   
27743   
27744   /*supplementary analysis*/
27745   data dat_ana_mi_supp;
27746    set dat_ana4;
27747    length ACAT1 $50.;
27748    ACAT1="Supplementary analysis 24.1";
27749    ACAT1N=2;
27750    ana_flag = "supp";
27751    IMPREAS=IMPREA02;
27752    if systrcrf="" then systrcrf="N";
27753    if imprea02='Missing data' or (EST02STP='Treatment policy' and aval=.) then imp_method='ALMCF';
27754    if trt01pn = 1 and EST02STP='Hypothetical strategy' then do; aval=.; chg=.; imp_method="J2R"; end;
27755    if trt01pn = 1 and AEDCDT NE . and imprea02='Missing data' then do; imp_method="J2R"; end;
27756     if trt01pn = 2 and EST02STP='Hypothetical strategy' then do; aval=.; chg=.; imp_method="MAR"; end;
27757     if trt01pn = 2 and AEDCDT NE . and imprea02='Missing data' then do; imp_method="MAR"; end;
27758   run;

NOTE: There were 75 observations read from the data set WORK.DAT_ANA4.
NOTE: The data set WORK.DAT_ANA_MI_SUPP has 75 observations and 36 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
9                                                          The SAS System                            04:10 Wednesday, April 15, 2026

      cpu time            0.00 seconds
      

27759   
27760   /***2.2Imputation step***/
27761   /**imputation model: aval=trt*time+base+strfactor**/
27762   
27763   %macro facit_mi(endpoint=);
27764    %part1A(Jobname=facit_mi
27765    ,Data=dat_ana_mi_&endpoint.
27766    ,Subject=USUBJID
27767    ,Response=AVAL
27768    ,Time=AVISITN
27769    ,Treat=TRT01PN
27770    ,Catcov=SYSTRCRF
27771    ,Cov = BASE
27772    );
27773   
27774    /*Ndraws=200 represents the number of draws from the posterior distribution with a thinning of 100 iterations*/
27775    %part1B(Jobname=facit_mi
27776    ,Ndraws=200
27777    ,thin=100
27778    ,seed=999
27779    );
27780   
27781    %part2A(Jobname=facit_mi_&endpoint., INName= facit_mi, MethodV= imp_method, Ref= 2)
27782    %part2B(Jobname=facit_mi_&endpoint., seed=999)
27783   
27784    data dat_ana_info;
27785       set dat_ana_mi_&endpoint.;
27786       keep acat1 acat1n usubjid avisitn ana_flag imp_method;
27787    run;
27788    proc sort data=dat_ana_info;
27789       by ACAT1 ACAT1N USUBJID AVISITN;
27790    run;
27791   
27792    data facit_mi_&endpoint._DataFull;
27793     set facit_mi_&endpoint._DataFull;
27794     length AVISIT $50.;
27795     AVISIT=put(AVISITN, avisitc.);
27796    run;
27797   
27798    proc sql;
27799    create table facit_mi_&endpoint._full as
27800    select x.*, y.ACAT1, y.ACAT1N, y.ana_flag, y.imp_method
27801    from facit_mi_&endpoint._DataFull as x left join dat_ana_info as y
27802    on x.usubjid = y.usubjid & x.avisitn=y.avisitn;
27803    quit;
27804   
27805    /*recover missing due to administrative reasons as missing status*/
27806    data facit_mi_&endpoint.;
27807       set facit_mi_&endpoint._full;
27808       chg=aval-base;
27809       if imp_method="ALMCF" then do chg=.; aval=.; imp_method=''; end;
27810    run;
27811   
27812   
27813    proc sort data=facit_mi_&endpoint.;
10                                                         The SAS System                            04:10 Wednesday, April 15, 2026

27814     by USUBJID TRT01PN AVISITN;
27815    run;
27816   
27817    proc sort data=analysis.adfacit out=adfacit1;
27818         where paramcd="FACIT" and AVISIT in ("Baseline","Day 14","Day 30","Day 90","Day 180") and ANL01FL="Y";
27819     by USUBJID TRT01PN AVISITN;
27820    run;
27821   
27822    data adfacmi_&endpoint.;
27823   
27824     merge facit_mi_&endpoint.(in=a) adfacit1(in=b drop=AVAL CHG BASE);
27825     by USUBJID TRT01PN AVISITN;
27826     if a;
27827     length DTYPE $20.;
27828     DTYPE=imp_method;
27829     * truncate the values larger than maximum and smaller than minimum;
27830     if ^missing(aval) and ^missing(DTYPE) then do;
27831      if aval>52 then aval=52;
27832      if aval<0 then aval=0;
27833     end;
27834     if nmiss(AVAL,BASE)=0 then CHG=AVAL-BASE;
27835     IMPNUM=draw;
27836   
27837     avisit=put(avisitn,avisitc.);
27838    run;
27839   %mend;
27840   
27841   
27842   %facit_mi(endpoint=sec);
MPRINT(PART1A):   * Check if jobname is a valid sas name;
MPRINT(PART1A):   data _null_;
MPRINT(PART1A):   facit_mi=0;
MPRINT(PART1A):   run;

NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Delete data sets before we start;
MPRINT(PART1A):   proc datasets library=WORK nolist;
MPRINT(PART1A):   delete facit_mi_master1 facit_mi_master2 facit_mi_datav facit_mi_temp0 facit_mi_temp1 facit_mi_temp2 
facit_mi_temp3 facit_mi_temp4 facit_mi_temp5 facit_mi_temp6 facit_mi_master;
MPRINT(PART1A):   quit;

NOTE: The file WORK.FACIT_MI_MASTER1 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_MASTER2 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_DATAV (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_TEMP0 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_TEMP1 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_TEMP2 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_TEMP3 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_TEMP4 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_TEMP5 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_TEMP6 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_MASTER (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: PROCEDURE DATASETS used (Total process time):
      real time           0.00 seconds
11                                                         The SAS System                            04:10 Wednesday, April 15, 2026

      cpu time            0.00 seconds
      

MPRINT(PART1A):   * If only one covariance group (default) then add indicator variable I_1;
MPRINT(PART1A):   data facit_mi_temp0;
MPRINT(PART1A):   set dat_ana_mi_sec;
MPRINT(PART1A):   I_1=1;
MPRINT(PART1A):   run;

NOTE: There were 75 observations read from the data set WORK.DAT_ANA_MI_SEC.
NOTE: The data set WORK.FACIT_MI_TEMP0 has 75 observations and 37 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Start to build master file and check model variables;
MPRINT(PART1A):   data facit_mi_master1;
MPRINT(PART1A):   keep Vname vlabel vnum vtype Vlen Vformat Role;
MPRINT(PART1A):   length txt $256 Vname $32 vlabel $256 vnum 8 vtype $1 Role $8 CatC CatN $1024;
MPRINT(PART1A):   * Space to hold names of variables used already;
MPRINT(PART1A):   array crosschk[100] $32;
MPRINT(PART1A):   ichk=0;
MPRINT(PART1A):   * Mark as failed and reset on completion;
MPRINT(PART1A):   Role="Master1A";
MPRINT(PART1A):   Vlabel="Failed";
MPRINT(PART1A):   Output;
MPRINT(PART1A):   * Open the data set to check its contents;
MPRINT(PART1A):   dsid=open("facit_mi_temp0","i");
MPRINT(PART1A):   if dsid<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Data set <dat_ana_mi_sec> does not exist");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   if attrn(dsid,"nlobs")=0 then do;
MPRINT(PART1A):  ;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","No observations found in Data set <dat_ana_mi_sec>");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   Role="Subject";
MPRINT(PART1A):   vnum=varnum(dsid,"USUBJID");
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Subject= parameter: Variable <USUBJID> not found in Data set 
<dat_ana_mi_sec>");
MPRINT(PART1A):   call symput("Errtext2","Hint: This can occur when the data set is null and so has no columns.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   output;
MPRINT(PART1A):   Role="Time";
12                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1A):   vnum=varnum(dsid,"AVISITN");
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Time= parameter: Variable <AVISITN> not found in Data set <dat_ana_mi_sec>");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   * Use the capitalisation in the data set;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   do i=1 to ichk;
MPRINT(PART1A):   if vname = crosschk[i] then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Time= parameter: Variable <" || trim(Vname) || "> used elsewhere.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   output;
MPRINT(PART1A):   if Vtype="C" then CatC=Trim(CatC)||"."||Vname;
MPRINT(PART1A):   if Vtype="N" then CatN=Trim(CatN)||"."||Vname;
MPRINT(PART1A):   if vtype= "C" and vlen>120 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Time= parameter: Character varables for Time should not be longer than 120 
chanarcters.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   Role="PEWhere";
MPRINT(PART1A):   vnum=0;
MPRINT(PART1A):   Vname=" ";
MPRINT(PART1A):   Vtype=" ";
MPRINT(PART1A):   vlen=.;
MPRINT(PART1A):   vlabel=" ";
MPRINT(PART1A):   vformat=" ";
MPRINT(PART1A):   output;
MPRINT(PART1A):   Role="Response";
MPRINT(PART1A):   vnum=varnum(dsid,"AVAL");
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Response= Variable <AVAL> not found in Data set <dat_ana_mi_sec>");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   * Use the capitalisation in the data set;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   do i=1 to ichk;
MPRINT(PART1A):   if vname = crosschk[i] then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Response= parameter: Variable <" || trim(Vname) || "> used elsewhere.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
13                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   if vtype="C" then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Response= Variable <AVAL> is character");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   if vlen<8 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Response= Variable <AVAL> is length less than 8.");
MPRINT(PART1A):   call symput("Errtext2","Proc MCMC will later require length 8");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   output;
MPRINT(PART1A):   Role="Treat";
MPRINT(PART1A):   vnum=varnum(dsid,"TRT01PN");
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Treat= parameter: Variable <TRT01PN> not found in Data set <dat_ana_mi_sec>");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   * Use the capitalisation in the data set;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   do i=1 to ichk;
MPRINT(PART1A):   if vname = crosschk[i] then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Treat= parameter: Variable <" || trim(Vname) || "> used elsewhere.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   output;
MPRINT(PART1A):   if Vtype="C" then CatC=Trim(CatC)||"."||Vname;
MPRINT(PART1A):   if Vtype="N" then CatN=Trim(CatN)||"."||Vname;
MPRINT(PART1A):   if vtype= "C" and vlen>120 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Treat= parameter: Character variables should not be longer than 120 
characters.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   Role="Covgp";
MPRINT(PART1A):   vnum=varnum(dsid,"I_1");
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Covgroup= parameter: Variable <I_1> not found in Data set <dat_ana_mi_sec>");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   * Use the capitalisation in the data set;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   do i=1 to ichk;
MPRINT(PART1A):   if vname = crosschk[i] and upcase(Vname) ^= upcase("TRT01PN") then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Covgroup= parameter: Variable <" || trim(Vname) || "> used elsewhere (other 
14                                                         The SAS System                            04:10 Wednesday, April 15, 2026

than Treat=).");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   output;
MPRINT(PART1A):   if Vtype="C" then CatC=Trim(CatC)||"."||Vname;
MPRINT(PART1A):   if Vtype="N" then CatN=Trim(CatN)||"."||Vname;
MPRINT(PART1A):   * Process CatCovbyTime;
MPRINT(PART1A):   txt="";
MPRINT(PART1A):   Varname=scan(txt,1," ");
MPRINT(PART1A):   i=1;
MPRINT(PART1A):   do while( Varname ^= " ");
MPRINT(PART1A):   Role="CatCovby";
MPRINT(PART1A):   vnum=varnum(dsid,Varname);
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","CatCovbyTime= Variable <"||trim(Varname)||"> not found in Data set 
<dat_ana_mi_sec>");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   do ii=1 to ichk;
MPRINT(PART1A):   if vname = crosschk[ii] then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","CatCovbyTime= parameter: Variable <" || trim(Vname) || "> used elsewhere.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   output;
MPRINT(PART1A):   if Vtype="C" then CatC=Trim(CatC)||"."||Vname;
MPRINT(PART1A):   if Vtype="N" then CatN=Trim(CatN)||"."||Vname;
MPRINT(PART1A):   if vtype= "C" and vlen>120 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","CatCovbyTime= parameter: Character varables should not be longer than 120 
chanarcters.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   i=i+1;
MPRINT(PART1A):   Varname=scan(txt,i," ");
MPRINT(PART1A):   * Emergency exit to stop endless loops;
MPRINT(PART1A):   if i>100 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Emergency exit: More than 100 loops inprocessing CarCovbyTime=");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
15                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1A):   * Process Covbytime;
MPRINT(PART1A):   txt="";
MPRINT(PART1A):   Varname=scan(txt,1," ");
MPRINT(PART1A):   i=1;
MPRINT(PART1A):   do while( Varname ^= " ");
MPRINT(PART1A):   Role="Covbytim";
MPRINT(PART1A):   vnum=varnum(dsid,Varname);
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","CovbyTime= Variable <"||trim(Varname)||"> not found in Data set 
<dat_ana_mi_sec>");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   do ii=1 to ichk;
MPRINT(PART1A):   if vname = crosschk[ii] then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","CovbyTime= parameter: Variable <" || trim(Vname) || "> used elsewhere.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   if vtype="C" then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","CovByTime= Variable <"||trim(Varname)||"> is character");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   if vlen<8 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","CovByTime= Variable <"||trim(Varname)||"> is length less than 8.");
MPRINT(PART1A):   call symput("Errtext2","Proc MCMC will later require length 8");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   output;
MPRINT(PART1A):   i=i+1;
MPRINT(PART1A):   Varname=scan(txt,i," ");
MPRINT(PART1A):   if i>100 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Emergency exit: More than 100 loops in processing CovbyTime=");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   * Process Catcov;
MPRINT(PART1A):   txt="SYSTRCRF";
MPRINT(PART1A):   Varname=scan(txt,1," ");
MPRINT(PART1A):   i=1;
MPRINT(PART1A):   do while( Varname ^= " ");
MPRINT(PART1A):   Role="CatCov";
MPRINT(PART1A):   vnum=varnum(dsid,Varname);
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","CatCov= Variable <"||trim(Varname)||"> not found in Data set 
<dat_ana_mi_sec>");
16                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   do ii=1 to ichk;
MPRINT(PART1A):   if vname = crosschk[ii] then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Catcov= parameter: Variable <" || trim(Vname) || "> used elsewhere.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   output;
MPRINT(PART1A):   if Vtype="C" then CatC=Trim(CatC)||"."||Vname;
MPRINT(PART1A):   if Vtype="N" then CatN=Trim(CatN)||"."||Vname;
MPRINT(PART1A):   if vtype= "C" and vlen>120 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","CatCovbyTime= parameter: Character varables should not be longer than 120 
chanarcters.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   i=i+1;
MPRINT(PART1A):   Varname=scan(txt,i," ");
MPRINT(PART1A):   if i>100 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Emergency exit: More than 100 loops in prcessing CatCov=");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   * Process cov;
MPRINT(PART1A):   txt="BASE";
MPRINT(PART1A):   Varname=scan(txt,1," ");
MPRINT(PART1A):   i=1;
MPRINT(PART1A):   do while( Varname ^= " " );
MPRINT(PART1A):   Role="Cov";
MPRINT(PART1A):   vnum=varnum(dsid,Varname);
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Cov= Variable <"||trim(Varname)||"> not found in Data set <dat_ana_mi_sec>");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   do ii=1 to ichk;
MPRINT(PART1A):   if vname = crosschk[ii] then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Cov= parameter: Variable <" || trim(Vname) || "> used elsewhere.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
17                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   if vtype="C" then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Cov= Variable <"||trim(Varname)||"> is character");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   if vlen<8 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Cov= Variable <"||trim(Varname)||"> is length less than 8.");
MPRINT(PART1A):   call symput("Errtext2","Proc MCMC will later require length 8");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   output;
MPRINT(PART1A):   i=i+1;
MPRINT(PART1A):   Varname=scan(txt,i," ");
MPRINT(PART1A):   if i>100 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Emergency exit: More than 100 loops in processing Cov=");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   * Process ID=;
MPRINT(PART1A):   txt="";
MPRINT(PART1A):   Varname=scan(txt,1," ");
MPRINT(PART1A):   i=1;
MPRINT(PART1A):   do while( Varname ^= " " );
MPRINT(PART1A):   Role="ID";
MPRINT(PART1A):   vnum=varnum(dsid,Varname);
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","ID= Variable <"||trim(Varname)||"> not found in Data set <dat_ana_mi_sec>");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   do ii=1 to ichk;
MPRINT(PART1A):   if vname = crosschk[ii] then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","ID= parameter: Variable <" || trim(Vname) || "> used elsewhere.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   output;
MPRINT(PART1A):   i=i+1;
MPRINT(PART1A):   Varname=scan(txt,i," ");
MPRINT(PART1A):   if i>100 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Emergency exit: More than 100 loops in processing ID=");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   rc=close(dsid);
MPRINT(PART1A):   call symput("catC",trim(catC));
18                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1A):   call symput("catN",trim(catN));
MPRINT(PART1A):   run;

NOTE: The data set WORK.FACIT_MI_MASTER1 has 9 observations and 7 variables.
NOTE: DATA statement used (Total process time):
      real time           0.01 seconds
      cpu time            0.01 seconds
      

MPRINT(PART1A):   * Check if _Master data set has been created successfully;
MPRINT(PART1A):   data _null_;
MPRINT(PART1A):   dsid=open("facit_mi_master1","i");
MPRINT(PART1A):   if dsid<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Data set facit_mi_master was not created properly");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   run;

NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Get the distinct levels for all the categorical variables;
MPRINT(PART1A):   * Select required variables and sort data into Work library;
MPRINT(PART1A):   proc sort data=facit_mi_temp0 out=facit_mi_data1( Keep= USUBJID AVAL AVISITN TRT01PN BASE SYSTRCRF 
I_1 );
MPRINT(PART1A):   by USUBJID AVISITN;
MPRINT(PART1A):   run;

NOTE: There were 75 observations read from the data set WORK.FACIT_MI_TEMP0.
NOTE: The data set WORK.FACIT_MI_DATA1 has 75 observations and 7 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Now get the levels of the categorical variables (Numeric and Character handled separately);
MPRINT(PART1A):   * Note we do this based on the PEWHere= selection. Then if we have levels that are not represented we 
can pick this up;
MPRINT(PART1A):   proc sql;
MPRINT(PART1A):   create table facit_mi_temp1 as select distinct SYSTRCRF as CLevel Label="Level as Character" 
length=120, . as NLevel Label="Level as Numeric", "SYSTRCRF" as Name length=32 from facit_mi_data1 order by SYSTRCRF;
NOTE: Table WORK.FACIT_MI_TEMP1 created, with 2 rows and 3 columns.

MPRINT(PART1A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Add index;
MPRINT(PART1A):   data facit_mi_temp2;
MPRINT(PART1A):   set facit_mi_temp1;
MPRINT(PART1A):   index=_N_;
MPRINT(PART1A):   run;

19                                                         The SAS System                            04:10 Wednesday, April 15, 2026

NOTE: There were 2 observations read from the data set WORK.FACIT_MI_TEMP1.
NOTE: The data set WORK.FACIT_MI_TEMP2 has 2 observations and 4 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   proc append data=facit_mi_temp2 base=facit_mi_temp3;
MPRINT(PART1A):   run;

NOTE: Appending WORK.FACIT_MI_TEMP2 to WORK.FACIT_MI_TEMP3.
NOTE: BASE data set does not exist. DATA file is being copied to BASE file.
NOTE: There were 2 observations read from the data set WORK.FACIT_MI_TEMP2.
NOTE: The data set WORK.FACIT_MI_TEMP3 has 2 observations and 4 variables.
NOTE: PROCEDURE APPEND used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   proc sql;
MPRINT(PART1A):   create table facit_mi_temp4 as select distinct Put(AVISITN,best12.) as CLevel Label="Level as 
Character" length=120, AVISITN as NLevel Label="Level as Numeric", "AVISITN" as Name length=32 from facit_mi_data1 
order by AVISITN;
NOTE: Table WORK.FACIT_MI_TEMP4 created, with 4 rows and 3 columns.

MPRINT(PART1A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Add index;
MPRINT(PART1A):   data facit_mi_temp5;
MPRINT(PART1A):   set facit_mi_temp4;
MPRINT(PART1A):   index=_N_;
MPRINT(PART1A):   run;

NOTE: There were 4 observations read from the data set WORK.FACIT_MI_TEMP4.
NOTE: The data set WORK.FACIT_MI_TEMP5 has 4 observations and 4 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   proc append data=facit_mi_temp5 base=facit_mi_temp3;
MPRINT(PART1A):   run;

NOTE: Appending WORK.FACIT_MI_TEMP5 to WORK.FACIT_MI_TEMP3.
NOTE: There were 4 observations read from the data set WORK.FACIT_MI_TEMP5.
NOTE: 4 observations added.
NOTE: The data set WORK.FACIT_MI_TEMP3 has 6 observations and 4 variables.
NOTE: PROCEDURE APPEND used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   proc sql;
MPRINT(PART1A):   create table facit_mi_temp4 as select distinct Put(TRT01PN,best12.) as CLevel Label="Level as 
20                                                         The SAS System                            04:10 Wednesday, April 15, 2026

Character" length=120, TRT01PN as NLevel Label="Level as Numeric", "TRT01PN" as Name length=32 from facit_mi_data1 
order by TRT01PN;
NOTE: Table WORK.FACIT_MI_TEMP4 created, with 2 rows and 3 columns.

MPRINT(PART1A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Add index;
MPRINT(PART1A):   data facit_mi_temp5;
MPRINT(PART1A):   set facit_mi_temp4;
MPRINT(PART1A):   index=_N_;
MPRINT(PART1A):   run;

NOTE: There were 2 observations read from the data set WORK.FACIT_MI_TEMP4.
NOTE: The data set WORK.FACIT_MI_TEMP5 has 2 observations and 4 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   proc append data=facit_mi_temp5 base=facit_mi_temp3;
MPRINT(PART1A):   run;

NOTE: Appending WORK.FACIT_MI_TEMP5 to WORK.FACIT_MI_TEMP3.
NOTE: There were 2 observations read from the data set WORK.FACIT_MI_TEMP5.
NOTE: 2 observations added.
NOTE: The data set WORK.FACIT_MI_TEMP3 has 8 observations and 4 variables.
NOTE: PROCEDURE APPEND used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   proc sql;
MPRINT(PART1A):   create table facit_mi_temp4 as select distinct Put(I_1,best12.) as CLevel Label="Level as Character" 
length=120, I_1 as NLevel Label="Level as Numeric", "I_1" as Name length=32 from facit_mi_data1 order by I_1;
NOTE: Table WORK.FACIT_MI_TEMP4 created, with 1 rows and 3 columns.

MPRINT(PART1A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Add index;
MPRINT(PART1A):   data facit_mi_temp5;
MPRINT(PART1A):   set facit_mi_temp4;
MPRINT(PART1A):   index=_N_;
MPRINT(PART1A):   run;

NOTE: There were 1 observations read from the data set WORK.FACIT_MI_TEMP4.
NOTE: The data set WORK.FACIT_MI_TEMP5 has 1 observations and 4 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      
21                                                         The SAS System                            04:10 Wednesday, April 15, 2026


MPRINT(PART1A):   proc append data=facit_mi_temp5 base=facit_mi_temp3;
MPRINT(PART1A):   run;

NOTE: Appending WORK.FACIT_MI_TEMP5 to WORK.FACIT_MI_TEMP3.
NOTE: There were 1 observations read from the data set WORK.FACIT_MI_TEMP5.
NOTE: 1 observations added.
NOTE: The data set WORK.FACIT_MI_TEMP3 has 9 observations and 4 variables.
NOTE: PROCEDURE APPEND used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * This removes duplicates for other factor that occur when Covgroup and Treatment use same variable 
(SQL side effect);
MPRINT(PART1A):   proc sort data=facit_mi_temp3 NODUPKEY;
MPRINT(PART1A):   by Name index;
MPRINT(PART1A):   run;

NOTE: There were 9 observations read from the data set WORK.FACIT_MI_TEMP3.
NOTE: 0 observations with duplicate key values were deleted.
NOTE: The data set WORK.FACIT_MI_TEMP3 has 9 observations and 4 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Check if there are any missing values in the quantitative covariates;
MPRINT(PART1A):   data _null_;
MPRINT(PART1A):   set facit_mi_temp0 end=myend;
MPRINT(PART1A):   length mylist $ 120;
MPRINT(PART1A):   retain mylist;
MPRINT(PART1A):   if BASE <= .z and not index(mylist,"BASE") then mylist= trim(mylist) || " BASE,";
MPRINT(PART1A):   if myend then do;
MPRINT(PART1A):   if length(mylist)>1 then call symput("Name",substr(mylist,1,length(mylist)-1));
MPRINT(PART1A):   else call symput("Name"," ");
MPRINT(PART1A):   end;
MPRINT(PART1A):   run;

NOTE: There were 75 observations read from the data set WORK.FACIT_MI_TEMP0.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Check if any records have a missing value for any categorical variable;
MPRINT(PART1A):   proc sql noprint;
MPRINT(PART1A):   select Name into :Name separated by ", " from facit_mi_temp3 where (Clevel="" or left(Clevel)=".") 
and Nlevel <=.z ;
NOTE: No rows were selected.
MPRINT(PART1A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Check if any of the categorical variables have only one level;
MPRINT(PART1A):   * Note that we allow the treatment variable to have only one level;
22                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1A):   proc sql noprint;
MPRINT(PART1A):   select Name into :Name separated by ", " from (select Name, Count(*) as N from 
facit_mi_temp3(where=(Name Notin("TRT01PN","I_1"))) group by Name) where n=1;
NOTE: No rows were selected.
MPRINT(PART1A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Now join these levels back into the master data set;
MPRINT(PART1A):   proc sql noprint;
MPRINT(PART1A):   create table facit_mi_master2 as select a.*, b.Clevel, b.Nlevel, b.index from facit_mi_master1 A full 
join facit_mi_temp3 B on A.Vname=B.Name order by Role, Vname, index;
NOTE: Table WORK.FACIT_MI_MASTER2 created, with 14 rows and 10 columns.

MPRINT(PART1A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   Data facit_mi_master;
MPRINT(PART1A):   set facit_mi_master2 end=myend;
MPRINT(PART1A):   * Set index when there is no Covgroup;
MPRINT(PART1A):   if role="Covgp" and index=. then index=1;
MPRINT(PART1A):   output;
MPRINT(PART1A):   if myend then do;
MPRINT(PART1A):   Vname=" ";
MPRINT(PART1A):   Role="DSName";
MPRINT(PART1A):   Vlabel="dat_ana_mi_sec";
MPRINT(PART1A):   Vnum=.;
MPRINT(PART1A):   Vtype=" ";
MPRINT(PART1A):   Vlen=.;
MPRINT(PART1A):   Vformat=" ";
MPRINT(PART1A):   CLevel=" ";
MPRINT(PART1A):   Nlevel=.;
MPRINT(PART1A):   Index=.;
MPRINT(PART1A):   output;
MPRINT(PART1A):   end;
MPRINT(PART1A):   run;

NOTE: There were 14 observations read from the data set WORK.FACIT_MI_MASTER2.
NOTE: The data set WORK.FACIT_MI_MASTER has 15 observations and 10 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   proc sort data=facit_mi_temp0 out=facit_mi_temp6 NODUPKEY;
MPRINT(PART1A):   by USUBJID AVISITN;
MPRINT(PART1A):   run;

NOTE: There were 75 observations read from the data set WORK.FACIT_MI_TEMP0.
NOTE: 0 observations with duplicate key values were deleted.
NOTE: The data set WORK.FACIT_MI_TEMP6 has 75 observations and 37 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
23                                                         The SAS System                            04:10 Wednesday, April 15, 2026

      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Check that the data set we will use in part 1B does not have duplicate records for a subject by 
time combination;
MPRINT(PART1A):   proc sql noprint;
MPRINT(PART1A):   select Count(*) into :n1 from facit_mi_temp0 ;
MPRINT(PART1A):   select Count(*) into :n2 from facit_mi_temp6;
MPRINT(PART1A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Build coded versions of Treat, Time, Catcov, Catcovbytime and Covgroup (I_ is used as prefix to 
indicate indexed version);
MPRINT(PART1A):   proc sql noprint;
MPRINT(PART1A):   *Note that this next line runs directly, so is ready for testing Vtype below at macro level;
MPRINT(PART1A):   select vtype into :vtype from facit_mi_master(where=(upcase(Vname)="TRT01PN" & Role in("CatCov" 
"Time" "CatCovby" "Treat" "Covgp")));
MPRINT(PART1A):   create table facit_mi_data2 as select A.*, B.index as I_TRT01PN from facit_mi_data1 A left join 
facit_mi_master(where=(upcase(Vname)="TRT01PN" & Role in("CatCov" "Time" "CatCovby" "Treat" "Covgp" ))) B on A.TRT01PN 
= B.Nlevel order by USUBJID, AVISITN;
NOTE: Table WORK.FACIT_MI_DATA2 created, with 75 rows and 8 columns.

MPRINT(PART1A):   select max(I_TRT01PN < .z) into :check from facit_mi_data2;
0
MPRINT(PART1A):   *Note that this next line runs directly, so is ready for testing Vtype below at macro level;
MPRINT(PART1A):   select vtype into :vtype from facit_mi_master(where=(upcase(Vname)="AVISITN" & Role in("CatCov" 
"Time" "CatCovby" "Treat" "Covgp")));
MPRINT(PART1A):   create table facit_mi_data3 as select A.*, B.index as I_AVISITN from facit_mi_data2 A left join 
facit_mi_master(where=(upcase(Vname)="AVISITN" & Role in("CatCov" "Time" "CatCovby" "Treat" "Covgp" ))) B on A.AVISITN 
= B.Nlevel order by USUBJID, AVISITN;
NOTE: Table WORK.FACIT_MI_DATA3 created, with 75 rows and 9 columns.

MPRINT(PART1A):   select max(I_AVISITN < .z) into :check from facit_mi_data3;
0
MPRINT(PART1A):   *Note that this next line runs directly, so is ready for testing Vtype below at macro level;
MPRINT(PART1A):   select vtype into :vtype from facit_mi_master(where=(upcase(Vname)="SYSTRCRF" & Role in("CatCov" 
"Time" "CatCovby" "Treat" "Covgp")));
MPRINT(PART1A):   create table facit_mi_data4 as select A.*, B.index as I_SYSTRCRF from facit_mi_data3 A left join 
facit_mi_master(where=(upcase(Vname)="SYSTRCRF" & Role in("CatCov" "Time" "CatCovby" "Treat" "Covgp" ))) B on 
A.SYSTRCRF = B.Clevel order by USUBJID, AVISITN;
NOTE: Table WORK.FACIT_MI_DATA4 created, with 75 rows and 10 columns.

MPRINT(PART1A):   select max(I_SYSTRCRF < .z) into :check from facit_mi_data4;
0
MPRINT(PART1A):   *Note that this next line runs directly, so is ready for testing Vtype below at macro level;
MPRINT(PART1A):   select vtype into :vtype from facit_mi_master(where=(upcase(Vname)="I_1" & Role in("CatCov" "Time" 
"CatCovby" "Treat" "Covgp")));
MPRINT(PART1A):   create table facit_mi_data5 as select A.*, B.index as I_I_1 from facit_mi_data4 A left join 
facit_mi_master(where=(upcase(Vname)="I_1" & Role in("CatCov" "Time" "CatCovby" "Treat" "Covgp" ))) B on A.I_1 = 
B.Nlevel order by USUBJID, AVISITN;
NOTE: Table WORK.FACIT_MI_DATA5 created, with 75 rows and 11 columns.

MPRINT(PART1A):   select max(I_I_1 < .z) into :check from facit_mi_data5;
0
MPRINT(PART1A):   quit;
24                                                         The SAS System                            04:10 Wednesday, April 15, 2026

NOTE: PROCEDURE SQL used (Total process time):
      real time           0.04 seconds
      cpu time            0.01 seconds
      

MPRINT(PART1A):   * Copy and sort into _Datav (sort order required in Part2B);
MPRINT(PART1A):   proc sort data=facit_mi_data5 out=facit_mi_datav;
MPRINT(PART1A):   by USUBJID I_AVISITN;
MPRINT(PART1A):   run;

NOTE: There were 75 observations read from the data set WORK.FACIT_MI_DATA5.
NOTE: The data set WORK.FACIT_MI_DATAV has 75 observations and 11 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   proc datasets library=WORK nolist;
MPRINT(PART1A):   delete facit_mi_master1 facit_mi_master2 facit_mi_temp0 facit_mi_temp1 facit_mi_temp2 facit_mi_temp3 
facit_mi_temp4 facit_mi_temp5 facit_mi_temp6 facit_mi_data1 facit_mi_data2 facit_mi_data3 facit_mi_data4 facit_mi_data5 
quit;

NOTE: The file WORK.QUIT (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: Deleting WORK.FACIT_MI_MASTER1 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_MASTER2 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_TEMP0 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_TEMP1 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_TEMP2 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_TEMP3 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_TEMP4 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_TEMP5 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_TEMP6 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_DATA1 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_DATA2 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_DATA3 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_DATA4 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_DATA5 (memtype=DATA).
NOTE: PROCEDURE DATASETS used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   proc sql;
MPRINT(PART1A):   update facit_mi_master set Vlabel="facit_mi @"||put(datetime(),datetime.) where Role="Master1A";
NOTE: 1 row was updated in WORK.FACIT_MI_MASTER.

MPRINT(PART1A):   delete from facit_mi_master where Role in("Master1B","Master2A","Master2B","Master3");
NOTE: No rows were deleted from WORK.FACIT_MI_MASTER.

MPRINT(PART1A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

################################
Macro Part1A ended succesfully
################################
25                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(FACIT_MI):  ;
MPRINT(PART1B):   proc sql noprint;
MPRINT(PART1B):   * Set status of Part1B as failed in case of error;
MPRINT(PART1B):   delete from facit_mi_master where Role="Master1B";
NOTE: No rows were deleted from WORK.FACIT_MI_MASTER.

MPRINT(PART1B):   insert into facit_mi_master set Vlabel="Failed", Role="Master1B";
NOTE: 1 row was inserted into WORK.FACIT_MI_MASTER.

MPRINT(PART1B):   * Remove any debris from existing Master data set;
MPRINT(PART1B):   delete from facit_mi_master where Role in("NDraws","Thin","Seed", 
"Master2A","Method","MethodV","Ref","RefV","VCRef","VCRefV","VCMeth","VCMethV", "Master2B","Seed", 
"Master3","ANWhere","ANTimes","ANRef","ANTreat","ANCov","ANCatCov","ANCovgp","Delta","DeltaV","DLag","Dgroups","DgroupsV
");
NOTE: No rows were deleted from WORK.FACIT_MI_MASTER.

MPRINT(PART1B):   * Record Ndraws and Thin in the master data set;
MPRINT(PART1B):   insert into facit_mi_master set Index=1, NLevel=200, Role="NDraws";
NOTE: 1 row was inserted into WORK.FACIT_MI_MASTER.

MPRINT(PART1B):   insert into facit_mi_master set Index=1, NLevel=100, Role="Thin";
NOTE: 1 row was inserted into WORK.FACIT_MI_MASTER.

MPRINT(PART1B):   insert into facit_mi_master set Index=1, NLevel=999, VLabel="MCMC", Role="Seed";
NOTE: 1 row was inserted into WORK.FACIT_MI_MASTER.

MPRINT(PART1B):   * Check if previous section (PART1A) ran correctly;
MPRINT(PART1B):   select Vlabel into :loc1A from facit_mi_master(where=(Role="Master1A"));
MPRINT(PART1B):   * Reload the macro variables;
MPRINT(PART1B):   select vname into :Response from facit_mi_master(where=(Role="Response"));
MPRINT(PART1B):   select vname into :PEWhere from facit_mi_master(where=(Role="PEWhere"));
MPRINT(PART1B):   select vtype, vname into :Timetype, :Time from facit_mi_master(where=(Role="Time" and index=1));
MPRINT(PART1B):   select vname into :Subject from facit_mi_master(where=(Role="Subject"));
MPRINT(PART1B):   select vname into :Treat from facit_mi_master(where=(Role="Treat" and index=1));
MPRINT(PART1B):   select vname, "STD_"||Vname into :Cov separated by " " , :STD_cov separated by " " from 
facit_mi_master(where=(Role="Cov"));
MPRINT(PART1B):   select vname, "STD_"||Vname into :CovbyTime separated by " " , :STD_CovbyTime separated by " " from 
facit_mi_master(where=(Role="Covbytim"));
NOTE: No rows were selected.
MPRINT(PART1B):   select vname, "I_"||Vname into :Catcov separated by " " , :I_Catcov separated by " " from 
facit_mi_master(where=(Role="CatCov" and index=1));
MPRINT(PART1B):   select vname, "I_"||Vname into :CatCovbytime separated by " " , :I_Catcovbytime separated by " " from 
facit_mi_master(where=(Role="CatCovby" and index=1));
NOTE: No rows were selected.
MPRINT(PART1B):   select vtype, vname into :Covgptype, :Covgroup from facit_mi_master(where=(Role="Covgp"));
MPRINT(PART1B):   select max(index) into :Ntimes from facit_mi_master(where=(Role="Time"));
MPRINT(PART1B):   select max(index) into :Nwish from facit_mi_master(where=(Role="Covgp"));
MPRINT(PART1B):   select max(index) into :NTreat from facit_mi_master(where=(Role="Treat"));
MPRINT(PART1B):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.01 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Check if jobname is a valid sas name;
MPRINT(PART1B):   data _null_;
MPRINT(PART1B):   facit_mi=0;
MPRINT(PART1B):   run;
26                                                         The SAS System                            04:10 Wednesday, April 15, 2026


NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Delete data sets before we start;
MPRINT(PART1B):   proc datasets library=WORK nolist;
MPRINT(PART1B):   delete dummy facit_mi_classout facit_mi_covp facit_mi_datap1 facit_mi_mean facit_mi_patterns1 
facit_mi_solf facit_mi_std facit_mi_temp7 facit_mi_temp12 facit_mi_datamcmc facit_mi_patterns facit_mi_postcvp 
facit_mi_postlp facit_mi_datap;
MPRINT(PART1B):   quit;

NOTE: The file WORK.DUMMY (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_CLASSOUT (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_COVP (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_DATAP1 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_MEAN (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_PATTERNS1 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_SOLF (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_STD (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_TEMP7 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_TEMP12 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_DATAMCMC (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_PATTERNS (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_POSTCVP (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_POSTLP (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_DATAP (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: PROCEDURE DATASETS used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Now centre and standarise the numeric covariates ready for mcmc;
MPRINT(PART1B):   * Count the number of quantitative covariates;
MPRINT(PART1B):   proc sql noprint;
MPRINT(PART1B):   select count(distinct Vname) into :N from facit_mi_master(where=(Role in("Cov","Covbytim")));
MPRINT(PART1B):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.01 seconds
      

MPRINT(PART1B):   * Here we standardise the regression covariates in the data set (data1 from macro Part1A);
MPRINT(PART1B):   * This is so that the regression parameters in the posterior are less correlated helping proc MCMC;
MPRINT(PART1B):   * This has no impact on the imputation;
MPRINT(PART1B):   * Note we use PEWhere= here ;
MPRINT(PART1B):   proc means data=facit_mi_datav noprint mean;
MPRINT(PART1B):   var BASE ;
MPRINT(PART1B):   output out=facit_mi_mean mean= BASE ;
MPRINT(PART1B):   output out=facit_mi_std std= BASE ;
MPRINT(PART1B):   run;

NOTE: There were 75 observations read from the data set WORK.FACIT_MI_DATAV.
NOTE: The data set WORK.FACIT_MI_MEAN has 1 observations and 3 variables.
NOTE: The data set WORK.FACIT_MI_STD has 1 observations and 3 variables.
NOTE: PROCEDURE MEANS used (Total process time):
      real time           0.01 seconds
27                                                         The SAS System                            04:10 Wednesday, April 15, 2026

      cpu time            0.01 seconds
      

MPRINT(PART1B):   data facit_mi_data1;
MPRINT(PART1B):   set facit_mi_mean(IN=InMean) facit_mi_std(in=InSTD) facit_mi_datav;
MPRINT(PART1B):   drop _type_ _freq_ i;
MPRINT(PART1B):   array my_mean[1] _temporary_;
MPRINT(PART1B):   array my_std[1] _temporary_;
MPRINT(PART1B):   array My_list[1] BASE ;
MPRINT(PART1B):   array std_list[1] STD_BASE ;
MPRINT(PART1B):   if inmean then do;
MPRINT(PART1B):   do i=1 to 1;
MPRINT(PART1B):   My_mean[i]=My_List[i];
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   else if instd then do;
MPRINT(PART1B):   do i=1 to 1;
MPRINT(PART1B):   My_std[i]=My_List[i];
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   else do;
MPRINT(PART1B):   do i=1 to 1;
MPRINT(PART1B):   STD_List[i]=(My_List[i]-My_mean[i])/My_std[i];
MPRINT(PART1B):   end;
MPRINT(PART1B):   output;
MPRINT(PART1B):   end;
MPRINT(PART1B):   run;

NOTE: There were 1 observations read from the data set WORK.FACIT_MI_MEAN.
NOTE: There were 1 observations read from the data set WORK.FACIT_MI_STD.
NOTE: There were 75 observations read from the data set WORK.FACIT_MI_DATAV.
NOTE: The data set WORK.FACIT_MI_DATA1 has 75 observations and 12 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Test for covariates changing in data set (this is not allowed);
MPRINT(PART1B):   * In Temp7 we have all the distinct records (after dropping the Response, Time and ind index of Time);
MPRINT(PART1B):   * These are used later to merge into parallel data;
MPRINT(PART1B):   * Then count number of distinct records within a subject and error if this is more than one;
MPRINT(PART1B):   proc sql noprint;
MPRINT(PART1B):   create table facit_mi_temp7 as select distinct * from facit_mi_data1(drop=AVAL AVISITN I_AVISITN ) 
order by USUBJID;
NOTE: Table WORK.FACIT_MI_TEMP7 created, with 21 rows and 9 columns.

MPRINT(PART1B):   select max(Num) into :maxrows from (select count(USUBJID) as Num from facit_mi_temp7 group by 
USUBJID);
MPRINT(PART1B):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Make the Response data parallel rather than vertical;
MPRINT(PART1B):   proc transpose data=facit_mi_data1(keep=USUBJID AVAL I_AVISITN ) out=facit_mi_temp12(drop=_name_ ) 
prefix=Super_Response;
MPRINT(PART1B):   var AVAL;
28                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   id I_AVISITN ;
MPRINT(PART1B):   by USUBJID;
MPRINT(PART1B):   run;

NOTE: There were 75 observations read from the data set WORK.FACIT_MI_DATA1.
NOTE: The data set WORK.FACIT_MI_TEMP12 has 21 observations and 6 variables.
NOTE: PROCEDURE TRANSPOSE used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Merge the covariate data to parallel outcome data;
MPRINT(PART1B):   * and build pattern indicator variable.;
MPRINT(PART1B):   data facit_mi_dataP1;
MPRINT(PART1B):   array Super_Response[4]Super_Response1-Super_Response4;
MPRINT(PART1B):   merge facit_mi_temp7 facit_mi_temp12 END=Myend;
MPRINT(PART1B):  ;
MPRINT(PART1B):   by USUBJID;
MPRINT(PART1B):   drop i;
MPRINT(PART1B):   Subject_index=_N_;
MPRINT(PART1B):   Super_Pattern=0;
MPRINT(PART1B):   Super_Nmiss=0;
MPRINT(PART1B):   Super_Last=0;
MPRINT(PART1B):   do i=1 to 4;
MPRINT(PART1B):   if Super_Response[i]<=.z then do;
MPRINT(PART1B):   Super_Pattern=Super_Pattern*2+1;
MPRINT(PART1B):   Super_Nmiss=Super_Nmiss+1;
MPRINT(PART1B):   end;
MPRINT(PART1B):   else do;
MPRINT(PART1B):   Super_Pattern=Super_Pattern*2;
MPRINT(PART1B):   Super_Last=i;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   run;

NOTE: There were 21 observations read from the data set WORK.FACIT_MI_TEMP7.
NOTE: There were 21 observations read from the data set WORK.FACIT_MI_TEMP12.
NOTE: The data set WORK.FACIT_MI_DATAP1 has 21 observations and 18 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   proc sql noprint;
MPRINT(PART1B):   create table facit_mi_patterns1 as select distinct Super_Pattern, Super_Nmiss, Super_Last from 
facit_mi_dataP1 order by Super_Pattern;
NOTE: Table WORK.FACIT_MI_PATTERNS1 created, with 4 rows and 3 columns.

MPRINT(PART1B):   select count(*) into :NPatt from facit_mi_patterns1 quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   data facit_mi_patterns;
MPRINT(PART1B):   set facit_mi_patterns1;
MPRINT(PART1B):   Super_Pindex=_N_;
MPRINT(PART1B):   run;
29                                                         The SAS System                            04:10 Wednesday, April 15, 2026


NOTE: There were 4 observations read from the data set WORK.FACIT_MI_PATTERNS1.
NOTE: The data set WORK.FACIT_MI_PATTERNS has 4 observations and 4 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Note that datap is sorted here into order Super_Pindex, <Covgroup> , SUBJECT order;
MPRINT(PART1B):   proc sql noprint;
MPRINT(PART1B):   create table facit_mi_datap as select A.*, B.Super_Pindex from facit_mi_dataP1 A left join 
facit_mi_patterns B on A.Super_Pattern = b.Super_Pattern order by Super_Pindex, I_1, USUBJID;
NOTE: Table WORK.FACIT_MI_DATAP created, with 21 rows and 19 columns.

MPRINT(PART1B):   select max(index) into :NWish from facit_mi_master(where=(Role ="Covgp"));
MPRINT(PART1B):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.01 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Run proc MIXED;
MPRINT(PART1B):   ODS select none;
MPRINT(PART1B):   ods output solutionf=facit_mi_Solf Covparms=facit_mi_Covp ;
MPRINT(PART1B):   proc mixed data=facit_mi_data1 ;
MPRINT(PART1B):   ;
MPRINT(PART1B):   class USUBJID I_TRT01PN I_SYSTRCRF I_I_1 I_AVISITN ;
MPRINT(PART1B):   model AVAL = I_TRT01PN*I_AVISITN I_SYSTRCRF STD_BASE / SOLUTION DDFM=RESIDUAL NOINT;
MPRINT(PART1B):   repeated I_AVISITN /SUBJECT=USUBJID TYPE=UN ;
MPRINT(PART1B):  ;
MPRINT(PART1B):   run;

NOTE: 5 observations are not included because of missing values.
NOTE: Convergence criteria met.
NOTE: The data set WORK.FACIT_MI_COVP has 10 observations and 3 variables.
NOTE: The data set WORK.FACIT_MI_SOLF has 11 observations and 9 variables.
NOTE: PROCEDURE MIXED used (Total process time):
      real time           0.01 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   ods output clear;
MPRINT(PART1B):   ods select all;
MPRINT(PART1B):   * Build text to declare R matrix in proc MCMC;
MPRINT(PART1B):   data _null_;
MPRINT(PART1B):   set facit_mi_Covp end=myend;
MPRINT(PART1B):  ;
MPRINT(PART1B):   length txt $ 10240;
MPRINT(PART1B):   retain row 1 col 1;
MPRINT(PART1B):   array v[ 1,4,4] _temporary_;
MPRINT(PART1B):   g=1;
MPRINT(PART1B):   row=input(scan(Covparm,1,"UN(,)"),6.0);
MPRINT(PART1B):   col=input(scan(Covparm,2,"UN(,)"),6.0);
MPRINT(PART1B):   v[g,row,col]=estimate;
MPRINT(PART1B):   v[g,col,row]=estimate;
MPRINT(PART1B):   if myend then do;
MPRINT(PART1B):   txt=" ";
MPRINT(PART1B):   do g=1 to 1;
30                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   do i=1 to 4;
MPRINT(PART1B):   do j=1 to 4;
MPRINT(PART1B):   if (length(txt)+10) > 10240 then do;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Insufficient space for R matrix text. Increase macro parameter Maxtxt in 
code.");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   txt=trim(txt)||" "||put(v[g,i,j], best8.);
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   call symput("Rmatrix",txt);
MPRINT(PART1B):   end;
MPRINT(PART1B):   run;

NOTE: There were 10 observations read from the data set WORK.FACIT_MI_COVP.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Set up macro variables to allow us to build the required array statement;
MPRINT(PART1B):   proc sql noprint;
MPRINT(PART1B):   select Max(index), Max(Vname) as Vname Into :NLcatcov separated by " ", :Vcatcov separated by " " 
from facit_mi_master(where=(Role ="CatCov")) group by Vname order by Vname;
MPRINT(PART1B):   select Count(*) into :N from facit_mi_solf;
MPRINT(PART1B):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.01 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Parmstext is text for the main parms statement for linear predictor parameters in MCMC;
MPRINT(PART1B):   * Difficulty is that Effect in SOLUTION data set is truncated by SAS at 20 characters;
MPRINT(PART1B):   * So we extract based on order of terms in model, and cross check truncated names of variables;
MPRINT(PART1B):   data _null_;
MPRINT(PART1B):   set facit_mi_Solf end=myend;
MPRINT(PART1B):   *length txt mtxt $ 10240;
MPRINT(PART1B):   length txt txtnocov $ 10240;
MPRINT(PART1B):   length txt1 txt2 $ 32;
MPRINT(PART1B):   array hold[ 11] _temporary_;
MPRINT(PART1B):   array heffect[ 11] $20 _temporary_;
MPRINT(PART1B):   * For constrained parameters set hold[ ] as missing, and trap later;
MPRINT(PART1B):   if df>.z then hold[_N_]=estimate;
MPRINT(PART1B):   else hold[_n_]=.;
MPRINT(PART1B):   heffect[_N_]=effect;
MPRINT(PART1B):   if myend then do;
MPRINT(PART1B):   n=1;
MPRINT(PART1B):   txt=" ";
MPRINT(PART1B):   do i =1 to 2;
MPRINT(PART1B):   * Have separate PARMS for each treatment arm;
MPRINT(PART1B):   txt=trim(txt) || " ;PARMS";
MPRINT(PART1B):   do j=1 to 4;
MPRINT(PART1B):   if (length(txt)+100) > 10240 then do;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Insufficient space for PARMS text. Increase macro parameter Maxtxt in code.");
MPRINT(PART1B):   stop;
31                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   end;
MPRINT(PART1B):   txt=trim(txt) || " P_I_TRT01PN_" || trim(left(put(n,4.0))) || " " || left(put(hold[n],best8.));
MPRINT(PART1B):   txt1=scan(heffect[n],1,"*");
MPRINT(PART1B):   if upcase(substr("I_TRT01PN",1,length(txt1))) ^= upcase(txt1) then do;
MPRINT(PART1B):   left=upcase(substr("I_TRT01PN",1,length(txt1)));
MPRINT(PART1B):   right=upcase(txt1);
MPRINT(PART1B):   put left=;
MPRINT(PART1B):   put right=;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Mismatch in Effect label in output from MIXED:"||txt1);
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   n=n+1;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   * And place all the other fixed effect parmaters in their own block;
MPRINT(PART1B):   * Hold current setting incase there are none;
MPRINT(PART1B):   txtnocov=txt;
MPRINT(PART1B):   txt=trim(txt) || " ;PARMS";
MPRINT(PART1B):   txt2="P_I_SYSTRCRF_1";
MPRINT(PART1B):   do i =1 to 2;
MPRINT(PART1B):   if hold[n]>.z then do;
MPRINT(PART1B):   if (length(txt)+100) > 10240 then do;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Insufficient space for PARMS text. Increase macro parameter Maxtxt in code.");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   txt=trim(txt) || " P_I_SYSTRCRF_" || trim(left(put(I,4.0))) || " " || left(put(hold[n],best8.));
MPRINT(PART1B):   txt1=scan(heffect[n],1,"*");
MPRINT(PART1B):   if upcase(substr("I_SYSTRCRF_",1,length(txt1))) ^= upcase(txt1) then do;
MPRINT(PART1B):   left=upcase(substr("I_SYSTRCRF_",1,length(txt1)));
MPRINT(PART1B):   right=upcase(txt1);
MPRINT(PART1B):   put left=;
MPRINT(PART1B):   put right=;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Mismatch in Effect label in output from MIXED:"||txt1 );
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   n=n+1;
MPRINT(PART1B):   end;
MPRINT(PART1B):   if (length(txt)+100) > 10240 then do;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Insufficient space for a text string. Increase macro parameter Maxtxt in 
code.");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   txt=trim(txt) || " P_STD_BASE " || left(put(hold[n],best8.));
MPRINT(PART1B):   txt2="P_STD_BASE";
MPRINT(PART1B):   txt1=scan(heffect[n],1,"*");
MPRINT(PART1B):   if upcase(substr("STD_BASE",1,length(txt1))) ^= upcase(txt1) then do;
MPRINT(PART1B):   left=upcase(substr("STD_BASE",1,length(txt1)));
MPRINT(PART1B):   right=upcase(txt1);
MPRINT(PART1B):   put left=;
MPRINT(PART1B):   put right=;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Mismatch in Effect label in output from MIXED:"||txt1 );
MPRINT(PART1B):   stop;
32                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   end;
MPRINT(PART1B):   n=n+1;
MPRINT(PART1B):   * If we have no covariates then go back to txt before we added last PARMS;
MPRINT(PART1B):   if txt2 = " " then txt=txtnocov;
MPRINT(PART1B):   call symput("Parmstext",txt);
MPRINT(PART1B):   * Covptext is the name of one of the parameters in the additonal covariates Block;
MPRINT(PART1B):   * The value of this variable s used to check whether this bolck is updated in the MCMC procedure;
MPRINT(PART1B):  ;
MPRINT(PART1B):   call symput("Covptext",txt2);
MPRINT(PART1B):   end;
MPRINT(PART1B):   run;

NOTE: There were 11 observations read from the data set WORK.FACIT_MI_SOLF.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Dummy data set to keep procedure happy;
MPRINT(PART1B):   data dummy;
MPRINT(PART1B):   run;

NOTE: The data set WORK.DUMMY has 1 observations and 0 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Note that datap has already been sorted into order Super_Pindex, <Covgroup> , SUBJECT order;
MPRINT(PART1B):   * Remove from MCMC those subject with no repnse data at all;
MPRINT(PART1B):   data facit_mi_datamcmc;
MPRINT(PART1B):   set facit_mi_datap end=myend;
MPRINT(PART1B):   array Super_Response[4]Super_Response1-Super_Response4;
MPRINT(PART1B):   retain Nsubj 0;
MPRINT(PART1B):   drop Nsubj flag i;
MPRINT(PART1B):   ;
MPRINT(PART1B):   flag=0;
MPRINT(PART1B):   do i=1 to 4;
MPRINT(PART1B):   if Super_Response[i]> .z then flag=1;
MPRINT(PART1B):   end;
MPRINT(PART1B):   if flag then do;
MPRINT(PART1B):   output;
MPRINT(PART1B):   Nsubj=Nsubj+1;
MPRINT(PART1B):   end;
MPRINT(PART1B):   if myend then call symput("NSubj",left(put(Nsubj,6.0)));
MPRINT(PART1B):   run;

NOTE: There were 21 observations read from the data set WORK.FACIT_MI_DATAP.
NOTE: The data set WORK.FACIT_MI_DATAMCMC has 21 observations and 19 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   ODS select none;
MPRINT(PART1B):   ******************************************************************************;
MPRINT(PART1B):   * Query add NTU=2000;
MPRINT(PART1B):   proc mcmc data=dummy outpost=facit_mi_classout PLOTS=NONE nmc=20000 NTU=2000 mintune=4 nbi=1000 
33                                                         The SAS System                            04:10 Wednesday, April 15, 2026

seed=999 thin=100 jointmodel missing=AC monitor=( RMVout_1-RMVout_16 P_I_TRT01PN );
MPRINT(PART1B):   BEGINCNST;
MPRINT(PART1B):   if _eval_cnst_ then do;
MPRINT(PART1B):   * Read the data in;
MPRINT(PART1B):   * Super_Response is the repeated observations;
MPRINT(PART1B):   array Super_Response[1]/nosymbols;
MPRINT(PART1B):   rc = read_array("facit_mi_datamcmc", Super_Response ,"Super_Response1" ,"Super_Response2" 
,"Super_Response3" ,"Super_Response4" );
MPRINT(PART1B):   if rc then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem in MCMC reading data set facit_mi_datamcmc, variables Super_Response1 etc.";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   Nsubj=dim(Super_Response,1);
MPRINT(PART1B):   Ntimes=dim(Super_Response,2);
MPRINT(PART1B):   if Ntimes<=.z then Ntimes=1;
MPRINT(PART1B):   if Nsubj ^= 21 then do;
MPRINT(PART1B):   put "Macro Nsubj=21    , while records from data set is " Nsubj=;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Problem reading data. Number of subjects does not match.");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   * Array P_<Treat> to hold the treatment*time parmater;
MPRINT(PART1B):   array P_I_TRT01PN[2,4] P_I_TRT01PN_1-P_I_TRT01PN_8;
MPRINT(PART1B):   array I_TRT01PN[1]/nosymbols;
MPRINT(PART1B):   rc = read_array("facit_mi_datamcmc", I_TRT01PN, "I_TRT01PN");
MPRINT(PART1B):   if rc then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem in MCMC reading data set facit_mi_datamcmc, variable I_TRT01PN";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   * In the case where we have a Covgroup that is not the treatment group then load it as well;
MPRINT(PART1B):   array I_I_1[1]/nosymbols;
MPRINT(PART1B):   rc = read_array("facit_mi_datamcmc", I_I_1, "I_I_1");
MPRINT(PART1B):   if rc then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem in MCMC reading data set facit_mi_datamcmc, variable I_I_1";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   array Super_Pindex[1]/nosymbols;
MPRINT(PART1B):   rc = read_array("facit_mi_datamcmc", Super_Pindex, "Super_Pindex");
MPRINT(PART1B):   if rc then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem in MCMC reading data set facit_mi_datamcmc, variable Super_Pindex";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   array Spattern[1]/nosymbols;
MPRINT(PART1B):   rc = read_array("facit_mi_datamcmc", Spattern, "Super_Pattern");
MPRINT(PART1B):   if rc then do;
MPRINT(PART1B):   Put "ERROR: ";
34                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   Put "ERROR: Problem in MCMC reading data set facit_mi_datamcmc, variable Super_Pattern";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   * Patt holds the actual pattern (binary notation) for the i th pattern;
MPRINT(PART1B):   array Patt[ 4];
MPRINT(PART1B):   * Vpoint points to index of stored V matrices for a specific subject;
MPRINT(PART1B):   array Vpoint[21 ];
MPRINT(PART1B):   * Vfind points to index of stored V matrices for a specific Covgroup by Pattern ;
MPRINT(PART1B):   array Vfind[ 1, 4];
MPRINT(PART1B):   do i=1 to 1;
MPRINT(PART1B):   do j=1 to 4;
MPRINT(PART1B):   Vfind[i,j]=0;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   PrevCG=.;
MPRINT(PART1B):   Prevp=.;
MPRINT(PART1B):   Vp=0;
MPRINT(PART1B):   * Note that datap was sorted into order Super_Pindex, <Covgroup> , SUBJECT order;
MPRINT(PART1B):   do s=1 to 21 ;
MPRINT(PART1B):   if I_I_1[s] ^= PrevCG | Super_Pindex[s]^=Prevp then do;
MPRINT(PART1B):   Prevcg=I_I_1[s];
MPRINT(PART1B):   PrevP=Super_Pindex[s];
MPRINT(PART1B):   Vp=Vp+1;
MPRINT(PART1B):   Vfind[Prevcg,PrevP]=vp;
MPRINT(PART1B):   end;
MPRINT(PART1B):   Vpoint[s]=Vp;
MPRINT(PART1B):   * Here we are putting the actual pattern into Patt;
MPRINT(PART1B):   Patt[Super_Pindex[s]]=Spattern[s];
MPRINT(PART1B):   end;
MPRINT(PART1B):   maxvp=vp;
MPRINT(PART1B):   * Set up array point, for each pattern which indexes the visits with data;
MPRINT(PART1B):   * Ndata[k] is the number of visits with data for this pattern;
MPRINT(PART1B):   array Point[ 4,4];
MPRINT(PART1B):   array Ndata[ 4];
MPRINT(PART1B):   do k=1 to 4;
MPRINT(PART1B):   ii=0;
MPRINT(PART1B):   iip=0;
MPRINT(PART1B):   chk=2**4;
MPRINT(PART1B):   code=patt[k];
MPRINT(PART1B):   do i=1 to 4;
MPRINT(PART1B):   chk=chk/2;
MPRINT(PART1B):   if code >= chk then do;
MPRINT(PART1B):   code=code-chk;
MPRINT(PART1B):   end;
MPRINT(PART1B):   else do;
MPRINT(PART1B):   * i is not missing;
MPRINT(PART1B):   ii=ii+1;
MPRINT(PART1B):   point[k,ii]=i;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   Ndata[k]=ii;
MPRINT(PART1B):   end;
MPRINT(PART1B):   ENDCNST;
MPRINT(PART1B):   end;
MPRINT(PART1B):   *******************************************************************************************;
MPRINT(PART1B):   * Declare the Wishart priors and invert to get repeated measures variance-covariance matrix;
35                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   * Declare parameters for MCMC;
MPRINT(PART1B):   array W_LS[ 1,4] W_LS1-W_LS4;
MPRINT(PART1B):   ***************************************<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
MPRINT(PART1B):   prior W_LS1 ~expchisq(4);
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _prior = lpdfechisq(W_LS1, _est0 );
MPRINT(PART1B):   end;
MPRINT(PART1B):   prior W_LS2 ~expchisq(3);
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _prior = _prior + lpdfechisq(W_LS2, _est1 );
MPRINT(PART1B):   end;
MPRINT(PART1B):   prior W_LS3 ~expchisq(2);
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _prior = _prior + lpdfechisq(W_LS3, _est2 );
MPRINT(PART1B):   end;
MPRINT(PART1B):   * With only one d.f. can get very small sampled values resulting in underflow.;
MPRINT(PART1B):   prior W_LS4 ~expchisq(1,lower=-28);
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _prior = _prior + lpdfechisq(W_LS4, _est3 , _est4);
MPRINT(PART1B):   end;
MPRINT(PART1B):   array W_Z[ 1,6] W_Z1-W_Z6;
MPRINT(PART1B):   prior W_Z1-W_Z6 ~ normal(0,var=1);
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _sd = sqrt(_est6);
MPRINT(PART1B):   _prior = _prior + lpdfnorm(W_Z1, _est5, _sd );
MPRINT(PART1B):   end;
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _sd = sqrt(_est6);
MPRINT(PART1B):   _prior = _prior + lpdfnorm(W_Z2, _est5, _sd );
MPRINT(PART1B):   end;
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _sd = sqrt(_est6);
MPRINT(PART1B):   _prior = _prior + lpdfnorm(W_Z3, _est5, _sd );
MPRINT(PART1B):   end;
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _sd = sqrt(_est6);
MPRINT(PART1B):   _prior = _prior + lpdfnorm(W_Z4, _est5, _sd );
MPRINT(PART1B):   end;
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _sd = sqrt(_est6);
MPRINT(PART1B):   _prior = _prior + lpdfnorm(W_Z5, _est5, _sd );
MPRINT(PART1B):   end;
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _sd = sqrt(_est6);
MPRINT(PART1B):   _prior = _prior + lpdfnorm(W_Z6, _est5, _sd );
MPRINT(PART1B):   end;
MPRINT(PART1B):   * Put each variance covariance matrix set of parameters on a separate PARMS statement;
MPRINT(PART1B):   ;
MPRINT(PART1B):   parms W_Z1-W_Z6 0 W_LS1 1.38629436111989 W_LS2 1.09861228866811 W_LS3 0.69314718055994 W_LS4 0 ;
MPRINT(PART1B):   * Declare working arrays;
MPRINT(PART1B):   ARRAY RMVout[ 1,4,4] RMVout_1-RMVout_16;
MPRINT(PART1B):   ARRAY RMV[4,4] RMV_1-RMV_16;
MPRINT(PART1B):   ARRAY IRMV[4,4] IRMV_1-IRMV_16;
MPRINT(PART1B):   array W_T[4,4];
MPRINT(PART1B):   array W_U[4,4];
MPRINT(PART1B):   array GW_U[ 1,4,4];
MPRINT(PART1B):   array W_Ctr[4,4];
MPRINT(PART1B):   array W_C[4,4];
36                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   array VV[16]VV1-VV16;
MPRINT(PART1B):   BEGINCNST;
MPRINT(PART1B):   if _eval_cnst_ then do;
MPRINT(PART1B):   **********************************************************************;
MPRINT(PART1B):   * Specify the R matrix for Wishart prior;
MPRINT(PART1B):   * This should be a best guess at the Variance covariance matrix;
MPRINT(PART1B):   * So we use the estimated matrix from REML;
MPRINT(PART1B):   * Note that this is still an uniformative prior as d.f. is set to tbe the number of times;
MPRINT(PART1B):   array GTestR [ 1,4,4] ( 21.65479 9.640414 2.795688 2.246426 9.640414 73.43704 66.76824 65.33466 
2.795688 66.76824 70.60576 73.8339 2.246426 65.33466 73.8339 92.07155 );
MPRINT(PART1B):   array TestR [4,4] ;
MPRINT(PART1B):   ARRAY Temp[4,4];
MPRINT(PART1B):   do g=1 to 1;
MPRINT(PART1B):   do i=1 to 4;
MPRINT(PART1B):   do j=1 to 4;
MPRINT(PART1B):   TestR[i,j]=GTestR[g,i,j];
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   call inv(TestR,Temp);
MPRINT(PART1B):   do i=1 to 4;
MPRINT(PART1B):   do j=1 to 4;
MPRINT(PART1B):   W_C[i,j] = Temp[i,j];
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   call chol(W_C,W_U);
MPRINT(PART1B):   do i=1 to 4;
MPRINT(PART1B):   do j=1 to 4;
MPRINT(PART1B):   if W_U[i,j]<.z then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem with Positive definitiveness of R matrix from MIXED.";
MPRINT(PART1B):   Put "ERROR: Cholesky routine fails to work.";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   GW_U[g,i,j]=W_U[i,j];
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   call zeromatrix(W_T);
MPRINT(PART1B):   *******************************************************************************************;
MPRINT(PART1B):   * Describe the model;
MPRINT(PART1B):   array BASE[1]/nosymbols;
MPRINT(PART1B):   rc = read_array("facit_mi_datamcmc", BASE, "STD_BASE");
MPRINT(PART1B):   if rc then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem in MCMC reading data set facit_mi_datamcmc, variable STD_BASE";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   array P_I_SYSTRCRF[2]P_I_SYSTRCRF_1-P_I_SYSTRCRF_2;
MPRINT(PART1B):   array I_SYSTRCRF[1]/nosymbols;
MPRINT(PART1B):   rc = read_array("facit_mi_datamcmc", I_SYSTRCRF, "I_SYSTRCRF");
MPRINT(PART1B):   if rc then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem in MCMC reading data set facit_mi_datamcmc, variable I_SYSTRCRF";
MPRINT(PART1B):   Put "ERROR: ";
37                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   * Add constraint. Note we set last level to zero in line with SAS;
MPRINT(PART1B):   P_I_SYSTRCRF[2]=0;
MPRINT(PART1B):   *Initialsie values for variables used in optimisation rules;
MPRINT(PART1B):   ARRAY OLDV1[ 1] _temporary_ ;
MPRINT(PART1B):   ARRAY OLDV2[ 1] _temporary_ ;
MPRINT(PART1B):   ARRAY VState[ 1] _temporary_ ;
MPRINT(PART1B):   ARRAY OLDT1[2] _temporary_ ;
MPRINT(PART1B):   ARRAY OLDT2[2] _temporary_ ;
MPRINT(PART1B):   do wish=1 to 1;
MPRINT(PART1B):   OLDV1[wish]=.a;
MPRINT(PART1B):   OLDV2[wish]=.a;
MPRINT(PART1B):   Vstate[wish]=0;
MPRINT(PART1B):   end;
MPRINT(PART1B):   do i = 1 to 2;
MPRINT(PART1B):   OLDT1[i]=.a;
MPRINT(PART1B):   OLDT2[i]=.a;
MPRINT(PART1B):   end;
MPRINT(PART1B):   OLDP1 =.a;
MPRINT(PART1B):   OLDP2 =.a;
MPRINT(PART1B):   optcode=.;
MPRINT(PART1B):   counter=0;
MPRINT(PART1B):   ENDCNST;
MPRINT(PART1B):   end;
MPRINT(PART1B):   * Declare array to hold mean for MV Normal;
MPRINT(PART1B):   * array arrmu[%eval(2*&Nsubj),&Ntimes];
MPRINT(PART1B):   array mu[4] mu1-mu4 ;
MPRINT(PART1B):   array Resp[4] Resp1-Resp4 ;
MPRINT(PART1B):   array loglike[21 ] _temporary_;
MPRINT(PART1B):   array oldLL[21 ] _temporary_;
MPRINT(PART1B):   array Covpart[21 ,4] _temporary_ ;
MPRINT(PART1B):   array PrevCovpart[21 ,4] _temporary_ ;
MPRINT(PART1B):   * Here is the PARMS declaration for the fixed effects parameters;
MPRINT(PART1B):   ;
MPRINT(PART1B):  PARMS P_I_TRT01PN_1 41.12746 P_I_TRT01PN_2 39.00246 P_I_TRT01PN_3 40.62605 P_I_TRT01PN_4 37.00181 ;
MPRINT(PART1B):  PARMS P_I_TRT01PN_5 43.41473 P_I_TRT01PN_6 44.38682 P_I_TRT01PN_7 43.21498 P_I_TRT01PN_8 44.13894 ;
MPRINT(PART1B):  PARMS P_I_SYSTRCRF_1 -2.53234 P_STD_BASE 7.504324 ;
MPRINT(PART1B):   prior P_I_TRT01PN_1-P_I_TRT01PN_8 P_STD_BASE P_I_SYSTRCRF_1-P_I_SYSTRCRF_1 ~ general(1);
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _prior = _prior + _est7;
MPRINT(PART1B):   end;
MPRINT(PART1B):   ***********************************************;
MPRINT(PART1B):   * Optimiser code;
MPRINT(PART1B):   oldoptcode=optcode;
MPRINT(PART1B):   optcode=.;
MPRINT(PART1B):   do wish=1 to 1;
MPRINT(PART1B):   if OLDV1[wish]^=W_Z[Wish,1] then do;
MPRINT(PART1B):   if OLDV2[wish]^=W_Z[Wish,1] then do;
MPRINT(PART1B):   * New position for this covariance matrix;
MPRINT(PART1B):   * Calculation of inverse-Wishart and store away;
MPRINT(PART1B):   k=1;
MPRINT(PART1B):   do i = 1 to 4;
MPRINT(PART1B):   W_T[i,i] = exp(0.5*W_LS[Wish,i]);
MPRINT(PART1B):   W_U[i,i]=GW_U[wish,i,i] ;
MPRINT(PART1B):   do j = 1 to i-1;
MPRINT(PART1B):   W_T[i,j] = W_Z[Wish,k];
38                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   W_U[i,j]=GW_U[wish,i,j];
MPRINT(PART1B):   k=k+1;
MPRINT(PART1B):   * Other halves of matrices remain zero throughout;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   call mult(W_U,W_T,W_Ctr);
MPRINT(PART1B):   call transpose(W_Ctr,W_C);
MPRINT(PART1B):   call mult(W_Ctr,W_C,IRMV);
MPRINT(PART1B):   call inv(IRMV,RMV);
MPRINT(PART1B):   * If IRMV is not positive definite then whole of RMV matrix is set to missing;
MPRINT(PART1B):   if RMV[1,1] < .z then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem in MCMC with sampled Wishart matrix not being positive definite";
MPRINT(PART1B):   Put "ERROR: This should never happen. Please report to developer.";
MPRINT(PART1B):   Put "ERROR: Then we can reset limit on sample from chi-square with one d.f..";
MPRINT(PART1B):   Put "ERROR: Might happen with very sparse data. If so try a different seed.";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   * RMVOut is stored here so that it is monitored and gives the value fr the posterior distribution;
MPRINT(PART1B):   do ii=1 to 4;
MPRINT(PART1B):   do jj=1 to 4;
MPRINT(PART1B):   * Copy here ready for output;
MPRINT(PART1B):   RMVOut[wish,ii,jj]=RMV[ii,jj];
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   *Switch to other store location, so previous is in other position;
MPRINT(PART1B):   VState[wish]= maxvp - VState[wish];
MPRINT(PART1B):   kk=VState[wish];
MPRINT(PART1B):   * Load all the new variance-covariance matrices for each pattern;
MPRINT(PART1B):   do i=1 to 4;
MPRINT(PART1B):   * Vii is the identification number for the combination of Covgroup (Wish) and Pattern (i);
MPRINT(PART1B):   Vii=Vfind[wish,i];
MPRINT(PART1B):   * Test if this combination exists in the data set;
MPRINT(PART1B):   if Vii >0 then do;
MPRINT(PART1B):   * Select required parts of Varcovar matrix for this pattern and Covgroup;
MPRINT(PART1B):   * Note that this use the lower tridiagonal (column number <= row number);
MPRINT(PART1B):   iip=0;
MPRINT(PART1B):   do ii=1 to ndata[i];
MPRINT(PART1B):   k=point[i,ii];
MPRINT(PART1B):   do jj=1 to ii;
MPRINT(PART1B):   iip=iip+1;
MPRINT(PART1B):   vv[iip]= RMV[k,point[i,jj]];
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   * Now hand it to LOGMPDFSET;
MPRINT(PART1B):   * Use select statement with multiple possibles lines of code, so that size of matrix can be 
determined at run time;
MPRINT(PART1B):   select(ndata[i]);
MPRINT(PART1B):   when(1) rc3 = logmpdfset("V"||left(put(Vii+kk,6.0)), of VV1-VV1);
MPRINT(PART1B):   when(2) rc3 = logmpdfset("V"||left(put(Vii+kk,6.0)), of VV1-VV3);
MPRINT(PART1B):   when(3) rc3 = logmpdfset("V"||left(put(Vii+kk,6.0)), of VV1-VV6);
MPRINT(PART1B):   when(4) rc3 = logmpdfset("V"||left(put(Vii+kk,6.0)), of VV1-VV10);
MPRINT(PART1B):   end;
MPRINT(PART1B):   if rc3<=.z then do;
MPRINT(PART1B):   Put "ERROR: Multivariate Repeated Measures using proc MCMC";
MPRINT(PART1B):   put "ERROR: Failed loading V matrix";
39                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   Put "ERROR:";
MPRINT(PART1B):   put rc3=;
MPRINT(PART1B):   ii=Ndata[i];
MPRINT(PART1B):   put ii= ;
MPRINT(PART1B):   do i=1 to 16;
MPRINT(PART1B):   val=vv[i];
MPRINT(PART1B):   put i= val=;
MPRINT(PART1B):   end;
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   OLDV2[wish]=OLDV1[wish];
MPRINT(PART1B):   OLDV1[wish]=W_Z[Wish,1];
MPRINT(PART1B):   if optcode ^= . and oldoptcode>.z then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem with code used for optimization";
MPRINT(PART1B):   Put "ERROR: This should never happen. Please report to developer.";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   optcode=-wish;
MPRINT(PART1B):   end;
MPRINT(PART1B):   else do;
MPRINT(PART1B):   * Return to previous setting;
MPRINT(PART1B):   * Return loglike value and Switch the pointer back;
MPRINT(PART1B):   do s=1 to 21 ;
MPRINT(PART1B):   if I_I_1[s]=Wish then loglike[s]=OldLL[s];
MPRINT(PART1B):   end;
MPRINT(PART1B):   VState[wish]= maxvp - VState[wish];
MPRINT(PART1B):   a=OLDV1[wish];
MPRINT(PART1B):   OLDV1[wish]=OLDV2[wish];
MPRINT(PART1B):   OLDV2[wish]=a;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   do i = 1 to 2;
MPRINT(PART1B):   if OLDT1[i]^= P_I_TRT01PN[i,1] then do;
MPRINT(PART1B):   if OLDT2[i]^= P_I_TRT01PN[i,1] then do;
MPRINT(PART1B):   * New position;
MPRINT(PART1B):   if optcode ^= . and oldoptcode>.z then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem with code used for optimization";
MPRINT(PART1B):   Put "ERROR: This should never happen. Please report to developer.";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   optcode=i;
MPRINT(PART1B):   OLDT2[i]=OLDT1[i];
MPRINT(PART1B):   OLDT1[i]=P_I_TRT01PN[i,1];
MPRINT(PART1B):   end;
MPRINT(PART1B):   else do;
MPRINT(PART1B):   * Return to previous setting;
MPRINT(PART1B):   * Return loglike value and Switch the pointer back;
MPRINT(PART1B):   do s=1 to 21 ;
MPRINT(PART1B):   if I_TRT01PN[s]=i then loglike[s]=OldLL[s];
40                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   end;
MPRINT(PART1B):   a=OLDT1[i];
MPRINT(PART1B):   OLDT1[i]=OLDT2[i];
MPRINT(PART1B):   OLDT2[i]=a;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   if OLDP1 ^= P_STD_BASE then do;
MPRINT(PART1B):   if OLDP2 ^= P_STD_BASE then do;
MPRINT(PART1B):   * New position;
MPRINT(PART1B):   do s=1 to 21 ;
MPRINT(PART1B):   do time=1 to 4;
MPRINT(PART1B):   PrevCovpart[s,time]=Covpart[s,time];
MPRINT(PART1B):   Covpart[s,time]=+ P_STD_BASE*BASE[s] + P_I_SYSTRCRF[I_SYSTRCRF[s]];
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   if optcode ^= . and oldoptcode>.z then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem with code used for optimization";
MPRINT(PART1B):   Put "ERROR: This should never happen. Please report to developer.";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   optcode=0;
MPRINT(PART1B):   OLDP2=OLDP1;
MPRINT(PART1B):   OLDP1=P_STD_BASE ;
MPRINT(PART1B):   end;
MPRINT(PART1B):   else do;
MPRINT(PART1B):   * Return to previous;
MPRINT(PART1B):   do s=1 to 21 ;
MPRINT(PART1B):   do time=1 to 4;
MPRINT(PART1B):   Covpart[s,time]=PrevCovpart[s,time];
MPRINT(PART1B):   loglike[s]=OldLL[s];
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   a=OLDP1;
MPRINT(PART1B):   OLDP1=OLDP2;
MPRINT(PART1B):   OLDP2=a;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   *Force update of all records at start by setting optcode to 0;
MPRINT(PART1B):   if oldoptcode=. then optcode=0;
MPRINT(PART1B):   *****************************;
MPRINT(PART1B):   * Specify MVNormal likelihood;
MPRINT(PART1B):   * Now actually calculate the likelihood (every record in every scan);
MPRINT(PART1B):   ll=0;
MPRINT(PART1B):   do s=1 to 21 ;
MPRINT(PART1B):   * Check if this to be recalculated;
MPRINT(PART1B):   if optcode=0 or (optcode=-I_I_1[s]) or (optcode=I_TRT01PN[s]) then do;
MPRINT(PART1B):   * Select required data;
MPRINT(PART1B):   p=Super_Pindex[s];
MPRINT(PART1B):   nv=Ndata[p];
MPRINT(PART1B):   it=I_TRT01PN[s];
MPRINT(PART1B):   do i=1 to nv;
MPRINT(PART1B):   time=point[p,i];
MPRINT(PART1B):   Resp[i]=Super_Response[s,time];
MPRINT(PART1B):   Mu[i]=P_I_TRT01PN[it,time] + Covpart[s,time] ;
41                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   end;
MPRINT(PART1B):   *Select the correct Var-covar matrix;
MPRINT(PART1B):   select(nv);
MPRINT(PART1B):   when(1) mvnlp = logmpdfnormal(of Resp1-Resp1, of Mu1-mu1, 
"V"||left(put(Vpoint[s]+VState[I_I_1[s]],6.0)));
MPRINT(PART1B):   when(2) mvnlp = logmpdfnormal(of Resp1-Resp2, of Mu1-mu2, 
"V"||left(put(Vpoint[s]+VState[I_I_1[s]],6.0)));
MPRINT(PART1B):   when(3) mvnlp = logmpdfnormal(of Resp1-Resp3, of Mu1-mu3, 
"V"||left(put(Vpoint[s]+VState[I_I_1[s]],6.0)));
MPRINT(PART1B):   when(4) mvnlp = logmpdfnormal(of Resp1-Resp4, of Mu1-mu4, 
"V"||left(put(Vpoint[s]+VState[I_I_1[s]],6.0)));
MPRINT(PART1B):   otherwise mvnlp=.;
MPRINT(PART1B):   end;
MPRINT(PART1B):   if mvnlp <= .z then do;
MPRINT(PART1B):   Put "ERROR: Multivariate Repeated Measures using proc MCMC";
MPRINT(PART1B):   Put "ERROR: Missing value created for likelihood";
MPRINT(PART1B):   Put "ERROR: " mvnlp= "  Response is:";
MPRINT(PART1B):   do i=1 to 4;
MPRINT(PART1B):   a=Resp[i];
MPRINT(PART1B):   put "ERR" "OR: Response[" i "]= " a;
MPRINT(PART1B):   a=Mu[i];
MPRINT(PART1B):   put "ERR" "OR: Mu[" i "]= " a;
MPRINT(PART1B):   end;
MPRINT(PART1B):   Put "ERR" "OR:" ;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Illegal likelihood calculation.");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   oldLL[s]=loglike[s];
MPRINT(PART1B):   loglike[s]=mvnlp;
MPRINT(PART1B):   end;
MPRINT(PART1B):   ll=ll+loglike[s];
MPRINT(PART1B):   end;
MPRINT(PART1B):   model general(ll);
MPRINT(PART1B):   _model = 0;
MPRINT(PART1B):   _model1 = _est8;
MPRINT(PART1B):   _model = _model + _model1;
MPRINT(PART1B):   run;

NOTE: Tuning the proposal distribution.
NOTE: Generating the burn-in samples.
NOTE: Beginning sample generation.
NOTE: The data set WORK.FACIT_MI_CLASSOUT has 200 observations and 40 variables.
NOTE: PROCEDURE MCMC used (Total process time):
      real time           7.96 seconds
      cpu time            2.14 seconds
      

MPRINT(PART1B):   ods select all;
MPRINT(PART1B):   * Free up the space;
MPRINT(PART1B):   data _null_;
MPRINT(PART1B):   rc=logmpdffree();
MPRINT(PART1B):   run;
NOTE: The matrix -  V1 - has been deleted.
NOTE: The matrix -  V2 - has been deleted.
NOTE: The matrix -  V3 - has been deleted.
NOTE: The matrix -  V4 - has been deleted.
NOTE: The matrix -  V5 - has been deleted.
42                                                         The SAS System                            04:10 Wednesday, April 15, 2026

NOTE: The matrix -  V6 - has been deleted.
NOTE: The matrix -  V7 - has been deleted.
NOTE: The matrix -  V8 - has been deleted.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   ods output clear;
MPRINT(PART1B):   data facit_mi_postLP;
MPRINT(PART1B):   set facit_mi_classout;
MPRINT(PART1B):   length Vname $32;
MPRINT(PART1B):   keep draw Vname Icat Itime value;
MPRINT(PART1B):   retain draw 0;
MPRINT(PART1B):   array P_I_TRT01PN[2,4] P_I_TRT01PN_1-P_I_TRT01PN_8;
MPRINT(PART1B):   draw=draw+1;
MPRINT(PART1B):   Vname="I_TRT01PN";
MPRINT(PART1B):   do icat=1 to 2;
MPRINT(PART1B):   do itime=1 to 4;
MPRINT(PART1B):   Value=P_I_TRT01PN[icat,itime];
MPRINT(PART1B):   output;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   Vname="STD_BASE";
MPRINT(PART1B):   Itime=.;
MPRINT(PART1B):   Icat=.;
MPRINT(PART1B):   Value=P_STD_BASE;
MPRINT(PART1B):   output;
MPRINT(PART1B):   array P_I_SYSTRCRF[2]P_I_SYSTRCRF_1-P_I_SYSTRCRF_2 ;
MPRINT(PART1B):   Vname="I_SYSTRCRF";
MPRINT(PART1B):   Itime=.;
MPRINT(PART1B):   P_I_SYSTRCRF[2]=0;
MPRINT(PART1B):   do icat=1 to 2;
MPRINT(PART1B):   Value=P_I_SYSTRCRF[icat];
MPRINT(PART1B):   output;
MPRINT(PART1B):   end;
MPRINT(PART1B):   * Add check here to trap any problems;
MPRINT(PART1B):   if draw <.z or value <.z then do;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Error in posterior sample data set. Please report.");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   run;

NOTE: There were 200 observations read from the data set WORK.FACIT_MI_CLASSOUT.
NOTE: The data set WORK.FACIT_MI_POSTLP has 2200 observations and 5 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   data facit_mi_postCVP;
MPRINT(PART1B):   set facit_mi_classout;
MPRINT(PART1B):   keep draw iteration RMVOUT_1-RMVOUT_16;
MPRINT(PART1B):   draw=_N_;
MPRINT(PART1B):   run;

NOTE: There were 200 observations read from the data set WORK.FACIT_MI_CLASSOUT.
43                                                         The SAS System                            04:10 Wednesday, April 15, 2026

NOTE: The data set WORK.FACIT_MI_POSTCVP has 200 observations and 18 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

DSVER=1
MPRINT(PART1B):   proc datasets library=WORK nolist;
MPRINT(PART1B):   delete dummy facit_mi_classout facit_mi_covp facit_mi_data1 facit_mi_datap1 facit_mi_datamcmc 
facit_mi_mean facit_mi_patterns1 facit_mi_solf facit_mi_std facit_mi_temp7 facit_mi_temp12;
MPRINT(PART1B):   quit;

NOTE: Deleting WORK.DUMMY (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_CLASSOUT (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_COVP (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_DATA1 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_DATAP1 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_DATAMCMC (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_MEAN (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_PATTERNS1 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SOLF (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_STD (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_TEMP7 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_TEMP12 (memtype=DATA).
NOTE: PROCEDURE DATASETS used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   proc sql;
MPRINT(PART1B):   update facit_mi_master set Vlabel="facit_mi @"||put(datetime(),datetime.) where Role="Master1B";
NOTE: 1 row was updated in WORK.FACIT_MI_MASTER.

MPRINT(PART1B):   delete from facit_mi_master where Role in("Master2A","Master2B","Master3");
NOTE: No rows were deleted from WORK.FACIT_MI_MASTER.

MPRINT(PART1B):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

################################
Macro Part1B ended succesfully
################################
MPRINT(FACIT_MI):  ;
MPRINT(PART2A):   * Defaults;
MPRINT(PART2A):   * Copy the master data set;
MPRINT(PART2A):   data facit_mi_sec_master;
MPRINT(PART2A):   set facit_mi_Master end=Myend;
MPRINT(PART2A):   run;

NOTE: There were 19 observations read from the data set WORK.FACIT_MI_MASTER.
NOTE: The data set WORK.FACIT_MI_SEC_MASTER has 19 observations and 10 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      
44                                                         The SAS System                            04:10 Wednesday, April 15, 2026


MPRINT(PART2A):   proc sql noprint;
MPRINT(PART2A):   * Set status of Part1B as failed in case of error;
MPRINT(PART2A):   delete from facit_mi_sec_master where Role="Master2A";
NOTE: No rows were deleted from WORK.FACIT_MI_SEC_MASTER.

MPRINT(PART2A):   insert into facit_mi_sec_master set Vlabel="Failed", Role="Master2A";
NOTE: 1 row was inserted into WORK.FACIT_MI_SEC_MASTER.

MPRINT(PART2A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2A):   proc sql noprint;
MPRINT(PART2A):   * Remove any debris from existing Master data set;
MPRINT(PART2A):   delete from facit_mi_sec_master where Role in( 
"Method","MethodV","Ref","RefV","VCRef","VCRefV","VCMeth","VCMethV", "Master2B", 
"Master3","ANWhere","ANTimes","ANRef","ANTreat","ANCov","ANCatCov","ANCovgp","Delta","DeltaV","DLag","Dgroups","DgroupsV
");
NOTE: No rows were deleted from WORK.FACIT_MI_SEC_MASTER.

MPRINT(PART2A):   delete from facit_mi_sec_master where Role="Seed" and Vlabel="Imputation";
NOTE: No rows were deleted from WORK.FACIT_MI_SEC_MASTER.

MPRINT(PART2A):   * Check if previous sections (PART1A and PART1B) ran correctly;
MPRINT(PART2A):   select Vlabel into :loc1A from facit_mi_master(where=(Role="Master1A"));
MPRINT(PART2A):   select Vlabel into :loc1B from facit_mi_master(where=(Role="Master1B"));
MPRINT(PART2A):   * Reload the macro variables;
MPRINT(PART2A):   select vlabel into :DSName from facit_mi_master(where=(Role="DSName"));
MPRINT(PART2A):   select vname into :Subject from facit_mi_master(where=(Role="Subject"));
MPRINT(PART2A):   select vname into :PEWhere from facit_mi_master(where=(Role="PEWhere"));
MPRINT(PART2A):   select vtype, vname into :Treattype, :Treat from facit_mi_master(where=(Role="Treat" and index=1));
MPRINT(PART2A):   select vname, "STD_"||Vname into :Cov separated by " " , :STD_cov separated by " " from 
facit_mi_master(where=(Role="Cov"));
MPRINT(PART2A):   select vname, "STD_"||Vname into :CovbyTime separated by " " , :STD_CovbyTime separated by " " from 
facit_mi_master(where=(Role="Covbytim"));
NOTE: No rows were selected.
MPRINT(PART2A):   select vname, "I_"||Vname into :Catcov separated by " " , :I_Catcov separated by " " from 
facit_mi_master(where=(Role="CatCov" and index=1));
MPRINT(PART2A):   select vname, "I_"||Vname into :Catcovbytime separated by " " , :I_Catcovbytime separated by " " from 
facit_mi_master(where=(Role="CatCovby" and index=1));
NOTE: No rows were selected.
MPRINT(PART2A):   select vtype, vname into :Covgptype, :Covgroup from facit_mi_master(where=(Role="Covgp"));
MPRINT(PART2A):   select max(index) into :Ntimes from facit_mi_master(where=(Role="Time"));
MPRINT(PART2A):   select max(index) into :NTreat from facit_mi_master(where=(Role="Treat"));
MPRINT(PART2A):   select max(draw) into :Ndraws from facit_mi_postlp;
MPRINT(PART2A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.01 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2A):   * Check if jobname is a valid sas name;
MPRINT(PART2A):   data _null_;
MPRINT(PART2A):   facit_mi_sec=0;
MPRINT(PART2A):   run;
45                                                         The SAS System                            04:10 Wednesday, April 15, 2026


NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2A):   proc datasets library=WORK nolist;
MPRINT(PART2A):   delete facit_mi_sec_temp21 facit_mi_sec_temp22 facit_mi_sec_temp39 facit_mi_sec_temp40 
facit_mi_sec_temp41 facit_mi_sec_temp42 facit_mi_sec_temp51 facit_mi_sec_datapM facit_mi_sec_newbits;
MPRINT(PART2A):   quit;

NOTE: The file WORK.FACIT_MI_SEC_TEMP21 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_SEC_TEMP22 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_SEC_TEMP39 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_SEC_TEMP40 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_SEC_TEMP41 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_SEC_TEMP42 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_SEC_TEMP51 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_SEC_DATAPM (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_SEC_NEWBITS (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: PROCEDURE DATASETS used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2A):   * Check required variables are in the original data set;
MPRINT(PART2A):   data facit_mi_sec_newbits;
MPRINT(PART2A):   keep Vname vlabel vnum vtype Vlen Vformat Role Clevel Nlevel Index;
MPRINT(PART2A):   length txt $256 Vname $32 vlabel $256 vnum 8 vtype $1 Role $8 Clevel $120 vformat $200;
MPRINT(PART2A):   drop txt dsid;
MPRINT(PART2A):   Clevel=" ";
MPRINT(PART2A):   Nlevel=.;
MPRINT(PART2A):   index=.;
MPRINT(PART2A):   dsid=open("dat_ana_mi_sec","i");
MPRINT(PART2A):   if dsid<=0 then do;
MPRINT(PART2A):   call symput("Stopflag","1");
MPRINT(PART2A):   call symput("Errtext1","The original Data set <dat_ana_mi_sec> no longer exists");
MPRINT(PART2A):   stop;
MPRINT(PART2A):   end;
MPRINT(PART2A):   vnum=varnum(dsid,"imp_method");
MPRINT(PART2A):   if vnum<=0 then do;
MPRINT(PART2A):   call symput("Stopflag","1");
MPRINT(PART2A):   call symput("Errtext1","MethodV= parameter: Variable <imp_method> not found in Data set 
dat_ana_mi_sec");
MPRINT(PART2A):   stop;
MPRINT(PART2A):   end;
MPRINT(PART2A):   vtype=vartype(dsid,vnum);
MPRINT(PART2A):   if vtype ^= "C" then do;
MPRINT(PART2A):   call symput("Stopflag","1");
MPRINT(PART2A):   call symput("Errtext1","MethodV= parameter: Variable <imp_method> in Data set <dat_ana_mi_sec> must 
be of type Character.");
MPRINT(PART2A):   stop;
MPRINT(PART2A):   end;
MPRINT(PART2A):   Role="MethodV";
MPRINT(PART2A):   Vname=varname(dsid,Vnum);
MPRINT(PART2A):   vlen=varlen(dsid,Vnum);
MPRINT(PART2A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART2A):   vformat=varfmt(dsid,vnum);
46                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART2A):   output;
MPRINT(PART2A):   Role="Ref";
MPRINT(PART2A):   Vname=" ";
MPRINT(PART2A):   vnum=.;
MPRINT(PART2A):   Vtype=" ";
MPRINT(PART2A):   vlen=.;
MPRINT(PART2A):   vlabel="2";
MPRINT(PART2A):   vformat=" ";
MPRINT(PART2A):   output;
MPRINT(PART2A):   Role="VCRef";
MPRINT(PART2A):   Vname=" ";
MPRINT(PART2A):   vnum=.;
MPRINT(PART2A):   Vtype=" ";
MPRINT(PART2A):   vlen=.;
MPRINT(PART2A):   vlabel="";
MPRINT(PART2A):   vformat=" ";
MPRINT(PART2A):   output;
MPRINT(PART2A):   rc=close(dsid);
MPRINT(PART2A):   run;

NOTE: Variable txt is uninitialized.
NOTE: The data set WORK.FACIT_MI_SEC_NEWBITS has 3 observations and 10 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2A):   * Extract a standard set of linear predictor parameter values;
MPRINT(PART2A):   proc sort data=facit_mi_postlp out=facit_mi_sec_temp51(where= (draw=1));
MPRINT(PART2A):   by vname icat itime;
MPRINT(PART2A):   run;

NOTE: There were 2200 observations read from the data set WORK.FACIT_MI_POSTLP.
NOTE: The data set WORK.FACIT_MI_SEC_TEMP51 has 11 observations and 5 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2A):   * Build text to 1) declare arrays, 2) store parameter values, 3) calculate linear predictor, 4) keep 
in data set;
MPRINT(PART2A):   data _Null_;
MPRINT(PART2A):   set facit_mi_sec_temp51 end=myend;
MPRINT(PART2A):   by vname icat itime;
MPRINT(PART2A):   length txt1 $ 1024;
MPRINT(PART2A):   length txt2 $ 1024;
MPRINT(PART2A):   length txt3 $ 1024;
MPRINT(PART2A):   length txt4 $ 1024;
MPRINT(PART2A):   retain txt1 txt2 txt3 txt4;
MPRINT(PART2A):   if last.vname then do;
MPRINT(PART2A):   if upcase(Vname) ^= upcase("I_TRT01PN") then do;
MPRINT(PART2A):   if icat^=. and itime^=. then do;
MPRINT(PART2A):   *CATCOVbyTime;
MPRINT(PART2A):   txt1=trim(txt1) || "array P_" || trim(Vname) || " [200," || trim(left(put(icat,6.0))) ||"," || 
trim(left(put(itime,6.0))) || "] _temporary_;" ;
MPRINT(PART2A):   txt2=trim(txt2) || "if Vname='" || trim(Vname) || "' then P_" || trim(Vname) || 
"[draw,icat,itime]=Value;" ;
MPRINT(PART2A):   txt3=trim(txt3) || "+P_" || trim(Vname) || "[draw," || trim(Vname) ||",itime]" ;
47                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART2A):   txt4=trim(txt4) || ",B." || trim(Vname);
MPRINT(PART2A):   end;
MPRINT(PART2A):   else do;
MPRINT(PART2A):   if icat=. and itime^=. then do;
MPRINT(PART2A):   *CovbyTime;
MPRINT(PART2A):   txt1=trim(txt1) || "array P_" || trim(Vname) || " [200," || trim(left(put(itime,6.0))) || "] 
_temporary_;" ;
MPRINT(PART2A):   txt2=trim(txt2) || "if Vname='" || trim(Vname) || "' then P_" ||trim(Vname) || "[draw,itime]=Value;" ;
MPRINT(PART2A):   txt3=trim(txt3) || "+P_" || trim(Vname) || "[draw,itime]*" || trim(Vname) ;
MPRINT(PART2A):   txt4=trim(txt4) || ",B." || trim(Vname);
MPRINT(PART2A):   end;
MPRINT(PART2A):   else do;
MPRINT(PART2A):   if icat^=. and itime=. then do;
MPRINT(PART2A):   *CatCov;
MPRINT(PART2A):   txt1=trim(txt1) || "array P_" || trim(Vname) || " [200," || trim(left(put(icat,6.0))) || "] 
_temporary_;" ;
MPRINT(PART2A):   txt2=trim(txt2) || "if Vname='" || trim(Vname) || "' then P_" ||trim(Vname) || "[draw,icat]=Value;" ;
MPRINT(PART2A):   txt3=trim(txt3) || "+P_" || trim(Vname) || "[draw," || trim(Vname) ||"]" ;
MPRINT(PART2A):   txt4=trim(txt4) || ",B." || trim(Vname);
MPRINT(PART2A):   end;
MPRINT(PART2A):   else do;
MPRINT(PART2A):   *Cov;
MPRINT(PART2A):   txt1=trim(txt1) || "array P_" || trim(Vname) || " [200] _temporary_;" ;
MPRINT(PART2A):   txt2=trim(txt2) || "if Vname='" || trim(Vname) || "' then P_" ||trim(Vname) || "[draw]=Value;" ;
MPRINT(PART2A):   txt3=trim(txt3) || "+P_" || trim(Vname) || "[draw]*" || trim(Vname);
MPRINT(PART2A):   txt4=trim(txt4) || ",B." || trim(Vname);
MPRINT(PART2A):   end;
MPRINT(PART2A):   end;
MPRINT(PART2A):   end;
MPRINT(PART2A):   end;
MPRINT(PART2A):   end;
MPRINT(PART2A):   if myend then do;
MPRINT(PART2A):   call symput("decarr",txt1);
MPRINT(PART2A):   call symput("store",txt2);
MPRINT(PART2A):   call symput("calc",txt3);
MPRINT(PART2A):   call symput("keep",txt4);
MPRINT(PART2A):   end;
MPRINT(PART2A):   run;

NOTE: There were 11 observations read from the data set WORK.FACIT_MI_SEC_TEMP51.
NOTE: DATA statement used (Total process time):
      real time           0.01 seconds
      cpu time            0.01 seconds
      

MPRINT(PART2A):   * Check that the MethodV=, RefV=, VCMethodv= and VCRefV= variables are unique with subject;
MPRINT(PART2A):   * And extract from original data set;
MPRINT(PART2A):   proc sql noprint;
MPRINT(PART2A):   create table facit_mi_sec_temp39 as select USUBJID ,Max(imp_method) as imp_method, Min(imp_method) as 
imp_method_check from dat_ana_mi_sec group by USUBJID;
NOTE: Table WORK.FACIT_MI_SEC_TEMP39 created, with 21 rows and 3 columns.

MPRINT(PART2A):   select 0 ,sum(imp_method ^= imp_method_check) into :dummy ,:sumcheck1 from facit_mi_sec_temp39 quit;
MPRINT(PART2A):   * Add the required variables to the data;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      
48                                                         The SAS System                            04:10 Wednesday, April 15, 2026


MPRINT(PART2A):   proc sql;
MPRINT(PART2A):   create table facit_mi_sec_temp40 as select A.* ,B.imp_method from 
facit_mi_datap(where=(Super_Nmiss>0)) A left join facit_mi_sec_temp39 B on A.USUBJID=B.USUBJID;
NOTE: Table WORK.FACIT_MI_SEC_TEMP40 created, with 9 rows and 20 columns.

MPRINT(PART2A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2A):   * Build required control variables;
MPRINT(PART2A):   data facit_mi_sec_temp41;
MPRINT(PART2A):   set facit_mi_sec_temp40;
MPRINT(PART2A):   keep USUBJID Subject_index I_TRT01PN I_SYSTRCRF STD_BASE I_I_1 imp_method 
Super_Response1-Super_Response4 Super_Nmiss Super_Pattern Super_Last Super_k Super_method Super_Ref Super_VCMethod 
Super_VCRef;
MPRINT(PART2A):   * Declare Super_ref and super_VCRef with correct type;
MPRINT(PART2A):   length Super_method $8 Super_VCMethod $8 Super_k 8 ;
MPRINT(PART2A):   * All methods translated to upper case for internal use;
MPRINT(PART2A):   Super_Method= UPCASE(imp_method);
MPRINT(PART2A):   Super_k=1;
MPRINT(PART2A):   * If reference variable exist copy it in, and if not then read it in from Ref. (Default is a missing 
value);
MPRINT(PART2A):   Super_Ref=2;
MPRINT(PART2A):   ;
MPRINT(PART2A):   Super_VCMethod=" ";
MPRINT(PART2A):   Super_VCRef=I_1;
MPRINT(PART2A):   run;

NOTE: There were 9 observations read from the data set WORK.FACIT_MI_SEC_TEMP40.
NOTE: The data set WORK.FACIT_MI_SEC_TEMP41 has 9 observations and 19 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2A):   * Now look up methods used;
MPRINT(PART2A):   * But first check we found something;
MPRINT(PART2A):   proc sql noprint;
MPRINT(PART2A):   select count(*) into :checkn from facit_mi_sec_temp41;
MPRINT(PART2A):   select distinct upcase(super_method) into :methods separated by " " from facit_mi_sec_temp41;
MPRINT(PART2A):   * and index the reference values;
MPRINT(PART2A):   create table facit_mi_sec_temp42 as select A.*, index as I_ref from facit_mi_sec_temp41 A left join 
facit_mi_master(where=(role="Treat")) B on A.super_ref = B.Nlevel ;
NOTE: Table WORK.FACIT_MI_SEC_TEMP42 created, with 9 rows and 20 columns.

MPRINT(PART2A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.01 seconds
      

MPRINT(PART2A):   data facit_mi_sec_datapm;
MPRINT(PART2A):   set facit_mi_postlp(in=inpostlp) facit_mi_datap( in=pass1) facit_mi_sec_temp42(in=pass2) ;
MPRINT(PART2A):   array values[200,2,4] _temporary_;
MPRINT(PART2A):   array avgmeanp[200,4] _temporary_ (800*0);
49                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART2A):   retain counter 0;
MPRINT(PART2A):   array P_I_SYSTRCRF [200,2] _temporary_;
MPRINT(PART2A):  array P_STD_BASE [200] _temporary_;
MPRINT(PART2A):   ;
MPRINT(PART2A):   array super_mean[4] super_mean1-super_mean4;
MPRINT(PART2A):   array super_mar[4] super_mar1-super_mar4;
MPRINT(PART2A):   array A[4] _temporary_;
MPRINT(PART2A):   array B[4] _temporary_;
MPRINT(PART2A):   array C[4] _temporary_;
MPRINT(PART2A):   array MyCov[4] _temporary_;
MPRINT(PART2A):   keep USUBJID draw super_mean1-super_mean4 super_mar1-super_mar4 subject_index 
Super_Response1-Super_Response4 Super_Pattern Super_Nmiss Super_Last Super_VCMethod Super_VCRef Super_k I_I_1 ;
MPRINT(PART2A):   length warntxt $128;
MPRINT(PART2A):   retain warncount 0;
MPRINT(PART2A):   if inpostlp then do;
MPRINT(PART2A):   * Copy parameter values into the values array;
MPRINT(PART2A):   if upcase(Vname) = upcase("I_TRT01PN") then do;
MPRINT(PART2A):   values[draw,icat,itime]=value;
MPRINT(PART2A):   end;
MPRINT(PART2A):   else do;
MPRINT(PART2A):   if Vname='I_SYSTRCRF' then P_I_SYSTRCRF[draw,icat]=Value;
MPRINT(PART2A):  if Vname='STD_BASE' then P_STD_BASE[draw]=Value;
MPRINT(PART2A):   end;
MPRINT(PART2A):   end;
MPRINT(PART2A):   if pass1 then do;
MPRINT(PART2A):   counter=counter+1;
MPRINT(PART2A):   do draw=1 to 200;
MPRINT(PART2A):   * &calc contains code to calculate the rest of the linear predictor.;
MPRINT(PART2A):   do itime=1 to 4;
MPRINT(PART2A):   tempval=avgmeanp[draw,itime];
MPRINT(PART2A):   avgmeanp[draw,itime]= tempval + ((0 +P_I_SYSTRCRF[draw,I_SYSTRCRF]+P_STD_BASE[draw]*STD_BASE ) - 
tempval)/counter ;
MPRINT(PART2A):   end;
MPRINT(PART2A):   end;
MPRINT(PART2A):   end;
MPRINT(PART2A):   if pass2 then do;
MPRINT(PART2A):   * Set up defaults for VCMethod;
MPRINT(PART2A):   if Super_VCMethod=" " then do;
MPRINT(PART2A):   if super_method in("MAR","OLMCF","ALMCF","OFCMCF","AFCMCF") then Super_VCMethod="THIS";
MPRINT(PART2A):   else if super_method in("CIR","J2R", "CAUSAL") then super_VCMethod="REF";
MPRINT(PART2A):   else if super_method="CR" then super_VCMethod="REF";
MPRINT(PART2A):   * If method not found then use "REF" if there is an Reference is set;
MPRINT(PART2A):   * or if no reference set then use "This";
MPRINT(PART2A):   else if I_Ref=. then super_VCMethod="THIS";
MPRINT(PART2A):   else super_VCMethod="REF";
MPRINT(PART2A):   end;
MPRINT(PART2A):   * Build in checks that REF= is set for standard methods that need it;
MPRINT(PART2A):   if (super_method in("CIR","J2R","CR", "CAUSAL")) and (I_Ref < 1 or I_Ref > 2) then do;
MPRINT(PART2A):   call symput("Stopflag","1");
MPRINT(PART2A):   call symput("Errtext1","Illegal value <Index= " || I_Ref || "> for Ref= or for content of Refv= 
variable. Method is "|| left(trim(super_method)) || " Subject ID= <" || USUBJID || ">.");
MPRINT(PART2A):   stop;
MPRINT(PART2A):   end;
MPRINT(PART2A):   * This makes user only one warning for each record in data set;
MPRINT(PART2A):   Warn=0;
MPRINT(PART2A):   do draw=1 to 200;
MPRINT(PART2A):   do itime=1 to 4;
MPRINT(PART2A):   * We hand in the Treat*Time predicted mean for the average subject;
50                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART2A):   A[itime]= values[draw,I_TRT01PN,itime] + AvgMeanp[draw,itime];
MPRINT(PART2A):   if I_ref>.z then B[itime]= values[draw,I_Ref,itime] + AvgMeanp[draw,itime];
MPRINT(PART2A):   else B[itime]= .;
MPRINT(PART2A):   * Mycov is the difference between this subjects predicted mean and that for an average usbject;
MPRINT(PART2A):   MyCov[itime]= (0 +P_I_SYSTRCRF[draw,I_SYSTRCRF]+P_STD_BASE[draw]*STD_BASE ) - AvgMeanp[draw,itime];
MPRINT(PART2A):   end;
MPRINT(PART2A):   select(Super_Method);
MPRINT(PART2A):   when("ALMCF") warntxt= ALMCF(Super_k,Super_Last,A,B,Mycov,C);
MPRINT(PART2A):   otherwise do;
MPRINT(PART2A):   put "ERROR: In otherwise clause";
MPRINT(PART2A):   put "ERROR: Trying to use Method <" Super_method ">";
MPRINT(PART2A):   call symput("Stopflag","1");
MPRINT(PART2A):   call symput("Errtext1","There is some problem with definition of Method");
MPRINT(PART2A):   call symput("Errtext2","Please check this aspect of your macro call. See above for details.");
MPRINT(PART2A):   stop;
MPRINT(PART2A):   end;
MPRINT(PART2A):   end;
MPRINT(PART2A):   if warn=0 and (warntxt ^= "") then do;
MPRINT(PART2A):   if warncount<10 then do;
MPRINT(PART2A):   put "WARNING: For subject, USUBJID=" USUBJID;
MPRINT(PART2A):   put "WARNING: " warntxt;
MPRINT(PART2A):   call symput("Warnflag","1");
MPRINT(PART2A):   end;
MPRINT(PART2A):   warncount +1;
MPRINT(PART2A):   warn +1;
MPRINT(PART2A):   end;
MPRINT(PART2A):   do itime=1 to 4;
MPRINT(PART2A):   super_mean[itime]=C[itime];
MPRINT(PART2A):   super_mar[itime]=A[itime]+MyCov[itime];
MPRINT(PART2A):   end;
MPRINT(PART2A):   output;
MPRINT(PART2A):   end;
MPRINT(PART2A):   end;
MPRINT(PART2A):   run;

NOTE: Numeric values have been converted to character values at the places given by: (Line):(Column).
      27842:2   
ERROR: In otherwise clause
ERROR: Trying to use Method <  >
NOTE: There were 2200 observations read from the data set WORK.FACIT_MI_POSTLP.
NOTE: There were 21 observations read from the data set WORK.FACIT_MI_DATAP.
NOTE: There were 1 observations read from the data set WORK.FACIT_MI_SEC_TEMP42.
NOTE: The data set WORK.FACIT_MI_SEC_DATAPM has 0 observations and 22 variables.
NOTE: DATA statement used (Total process time):
      real time           0.03 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2A):   * Additional quit and run to flush any existing data step or proc;
MPRINT(PART2A):   quit;
MPRINT(PART2A):   run;
MPRINT(PART2A):   * Now put error message and stop macro;
ERROR:
ERROR: In macro Part2A with Jobname= facit_mi_sec
ERROR: There is some problem with definition of Method
ERROR: Please check this aspect of your macro call. See above for details.
ERROR:
MPRINT(PART2B):   proc sql noprint;
51                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART2B):   * Set status of Part2B as failed in case of error;
MPRINT(PART2B):   delete from facit_mi_sec_master where Role="Master2B";
NOTE: No rows were deleted from WORK.FACIT_MI_SEC_MASTER.

MPRINT(PART2B):   insert into facit_mi_sec_master set Vlabel="Failed", Role="Master2B";
NOTE: 1 row was inserted into WORK.FACIT_MI_SEC_MASTER.

MPRINT(PART2B):   * Remove any debris from existing Master data set;
MPRINT(PART2B):   delete from facit_mi_sec_master where Role in( 
"Master3","ANWhere","ANTimes","ANRef","ANTreat","ANCov","ANCatCov","ANCovgp","Delta","DeltaV","DLag","Dgroups","DgroupsV
");
NOTE: No rows were deleted from WORK.FACIT_MI_SEC_MASTER.

MPRINT(PART2B):   delete from facit_mi_sec_master where Role="Seed" and Vlabel="Imputation";
NOTE: No rows were deleted from WORK.FACIT_MI_SEC_MASTER.

MPRINT(PART2B):   insert into facit_mi_sec_master set Index=1, NLevel=999, VLabel="Imputation", Role="Seed";
NOTE: 1 row was inserted into WORK.FACIT_MI_SEC_MASTER.

MPRINT(PART2B):   * Check if previous sections (PART1A, PART1B and PART2A) ran correctly;
MPRINT(PART2B):   select Vlabel into :loc1A from facit_mi_sec_master(where=(Role="Master1A"));
MPRINT(PART2B):   select Vlabel into :loc1B from facit_mi_sec_master(where=(Role="Master1B"));
MPRINT(PART2B):   select Vlabel into :loc2A from facit_mi_sec_master(where=(Role="Master2A"));
MPRINT(PART2B):   * Additional quit and run to flush any existing data step or proc;
MPRINT(PART2B):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2B):   run;
MPRINT(PART2B):   * Now put error message and stop macro;
ERROR:
ERROR: In macro Part2B with Jobname= facit_mi_sec
ERROR: Part 2A has been run but failed for <facit_mi_sec>
ERROR:
ERROR:
MPRINT(FACIT_MI):   data dat_ana_info;
MPRINT(FACIT_MI):   set dat_ana_mi_sec;
MPRINT(FACIT_MI):   keep acat1 acat1n usubjid avisitn ana_flag imp_method;
MPRINT(FACIT_MI):   run;

NOTE: There were 75 observations read from the data set WORK.DAT_ANA_MI_SEC.
NOTE: The data set WORK.DAT_ANA_INFO has 75 observations and 6 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(FACIT_MI):   proc sort data=dat_ana_info;
MPRINT(FACIT_MI):   by ACAT1 ACAT1N USUBJID AVISITN;
MPRINT(FACIT_MI):   run;

NOTE: There were 75 observations read from the data set WORK.DAT_ANA_INFO.
NOTE: The data set WORK.DAT_ANA_INFO has 75 observations and 6 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
52                                                         The SAS System                            04:10 Wednesday, April 15, 2026

      

MPRINT(FACIT_MI):   data facit_mi_sec_DataFull;
MPRINT(FACIT_MI):   set facit_mi_sec_DataFull;
ERROR: File WORK.FACIT_MI_SEC_DATAFULL.DATA does not exist.
MPRINT(FACIT_MI):   length AVISIT $50.;
MPRINT(FACIT_MI):   AVISIT=put(AVISITN, avisitc.);
MPRINT(FACIT_MI):   run;

NOTE: The SAS System stopped processing this step because of errors.
WARNING: The data set WORK.FACIT_MI_SEC_DATAFULL may be incomplete.  When this step was stopped there were 0 
         observations and 2 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(FACIT_MI):   proc sql;
MPRINT(FACIT_MI):   create table facit_mi_sec_full as select x.*, y.ACAT1, y.ACAT1N, y.ana_flag, y.imp_method from 
facit_mi_sec_DataFull as x left join dat_ana_info as y on x.usubjid = y.usubjid & x.avisitn=y.avisitn;
ERROR: Column usubjid could not be found in the table/view identified with the correlation name X.
ERROR: Column usubjid could not be found in the table/view identified with the correlation name X.
NOTE: PROC SQL set option NOEXEC and will continue to check the syntax of statements.
MPRINT(FACIT_MI):   quit;
NOTE: The SAS System stopped processing this step because of errors.
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      


MPRINT(FACIT_MI):   data facit_mi_sec;
MPRINT(FACIT_MI):   set facit_mi_sec_full;
ERROR: File WORK.FACIT_MI_SEC_FULL.DATA does not exist.
MPRINT(FACIT_MI):   chg=aval-base;
MPRINT(FACIT_MI):   if imp_method="ALMCF" then do chg=.;
MPRINT(FACIT_MI):   aval=.;
MPRINT(FACIT_MI):   imp_method='';
MPRINT(FACIT_MI):   end;
MPRINT(FACIT_MI):   run;

NOTE: The SAS System stopped processing this step because of errors.
WARNING: The data set WORK.FACIT_MI_SEC may be incomplete.  When this step was stopped there were 0 observations and 4 
         variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      


MPRINT(FACIT_MI):   proc sort data=facit_mi_sec;
ERROR: Variable USUBJID not found.
ERROR: Variable TRT01PN not found.
MPRINT(FACIT_MI):   by USUBJID TRT01PN AVISITN;
ERROR: Variable AVISITN not found.
MPRINT(FACIT_MI):   run;

NOTE: The SAS System stopped processing this step because of errors.
53                                                         The SAS System                            04:10 Wednesday, April 15, 2026

NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      


MPRINT(FACIT_MI):   proc sort data=analysis.adfacit out=adfacit1;
MPRINT(FACIT_MI):   where paramcd="FACIT" and AVISIT in ("Baseline","Day 14","Day 30","Day 90","Day 180") and 
ANL01FL="Y";
MPRINT(FACIT_MI):   by USUBJID TRT01PN AVISITN;
MPRINT(FACIT_MI):   run;

NOTE: There were 103 observations read from the data set ANALYSIS.ADFACIT.
      WHERE (paramcd='FACIT') and AVISIT in ('Baseline', 'Day 14', 'Day 180', 'Day 30', 'Day 90') and (ANL01FL='Y');
NOTE: The data set WORK.ADFACIT1 has 103 observations and 87 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.01 seconds
      cpu time            0.00 seconds
      

MPRINT(FACIT_MI):   data adfacmi_sec;
MPRINT(FACIT_MI):   merge facit_mi_sec(in=a) adfacit1(in=b drop=AVAL CHG BASE);
MPRINT(FACIT_MI):   by USUBJID TRT01PN AVISITN;
MPRINT(FACIT_MI):   if a;
MPRINT(FACIT_MI):   length DTYPE $20.;
MPRINT(FACIT_MI):   DTYPE=imp_method;
MPRINT(FACIT_MI):   * truncate the values larger than maximum and smaller than minimum;
MPRINT(FACIT_MI):   if ^missing(aval) and ^missing(DTYPE) then do;
MPRINT(FACIT_MI):   if aval>52 then aval=52;
MPRINT(FACIT_MI):   if aval<0 then aval=0;
MPRINT(FACIT_MI):   end;
MPRINT(FACIT_MI):   if nmiss(AVAL,BASE)=0 then CHG=AVAL-BASE;
MPRINT(FACIT_MI):   IMPNUM=draw;
MPRINT(FACIT_MI):   avisit=put(avisitn,avisitc.);
MPRINT(FACIT_MI):   run;

NOTE: Variable draw is uninitialized.
ERROR: BY variable USUBJID is not on input data set WORK.FACIT_MI_SEC.
ERROR: BY variable TRT01PN is not on input data set WORK.FACIT_MI_SEC.
ERROR: BY variable AVISITN is not on input data set WORK.FACIT_MI_SEC.
NOTE: The SAS System stopped processing this step because of errors.
WARNING: The data set WORK.ADFACMI_SEC may be incomplete.  When this step was stopped there were 0 observations and 91 
         variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

27843   %facit_mi(endpoint=supp);
MPRINT(PART1A):   * Check if jobname is a valid sas name;
MPRINT(PART1A):   data _null_;
MPRINT(PART1A):   facit_mi=0;
MPRINT(PART1A):   run;

NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      
54                                                         The SAS System                            04:10 Wednesday, April 15, 2026


MPRINT(PART1A):   * Delete data sets before we start;
MPRINT(PART1A):   proc datasets library=WORK nolist;
MPRINT(PART1A):   delete facit_mi_master1 facit_mi_master2 facit_mi_datav facit_mi_temp0 facit_mi_temp1 facit_mi_temp2 
facit_mi_temp3 facit_mi_temp4 facit_mi_temp5 facit_mi_temp6 facit_mi_master;
MPRINT(PART1A):   quit;

NOTE: The file WORK.FACIT_MI_MASTER1 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_MASTER2 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_TEMP0 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_TEMP1 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_TEMP2 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_TEMP3 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_TEMP4 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_TEMP5 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_TEMP6 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: Deleting WORK.FACIT_MI_DATAV (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_MASTER (memtype=DATA).
NOTE: PROCEDURE DATASETS used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * If only one covariance group (default) then add indicator variable I_1;
MPRINT(PART1A):   data facit_mi_temp0;
MPRINT(PART1A):   set dat_ana_mi_supp;
MPRINT(PART1A):   I_1=1;
MPRINT(PART1A):   run;

NOTE: There were 75 observations read from the data set WORK.DAT_ANA_MI_SUPP.
NOTE: The data set WORK.FACIT_MI_TEMP0 has 75 observations and 37 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Start to build master file and check model variables;
MPRINT(PART1A):   data facit_mi_master1;
MPRINT(PART1A):   keep Vname vlabel vnum vtype Vlen Vformat Role;
MPRINT(PART1A):   length txt $256 Vname $32 vlabel $256 vnum 8 vtype $1 Role $8 CatC CatN $1024;
MPRINT(PART1A):   * Space to hold names of variables used already;
MPRINT(PART1A):   array crosschk[100] $32;
MPRINT(PART1A):   ichk=0;
MPRINT(PART1A):   * Mark as failed and reset on completion;
MPRINT(PART1A):   Role="Master1A";
MPRINT(PART1A):   Vlabel="Failed";
MPRINT(PART1A):   Output;
MPRINT(PART1A):   * Open the data set to check its contents;
MPRINT(PART1A):   dsid=open("facit_mi_temp0","i");
MPRINT(PART1A):   if dsid<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Data set <dat_ana_mi_supp> does not exist");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   if attrn(dsid,"nlobs")=0 then do;
MPRINT(PART1A):  ;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","No observations found in Data set <dat_ana_mi_supp>");
55                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   Role="Subject";
MPRINT(PART1A):   vnum=varnum(dsid,"USUBJID");
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Subject= parameter: Variable <USUBJID> not found in Data set 
<dat_ana_mi_supp>");
MPRINT(PART1A):   call symput("Errtext2","Hint: This can occur when the data set is null and so has no columns.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   output;
MPRINT(PART1A):   Role="Time";
MPRINT(PART1A):   vnum=varnum(dsid,"AVISITN");
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Time= parameter: Variable <AVISITN> not found in Data set <dat_ana_mi_supp>");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   * Use the capitalisation in the data set;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   do i=1 to ichk;
MPRINT(PART1A):   if vname = crosschk[i] then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Time= parameter: Variable <" || trim(Vname) || "> used elsewhere.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   output;
MPRINT(PART1A):   if Vtype="C" then CatC=Trim(CatC)||"."||Vname;
MPRINT(PART1A):   if Vtype="N" then CatN=Trim(CatN)||"."||Vname;
MPRINT(PART1A):   if vtype= "C" and vlen>120 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Time= parameter: Character varables for Time should not be longer than 120 
chanarcters.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   Role="PEWhere";
MPRINT(PART1A):   vnum=0;
MPRINT(PART1A):   Vname=" ";
MPRINT(PART1A):   Vtype=" ";
MPRINT(PART1A):   vlen=.;
MPRINT(PART1A):   vlabel=" ";
MPRINT(PART1A):   vformat=" ";
MPRINT(PART1A):   output;
56                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1A):   Role="Response";
MPRINT(PART1A):   vnum=varnum(dsid,"AVAL");
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Response= Variable <AVAL> not found in Data set <dat_ana_mi_supp>");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   * Use the capitalisation in the data set;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   do i=1 to ichk;
MPRINT(PART1A):   if vname = crosschk[i] then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Response= parameter: Variable <" || trim(Vname) || "> used elsewhere.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   if vtype="C" then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Response= Variable <AVAL> is character");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   if vlen<8 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Response= Variable <AVAL> is length less than 8.");
MPRINT(PART1A):   call symput("Errtext2","Proc MCMC will later require length 8");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   output;
MPRINT(PART1A):   Role="Treat";
MPRINT(PART1A):   vnum=varnum(dsid,"TRT01PN");
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Treat= parameter: Variable <TRT01PN> not found in Data set 
<dat_ana_mi_supp>");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   * Use the capitalisation in the data set;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   do i=1 to ichk;
MPRINT(PART1A):   if vname = crosschk[i] then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Treat= parameter: Variable <" || trim(Vname) || "> used elsewhere.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   output;
57                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1A):   if Vtype="C" then CatC=Trim(CatC)||"."||Vname;
MPRINT(PART1A):   if Vtype="N" then CatN=Trim(CatN)||"."||Vname;
MPRINT(PART1A):   if vtype= "C" and vlen>120 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Treat= parameter: Character variables should not be longer than 120 
characters.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   Role="Covgp";
MPRINT(PART1A):   vnum=varnum(dsid,"I_1");
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Covgroup= parameter: Variable <I_1> not found in Data set <dat_ana_mi_supp>");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   * Use the capitalisation in the data set;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   do i=1 to ichk;
MPRINT(PART1A):   if vname = crosschk[i] and upcase(Vname) ^= upcase("TRT01PN") then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Covgroup= parameter: Variable <" || trim(Vname) || "> used elsewhere (other 
than Treat=).");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   output;
MPRINT(PART1A):   if Vtype="C" then CatC=Trim(CatC)||"."||Vname;
MPRINT(PART1A):   if Vtype="N" then CatN=Trim(CatN)||"."||Vname;
MPRINT(PART1A):   * Process CatCovbyTime;
MPRINT(PART1A):   txt="";
MPRINT(PART1A):   Varname=scan(txt,1," ");
MPRINT(PART1A):   i=1;
MPRINT(PART1A):   do while( Varname ^= " ");
MPRINT(PART1A):   Role="CatCovby";
MPRINT(PART1A):   vnum=varnum(dsid,Varname);
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","CatCovbyTime= Variable <"||trim(Varname)||"> not found in Data set 
<dat_ana_mi_supp>");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   do ii=1 to ichk;
MPRINT(PART1A):   if vname = crosschk[ii] then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","CatCovbyTime= parameter: Variable <" || trim(Vname) || "> used elsewhere.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
58                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   output;
MPRINT(PART1A):   if Vtype="C" then CatC=Trim(CatC)||"."||Vname;
MPRINT(PART1A):   if Vtype="N" then CatN=Trim(CatN)||"."||Vname;
MPRINT(PART1A):   if vtype= "C" and vlen>120 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","CatCovbyTime= parameter: Character varables should not be longer than 120 
chanarcters.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   i=i+1;
MPRINT(PART1A):   Varname=scan(txt,i," ");
MPRINT(PART1A):   * Emergency exit to stop endless loops;
MPRINT(PART1A):   if i>100 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Emergency exit: More than 100 loops inprocessing CarCovbyTime=");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   * Process Covbytime;
MPRINT(PART1A):   txt="";
MPRINT(PART1A):   Varname=scan(txt,1," ");
MPRINT(PART1A):   i=1;
MPRINT(PART1A):   do while( Varname ^= " ");
MPRINT(PART1A):   Role="Covbytim";
MPRINT(PART1A):   vnum=varnum(dsid,Varname);
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","CovbyTime= Variable <"||trim(Varname)||"> not found in Data set 
<dat_ana_mi_supp>");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   do ii=1 to ichk;
MPRINT(PART1A):   if vname = crosschk[ii] then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","CovbyTime= parameter: Variable <" || trim(Vname) || "> used elsewhere.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   if vtype="C" then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","CovByTime= Variable <"||trim(Varname)||"> is character");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   if vlen<8 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","CovByTime= Variable <"||trim(Varname)||"> is length less than 8.");
MPRINT(PART1A):   call symput("Errtext2","Proc MCMC will later require length 8");
MPRINT(PART1A):   stop;
59                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1A):   end;
MPRINT(PART1A):   output;
MPRINT(PART1A):   i=i+1;
MPRINT(PART1A):   Varname=scan(txt,i," ");
MPRINT(PART1A):   if i>100 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Emergency exit: More than 100 loops in processing CovbyTime=");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   * Process Catcov;
MPRINT(PART1A):   txt="SYSTRCRF";
MPRINT(PART1A):   Varname=scan(txt,1," ");
MPRINT(PART1A):   i=1;
MPRINT(PART1A):   do while( Varname ^= " ");
MPRINT(PART1A):   Role="CatCov";
MPRINT(PART1A):   vnum=varnum(dsid,Varname);
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","CatCov= Variable <"||trim(Varname)||"> not found in Data set 
<dat_ana_mi_supp>");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   do ii=1 to ichk;
MPRINT(PART1A):   if vname = crosschk[ii] then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Catcov= parameter: Variable <" || trim(Vname) || "> used elsewhere.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   output;
MPRINT(PART1A):   if Vtype="C" then CatC=Trim(CatC)||"."||Vname;
MPRINT(PART1A):   if Vtype="N" then CatN=Trim(CatN)||"."||Vname;
MPRINT(PART1A):   if vtype= "C" and vlen>120 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","CatCovbyTime= parameter: Character varables should not be longer than 120 
chanarcters.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   i=i+1;
MPRINT(PART1A):   Varname=scan(txt,i," ");
MPRINT(PART1A):   if i>100 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Emergency exit: More than 100 loops in prcessing CatCov=");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   * Process cov;
MPRINT(PART1A):   txt="BASE";
MPRINT(PART1A):   Varname=scan(txt,1," ");
MPRINT(PART1A):   i=1;
60                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1A):   do while( Varname ^= " " );
MPRINT(PART1A):   Role="Cov";
MPRINT(PART1A):   vnum=varnum(dsid,Varname);
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Cov= Variable <"||trim(Varname)||"> not found in Data set <dat_ana_mi_supp>");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   do ii=1 to ichk;
MPRINT(PART1A):   if vname = crosschk[ii] then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Cov= parameter: Variable <" || trim(Vname) || "> used elsewhere.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   if vtype="C" then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Cov= Variable <"||trim(Varname)||"> is character");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   if vlen<8 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Cov= Variable <"||trim(Varname)||"> is length less than 8.");
MPRINT(PART1A):   call symput("Errtext2","Proc MCMC will later require length 8");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   output;
MPRINT(PART1A):   i=i+1;
MPRINT(PART1A):   Varname=scan(txt,i," ");
MPRINT(PART1A):   if i>100 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Emergency exit: More than 100 loops in processing Cov=");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   * Process ID=;
MPRINT(PART1A):   txt="";
MPRINT(PART1A):   Varname=scan(txt,1," ");
MPRINT(PART1A):   i=1;
MPRINT(PART1A):   do while( Varname ^= " " );
MPRINT(PART1A):   Role="ID";
MPRINT(PART1A):   vnum=varnum(dsid,Varname);
MPRINT(PART1A):   if vnum<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","ID= Variable <"||trim(Varname)||"> not found in Data set <dat_ana_mi_supp>");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   Vname=varname(dsid,Vnum);
MPRINT(PART1A):   do ii=1 to ichk;
MPRINT(PART1A):   if vname = crosschk[ii] then do;
MPRINT(PART1A):   call symput("Stopflag","1");
61                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1A):   call symput("Errtext1","ID= parameter: Variable <" || trim(Vname) || "> used elsewhere.");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   ichk=ichk+1;
MPRINT(PART1A):   crosschk[ichk]=vname;
MPRINT(PART1A):   vtype=vartype(dsid,vnum);
MPRINT(PART1A):   vlen=varlen(dsid,Vnum);
MPRINT(PART1A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART1A):   vformat=varfmt(dsid,vnum);
MPRINT(PART1A):   output;
MPRINT(PART1A):   i=i+1;
MPRINT(PART1A):   Varname=scan(txt,i," ");
MPRINT(PART1A):   if i>100 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Emergency exit: More than 100 loops in processing ID=");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   end;
MPRINT(PART1A):   rc=close(dsid);
MPRINT(PART1A):   call symput("catC",trim(catC));
MPRINT(PART1A):   call symput("catN",trim(catN));
MPRINT(PART1A):   run;

NOTE: The data set WORK.FACIT_MI_MASTER1 has 9 observations and 7 variables.
NOTE: DATA statement used (Total process time):
      real time           0.01 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Check if _Master data set has been created successfully;
MPRINT(PART1A):   data _null_;
MPRINT(PART1A):   dsid=open("facit_mi_master1","i");
MPRINT(PART1A):   if dsid<=0 then do;
MPRINT(PART1A):   call symput("Stopflag","1");
MPRINT(PART1A):   call symput("Errtext1","Data set facit_mi_master was not created properly");
MPRINT(PART1A):   stop;
MPRINT(PART1A):   end;
MPRINT(PART1A):   run;

NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Get the distinct levels for all the categorical variables;
MPRINT(PART1A):   * Select required variables and sort data into Work library;
MPRINT(PART1A):   proc sort data=facit_mi_temp0 out=facit_mi_data1( Keep= USUBJID AVAL AVISITN TRT01PN BASE SYSTRCRF 
I_1 );
MPRINT(PART1A):   by USUBJID AVISITN;
MPRINT(PART1A):   run;

NOTE: There were 75 observations read from the data set WORK.FACIT_MI_TEMP0.
NOTE: The data set WORK.FACIT_MI_DATA1 has 75 observations and 7 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      
62                                                         The SAS System                            04:10 Wednesday, April 15, 2026


MPRINT(PART1A):   * Now get the levels of the categorical variables (Numeric and Character handled separately);
MPRINT(PART1A):   * Note we do this based on the PEWHere= selection. Then if we have levels that are not represented we 
can pick this up;
MPRINT(PART1A):   proc sql;
MPRINT(PART1A):   create table facit_mi_temp1 as select distinct SYSTRCRF as CLevel Label="Level as Character" 
length=120, . as NLevel Label="Level as Numeric", "SYSTRCRF" as Name length=32 from facit_mi_data1 order by SYSTRCRF;
NOTE: Table WORK.FACIT_MI_TEMP1 created, with 2 rows and 3 columns.

MPRINT(PART1A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Add index;
MPRINT(PART1A):   data facit_mi_temp2;
MPRINT(PART1A):   set facit_mi_temp1;
MPRINT(PART1A):   index=_N_;
MPRINT(PART1A):   run;

NOTE: There were 2 observations read from the data set WORK.FACIT_MI_TEMP1.
NOTE: The data set WORK.FACIT_MI_TEMP2 has 2 observations and 4 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.01 seconds
      

MPRINT(PART1A):   proc append data=facit_mi_temp2 base=facit_mi_temp3;
MPRINT(PART1A):   run;

NOTE: Appending WORK.FACIT_MI_TEMP2 to WORK.FACIT_MI_TEMP3.
NOTE: BASE data set does not exist. DATA file is being copied to BASE file.
NOTE: There were 2 observations read from the data set WORK.FACIT_MI_TEMP2.
NOTE: The data set WORK.FACIT_MI_TEMP3 has 2 observations and 4 variables.
NOTE: PROCEDURE APPEND used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   proc sql;
MPRINT(PART1A):   create table facit_mi_temp4 as select distinct Put(AVISITN,best12.) as CLevel Label="Level as 
Character" length=120, AVISITN as NLevel Label="Level as Numeric", "AVISITN" as Name length=32 from facit_mi_data1 
order by AVISITN;
NOTE: Table WORK.FACIT_MI_TEMP4 created, with 4 rows and 3 columns.

MPRINT(PART1A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Add index;
MPRINT(PART1A):   data facit_mi_temp5;
MPRINT(PART1A):   set facit_mi_temp4;
MPRINT(PART1A):   index=_N_;
MPRINT(PART1A):   run;

63                                                         The SAS System                            04:10 Wednesday, April 15, 2026

NOTE: There were 4 observations read from the data set WORK.FACIT_MI_TEMP4.
NOTE: The data set WORK.FACIT_MI_TEMP5 has 4 observations and 4 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   proc append data=facit_mi_temp5 base=facit_mi_temp3;
MPRINT(PART1A):   run;

NOTE: Appending WORK.FACIT_MI_TEMP5 to WORK.FACIT_MI_TEMP3.
NOTE: There were 4 observations read from the data set WORK.FACIT_MI_TEMP5.
NOTE: 4 observations added.
NOTE: The data set WORK.FACIT_MI_TEMP3 has 6 observations and 4 variables.
NOTE: PROCEDURE APPEND used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   proc sql;
MPRINT(PART1A):   create table facit_mi_temp4 as select distinct Put(TRT01PN,best12.) as CLevel Label="Level as 
Character" length=120, TRT01PN as NLevel Label="Level as Numeric", "TRT01PN" as Name length=32 from facit_mi_data1 
order by TRT01PN;
NOTE: Table WORK.FACIT_MI_TEMP4 created, with 2 rows and 3 columns.

MPRINT(PART1A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Add index;
MPRINT(PART1A):   data facit_mi_temp5;
MPRINT(PART1A):   set facit_mi_temp4;
MPRINT(PART1A):   index=_N_;
MPRINT(PART1A):   run;

NOTE: There were 2 observations read from the data set WORK.FACIT_MI_TEMP4.
NOTE: The data set WORK.FACIT_MI_TEMP5 has 2 observations and 4 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   proc append data=facit_mi_temp5 base=facit_mi_temp3;
MPRINT(PART1A):   run;

NOTE: Appending WORK.FACIT_MI_TEMP5 to WORK.FACIT_MI_TEMP3.
NOTE: There were 2 observations read from the data set WORK.FACIT_MI_TEMP5.
NOTE: 2 observations added.
NOTE: The data set WORK.FACIT_MI_TEMP3 has 8 observations and 4 variables.
NOTE: PROCEDURE APPEND used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   proc sql;
MPRINT(PART1A):   create table facit_mi_temp4 as select distinct Put(I_1,best12.) as CLevel Label="Level as Character" 
64                                                         The SAS System                            04:10 Wednesday, April 15, 2026

length=120, I_1 as NLevel Label="Level as Numeric", "I_1" as Name length=32 from facit_mi_data1 order by I_1;
NOTE: Table WORK.FACIT_MI_TEMP4 created, with 1 rows and 3 columns.

MPRINT(PART1A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Add index;
MPRINT(PART1A):   data facit_mi_temp5;
MPRINT(PART1A):   set facit_mi_temp4;
MPRINT(PART1A):   index=_N_;
MPRINT(PART1A):   run;

NOTE: There were 1 observations read from the data set WORK.FACIT_MI_TEMP4.
NOTE: The data set WORK.FACIT_MI_TEMP5 has 1 observations and 4 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   proc append data=facit_mi_temp5 base=facit_mi_temp3;
MPRINT(PART1A):   run;

NOTE: Appending WORK.FACIT_MI_TEMP5 to WORK.FACIT_MI_TEMP3.
NOTE: There were 1 observations read from the data set WORK.FACIT_MI_TEMP5.
NOTE: 1 observations added.
NOTE: The data set WORK.FACIT_MI_TEMP3 has 9 observations and 4 variables.
NOTE: PROCEDURE APPEND used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * This removes duplicates for other factor that occur when Covgroup and Treatment use same variable 
(SQL side effect);
MPRINT(PART1A):   proc sort data=facit_mi_temp3 NODUPKEY;
MPRINT(PART1A):   by Name index;
MPRINT(PART1A):   run;

NOTE: There were 9 observations read from the data set WORK.FACIT_MI_TEMP3.
NOTE: 0 observations with duplicate key values were deleted.
NOTE: The data set WORK.FACIT_MI_TEMP3 has 9 observations and 4 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Check if there are any missing values in the quantitative covariates;
MPRINT(PART1A):   data _null_;
MPRINT(PART1A):   set facit_mi_temp0 end=myend;
MPRINT(PART1A):   length mylist $ 120;
MPRINT(PART1A):   retain mylist;
MPRINT(PART1A):   if BASE <= .z and not index(mylist,"BASE") then mylist= trim(mylist) || " BASE,";
MPRINT(PART1A):   if myend then do;
MPRINT(PART1A):   if length(mylist)>1 then call symput("Name",substr(mylist,1,length(mylist)-1));
MPRINT(PART1A):   else call symput("Name"," ");
MPRINT(PART1A):   end;
65                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1A):   run;

NOTE: There were 75 observations read from the data set WORK.FACIT_MI_TEMP0.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Check if any records have a missing value for any categorical variable;
MPRINT(PART1A):   proc sql noprint;
MPRINT(PART1A):   select Name into :Name separated by ", " from facit_mi_temp3 where (Clevel="" or left(Clevel)=".") 
and Nlevel <=.z ;
NOTE: No rows were selected.
MPRINT(PART1A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Check if any of the categorical variables have only one level;
MPRINT(PART1A):   * Note that we allow the treatment variable to have only one level;
MPRINT(PART1A):   proc sql noprint;
MPRINT(PART1A):   select Name into :Name separated by ", " from (select Name, Count(*) as N from 
facit_mi_temp3(where=(Name Notin("TRT01PN","I_1"))) group by Name) where n=1;
NOTE: No rows were selected.
MPRINT(PART1A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Now join these levels back into the master data set;
MPRINT(PART1A):   proc sql noprint;
MPRINT(PART1A):   create table facit_mi_master2 as select a.*, b.Clevel, b.Nlevel, b.index from facit_mi_master1 A full 
join facit_mi_temp3 B on A.Vname=B.Name order by Role, Vname, index;
NOTE: Table WORK.FACIT_MI_MASTER2 created, with 14 rows and 10 columns.

MPRINT(PART1A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.01 seconds
      

MPRINT(PART1A):   Data facit_mi_master;
MPRINT(PART1A):   set facit_mi_master2 end=myend;
MPRINT(PART1A):   * Set index when there is no Covgroup;
MPRINT(PART1A):   if role="Covgp" and index=. then index=1;
MPRINT(PART1A):   output;
MPRINT(PART1A):   if myend then do;
MPRINT(PART1A):   Vname=" ";
MPRINT(PART1A):   Role="DSName";
MPRINT(PART1A):   Vlabel="dat_ana_mi_supp";
MPRINT(PART1A):   Vnum=.;
MPRINT(PART1A):   Vtype=" ";
MPRINT(PART1A):   Vlen=.;
MPRINT(PART1A):   Vformat=" ";
MPRINT(PART1A):   CLevel=" ";
MPRINT(PART1A):   Nlevel=.;
66                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1A):   Index=.;
MPRINT(PART1A):   output;
MPRINT(PART1A):   end;
MPRINT(PART1A):   run;

NOTE: There were 14 observations read from the data set WORK.FACIT_MI_MASTER2.
NOTE: The data set WORK.FACIT_MI_MASTER has 15 observations and 10 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   proc sort data=facit_mi_temp0 out=facit_mi_temp6 NODUPKEY;
MPRINT(PART1A):   by USUBJID AVISITN;
MPRINT(PART1A):   run;

NOTE: There were 75 observations read from the data set WORK.FACIT_MI_TEMP0.
NOTE: 0 observations with duplicate key values were deleted.
NOTE: The data set WORK.FACIT_MI_TEMP6 has 75 observations and 37 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Check that the data set we will use in part 1B does not have duplicate records for a subject by 
time combination;
MPRINT(PART1A):   proc sql noprint;
MPRINT(PART1A):   select Count(*) into :n1 from facit_mi_temp0 ;
MPRINT(PART1A):   select Count(*) into :n2 from facit_mi_temp6;
MPRINT(PART1A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   * Build coded versions of Treat, Time, Catcov, Catcovbytime and Covgroup (I_ is used as prefix to 
indicate indexed version);
MPRINT(PART1A):   proc sql noprint;
MPRINT(PART1A):   *Note that this next line runs directly, so is ready for testing Vtype below at macro level;
MPRINT(PART1A):   select vtype into :vtype from facit_mi_master(where=(upcase(Vname)="TRT01PN" & Role in("CatCov" 
"Time" "CatCovby" "Treat" "Covgp")));
MPRINT(PART1A):   create table facit_mi_data2 as select A.*, B.index as I_TRT01PN from facit_mi_data1 A left join 
facit_mi_master(where=(upcase(Vname)="TRT01PN" & Role in("CatCov" "Time" "CatCovby" "Treat" "Covgp" ))) B on A.TRT01PN 
= B.Nlevel order by USUBJID, AVISITN;
NOTE: Table WORK.FACIT_MI_DATA2 created, with 75 rows and 8 columns.

MPRINT(PART1A):   select max(I_TRT01PN < .z) into :check from facit_mi_data2;
0
MPRINT(PART1A):   *Note that this next line runs directly, so is ready for testing Vtype below at macro level;
MPRINT(PART1A):   select vtype into :vtype from facit_mi_master(where=(upcase(Vname)="AVISITN" & Role in("CatCov" 
"Time" "CatCovby" "Treat" "Covgp")));
MPRINT(PART1A):   create table facit_mi_data3 as select A.*, B.index as I_AVISITN from facit_mi_data2 A left join 
facit_mi_master(where=(upcase(Vname)="AVISITN" & Role in("CatCov" "Time" "CatCovby" "Treat" "Covgp" ))) B on A.AVISITN 
= B.Nlevel order by USUBJID, AVISITN;
NOTE: Table WORK.FACIT_MI_DATA3 created, with 75 rows and 9 columns.

MPRINT(PART1A):   select max(I_AVISITN < .z) into :check from facit_mi_data3;
0
67                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1A):   *Note that this next line runs directly, so is ready for testing Vtype below at macro level;
MPRINT(PART1A):   select vtype into :vtype from facit_mi_master(where=(upcase(Vname)="SYSTRCRF" & Role in("CatCov" 
"Time" "CatCovby" "Treat" "Covgp")));
MPRINT(PART1A):   create table facit_mi_data4 as select A.*, B.index as I_SYSTRCRF from facit_mi_data3 A left join 
facit_mi_master(where=(upcase(Vname)="SYSTRCRF" & Role in("CatCov" "Time" "CatCovby" "Treat" "Covgp" ))) B on 
A.SYSTRCRF = B.Clevel order by USUBJID, AVISITN;
NOTE: Table WORK.FACIT_MI_DATA4 created, with 75 rows and 10 columns.

MPRINT(PART1A):   select max(I_SYSTRCRF < .z) into :check from facit_mi_data4;
0
MPRINT(PART1A):   *Note that this next line runs directly, so is ready for testing Vtype below at macro level;
MPRINT(PART1A):   select vtype into :vtype from facit_mi_master(where=(upcase(Vname)="I_1" & Role in("CatCov" "Time" 
"CatCovby" "Treat" "Covgp")));
MPRINT(PART1A):   create table facit_mi_data5 as select A.*, B.index as I_I_1 from facit_mi_data4 A left join 
facit_mi_master(where=(upcase(Vname)="I_1" & Role in("CatCov" "Time" "CatCovby" "Treat" "Covgp" ))) B on A.I_1 = 
B.Nlevel order by USUBJID, AVISITN;
NOTE: Table WORK.FACIT_MI_DATA5 created, with 75 rows and 11 columns.

MPRINT(PART1A):   select max(I_I_1 < .z) into :check from facit_mi_data5;
0
MPRINT(PART1A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.04 seconds
      cpu time            0.01 seconds
      

MPRINT(PART1A):   * Copy and sort into _Datav (sort order required in Part2B);
MPRINT(PART1A):   proc sort data=facit_mi_data5 out=facit_mi_datav;
MPRINT(PART1A):   by USUBJID I_AVISITN;
MPRINT(PART1A):   run;

NOTE: There were 75 observations read from the data set WORK.FACIT_MI_DATA5.
NOTE: The data set WORK.FACIT_MI_DATAV has 75 observations and 11 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   proc datasets library=WORK nolist;
MPRINT(PART1A):   delete facit_mi_master1 facit_mi_master2 facit_mi_temp0 facit_mi_temp1 facit_mi_temp2 facit_mi_temp3 
facit_mi_temp4 facit_mi_temp5 facit_mi_temp6 facit_mi_data1 facit_mi_data2 facit_mi_data3 facit_mi_data4 facit_mi_data5 
quit;

NOTE: The file WORK.QUIT (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: Deleting WORK.FACIT_MI_MASTER1 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_MASTER2 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_TEMP0 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_TEMP1 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_TEMP2 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_TEMP3 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_TEMP4 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_TEMP5 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_TEMP6 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_DATA1 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_DATA2 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_DATA3 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_DATA4 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_DATA5 (memtype=DATA).
68                                                         The SAS System                            04:10 Wednesday, April 15, 2026

NOTE: PROCEDURE DATASETS used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1A):   proc sql;
MPRINT(PART1A):   update facit_mi_master set Vlabel="facit_mi @"||put(datetime(),datetime.) where Role="Master1A";
NOTE: 1 row was updated in WORK.FACIT_MI_MASTER.

MPRINT(PART1A):   delete from facit_mi_master where Role in("Master1B","Master2A","Master2B","Master3");
NOTE: No rows were deleted from WORK.FACIT_MI_MASTER.

MPRINT(PART1A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

################################
Macro Part1A ended succesfully
################################
MPRINT(FACIT_MI):  ;
MPRINT(PART1B):   proc sql noprint;
MPRINT(PART1B):   * Set status of Part1B as failed in case of error;
MPRINT(PART1B):   delete from facit_mi_master where Role="Master1B";
NOTE: No rows were deleted from WORK.FACIT_MI_MASTER.

MPRINT(PART1B):   insert into facit_mi_master set Vlabel="Failed", Role="Master1B";
NOTE: 1 row was inserted into WORK.FACIT_MI_MASTER.

MPRINT(PART1B):   * Remove any debris from existing Master data set;
MPRINT(PART1B):   delete from facit_mi_master where Role in("NDraws","Thin","Seed", 
"Master2A","Method","MethodV","Ref","RefV","VCRef","VCRefV","VCMeth","VCMethV", "Master2B","Seed", 
"Master3","ANWhere","ANTimes","ANRef","ANTreat","ANCov","ANCatCov","ANCovgp","Delta","DeltaV","DLag","Dgroups","DgroupsV
");
NOTE: No rows were deleted from WORK.FACIT_MI_MASTER.

MPRINT(PART1B):   * Record Ndraws and Thin in the master data set;
MPRINT(PART1B):   insert into facit_mi_master set Index=1, NLevel=200, Role="NDraws";
NOTE: 1 row was inserted into WORK.FACIT_MI_MASTER.

MPRINT(PART1B):   insert into facit_mi_master set Index=1, NLevel=100, Role="Thin";
NOTE: 1 row was inserted into WORK.FACIT_MI_MASTER.

MPRINT(PART1B):   insert into facit_mi_master set Index=1, NLevel=999, VLabel="MCMC", Role="Seed";
NOTE: 1 row was inserted into WORK.FACIT_MI_MASTER.

MPRINT(PART1B):   * Check if previous section (PART1A) ran correctly;
MPRINT(PART1B):   select Vlabel into :loc1A from facit_mi_master(where=(Role="Master1A"));
MPRINT(PART1B):   * Reload the macro variables;
MPRINT(PART1B):   select vname into :Response from facit_mi_master(where=(Role="Response"));
MPRINT(PART1B):   select vname into :PEWhere from facit_mi_master(where=(Role="PEWhere"));
MPRINT(PART1B):   select vtype, vname into :Timetype, :Time from facit_mi_master(where=(Role="Time" and index=1));
MPRINT(PART1B):   select vname into :Subject from facit_mi_master(where=(Role="Subject"));
MPRINT(PART1B):   select vname into :Treat from facit_mi_master(where=(Role="Treat" and index=1));
MPRINT(PART1B):   select vname, "STD_"||Vname into :Cov separated by " " , :STD_cov separated by " " from 
facit_mi_master(where=(Role="Cov"));
MPRINT(PART1B):   select vname, "STD_"||Vname into :CovbyTime separated by " " , :STD_CovbyTime separated by " " from 
69                                                         The SAS System                            04:10 Wednesday, April 15, 2026

facit_mi_master(where=(Role="Covbytim"));
NOTE: No rows were selected.
MPRINT(PART1B):   select vname, "I_"||Vname into :Catcov separated by " " , :I_Catcov separated by " " from 
facit_mi_master(where=(Role="CatCov" and index=1));
MPRINT(PART1B):   select vname, "I_"||Vname into :CatCovbytime separated by " " , :I_Catcovbytime separated by " " from 
facit_mi_master(where=(Role="CatCovby" and index=1));
NOTE: No rows were selected.
MPRINT(PART1B):   select vtype, vname into :Covgptype, :Covgroup from facit_mi_master(where=(Role="Covgp"));
MPRINT(PART1B):   select max(index) into :Ntimes from facit_mi_master(where=(Role="Time"));
MPRINT(PART1B):   select max(index) into :Nwish from facit_mi_master(where=(Role="Covgp"));
MPRINT(PART1B):   select max(index) into :NTreat from facit_mi_master(where=(Role="Treat"));
MPRINT(PART1B):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.01 seconds
      cpu time            0.01 seconds
      

MPRINT(PART1B):   * Check if jobname is a valid sas name;
MPRINT(PART1B):   data _null_;
MPRINT(PART1B):   facit_mi=0;
MPRINT(PART1B):   run;

NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Delete data sets before we start;
MPRINT(PART1B):   proc datasets library=WORK nolist;
MPRINT(PART1B):   delete dummy facit_mi_classout facit_mi_covp facit_mi_datap1 facit_mi_mean facit_mi_patterns1 
facit_mi_solf facit_mi_std facit_mi_temp7 facit_mi_temp12 facit_mi_datamcmc facit_mi_patterns facit_mi_postcvp 
facit_mi_postlp facit_mi_datap;
MPRINT(PART1B):   quit;

NOTE: The file WORK.DUMMY (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_CLASSOUT (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_COVP (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_DATAP1 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_MEAN (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_PATTERNS1 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_SOLF (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_STD (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_TEMP7 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_TEMP12 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_DATAMCMC (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: Deleting WORK.FACIT_MI_PATTERNS (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_POSTCVP (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_POSTLP (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_DATAP (memtype=DATA).
NOTE: PROCEDURE DATASETS used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Now centre and standarise the numeric covariates ready for mcmc;
MPRINT(PART1B):   * Count the number of quantitative covariates;
MPRINT(PART1B):   proc sql noprint;
MPRINT(PART1B):   select count(distinct Vname) into :N from facit_mi_master(where=(Role in("Cov","Covbytim")));
70                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Here we standardise the regression covariates in the data set (data1 from macro Part1A);
MPRINT(PART1B):   * This is so that the regression parameters in the posterior are less correlated helping proc MCMC;
MPRINT(PART1B):   * This has no impact on the imputation;
MPRINT(PART1B):   * Note we use PEWhere= here ;
MPRINT(PART1B):   proc means data=facit_mi_datav noprint mean;
MPRINT(PART1B):   var BASE ;
MPRINT(PART1B):   output out=facit_mi_mean mean= BASE ;
MPRINT(PART1B):   output out=facit_mi_std std= BASE ;
MPRINT(PART1B):   run;

NOTE: There were 75 observations read from the data set WORK.FACIT_MI_DATAV.
NOTE: The data set WORK.FACIT_MI_MEAN has 1 observations and 3 variables.
NOTE: The data set WORK.FACIT_MI_STD has 1 observations and 3 variables.
NOTE: PROCEDURE MEANS used (Total process time):
      real time           0.01 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   data facit_mi_data1;
MPRINT(PART1B):   set facit_mi_mean(IN=InMean) facit_mi_std(in=InSTD) facit_mi_datav;
MPRINT(PART1B):   drop _type_ _freq_ i;
MPRINT(PART1B):   array my_mean[1] _temporary_;
MPRINT(PART1B):   array my_std[1] _temporary_;
MPRINT(PART1B):   array My_list[1] BASE ;
MPRINT(PART1B):   array std_list[1] STD_BASE ;
MPRINT(PART1B):   if inmean then do;
MPRINT(PART1B):   do i=1 to 1;
MPRINT(PART1B):   My_mean[i]=My_List[i];
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   else if instd then do;
MPRINT(PART1B):   do i=1 to 1;
MPRINT(PART1B):   My_std[i]=My_List[i];
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   else do;
MPRINT(PART1B):   do i=1 to 1;
MPRINT(PART1B):   STD_List[i]=(My_List[i]-My_mean[i])/My_std[i];
MPRINT(PART1B):   end;
MPRINT(PART1B):   output;
MPRINT(PART1B):   end;
MPRINT(PART1B):   run;

NOTE: There were 1 observations read from the data set WORK.FACIT_MI_MEAN.
NOTE: There were 1 observations read from the data set WORK.FACIT_MI_STD.
NOTE: There were 75 observations read from the data set WORK.FACIT_MI_DATAV.
NOTE: The data set WORK.FACIT_MI_DATA1 has 75 observations and 12 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

71                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   * Test for covariates changing in data set (this is not allowed);
MPRINT(PART1B):   * In Temp7 we have all the distinct records (after dropping the Response, Time and ind index of Time);
MPRINT(PART1B):   * These are used later to merge into parallel data;
MPRINT(PART1B):   * Then count number of distinct records within a subject and error if this is more than one;
MPRINT(PART1B):   proc sql noprint;
MPRINT(PART1B):   create table facit_mi_temp7 as select distinct * from facit_mi_data1(drop=AVAL AVISITN I_AVISITN ) 
order by USUBJID;
NOTE: Table WORK.FACIT_MI_TEMP7 created, with 21 rows and 9 columns.

MPRINT(PART1B):   select max(Num) into :maxrows from (select count(USUBJID) as Num from facit_mi_temp7 group by 
USUBJID);
MPRINT(PART1B):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Make the Response data parallel rather than vertical;
MPRINT(PART1B):   proc transpose data=facit_mi_data1(keep=USUBJID AVAL I_AVISITN ) out=facit_mi_temp12(drop=_name_ ) 
prefix=Super_Response;
MPRINT(PART1B):   var AVAL;
MPRINT(PART1B):   id I_AVISITN ;
MPRINT(PART1B):   by USUBJID;
MPRINT(PART1B):   run;

NOTE: There were 75 observations read from the data set WORK.FACIT_MI_DATA1.
NOTE: The data set WORK.FACIT_MI_TEMP12 has 21 observations and 6 variables.
NOTE: PROCEDURE TRANSPOSE used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Merge the covariate data to parallel outcome data;
MPRINT(PART1B):   * and build pattern indicator variable.;
MPRINT(PART1B):   data facit_mi_dataP1;
MPRINT(PART1B):   array Super_Response[4]Super_Response1-Super_Response4;
MPRINT(PART1B):   merge facit_mi_temp7 facit_mi_temp12 END=Myend;
MPRINT(PART1B):  ;
MPRINT(PART1B):   by USUBJID;
MPRINT(PART1B):   drop i;
MPRINT(PART1B):   Subject_index=_N_;
MPRINT(PART1B):   Super_Pattern=0;
MPRINT(PART1B):   Super_Nmiss=0;
MPRINT(PART1B):   Super_Last=0;
MPRINT(PART1B):   do i=1 to 4;
MPRINT(PART1B):   if Super_Response[i]<=.z then do;
MPRINT(PART1B):   Super_Pattern=Super_Pattern*2+1;
MPRINT(PART1B):   Super_Nmiss=Super_Nmiss+1;
MPRINT(PART1B):   end;
MPRINT(PART1B):   else do;
MPRINT(PART1B):   Super_Pattern=Super_Pattern*2;
MPRINT(PART1B):   Super_Last=i;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   run;

NOTE: There were 21 observations read from the data set WORK.FACIT_MI_TEMP7.
NOTE: There were 21 observations read from the data set WORK.FACIT_MI_TEMP12.
72                                                         The SAS System                            04:10 Wednesday, April 15, 2026

NOTE: The data set WORK.FACIT_MI_DATAP1 has 21 observations and 18 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   proc sql noprint;
MPRINT(PART1B):   create table facit_mi_patterns1 as select distinct Super_Pattern, Super_Nmiss, Super_Last from 
facit_mi_dataP1 order by Super_Pattern;
NOTE: Table WORK.FACIT_MI_PATTERNS1 created, with 4 rows and 3 columns.

MPRINT(PART1B):   select count(*) into :NPatt from facit_mi_patterns1 quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   data facit_mi_patterns;
MPRINT(PART1B):   set facit_mi_patterns1;
MPRINT(PART1B):   Super_Pindex=_N_;
MPRINT(PART1B):   run;

NOTE: There were 4 observations read from the data set WORK.FACIT_MI_PATTERNS1.
NOTE: The data set WORK.FACIT_MI_PATTERNS has 4 observations and 4 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Note that datap is sorted here into order Super_Pindex, <Covgroup> , SUBJECT order;
MPRINT(PART1B):   proc sql noprint;
MPRINT(PART1B):   create table facit_mi_datap as select A.*, B.Super_Pindex from facit_mi_dataP1 A left join 
facit_mi_patterns B on A.Super_Pattern = b.Super_Pattern order by Super_Pindex, I_1, USUBJID;
NOTE: Table WORK.FACIT_MI_DATAP created, with 21 rows and 19 columns.

MPRINT(PART1B):   select max(index) into :NWish from facit_mi_master(where=(Role ="Covgp"));
MPRINT(PART1B):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Run proc MIXED;
MPRINT(PART1B):   ODS select none;
MPRINT(PART1B):   ods output solutionf=facit_mi_Solf Covparms=facit_mi_Covp ;
MPRINT(PART1B):   proc mixed data=facit_mi_data1 ;
MPRINT(PART1B):   ;
MPRINT(PART1B):   class USUBJID I_TRT01PN I_SYSTRCRF I_I_1 I_AVISITN ;
MPRINT(PART1B):   model AVAL = I_TRT01PN*I_AVISITN I_SYSTRCRF STD_BASE / SOLUTION DDFM=RESIDUAL NOINT;
MPRINT(PART1B):   repeated I_AVISITN /SUBJECT=USUBJID TYPE=UN ;
MPRINT(PART1B):  ;
MPRINT(PART1B):   run;

NOTE: 5 observations are not included because of missing values.
NOTE: Convergence criteria met.
NOTE: The data set WORK.FACIT_MI_COVP has 10 observations and 3 variables.
NOTE: The data set WORK.FACIT_MI_SOLF has 11 observations and 9 variables.
NOTE: PROCEDURE MIXED used (Total process time):
73                                                         The SAS System                            04:10 Wednesday, April 15, 2026

      real time           0.01 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   ods output clear;
MPRINT(PART1B):   ods select all;
MPRINT(PART1B):   * Build text to declare R matrix in proc MCMC;
MPRINT(PART1B):   data _null_;
MPRINT(PART1B):   set facit_mi_Covp end=myend;
MPRINT(PART1B):  ;
MPRINT(PART1B):   length txt $ 10240;
MPRINT(PART1B):   retain row 1 col 1;
MPRINT(PART1B):   array v[ 1,4,4] _temporary_;
MPRINT(PART1B):   g=1;
MPRINT(PART1B):   row=input(scan(Covparm,1,"UN(,)"),6.0);
MPRINT(PART1B):   col=input(scan(Covparm,2,"UN(,)"),6.0);
MPRINT(PART1B):   v[g,row,col]=estimate;
MPRINT(PART1B):   v[g,col,row]=estimate;
MPRINT(PART1B):   if myend then do;
MPRINT(PART1B):   txt=" ";
MPRINT(PART1B):   do g=1 to 1;
MPRINT(PART1B):   do i=1 to 4;
MPRINT(PART1B):   do j=1 to 4;
MPRINT(PART1B):   if (length(txt)+10) > 10240 then do;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Insufficient space for R matrix text. Increase macro parameter Maxtxt in 
code.");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   txt=trim(txt)||" "||put(v[g,i,j], best8.);
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   call symput("Rmatrix",txt);
MPRINT(PART1B):   end;
MPRINT(PART1B):   run;

NOTE: There were 10 observations read from the data set WORK.FACIT_MI_COVP.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Set up macro variables to allow us to build the required array statement;
MPRINT(PART1B):   proc sql noprint;
MPRINT(PART1B):   select Max(index), Max(Vname) as Vname Into :NLcatcov separated by " ", :Vcatcov separated by " " 
from facit_mi_master(where=(Role ="CatCov")) group by Vname order by Vname;
MPRINT(PART1B):   select Count(*) into :N from facit_mi_solf;
MPRINT(PART1B):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Parmstext is text for the main parms statement for linear predictor parameters in MCMC;
MPRINT(PART1B):   * Difficulty is that Effect in SOLUTION data set is truncated by SAS at 20 characters;
MPRINT(PART1B):   * So we extract based on order of terms in model, and cross check truncated names of variables;
MPRINT(PART1B):   data _null_;
74                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   set facit_mi_Solf end=myend;
MPRINT(PART1B):   *length txt mtxt $ 10240;
MPRINT(PART1B):   length txt txtnocov $ 10240;
MPRINT(PART1B):   length txt1 txt2 $ 32;
MPRINT(PART1B):   array hold[ 11] _temporary_;
MPRINT(PART1B):   array heffect[ 11] $20 _temporary_;
MPRINT(PART1B):   * For constrained parameters set hold[ ] as missing, and trap later;
MPRINT(PART1B):   if df>.z then hold[_N_]=estimate;
MPRINT(PART1B):   else hold[_n_]=.;
MPRINT(PART1B):   heffect[_N_]=effect;
MPRINT(PART1B):   if myend then do;
MPRINT(PART1B):   n=1;
MPRINT(PART1B):   txt=" ";
MPRINT(PART1B):   do i =1 to 2;
MPRINT(PART1B):   * Have separate PARMS for each treatment arm;
MPRINT(PART1B):   txt=trim(txt) || " ;PARMS";
MPRINT(PART1B):   do j=1 to 4;
MPRINT(PART1B):   if (length(txt)+100) > 10240 then do;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Insufficient space for PARMS text. Increase macro parameter Maxtxt in code.");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   txt=trim(txt) || " P_I_TRT01PN_" || trim(left(put(n,4.0))) || " " || left(put(hold[n],best8.));
MPRINT(PART1B):   txt1=scan(heffect[n],1,"*");
MPRINT(PART1B):   if upcase(substr("I_TRT01PN",1,length(txt1))) ^= upcase(txt1) then do;
MPRINT(PART1B):   left=upcase(substr("I_TRT01PN",1,length(txt1)));
MPRINT(PART1B):   right=upcase(txt1);
MPRINT(PART1B):   put left=;
MPRINT(PART1B):   put right=;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Mismatch in Effect label in output from MIXED:"||txt1);
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   n=n+1;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   * And place all the other fixed effect parmaters in their own block;
MPRINT(PART1B):   * Hold current setting incase there are none;
MPRINT(PART1B):   txtnocov=txt;
MPRINT(PART1B):   txt=trim(txt) || " ;PARMS";
MPRINT(PART1B):   txt2="P_I_SYSTRCRF_1";
MPRINT(PART1B):   do i =1 to 2;
MPRINT(PART1B):   if hold[n]>.z then do;
MPRINT(PART1B):   if (length(txt)+100) > 10240 then do;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Insufficient space for PARMS text. Increase macro parameter Maxtxt in code.");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   txt=trim(txt) || " P_I_SYSTRCRF_" || trim(left(put(I,4.0))) || " " || left(put(hold[n],best8.));
MPRINT(PART1B):   txt1=scan(heffect[n],1,"*");
MPRINT(PART1B):   if upcase(substr("I_SYSTRCRF_",1,length(txt1))) ^= upcase(txt1) then do;
MPRINT(PART1B):   left=upcase(substr("I_SYSTRCRF_",1,length(txt1)));
MPRINT(PART1B):   right=upcase(txt1);
MPRINT(PART1B):   put left=;
MPRINT(PART1B):   put right=;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Mismatch in Effect label in output from MIXED:"||txt1 );
MPRINT(PART1B):   stop;
75                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   n=n+1;
MPRINT(PART1B):   end;
MPRINT(PART1B):   if (length(txt)+100) > 10240 then do;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Insufficient space for a text string. Increase macro parameter Maxtxt in 
code.");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   txt=trim(txt) || " P_STD_BASE " || left(put(hold[n],best8.));
MPRINT(PART1B):   txt2="P_STD_BASE";
MPRINT(PART1B):   txt1=scan(heffect[n],1,"*");
MPRINT(PART1B):   if upcase(substr("STD_BASE",1,length(txt1))) ^= upcase(txt1) then do;
MPRINT(PART1B):   left=upcase(substr("STD_BASE",1,length(txt1)));
MPRINT(PART1B):   right=upcase(txt1);
MPRINT(PART1B):   put left=;
MPRINT(PART1B):   put right=;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Mismatch in Effect label in output from MIXED:"||txt1 );
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   n=n+1;
MPRINT(PART1B):   * If we have no covariates then go back to txt before we added last PARMS;
MPRINT(PART1B):   if txt2 = " " then txt=txtnocov;
MPRINT(PART1B):   call symput("Parmstext",txt);
MPRINT(PART1B):   * Covptext is the name of one of the parameters in the additonal covariates Block;
MPRINT(PART1B):   * The value of this variable s used to check whether this bolck is updated in the MCMC procedure;
MPRINT(PART1B):  ;
MPRINT(PART1B):   call symput("Covptext",txt2);
MPRINT(PART1B):   end;
MPRINT(PART1B):   run;

NOTE: There were 11 observations read from the data set WORK.FACIT_MI_SOLF.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Dummy data set to keep procedure happy;
MPRINT(PART1B):   data dummy;
MPRINT(PART1B):   run;

NOTE: The data set WORK.DUMMY has 1 observations and 0 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   * Note that datap has already been sorted into order Super_Pindex, <Covgroup> , SUBJECT order;
MPRINT(PART1B):   * Remove from MCMC those subject with no repnse data at all;
MPRINT(PART1B):   data facit_mi_datamcmc;
MPRINT(PART1B):   set facit_mi_datap end=myend;
MPRINT(PART1B):   array Super_Response[4]Super_Response1-Super_Response4;
MPRINT(PART1B):   retain Nsubj 0;
MPRINT(PART1B):   drop Nsubj flag i;
MPRINT(PART1B):   ;
MPRINT(PART1B):   flag=0;
76                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   do i=1 to 4;
MPRINT(PART1B):   if Super_Response[i]> .z then flag=1;
MPRINT(PART1B):   end;
MPRINT(PART1B):   if flag then do;
MPRINT(PART1B):   output;
MPRINT(PART1B):   Nsubj=Nsubj+1;
MPRINT(PART1B):   end;
MPRINT(PART1B):   if myend then call symput("NSubj",left(put(Nsubj,6.0)));
MPRINT(PART1B):   run;

NOTE: There were 21 observations read from the data set WORK.FACIT_MI_DATAP.
NOTE: The data set WORK.FACIT_MI_DATAMCMC has 21 observations and 19 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   ODS select none;
MPRINT(PART1B):   ******************************************************************************;
MPRINT(PART1B):   * Query add NTU=2000;
MPRINT(PART1B):   proc mcmc data=dummy outpost=facit_mi_classout PLOTS=NONE nmc=20000 NTU=2000 mintune=4 nbi=1000 
seed=999 thin=100 jointmodel missing=AC monitor=( RMVout_1-RMVout_16 P_I_TRT01PN );
MPRINT(PART1B):   BEGINCNST;
MPRINT(PART1B):   if _eval_cnst_ then do;
MPRINT(PART1B):   * Read the data in;
MPRINT(PART1B):   * Super_Response is the repeated observations;
MPRINT(PART1B):   array Super_Response[1]/nosymbols;
MPRINT(PART1B):   rc = read_array("facit_mi_datamcmc", Super_Response ,"Super_Response1" ,"Super_Response2" 
,"Super_Response3" ,"Super_Response4" );
MPRINT(PART1B):   if rc then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem in MCMC reading data set facit_mi_datamcmc, variables Super_Response1 etc.";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   Nsubj=dim(Super_Response,1);
MPRINT(PART1B):   Ntimes=dim(Super_Response,2);
MPRINT(PART1B):   if Ntimes<=.z then Ntimes=1;
MPRINT(PART1B):   if Nsubj ^= 21 then do;
MPRINT(PART1B):   put "Macro Nsubj=21    , while records from data set is " Nsubj=;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Problem reading data. Number of subjects does not match.");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   * Array P_<Treat> to hold the treatment*time parmater;
MPRINT(PART1B):   array P_I_TRT01PN[2,4] P_I_TRT01PN_1-P_I_TRT01PN_8;
MPRINT(PART1B):   array I_TRT01PN[1]/nosymbols;
MPRINT(PART1B):   rc = read_array("facit_mi_datamcmc", I_TRT01PN, "I_TRT01PN");
MPRINT(PART1B):   if rc then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem in MCMC reading data set facit_mi_datamcmc, variable I_TRT01PN";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   * In the case where we have a Covgroup that is not the treatment group then load it as well;
MPRINT(PART1B):   array I_I_1[1]/nosymbols;
77                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   rc = read_array("facit_mi_datamcmc", I_I_1, "I_I_1");
MPRINT(PART1B):   if rc then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem in MCMC reading data set facit_mi_datamcmc, variable I_I_1";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   array Super_Pindex[1]/nosymbols;
MPRINT(PART1B):   rc = read_array("facit_mi_datamcmc", Super_Pindex, "Super_Pindex");
MPRINT(PART1B):   if rc then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem in MCMC reading data set facit_mi_datamcmc, variable Super_Pindex";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   array Spattern[1]/nosymbols;
MPRINT(PART1B):   rc = read_array("facit_mi_datamcmc", Spattern, "Super_Pattern");
MPRINT(PART1B):   if rc then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem in MCMC reading data set facit_mi_datamcmc, variable Super_Pattern";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   * Patt holds the actual pattern (binary notation) for the i th pattern;
MPRINT(PART1B):   array Patt[ 4];
MPRINT(PART1B):   * Vpoint points to index of stored V matrices for a specific subject;
MPRINT(PART1B):   array Vpoint[21 ];
MPRINT(PART1B):   * Vfind points to index of stored V matrices for a specific Covgroup by Pattern ;
MPRINT(PART1B):   array Vfind[ 1, 4];
MPRINT(PART1B):   do i=1 to 1;
MPRINT(PART1B):   do j=1 to 4;
MPRINT(PART1B):   Vfind[i,j]=0;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   PrevCG=.;
MPRINT(PART1B):   Prevp=.;
MPRINT(PART1B):   Vp=0;
MPRINT(PART1B):   * Note that datap was sorted into order Super_Pindex, <Covgroup> , SUBJECT order;
MPRINT(PART1B):   do s=1 to 21 ;
MPRINT(PART1B):   if I_I_1[s] ^= PrevCG | Super_Pindex[s]^=Prevp then do;
MPRINT(PART1B):   Prevcg=I_I_1[s];
MPRINT(PART1B):   PrevP=Super_Pindex[s];
MPRINT(PART1B):   Vp=Vp+1;
MPRINT(PART1B):   Vfind[Prevcg,PrevP]=vp;
MPRINT(PART1B):   end;
MPRINT(PART1B):   Vpoint[s]=Vp;
MPRINT(PART1B):   * Here we are putting the actual pattern into Patt;
MPRINT(PART1B):   Patt[Super_Pindex[s]]=Spattern[s];
MPRINT(PART1B):   end;
MPRINT(PART1B):   maxvp=vp;
MPRINT(PART1B):   * Set up array point, for each pattern which indexes the visits with data;
MPRINT(PART1B):   * Ndata[k] is the number of visits with data for this pattern;
MPRINT(PART1B):   array Point[ 4,4];
MPRINT(PART1B):   array Ndata[ 4];
MPRINT(PART1B):   do k=1 to 4;
78                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   ii=0;
MPRINT(PART1B):   iip=0;
MPRINT(PART1B):   chk=2**4;
MPRINT(PART1B):   code=patt[k];
MPRINT(PART1B):   do i=1 to 4;
MPRINT(PART1B):   chk=chk/2;
MPRINT(PART1B):   if code >= chk then do;
MPRINT(PART1B):   code=code-chk;
MPRINT(PART1B):   end;
MPRINT(PART1B):   else do;
MPRINT(PART1B):   * i is not missing;
MPRINT(PART1B):   ii=ii+1;
MPRINT(PART1B):   point[k,ii]=i;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   Ndata[k]=ii;
MPRINT(PART1B):   end;
MPRINT(PART1B):   ENDCNST;
MPRINT(PART1B):   end;
MPRINT(PART1B):   *******************************************************************************************;
MPRINT(PART1B):   * Declare the Wishart priors and invert to get repeated measures variance-covariance matrix;
MPRINT(PART1B):   * Declare parameters for MCMC;
MPRINT(PART1B):   array W_LS[ 1,4] W_LS1-W_LS4;
MPRINT(PART1B):   ***************************************<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<;
MPRINT(PART1B):   prior W_LS1 ~expchisq(4);
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _prior = lpdfechisq(W_LS1, _est0 );
MPRINT(PART1B):   end;
MPRINT(PART1B):   prior W_LS2 ~expchisq(3);
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _prior = _prior + lpdfechisq(W_LS2, _est1 );
MPRINT(PART1B):   end;
MPRINT(PART1B):   prior W_LS3 ~expchisq(2);
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _prior = _prior + lpdfechisq(W_LS3, _est2 );
MPRINT(PART1B):   end;
MPRINT(PART1B):   * With only one d.f. can get very small sampled values resulting in underflow.;
MPRINT(PART1B):   prior W_LS4 ~expchisq(1,lower=-28);
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _prior = _prior + lpdfechisq(W_LS4, _est3 , _est4);
MPRINT(PART1B):   end;
MPRINT(PART1B):   array W_Z[ 1,6] W_Z1-W_Z6;
MPRINT(PART1B):   prior W_Z1-W_Z6 ~ normal(0,var=1);
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _sd = sqrt(_est6);
MPRINT(PART1B):   _prior = _prior + lpdfnorm(W_Z1, _est5, _sd );
MPRINT(PART1B):   end;
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _sd = sqrt(_est6);
MPRINT(PART1B):   _prior = _prior + lpdfnorm(W_Z2, _est5, _sd );
MPRINT(PART1B):   end;
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _sd = sqrt(_est6);
MPRINT(PART1B):   _prior = _prior + lpdfnorm(W_Z3, _est5, _sd );
MPRINT(PART1B):   end;
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _sd = sqrt(_est6);
MPRINT(PART1B):   _prior = _prior + lpdfnorm(W_Z4, _est5, _sd );
79                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   end;
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _sd = sqrt(_est6);
MPRINT(PART1B):   _prior = _prior + lpdfnorm(W_Z5, _est5, _sd );
MPRINT(PART1B):   end;
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _sd = sqrt(_est6);
MPRINT(PART1B):   _prior = _prior + lpdfnorm(W_Z6, _est5, _sd );
MPRINT(PART1B):   end;
MPRINT(PART1B):   * Put each variance covariance matrix set of parameters on a separate PARMS statement;
MPRINT(PART1B):   ;
MPRINT(PART1B):   parms W_Z1-W_Z6 0 W_LS1 1.38629436111989 W_LS2 1.09861228866811 W_LS3 0.69314718055994 W_LS4 0 ;
MPRINT(PART1B):   * Declare working arrays;
MPRINT(PART1B):   ARRAY RMVout[ 1,4,4] RMVout_1-RMVout_16;
MPRINT(PART1B):   ARRAY RMV[4,4] RMV_1-RMV_16;
MPRINT(PART1B):   ARRAY IRMV[4,4] IRMV_1-IRMV_16;
MPRINT(PART1B):   array W_T[4,4];
MPRINT(PART1B):   array W_U[4,4];
MPRINT(PART1B):   array GW_U[ 1,4,4];
MPRINT(PART1B):   array W_Ctr[4,4];
MPRINT(PART1B):   array W_C[4,4];
MPRINT(PART1B):   array VV[16]VV1-VV16;
MPRINT(PART1B):   BEGINCNST;
MPRINT(PART1B):   if _eval_cnst_ then do;
MPRINT(PART1B):   **********************************************************************;
MPRINT(PART1B):   * Specify the R matrix for Wishart prior;
MPRINT(PART1B):   * This should be a best guess at the Variance covariance matrix;
MPRINT(PART1B):   * So we use the estimated matrix from REML;
MPRINT(PART1B):   * Note that this is still an uniformative prior as d.f. is set to tbe the number of times;
MPRINT(PART1B):   array GTestR [ 1,4,4] ( 21.65479 9.640414 2.795688 2.246426 9.640414 73.43704 66.76824 65.33466 
2.795688 66.76824 70.60576 73.8339 2.246426 65.33466 73.8339 92.07155 );
MPRINT(PART1B):   array TestR [4,4] ;
MPRINT(PART1B):   ARRAY Temp[4,4];
MPRINT(PART1B):   do g=1 to 1;
MPRINT(PART1B):   do i=1 to 4;
MPRINT(PART1B):   do j=1 to 4;
MPRINT(PART1B):   TestR[i,j]=GTestR[g,i,j];
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   call inv(TestR,Temp);
MPRINT(PART1B):   do i=1 to 4;
MPRINT(PART1B):   do j=1 to 4;
MPRINT(PART1B):   W_C[i,j] = Temp[i,j];
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   call chol(W_C,W_U);
MPRINT(PART1B):   do i=1 to 4;
MPRINT(PART1B):   do j=1 to 4;
MPRINT(PART1B):   if W_U[i,j]<.z then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem with Positive definitiveness of R matrix from MIXED.";
MPRINT(PART1B):   Put "ERROR: Cholesky routine fails to work.";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   GW_U[g,i,j]=W_U[i,j];
MPRINT(PART1B):   end;
80                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   call zeromatrix(W_T);
MPRINT(PART1B):   *******************************************************************************************;
MPRINT(PART1B):   * Describe the model;
MPRINT(PART1B):   array BASE[1]/nosymbols;
MPRINT(PART1B):   rc = read_array("facit_mi_datamcmc", BASE, "STD_BASE");
MPRINT(PART1B):   if rc then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem in MCMC reading data set facit_mi_datamcmc, variable STD_BASE";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   array P_I_SYSTRCRF[2]P_I_SYSTRCRF_1-P_I_SYSTRCRF_2;
MPRINT(PART1B):   array I_SYSTRCRF[1]/nosymbols;
MPRINT(PART1B):   rc = read_array("facit_mi_datamcmc", I_SYSTRCRF, "I_SYSTRCRF");
MPRINT(PART1B):   if rc then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem in MCMC reading data set facit_mi_datamcmc, variable I_SYSTRCRF";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   * Add constraint. Note we set last level to zero in line with SAS;
MPRINT(PART1B):   P_I_SYSTRCRF[2]=0;
MPRINT(PART1B):   *Initialsie values for variables used in optimisation rules;
MPRINT(PART1B):   ARRAY OLDV1[ 1] _temporary_ ;
MPRINT(PART1B):   ARRAY OLDV2[ 1] _temporary_ ;
MPRINT(PART1B):   ARRAY VState[ 1] _temporary_ ;
MPRINT(PART1B):   ARRAY OLDT1[2] _temporary_ ;
MPRINT(PART1B):   ARRAY OLDT2[2] _temporary_ ;
MPRINT(PART1B):   do wish=1 to 1;
MPRINT(PART1B):   OLDV1[wish]=.a;
MPRINT(PART1B):   OLDV2[wish]=.a;
MPRINT(PART1B):   Vstate[wish]=0;
MPRINT(PART1B):   end;
MPRINT(PART1B):   do i = 1 to 2;
MPRINT(PART1B):   OLDT1[i]=.a;
MPRINT(PART1B):   OLDT2[i]=.a;
MPRINT(PART1B):   end;
MPRINT(PART1B):   OLDP1 =.a;
MPRINT(PART1B):   OLDP2 =.a;
MPRINT(PART1B):   optcode=.;
MPRINT(PART1B):   counter=0;
MPRINT(PART1B):   ENDCNST;
MPRINT(PART1B):   end;
MPRINT(PART1B):   * Declare array to hold mean for MV Normal;
MPRINT(PART1B):   * array arrmu[%eval(2*&Nsubj),&Ntimes];
MPRINT(PART1B):   array mu[4] mu1-mu4 ;
MPRINT(PART1B):   array Resp[4] Resp1-Resp4 ;
MPRINT(PART1B):   array loglike[21 ] _temporary_;
MPRINT(PART1B):   array oldLL[21 ] _temporary_;
MPRINT(PART1B):   array Covpart[21 ,4] _temporary_ ;
MPRINT(PART1B):   array PrevCovpart[21 ,4] _temporary_ ;
MPRINT(PART1B):   * Here is the PARMS declaration for the fixed effects parameters;
MPRINT(PART1B):   ;
MPRINT(PART1B):  PARMS P_I_TRT01PN_1 41.12746 P_I_TRT01PN_2 39.00246 P_I_TRT01PN_3 40.62605 P_I_TRT01PN_4 37.00181 ;
81                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):  PARMS P_I_TRT01PN_5 43.41473 P_I_TRT01PN_6 44.38682 P_I_TRT01PN_7 43.21498 P_I_TRT01PN_8 44.13894 ;
MPRINT(PART1B):  PARMS P_I_SYSTRCRF_1 -2.53234 P_STD_BASE 7.504324 ;
MPRINT(PART1B):   prior P_I_TRT01PN_1-P_I_TRT01PN_8 P_STD_BASE P_I_SYSTRCRF_1-P_I_SYSTRCRF_1 ~ general(1);
MPRINT(PART1B):   if _eval_prior_ then do;
MPRINT(PART1B):   _prior = _prior + _est7;
MPRINT(PART1B):   end;
MPRINT(PART1B):   ***********************************************;
MPRINT(PART1B):   * Optimiser code;
MPRINT(PART1B):   oldoptcode=optcode;
MPRINT(PART1B):   optcode=.;
MPRINT(PART1B):   do wish=1 to 1;
MPRINT(PART1B):   if OLDV1[wish]^=W_Z[Wish,1] then do;
MPRINT(PART1B):   if OLDV2[wish]^=W_Z[Wish,1] then do;
MPRINT(PART1B):   * New position for this covariance matrix;
MPRINT(PART1B):   * Calculation of inverse-Wishart and store away;
MPRINT(PART1B):   k=1;
MPRINT(PART1B):   do i = 1 to 4;
MPRINT(PART1B):   W_T[i,i] = exp(0.5*W_LS[Wish,i]);
MPRINT(PART1B):   W_U[i,i]=GW_U[wish,i,i] ;
MPRINT(PART1B):   do j = 1 to i-1;
MPRINT(PART1B):   W_T[i,j] = W_Z[Wish,k];
MPRINT(PART1B):   W_U[i,j]=GW_U[wish,i,j];
MPRINT(PART1B):   k=k+1;
MPRINT(PART1B):   * Other halves of matrices remain zero throughout;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   call mult(W_U,W_T,W_Ctr);
MPRINT(PART1B):   call transpose(W_Ctr,W_C);
MPRINT(PART1B):   call mult(W_Ctr,W_C,IRMV);
MPRINT(PART1B):   call inv(IRMV,RMV);
MPRINT(PART1B):   * If IRMV is not positive definite then whole of RMV matrix is set to missing;
MPRINT(PART1B):   if RMV[1,1] < .z then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem in MCMC with sampled Wishart matrix not being positive definite";
MPRINT(PART1B):   Put "ERROR: This should never happen. Please report to developer.";
MPRINT(PART1B):   Put "ERROR: Then we can reset limit on sample from chi-square with one d.f..";
MPRINT(PART1B):   Put "ERROR: Might happen with very sparse data. If so try a different seed.";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   * RMVOut is stored here so that it is monitored and gives the value fr the posterior distribution;
MPRINT(PART1B):   do ii=1 to 4;
MPRINT(PART1B):   do jj=1 to 4;
MPRINT(PART1B):   * Copy here ready for output;
MPRINT(PART1B):   RMVOut[wish,ii,jj]=RMV[ii,jj];
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   *Switch to other store location, so previous is in other position;
MPRINT(PART1B):   VState[wish]= maxvp - VState[wish];
MPRINT(PART1B):   kk=VState[wish];
MPRINT(PART1B):   * Load all the new variance-covariance matrices for each pattern;
MPRINT(PART1B):   do i=1 to 4;
MPRINT(PART1B):   * Vii is the identification number for the combination of Covgroup (Wish) and Pattern (i);
MPRINT(PART1B):   Vii=Vfind[wish,i];
MPRINT(PART1B):   * Test if this combination exists in the data set;
MPRINT(PART1B):   if Vii >0 then do;
MPRINT(PART1B):   * Select required parts of Varcovar matrix for this pattern and Covgroup;
82                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   * Note that this use the lower tridiagonal (column number <= row number);
MPRINT(PART1B):   iip=0;
MPRINT(PART1B):   do ii=1 to ndata[i];
MPRINT(PART1B):   k=point[i,ii];
MPRINT(PART1B):   do jj=1 to ii;
MPRINT(PART1B):   iip=iip+1;
MPRINT(PART1B):   vv[iip]= RMV[k,point[i,jj]];
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   * Now hand it to LOGMPDFSET;
MPRINT(PART1B):   * Use select statement with multiple possibles lines of code, so that size of matrix can be 
determined at run time;
MPRINT(PART1B):   select(ndata[i]);
MPRINT(PART1B):   when(1) rc3 = logmpdfset("V"||left(put(Vii+kk,6.0)), of VV1-VV1);
MPRINT(PART1B):   when(2) rc3 = logmpdfset("V"||left(put(Vii+kk,6.0)), of VV1-VV3);
MPRINT(PART1B):   when(3) rc3 = logmpdfset("V"||left(put(Vii+kk,6.0)), of VV1-VV6);
MPRINT(PART1B):   when(4) rc3 = logmpdfset("V"||left(put(Vii+kk,6.0)), of VV1-VV10);
MPRINT(PART1B):   end;
MPRINT(PART1B):   if rc3<=.z then do;
MPRINT(PART1B):   Put "ERROR: Multivariate Repeated Measures using proc MCMC";
MPRINT(PART1B):   put "ERROR: Failed loading V matrix";
MPRINT(PART1B):   Put "ERROR:";
MPRINT(PART1B):   put rc3=;
MPRINT(PART1B):   ii=Ndata[i];
MPRINT(PART1B):   put ii= ;
MPRINT(PART1B):   do i=1 to 16;
MPRINT(PART1B):   val=vv[i];
MPRINT(PART1B):   put i= val=;
MPRINT(PART1B):   end;
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   OLDV2[wish]=OLDV1[wish];
MPRINT(PART1B):   OLDV1[wish]=W_Z[Wish,1];
MPRINT(PART1B):   if optcode ^= . and oldoptcode>.z then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem with code used for optimization";
MPRINT(PART1B):   Put "ERROR: This should never happen. Please report to developer.";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   optcode=-wish;
MPRINT(PART1B):   end;
MPRINT(PART1B):   else do;
MPRINT(PART1B):   * Return to previous setting;
MPRINT(PART1B):   * Return loglike value and Switch the pointer back;
MPRINT(PART1B):   do s=1 to 21 ;
MPRINT(PART1B):   if I_I_1[s]=Wish then loglike[s]=OldLL[s];
MPRINT(PART1B):   end;
MPRINT(PART1B):   VState[wish]= maxvp - VState[wish];
MPRINT(PART1B):   a=OLDV1[wish];
MPRINT(PART1B):   OLDV1[wish]=OLDV2[wish];
MPRINT(PART1B):   OLDV2[wish]=a;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
83                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   do i = 1 to 2;
MPRINT(PART1B):   if OLDT1[i]^= P_I_TRT01PN[i,1] then do;
MPRINT(PART1B):   if OLDT2[i]^= P_I_TRT01PN[i,1] then do;
MPRINT(PART1B):   * New position;
MPRINT(PART1B):   if optcode ^= . and oldoptcode>.z then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem with code used for optimization";
MPRINT(PART1B):   Put "ERROR: This should never happen. Please report to developer.";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   optcode=i;
MPRINT(PART1B):   OLDT2[i]=OLDT1[i];
MPRINT(PART1B):   OLDT1[i]=P_I_TRT01PN[i,1];
MPRINT(PART1B):   end;
MPRINT(PART1B):   else do;
MPRINT(PART1B):   * Return to previous setting;
MPRINT(PART1B):   * Return loglike value and Switch the pointer back;
MPRINT(PART1B):   do s=1 to 21 ;
MPRINT(PART1B):   if I_TRT01PN[s]=i then loglike[s]=OldLL[s];
MPRINT(PART1B):   end;
MPRINT(PART1B):   a=OLDT1[i];
MPRINT(PART1B):   OLDT1[i]=OLDT2[i];
MPRINT(PART1B):   OLDT2[i]=a;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   if OLDP1 ^= P_STD_BASE then do;
MPRINT(PART1B):   if OLDP2 ^= P_STD_BASE then do;
MPRINT(PART1B):   * New position;
MPRINT(PART1B):   do s=1 to 21 ;
MPRINT(PART1B):   do time=1 to 4;
MPRINT(PART1B):   PrevCovpart[s,time]=Covpart[s,time];
MPRINT(PART1B):   Covpart[s,time]=+ P_STD_BASE*BASE[s] + P_I_SYSTRCRF[I_SYSTRCRF[s]];
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   if optcode ^= . and oldoptcode>.z then do;
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   Put "ERROR: Problem with code used for optimization";
MPRINT(PART1B):   Put "ERROR: This should never happen. Please report to developer.";
MPRINT(PART1B):   Put "ERROR: ";
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   optcode=0;
MPRINT(PART1B):   OLDP2=OLDP1;
MPRINT(PART1B):   OLDP1=P_STD_BASE ;
MPRINT(PART1B):   end;
MPRINT(PART1B):   else do;
MPRINT(PART1B):   * Return to previous;
MPRINT(PART1B):   do s=1 to 21 ;
MPRINT(PART1B):   do time=1 to 4;
MPRINT(PART1B):   Covpart[s,time]=PrevCovpart[s,time];
MPRINT(PART1B):   loglike[s]=OldLL[s];
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   a=OLDP1;
84                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   OLDP1=OLDP2;
MPRINT(PART1B):   OLDP2=a;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   *Force update of all records at start by setting optcode to 0;
MPRINT(PART1B):   if oldoptcode=. then optcode=0;
MPRINT(PART1B):   *****************************;
MPRINT(PART1B):   * Specify MVNormal likelihood;
MPRINT(PART1B):   * Now actually calculate the likelihood (every record in every scan);
MPRINT(PART1B):   ll=0;
MPRINT(PART1B):   do s=1 to 21 ;
MPRINT(PART1B):   * Check if this to be recalculated;
MPRINT(PART1B):   if optcode=0 or (optcode=-I_I_1[s]) or (optcode=I_TRT01PN[s]) then do;
MPRINT(PART1B):   * Select required data;
MPRINT(PART1B):   p=Super_Pindex[s];
MPRINT(PART1B):   nv=Ndata[p];
MPRINT(PART1B):   it=I_TRT01PN[s];
MPRINT(PART1B):   do i=1 to nv;
MPRINT(PART1B):   time=point[p,i];
MPRINT(PART1B):   Resp[i]=Super_Response[s,time];
MPRINT(PART1B):   Mu[i]=P_I_TRT01PN[it,time] + Covpart[s,time] ;
MPRINT(PART1B):   end;
MPRINT(PART1B):   *Select the correct Var-covar matrix;
MPRINT(PART1B):   select(nv);
MPRINT(PART1B):   when(1) mvnlp = logmpdfnormal(of Resp1-Resp1, of Mu1-mu1, 
"V"||left(put(Vpoint[s]+VState[I_I_1[s]],6.0)));
MPRINT(PART1B):   when(2) mvnlp = logmpdfnormal(of Resp1-Resp2, of Mu1-mu2, 
"V"||left(put(Vpoint[s]+VState[I_I_1[s]],6.0)));
MPRINT(PART1B):   when(3) mvnlp = logmpdfnormal(of Resp1-Resp3, of Mu1-mu3, 
"V"||left(put(Vpoint[s]+VState[I_I_1[s]],6.0)));
MPRINT(PART1B):   when(4) mvnlp = logmpdfnormal(of Resp1-Resp4, of Mu1-mu4, 
"V"||left(put(Vpoint[s]+VState[I_I_1[s]],6.0)));
MPRINT(PART1B):   otherwise mvnlp=.;
MPRINT(PART1B):   end;
MPRINT(PART1B):   if mvnlp <= .z then do;
MPRINT(PART1B):   Put "ERROR: Multivariate Repeated Measures using proc MCMC";
MPRINT(PART1B):   Put "ERROR: Missing value created for likelihood";
MPRINT(PART1B):   Put "ERROR: " mvnlp= "  Response is:";
MPRINT(PART1B):   do i=1 to 4;
MPRINT(PART1B):   a=Resp[i];
MPRINT(PART1B):   put "ERR" "OR: Response[" i "]= " a;
MPRINT(PART1B):   a=Mu[i];
MPRINT(PART1B):   put "ERR" "OR: Mu[" i "]= " a;
MPRINT(PART1B):   end;
MPRINT(PART1B):   Put "ERR" "OR:" ;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Illegal likelihood calculation.");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   oldLL[s]=loglike[s];
MPRINT(PART1B):   loglike[s]=mvnlp;
MPRINT(PART1B):   end;
MPRINT(PART1B):   ll=ll+loglike[s];
MPRINT(PART1B):   end;
MPRINT(PART1B):   model general(ll);
MPRINT(PART1B):   _model = 0;
MPRINT(PART1B):   _model1 = _est8;
MPRINT(PART1B):   _model = _model + _model1;
85                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   run;

NOTE: Tuning the proposal distribution.
NOTE: Generating the burn-in samples.
NOTE: Beginning sample generation.
NOTE: The data set WORK.FACIT_MI_CLASSOUT has 200 observations and 40 variables.
NOTE: PROCEDURE MCMC used (Total process time):
      real time           8.23 seconds
      cpu time            2.15 seconds
      

MPRINT(PART1B):   ods select all;
MPRINT(PART1B):   * Free up the space;
MPRINT(PART1B):   data _null_;
MPRINT(PART1B):   rc=logmpdffree();
MPRINT(PART1B):   run;
NOTE: The matrix -  V1 - has been deleted.
NOTE: The matrix -  V2 - has been deleted.
NOTE: The matrix -  V3 - has been deleted.
NOTE: The matrix -  V4 - has been deleted.
NOTE: The matrix -  V5 - has been deleted.
NOTE: The matrix -  V6 - has been deleted.
NOTE: The matrix -  V7 - has been deleted.
NOTE: The matrix -  V8 - has been deleted.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   ods output clear;
MPRINT(PART1B):   data facit_mi_postLP;
MPRINT(PART1B):   set facit_mi_classout;
MPRINT(PART1B):   length Vname $32;
MPRINT(PART1B):   keep draw Vname Icat Itime value;
MPRINT(PART1B):   retain draw 0;
MPRINT(PART1B):   array P_I_TRT01PN[2,4] P_I_TRT01PN_1-P_I_TRT01PN_8;
MPRINT(PART1B):   draw=draw+1;
MPRINT(PART1B):   Vname="I_TRT01PN";
MPRINT(PART1B):   do icat=1 to 2;
MPRINT(PART1B):   do itime=1 to 4;
MPRINT(PART1B):   Value=P_I_TRT01PN[icat,itime];
MPRINT(PART1B):   output;
MPRINT(PART1B):   end;
MPRINT(PART1B):   end;
MPRINT(PART1B):   Vname="STD_BASE";
MPRINT(PART1B):   Itime=.;
MPRINT(PART1B):   Icat=.;
MPRINT(PART1B):   Value=P_STD_BASE;
MPRINT(PART1B):   output;
MPRINT(PART1B):   array P_I_SYSTRCRF[2]P_I_SYSTRCRF_1-P_I_SYSTRCRF_2 ;
MPRINT(PART1B):   Vname="I_SYSTRCRF";
MPRINT(PART1B):   Itime=.;
MPRINT(PART1B):   P_I_SYSTRCRF[2]=0;
MPRINT(PART1B):   do icat=1 to 2;
MPRINT(PART1B):   Value=P_I_SYSTRCRF[icat];
MPRINT(PART1B):   output;
MPRINT(PART1B):   end;
MPRINT(PART1B):   * Add check here to trap any problems;
86                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART1B):   if draw <.z or value <.z then do;
MPRINT(PART1B):   call symput("Stopflag","1");
MPRINT(PART1B):   call symput("Errtext1","Error in posterior sample data set. Please report.");
MPRINT(PART1B):   stop;
MPRINT(PART1B):   end;
MPRINT(PART1B):   run;

NOTE: There were 200 observations read from the data set WORK.FACIT_MI_CLASSOUT.
NOTE: The data set WORK.FACIT_MI_POSTLP has 2200 observations and 5 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   data facit_mi_postCVP;
MPRINT(PART1B):   set facit_mi_classout;
MPRINT(PART1B):   keep draw iteration RMVOUT_1-RMVOUT_16;
MPRINT(PART1B):   draw=_N_;
MPRINT(PART1B):   run;

NOTE: There were 200 observations read from the data set WORK.FACIT_MI_CLASSOUT.
NOTE: The data set WORK.FACIT_MI_POSTCVP has 200 observations and 18 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

DSVER=1
MPRINT(PART1B):   proc datasets library=WORK nolist;
MPRINT(PART1B):   delete dummy facit_mi_classout facit_mi_covp facit_mi_data1 facit_mi_datap1 facit_mi_datamcmc 
facit_mi_mean facit_mi_patterns1 facit_mi_solf facit_mi_std facit_mi_temp7 facit_mi_temp12;
MPRINT(PART1B):   quit;

NOTE: Deleting WORK.DUMMY (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_CLASSOUT (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_COVP (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_DATA1 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_DATAP1 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_DATAMCMC (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_MEAN (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_PATTERNS1 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_SOLF (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_STD (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_TEMP7 (memtype=DATA).
NOTE: Deleting WORK.FACIT_MI_TEMP12 (memtype=DATA).
NOTE: PROCEDURE DATASETS used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART1B):   proc sql;
MPRINT(PART1B):   update facit_mi_master set Vlabel="facit_mi @"||put(datetime(),datetime.) where Role="Master1B";
NOTE: 1 row was updated in WORK.FACIT_MI_MASTER.

MPRINT(PART1B):   delete from facit_mi_master where Role in("Master2A","Master2B","Master3");
NOTE: No rows were deleted from WORK.FACIT_MI_MASTER.

MPRINT(PART1B):   quit;
87                                                         The SAS System                            04:10 Wednesday, April 15, 2026

NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.01 seconds
      

################################
Macro Part1B ended succesfully
################################
MPRINT(FACIT_MI):  ;
MPRINT(PART2A):   * Defaults;
MPRINT(PART2A):   * Copy the master data set;
MPRINT(PART2A):   data facit_mi_supp_master;
MPRINT(PART2A):   set facit_mi_Master end=Myend;
MPRINT(PART2A):   run;

NOTE: There were 19 observations read from the data set WORK.FACIT_MI_MASTER.
NOTE: The data set WORK.FACIT_MI_SUPP_MASTER has 19 observations and 10 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2A):   proc sql noprint;
MPRINT(PART2A):   * Set status of Part1B as failed in case of error;
MPRINT(PART2A):   delete from facit_mi_supp_master where Role="Master2A";
NOTE: No rows were deleted from WORK.FACIT_MI_SUPP_MASTER.

MPRINT(PART2A):   insert into facit_mi_supp_master set Vlabel="Failed", Role="Master2A";
NOTE: 1 row was inserted into WORK.FACIT_MI_SUPP_MASTER.

MPRINT(PART2A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2A):   proc sql noprint;
MPRINT(PART2A):   * Remove any debris from existing Master data set;
MPRINT(PART2A):   delete from facit_mi_supp_master where Role in( 
"Method","MethodV","Ref","RefV","VCRef","VCRefV","VCMeth","VCMethV", "Master2B", 
"Master3","ANWhere","ANTimes","ANRef","ANTreat","ANCov","ANCatCov","ANCovgp","Delta","DeltaV","DLag","Dgroups","DgroupsV
");
NOTE: No rows were deleted from WORK.FACIT_MI_SUPP_MASTER.

MPRINT(PART2A):   delete from facit_mi_supp_master where Role="Seed" and Vlabel="Imputation";
NOTE: No rows were deleted from WORK.FACIT_MI_SUPP_MASTER.

MPRINT(PART2A):   * Check if previous sections (PART1A and PART1B) ran correctly;
MPRINT(PART2A):   select Vlabel into :loc1A from facit_mi_master(where=(Role="Master1A"));
MPRINT(PART2A):   select Vlabel into :loc1B from facit_mi_master(where=(Role="Master1B"));
MPRINT(PART2A):   * Reload the macro variables;
MPRINT(PART2A):   select vlabel into :DSName from facit_mi_master(where=(Role="DSName"));
MPRINT(PART2A):   select vname into :Subject from facit_mi_master(where=(Role="Subject"));
MPRINT(PART2A):   select vname into :PEWhere from facit_mi_master(where=(Role="PEWhere"));
MPRINT(PART2A):   select vtype, vname into :Treattype, :Treat from facit_mi_master(where=(Role="Treat" and index=1));
MPRINT(PART2A):   select vname, "STD_"||Vname into :Cov separated by " " , :STD_cov separated by " " from 
facit_mi_master(where=(Role="Cov"));
MPRINT(PART2A):   select vname, "STD_"||Vname into :CovbyTime separated by " " , :STD_CovbyTime separated by " " from 
88                                                         The SAS System                            04:10 Wednesday, April 15, 2026

facit_mi_master(where=(Role="Covbytim"));
NOTE: No rows were selected.
MPRINT(PART2A):   select vname, "I_"||Vname into :Catcov separated by " " , :I_Catcov separated by " " from 
facit_mi_master(where=(Role="CatCov" and index=1));
MPRINT(PART2A):   select vname, "I_"||Vname into :Catcovbytime separated by " " , :I_Catcovbytime separated by " " from 
facit_mi_master(where=(Role="CatCovby" and index=1));
NOTE: No rows were selected.
MPRINT(PART2A):   select vtype, vname into :Covgptype, :Covgroup from facit_mi_master(where=(Role="Covgp"));
MPRINT(PART2A):   select max(index) into :Ntimes from facit_mi_master(where=(Role="Time"));
MPRINT(PART2A):   select max(index) into :NTreat from facit_mi_master(where=(Role="Treat"));
MPRINT(PART2A):   select max(draw) into :Ndraws from facit_mi_postlp;
MPRINT(PART2A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.01 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2A):   * Check if jobname is a valid sas name;
MPRINT(PART2A):   data _null_;
MPRINT(PART2A):   facit_mi_supp=0;
MPRINT(PART2A):   run;

NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2A):   proc datasets library=WORK nolist;
MPRINT(PART2A):   delete facit_mi_supp_temp21 facit_mi_supp_temp22 facit_mi_supp_temp39 facit_mi_supp_temp40 
facit_mi_supp_temp41 facit_mi_supp_temp42 facit_mi_supp_temp51 facit_mi_supp_datapM facit_mi_supp_newbits;
MPRINT(PART2A):   quit;

NOTE: The file WORK.FACIT_MI_SUPP_TEMP21 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_SUPP_TEMP22 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_SUPP_TEMP39 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_SUPP_TEMP40 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_SUPP_TEMP41 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_SUPP_TEMP42 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_SUPP_TEMP51 (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_SUPP_DATAPM (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: The file WORK.FACIT_MI_SUPP_NEWBITS (memtype=DATA) was not found, but appears on a DELETE statement.
NOTE: PROCEDURE DATASETS used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2A):   * Check required variables are in the original data set;
MPRINT(PART2A):   data facit_mi_supp_newbits;
MPRINT(PART2A):   keep Vname vlabel vnum vtype Vlen Vformat Role Clevel Nlevel Index;
MPRINT(PART2A):   length txt $256 Vname $32 vlabel $256 vnum 8 vtype $1 Role $8 Clevel $120 vformat $200;
MPRINT(PART2A):   drop txt dsid;
MPRINT(PART2A):   Clevel=" ";
MPRINT(PART2A):   Nlevel=.;
MPRINT(PART2A):   index=.;
MPRINT(PART2A):   dsid=open("dat_ana_mi_supp","i");
MPRINT(PART2A):   if dsid<=0 then do;
MPRINT(PART2A):   call symput("Stopflag","1");
MPRINT(PART2A):   call symput("Errtext1","The original Data set <dat_ana_mi_supp> no longer exists");
89                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART2A):   stop;
MPRINT(PART2A):   end;
MPRINT(PART2A):   vnum=varnum(dsid,"imp_method");
MPRINT(PART2A):   if vnum<=0 then do;
MPRINT(PART2A):   call symput("Stopflag","1");
MPRINT(PART2A):   call symput("Errtext1","MethodV= parameter: Variable <imp_method> not found in Data set 
dat_ana_mi_supp");
MPRINT(PART2A):   stop;
MPRINT(PART2A):   end;
MPRINT(PART2A):   vtype=vartype(dsid,vnum);
MPRINT(PART2A):   if vtype ^= "C" then do;
MPRINT(PART2A):   call symput("Stopflag","1");
MPRINT(PART2A):   call symput("Errtext1","MethodV= parameter: Variable <imp_method> in Data set <dat_ana_mi_supp> must 
be of type Character.");
MPRINT(PART2A):   stop;
MPRINT(PART2A):   end;
MPRINT(PART2A):   Role="MethodV";
MPRINT(PART2A):   Vname=varname(dsid,Vnum);
MPRINT(PART2A):   vlen=varlen(dsid,Vnum);
MPRINT(PART2A):   vlabel=varlabel(dsid,vnum);
MPRINT(PART2A):   vformat=varfmt(dsid,vnum);
MPRINT(PART2A):   output;
MPRINT(PART2A):   Role="Ref";
MPRINT(PART2A):   Vname=" ";
MPRINT(PART2A):   vnum=.;
MPRINT(PART2A):   Vtype=" ";
MPRINT(PART2A):   vlen=.;
MPRINT(PART2A):   vlabel="2";
MPRINT(PART2A):   vformat=" ";
MPRINT(PART2A):   output;
MPRINT(PART2A):   Role="VCRef";
MPRINT(PART2A):   Vname=" ";
MPRINT(PART2A):   vnum=.;
MPRINT(PART2A):   Vtype=" ";
MPRINT(PART2A):   vlen=.;
MPRINT(PART2A):   vlabel="";
MPRINT(PART2A):   vformat=" ";
MPRINT(PART2A):   output;
MPRINT(PART2A):   rc=close(dsid);
MPRINT(PART2A):   run;

NOTE: Variable txt is uninitialized.
NOTE: The data set WORK.FACIT_MI_SUPP_NEWBITS has 3 observations and 10 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2A):   * Extract a standard set of linear predictor parameter values;
MPRINT(PART2A):   proc sort data=facit_mi_postlp out=facit_mi_supp_temp51(where= (draw=1));
MPRINT(PART2A):   by vname icat itime;
MPRINT(PART2A):   run;

NOTE: There were 2200 observations read from the data set WORK.FACIT_MI_POSTLP.
NOTE: The data set WORK.FACIT_MI_SUPP_TEMP51 has 11 observations and 5 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
90                                                         The SAS System                            04:10 Wednesday, April 15, 2026

      

MPRINT(PART2A):   * Build text to 1) declare arrays, 2) store parameter values, 3) calculate linear predictor, 4) keep 
in data set;
MPRINT(PART2A):   data _Null_;
MPRINT(PART2A):   set facit_mi_supp_temp51 end=myend;
MPRINT(PART2A):   by vname icat itime;
MPRINT(PART2A):   length txt1 $ 1024;
MPRINT(PART2A):   length txt2 $ 1024;
MPRINT(PART2A):   length txt3 $ 1024;
MPRINT(PART2A):   length txt4 $ 1024;
MPRINT(PART2A):   retain txt1 txt2 txt3 txt4;
MPRINT(PART2A):   if last.vname then do;
MPRINT(PART2A):   if upcase(Vname) ^= upcase("I_TRT01PN") then do;
MPRINT(PART2A):   if icat^=. and itime^=. then do;
MPRINT(PART2A):   *CATCOVbyTime;
MPRINT(PART2A):   txt1=trim(txt1) || "array P_" || trim(Vname) || " [200," || trim(left(put(icat,6.0))) ||"," || 
trim(left(put(itime,6.0))) || "] _temporary_;" ;
MPRINT(PART2A):   txt2=trim(txt2) || "if Vname='" || trim(Vname) || "' then P_" || trim(Vname) || 
"[draw,icat,itime]=Value;" ;
MPRINT(PART2A):   txt3=trim(txt3) || "+P_" || trim(Vname) || "[draw," || trim(Vname) ||",itime]" ;
MPRINT(PART2A):   txt4=trim(txt4) || ",B." || trim(Vname);
MPRINT(PART2A):   end;
MPRINT(PART2A):   else do;
MPRINT(PART2A):   if icat=. and itime^=. then do;
MPRINT(PART2A):   *CovbyTime;
MPRINT(PART2A):   txt1=trim(txt1) || "array P_" || trim(Vname) || " [200," || trim(left(put(itime,6.0))) || "] 
_temporary_;" ;
MPRINT(PART2A):   txt2=trim(txt2) || "if Vname='" || trim(Vname) || "' then P_" ||trim(Vname) || "[draw,itime]=Value;" ;
MPRINT(PART2A):   txt3=trim(txt3) || "+P_" || trim(Vname) || "[draw,itime]*" || trim(Vname) ;
MPRINT(PART2A):   txt4=trim(txt4) || ",B." || trim(Vname);
MPRINT(PART2A):   end;
MPRINT(PART2A):   else do;
MPRINT(PART2A):   if icat^=. and itime=. then do;
MPRINT(PART2A):   *CatCov;
MPRINT(PART2A):   txt1=trim(txt1) || "array P_" || trim(Vname) || " [200," || trim(left(put(icat,6.0))) || "] 
_temporary_;" ;
MPRINT(PART2A):   txt2=trim(txt2) || "if Vname='" || trim(Vname) || "' then P_" ||trim(Vname) || "[draw,icat]=Value;" ;
MPRINT(PART2A):   txt3=trim(txt3) || "+P_" || trim(Vname) || "[draw," || trim(Vname) ||"]" ;
MPRINT(PART2A):   txt4=trim(txt4) || ",B." || trim(Vname);
MPRINT(PART2A):   end;
MPRINT(PART2A):   else do;
MPRINT(PART2A):   *Cov;
MPRINT(PART2A):   txt1=trim(txt1) || "array P_" || trim(Vname) || " [200] _temporary_;" ;
MPRINT(PART2A):   txt2=trim(txt2) || "if Vname='" || trim(Vname) || "' then P_" ||trim(Vname) || "[draw]=Value;" ;
MPRINT(PART2A):   txt3=trim(txt3) || "+P_" || trim(Vname) || "[draw]*" || trim(Vname);
MPRINT(PART2A):   txt4=trim(txt4) || ",B." || trim(Vname);
MPRINT(PART2A):   end;
MPRINT(PART2A):   end;
MPRINT(PART2A):   end;
MPRINT(PART2A):   end;
MPRINT(PART2A):   end;
MPRINT(PART2A):   if myend then do;
MPRINT(PART2A):   call symput("decarr",txt1);
MPRINT(PART2A):   call symput("store",txt2);
MPRINT(PART2A):   call symput("calc",txt3);
MPRINT(PART2A):   call symput("keep",txt4);
MPRINT(PART2A):   end;
91                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART2A):   run;

NOTE: There were 11 observations read from the data set WORK.FACIT_MI_SUPP_TEMP51.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2A):   * Check that the MethodV=, RefV=, VCMethodv= and VCRefV= variables are unique with subject;
MPRINT(PART2A):   * And extract from original data set;
MPRINT(PART2A):   proc sql noprint;
MPRINT(PART2A):   create table facit_mi_supp_temp39 as select USUBJID ,Max(imp_method) as imp_method, Min(imp_method) 
as imp_method_check from dat_ana_mi_supp group by USUBJID;
NOTE: Table WORK.FACIT_MI_SUPP_TEMP39 created, with 21 rows and 3 columns.

MPRINT(PART2A):   select 0 ,sum(imp_method ^= imp_method_check) into :dummy ,:sumcheck1 from facit_mi_supp_temp39 quit;
MPRINT(PART2A):   * Add the required variables to the data;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2A):   proc sql;
MPRINT(PART2A):   create table facit_mi_supp_temp40 as select A.* ,B.imp_method from 
facit_mi_datap(where=(Super_Nmiss>0)) A left join facit_mi_supp_temp39 B on A.USUBJID=B.USUBJID;
NOTE: Table WORK.FACIT_MI_SUPP_TEMP40 created, with 9 rows and 20 columns.

MPRINT(PART2A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.01 seconds
      

MPRINT(PART2A):   * Build required control variables;
MPRINT(PART2A):   data facit_mi_supp_temp41;
MPRINT(PART2A):   set facit_mi_supp_temp40;
MPRINT(PART2A):   keep USUBJID Subject_index I_TRT01PN I_SYSTRCRF STD_BASE I_I_1 imp_method 
Super_Response1-Super_Response4 Super_Nmiss Super_Pattern Super_Last Super_k Super_method Super_Ref Super_VCMethod 
Super_VCRef;
MPRINT(PART2A):   * Declare Super_ref and super_VCRef with correct type;
MPRINT(PART2A):   length Super_method $8 Super_VCMethod $8 Super_k 8 ;
MPRINT(PART2A):   * All methods translated to upper case for internal use;
MPRINT(PART2A):   Super_Method= UPCASE(imp_method);
MPRINT(PART2A):   Super_k=1;
MPRINT(PART2A):   * If reference variable exist copy it in, and if not then read it in from Ref. (Default is a missing 
value);
MPRINT(PART2A):   Super_Ref=2;
MPRINT(PART2A):   ;
MPRINT(PART2A):   Super_VCMethod=" ";
MPRINT(PART2A):   Super_VCRef=I_1;
MPRINT(PART2A):   run;

NOTE: There were 9 observations read from the data set WORK.FACIT_MI_SUPP_TEMP40.
NOTE: The data set WORK.FACIT_MI_SUPP_TEMP41 has 9 observations and 19 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      
92                                                         The SAS System                            04:10 Wednesday, April 15, 2026


MPRINT(PART2A):   * Now look up methods used;
MPRINT(PART2A):   * But first check we found something;
MPRINT(PART2A):   proc sql noprint;
MPRINT(PART2A):   select count(*) into :checkn from facit_mi_supp_temp41;
MPRINT(PART2A):   select distinct upcase(super_method) into :methods separated by " " from facit_mi_supp_temp41;
MPRINT(PART2A):   * and index the reference values;
MPRINT(PART2A):   create table facit_mi_supp_temp42 as select A.*, index as I_ref from facit_mi_supp_temp41 A left join 
facit_mi_master(where=(role="Treat")) B on A.super_ref = B.Nlevel ;
NOTE: Table WORK.FACIT_MI_SUPP_TEMP42 created, with 9 rows and 20 columns.

MPRINT(PART2A):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2A):   data facit_mi_supp_datapm;
MPRINT(PART2A):   set facit_mi_postlp(in=inpostlp) facit_mi_datap( in=pass1) facit_mi_supp_temp42(in=pass2) ;
MPRINT(PART2A):   array values[200,2,4] _temporary_;
MPRINT(PART2A):   array avgmeanp[200,4] _temporary_ (800*0);
MPRINT(PART2A):   retain counter 0;
MPRINT(PART2A):   array P_I_SYSTRCRF [200,2] _temporary_;
MPRINT(PART2A):  array P_STD_BASE [200] _temporary_;
MPRINT(PART2A):   ;
MPRINT(PART2A):   array super_mean[4] super_mean1-super_mean4;
MPRINT(PART2A):   array super_mar[4] super_mar1-super_mar4;
MPRINT(PART2A):   array A[4] _temporary_;
MPRINT(PART2A):   array B[4] _temporary_;
MPRINT(PART2A):   array C[4] _temporary_;
MPRINT(PART2A):   array MyCov[4] _temporary_;
MPRINT(PART2A):   keep USUBJID draw super_mean1-super_mean4 super_mar1-super_mar4 subject_index 
Super_Response1-Super_Response4 Super_Pattern Super_Nmiss Super_Last Super_VCMethod Super_VCRef Super_k I_I_1 ;
MPRINT(PART2A):   length warntxt $128;
MPRINT(PART2A):   retain warncount 0;
MPRINT(PART2A):   if inpostlp then do;
MPRINT(PART2A):   * Copy parameter values into the values array;
MPRINT(PART2A):   if upcase(Vname) = upcase("I_TRT01PN") then do;
MPRINT(PART2A):   values[draw,icat,itime]=value;
MPRINT(PART2A):   end;
MPRINT(PART2A):   else do;
MPRINT(PART2A):   if Vname='I_SYSTRCRF' then P_I_SYSTRCRF[draw,icat]=Value;
MPRINT(PART2A):  if Vname='STD_BASE' then P_STD_BASE[draw]=Value;
MPRINT(PART2A):   end;
MPRINT(PART2A):   end;
MPRINT(PART2A):   if pass1 then do;
MPRINT(PART2A):   counter=counter+1;
MPRINT(PART2A):   do draw=1 to 200;
MPRINT(PART2A):   * &calc contains code to calculate the rest of the linear predictor.;
MPRINT(PART2A):   do itime=1 to 4;
MPRINT(PART2A):   tempval=avgmeanp[draw,itime];
MPRINT(PART2A):   avgmeanp[draw,itime]= tempval + ((0 +P_I_SYSTRCRF[draw,I_SYSTRCRF]+P_STD_BASE[draw]*STD_BASE ) - 
tempval)/counter ;
MPRINT(PART2A):   end;
MPRINT(PART2A):   end;
MPRINT(PART2A):   end;
MPRINT(PART2A):   if pass2 then do;
MPRINT(PART2A):   * Set up defaults for VCMethod;
93                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART2A):   if Super_VCMethod=" " then do;
MPRINT(PART2A):   if super_method in("MAR","OLMCF","ALMCF","OFCMCF","AFCMCF") then Super_VCMethod="THIS";
MPRINT(PART2A):   else if super_method in("CIR","J2R", "CAUSAL") then super_VCMethod="REF";
MPRINT(PART2A):   else if super_method="CR" then super_VCMethod="REF";
MPRINT(PART2A):   * If method not found then use "REF" if there is an Reference is set;
MPRINT(PART2A):   * or if no reference set then use "This";
MPRINT(PART2A):   else if I_Ref=. then super_VCMethod="THIS";
MPRINT(PART2A):   else super_VCMethod="REF";
MPRINT(PART2A):   end;
MPRINT(PART2A):   * Build in checks that REF= is set for standard methods that need it;
MPRINT(PART2A):   if (super_method in("CIR","J2R","CR", "CAUSAL")) and (I_Ref < 1 or I_Ref > 2) then do;
MPRINT(PART2A):   call symput("Stopflag","1");
MPRINT(PART2A):   call symput("Errtext1","Illegal value <Index= " || I_Ref || "> for Ref= or for content of Refv= 
variable. Method is "|| left(trim(super_method)) || " Subject ID= <" || USUBJID || ">.");
MPRINT(PART2A):   stop;
MPRINT(PART2A):   end;
MPRINT(PART2A):   * This makes user only one warning for each record in data set;
MPRINT(PART2A):   Warn=0;
MPRINT(PART2A):   do draw=1 to 200;
MPRINT(PART2A):   do itime=1 to 4;
MPRINT(PART2A):   * We hand in the Treat*Time predicted mean for the average subject;
MPRINT(PART2A):   A[itime]= values[draw,I_TRT01PN,itime] + AvgMeanp[draw,itime];
MPRINT(PART2A):   if I_ref>.z then B[itime]= values[draw,I_Ref,itime] + AvgMeanp[draw,itime];
MPRINT(PART2A):   else B[itime]= .;
MPRINT(PART2A):   * Mycov is the difference between this subjects predicted mean and that for an average usbject;
MPRINT(PART2A):   MyCov[itime]= (0 +P_I_SYSTRCRF[draw,I_SYSTRCRF]+P_STD_BASE[draw]*STD_BASE ) - AvgMeanp[draw,itime];
MPRINT(PART2A):   end;
MPRINT(PART2A):   select(Super_Method);
MPRINT(PART2A):   when("ALMCF") warntxt= ALMCF(Super_k,Super_Last,A,B,Mycov,C);
MPRINT(PART2A):   otherwise do;
MPRINT(PART2A):   put "ERROR: In otherwise clause";
MPRINT(PART2A):   put "ERROR: Trying to use Method <" Super_method ">";
MPRINT(PART2A):   call symput("Stopflag","1");
MPRINT(PART2A):   call symput("Errtext1","There is some problem with definition of Method");
MPRINT(PART2A):   call symput("Errtext2","Please check this aspect of your macro call. See above for details.");
MPRINT(PART2A):   stop;
MPRINT(PART2A):   end;
MPRINT(PART2A):   end;
MPRINT(PART2A):   if warn=0 and (warntxt ^= "") then do;
MPRINT(PART2A):   if warncount<10 then do;
MPRINT(PART2A):   put "WARNING: For subject, USUBJID=" USUBJID;
MPRINT(PART2A):   put "WARNING: " warntxt;
MPRINT(PART2A):   call symput("Warnflag","1");
MPRINT(PART2A):   end;
MPRINT(PART2A):   warncount +1;
MPRINT(PART2A):   warn +1;
MPRINT(PART2A):   end;
MPRINT(PART2A):   do itime=1 to 4;
MPRINT(PART2A):   super_mean[itime]=C[itime];
MPRINT(PART2A):   super_mar[itime]=A[itime]+MyCov[itime];
MPRINT(PART2A):   end;
MPRINT(PART2A):   output;
MPRINT(PART2A):   end;
MPRINT(PART2A):   end;
MPRINT(PART2A):   run;

NOTE: Numeric values have been converted to character values at the places given by: (Line):(Column).
      27843:2   
94                                                         The SAS System                            04:10 Wednesday, April 15, 2026

ERROR: In otherwise clause
ERROR: Trying to use Method <  >
NOTE: There were 2200 observations read from the data set WORK.FACIT_MI_POSTLP.
NOTE: There were 21 observations read from the data set WORK.FACIT_MI_DATAP.
NOTE: There were 1 observations read from the data set WORK.FACIT_MI_SUPP_TEMP42.
NOTE: The data set WORK.FACIT_MI_SUPP_DATAPM has 0 observations and 22 variables.
NOTE: DATA statement used (Total process time):
      real time           0.02 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2A):   * Additional quit and run to flush any existing data step or proc;
MPRINT(PART2A):   quit;
MPRINT(PART2A):   run;
MPRINT(PART2A):   * Now put error message and stop macro;
ERROR:
ERROR: In macro Part2A with Jobname= facit_mi_supp
ERROR: There is some problem with definition of Method
ERROR: Please check this aspect of your macro call. See above for details.
ERROR:
MPRINT(PART2B):   proc sql noprint;
MPRINT(PART2B):   * Set status of Part2B as failed in case of error;
MPRINT(PART2B):   delete from facit_mi_supp_master where Role="Master2B";
NOTE: No rows were deleted from WORK.FACIT_MI_SUPP_MASTER.

MPRINT(PART2B):   insert into facit_mi_supp_master set Vlabel="Failed", Role="Master2B";
NOTE: 1 row was inserted into WORK.FACIT_MI_SUPP_MASTER.

MPRINT(PART2B):   * Remove any debris from existing Master data set;
MPRINT(PART2B):   delete from facit_mi_supp_master where Role in( 
"Master3","ANWhere","ANTimes","ANRef","ANTreat","ANCov","ANCatCov","ANCovgp","Delta","DeltaV","DLag","Dgroups","DgroupsV
");
NOTE: No rows were deleted from WORK.FACIT_MI_SUPP_MASTER.

MPRINT(PART2B):   delete from facit_mi_supp_master where Role="Seed" and Vlabel="Imputation";
NOTE: No rows were deleted from WORK.FACIT_MI_SUPP_MASTER.

MPRINT(PART2B):   insert into facit_mi_supp_master set Index=1, NLevel=999, VLabel="Imputation", Role="Seed";
NOTE: 1 row was inserted into WORK.FACIT_MI_SUPP_MASTER.

MPRINT(PART2B):   * Check if previous sections (PART1A, PART1B and PART2A) ran correctly;
MPRINT(PART2B):   select Vlabel into :loc1A from facit_mi_supp_master(where=(Role="Master1A"));
MPRINT(PART2B):   select Vlabel into :loc1B from facit_mi_supp_master(where=(Role="Master1B"));
MPRINT(PART2B):   select Vlabel into :loc2A from facit_mi_supp_master(where=(Role="Master2A"));
MPRINT(PART2B):   * Additional quit and run to flush any existing data step or proc;
MPRINT(PART2B):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.01 seconds
      cpu time            0.00 seconds
      

MPRINT(PART2B):   run;
MPRINT(PART2B):   * Now put error message and stop macro;
ERROR:
ERROR: In macro Part2B with Jobname= facit_mi_supp
ERROR: Part 2A has been run but failed for <facit_mi_supp>
ERROR:
ERROR:
95                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(FACIT_MI):   data dat_ana_info;
MPRINT(FACIT_MI):   set dat_ana_mi_supp;
MPRINT(FACIT_MI):   keep acat1 acat1n usubjid avisitn ana_flag imp_method;
MPRINT(FACIT_MI):   run;

NOTE: There were 75 observations read from the data set WORK.DAT_ANA_MI_SUPP.
NOTE: The data set WORK.DAT_ANA_INFO has 75 observations and 6 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(FACIT_MI):   proc sort data=dat_ana_info;
MPRINT(FACIT_MI):   by ACAT1 ACAT1N USUBJID AVISITN;
MPRINT(FACIT_MI):   run;

NOTE: There were 75 observations read from the data set WORK.DAT_ANA_INFO.
NOTE: The data set WORK.DAT_ANA_INFO has 75 observations and 6 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.01 seconds
      

MPRINT(FACIT_MI):   data facit_mi_supp_DataFull;
MPRINT(FACIT_MI):   set facit_mi_supp_DataFull;
ERROR: File WORK.FACIT_MI_SUPP_DATAFULL.DATA does not exist.
MPRINT(FACIT_MI):   length AVISIT $50.;
MPRINT(FACIT_MI):   AVISIT=put(AVISITN, avisitc.);
MPRINT(FACIT_MI):   run;

NOTE: The SAS System stopped processing this step because of errors.
WARNING: The data set WORK.FACIT_MI_SUPP_DATAFULL may be incomplete.  When this step was stopped there were 0 
         observations and 2 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(FACIT_MI):   proc sql;
MPRINT(FACIT_MI):   create table facit_mi_supp_full as select x.*, y.ACAT1, y.ACAT1N, y.ana_flag, y.imp_method from 
facit_mi_supp_DataFull as x left join dat_ana_info as y on x.usubjid = y.usubjid & x.avisitn=y.avisitn;
ERROR: Column usubjid could not be found in the table/view identified with the correlation name X.
ERROR: Column usubjid could not be found in the table/view identified with the correlation name X.
NOTE: PROC SQL set option NOEXEC and will continue to check the syntax of statements.
MPRINT(FACIT_MI):   quit;
NOTE: The SAS System stopped processing this step because of errors.
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      


MPRINT(FACIT_MI):   data facit_mi_supp;
MPRINT(FACIT_MI):   set facit_mi_supp_full;
ERROR: File WORK.FACIT_MI_SUPP_FULL.DATA does not exist.
MPRINT(FACIT_MI):   chg=aval-base;
MPRINT(FACIT_MI):   if imp_method="ALMCF" then do chg=.;
MPRINT(FACIT_MI):   aval=.;
96                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(FACIT_MI):   imp_method='';
MPRINT(FACIT_MI):   end;
MPRINT(FACIT_MI):   run;

NOTE: The SAS System stopped processing this step because of errors.
WARNING: The data set WORK.FACIT_MI_SUPP may be incomplete.  When this step was stopped there were 0 observations and 4 
         variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.01 seconds
      


MPRINT(FACIT_MI):   proc sort data=facit_mi_supp;
ERROR: Variable USUBJID not found.
ERROR: Variable TRT01PN not found.
MPRINT(FACIT_MI):   by USUBJID TRT01PN AVISITN;
ERROR: Variable AVISITN not found.
MPRINT(FACIT_MI):   run;

NOTE: The SAS System stopped processing this step because of errors.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      


MPRINT(FACIT_MI):   proc sort data=analysis.adfacit out=adfacit1;
MPRINT(FACIT_MI):   where paramcd="FACIT" and AVISIT in ("Baseline","Day 14","Day 30","Day 90","Day 180") and 
ANL01FL="Y";
MPRINT(FACIT_MI):   by USUBJID TRT01PN AVISITN;
MPRINT(FACIT_MI):   run;

NOTE: There were 103 observations read from the data set ANALYSIS.ADFACIT.
      WHERE (paramcd='FACIT') and AVISIT in ('Baseline', 'Day 14', 'Day 180', 'Day 30', 'Day 90') and (ANL01FL='Y');
NOTE: The data set WORK.ADFACIT1 has 103 observations and 87 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.01 seconds
      cpu time            0.00 seconds
      

MPRINT(FACIT_MI):   data adfacmi_supp;
MPRINT(FACIT_MI):   merge facit_mi_supp(in=a) adfacit1(in=b drop=AVAL CHG BASE);
MPRINT(FACIT_MI):   by USUBJID TRT01PN AVISITN;
MPRINT(FACIT_MI):   if a;
MPRINT(FACIT_MI):   length DTYPE $20.;
MPRINT(FACIT_MI):   DTYPE=imp_method;
MPRINT(FACIT_MI):   * truncate the values larger than maximum and smaller than minimum;
MPRINT(FACIT_MI):   if ^missing(aval) and ^missing(DTYPE) then do;
MPRINT(FACIT_MI):   if aval>52 then aval=52;
MPRINT(FACIT_MI):   if aval<0 then aval=0;
MPRINT(FACIT_MI):   end;
MPRINT(FACIT_MI):   if nmiss(AVAL,BASE)=0 then CHG=AVAL-BASE;
MPRINT(FACIT_MI):   IMPNUM=draw;
MPRINT(FACIT_MI):   avisit=put(avisitn,avisitc.);
MPRINT(FACIT_MI):   run;

NOTE: Variable draw is uninitialized.
97                                                         The SAS System                            04:10 Wednesday, April 15, 2026

ERROR: BY variable USUBJID is not on input data set WORK.FACIT_MI_SUPP.
ERROR: BY variable TRT01PN is not on input data set WORK.FACIT_MI_SUPP.
ERROR: BY variable AVISITN is not on input data set WORK.FACIT_MI_SUPP.
NOTE: The SAS System stopped processing this step because of errors.
WARNING: The data set WORK.ADFACMI_SUPP may be incomplete.  When this step was stopped there were 0 observations and 91 
         variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

27844   
27845   /* Re-merge EST/ICE variables from source data */
27846   proc sql;
27847    create table adfacmi_sec1 as
27848    select distinct a.*, b.EST01STP, b.ICE01F, b.IMPREA01
27849    from adfacmi_sec(DROP=EST01STP ICE01F IMPREA01) as a
27850    left join dat_ana4(where=(^missing(EST01STP))) as b
27851    on a.USUBJID=b.USUBJID and a.AVISIT=b.AVISIT
27852    order by a.USUBJID
27853    ;
NOTE: Table WORK.ADFACMI_SEC1 created, with 0 rows and 91 columns.

27854   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

27855   
27856   proc sql;
27857    create table adfacmi_supp1 as
27858    select distinct a.*, b.EST02STP, b.ICE02F, b.IMPREA02
27859    from adfacmi_supp(DROP=EST02STP ICE02F IMPREA02) as a
27860    left join dat_ana4(where=(^missing(EST02STP))) as b
27861    on a.USUBJID=b.USUBJID and a.AVISIT=b.AVISIT
27862    order by a.USUBJID
27863    ;
NOTE: Table WORK.ADFACMI_SUPP1 created, with 0 rows and 91 columns.

27864   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

27865   
27866   data adfacmi_comb1;
27867    length ana_flag $10.;
27868    set adfacmi_sec1 adfacmi_supp1
27869    analysis.adfacit(where=(AVISIT="Baseline" and paramcd='FACIT'));
27870    by USUBJID;
27871    drop ANL05FL ANL06FL ANL07FL AEFLAG;
27872   run;

NOTE: Variable ana_flag is uninitialized.
NOTE: There were 0 observations read from the data set WORK.ADFACMI_SEC1.
NOTE: There were 0 observations read from the data set WORK.ADFACMI_SUPP1.
98                                                         The SAS System                            04:10 Wednesday, April 15, 2026

NOTE: There were 21 observations read from the data set ANALYSIS.ADFACIT.
      WHERE (AVISIT='Baseline') and (paramcd='FACIT');
NOTE: The data set WORK.ADFACMI_COMB1 has 21 observations and 88 variables.
NOTE: DATA statement used (Total process time):
      real time           0.01 seconds
      cpu time            0.00 seconds
      

27873   
27874   
27875   proc sql noprint;
27876    select distinct name into: dropvar separated by " "
27877    from sashelp.vcolumn where find(libname,"WORK") and memname="ADFACMI_COMB1"
27878    and (name^="USUBJID" and name in
27879     (select distinct name from sashelp.vcolumn where find(libname,"ANALYSIS") and memname="ADSL"))
27880    ;
27881   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.02 seconds
      cpu time            0.01 seconds
      

27882   
27883   data adfacmi_final;
27884    length PROEVFL $1.;
27885    merge adfacmi_comb1(in=a drop=&dropvar SYSTRCRF) analysis.ADSL analysis.adbs(keep=USUBJID SYSTRCRF);
ERROR: The variable SYSTRCRF in the DROP, KEEP, or RENAME list has never been referenced.
ERROR: Invalid DROP, KEEP, or RENAME option on file WORK.ADFACMI_COMB1.
27886    by USUBJID;
27887    if a;
27888    if missing(param) and missing(paramcd) then do;
27889     param='FACIT Fatigue score';
27890     paramcd='FACIT';
27891    end;
27892   
27893    /* Re-derive ANL05FL/ANL06FL/ANL07FL/AEFLAG based on EST variables */
27894    if (EST01STP='Hypothetical strategy' or EST02STP='Hypothetical strategy') and ANL05DT ne . then do;
27895     ANL05FL="Y";
27896     ANL05DSC="Record after initiation or intensification of anti-proteinuric therapies";
27897    end;
27898    if (EST01STP='Hypothetical strategy' or EST02STP='Treatment policy') and ANL06DT ne . then do;
27899     ANL06FL="Y";
27900     ANL06DSC="Record after initiation of RRT";
27901    end;
27902    if EST01STP='Treatment policy' or EST02STP='Treatment policy' then do;
27903     ANL07FL="Y";
27904     ANL07DSC="Record after treatment discontinuation for any other reason";
27905    end;
27906    if AEDCDT NE . then do; AEFLAG='Y'; end;
27907   
27908    /* Derive IMPREAS based on ACAT1 */
27909    if dtype ne '' then do;
27910     if ana_flag='sec' then IMPREAS=IMPREA01;
27911     if ana_flag='supp' then IMPREAS=IMPREA02;
27912    end;
27913   
27914    if ^missing(BASE) and FASFL='Y' then PROEVFL='Y'; else PROEVFL='N';
27915    if paramcd='FACIT';
99                                                         The SAS System                            04:10 Wednesday, April 15, 2026

27916   run;

NOTE: Character values have been converted to numeric values at the places given by: (Line):(Column).
      27889:9    27890:11   27915:13   
NOTE: The SAS System stopped processing this step because of errors.
WARNING: The data set WORK.ADFACMI_FINAL may be incomplete.  When this step was stopped there were 0 observations and 
         101 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

27917   
27918   *----------------------------------------------------------------------;
27919   *set the final dataset
27920   *do sorting;
27921   *select avariable and apply format from PDS;
27922   *----------------------------------------------------------------------;
27923   
27924   
27925   %_std_varpadding_submission( calledby =
27926   ,in_lib = work
27927   ,out_lib = work
27928   ,include_ds = adfacmi_final
27929   ,exclude_ds =
27930   );
MPRINT(_STD_VARPADDING_SUBMISSION):   option nonotes nomprint nomlogic
-> VARPADDING
SCR NOTE : Variable padding removal in library WORK. Processed 1 datasets.
SCR NOTE : ADFACMI_FINAL size is reduced by 20.0% (32 KB removed).

MPRINT(_STD_VARPADDING_SUBMISSION):   ;

SCR NOTE : Running time for VARPADDING: 0:00:00

28158   
28159   
28160   %opSetAttr(domain=adfacmi, inData=adfacmi_final, metaData  = RPRTDSM.study_adam_metadata);
**********opSetAttr Start************************************************************
NOTE: domain    = adfacmi
NOTE: inData    = adfacmi_final
NOTE: outData   =
NOTE: metaData  = RPRTDSM.study_adam_metadata
NOTE: tempVars  =
NOTE: setLength = Y
MPRINT(OPSETATTR):   ;
MPRINT(OPSETATTR):  ;
MPRINT(OPSETATTR):   proc sql noprint;
MPRINT(OPSETATTR):   select distinct upcase(substr(com_var_in,1,1)) into: commin from RPRTDSM.study_adam_metadata where 
dsname="ADFACMI";
MPRINT(OPSETATTR):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(OPSETATTR):   data opsa_temp_meta1(drop=getDataInfo);
MPRINT(OPSETATTR):   set RPRTDSM.study_adam_metadata(where=((dsname="ADFACMI") and var not in (""))) end=eof;
100                                                        The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(OPSETATTR):   if var_order=. then var_order=1e5-1;
MPRINT(OPSETATTR):   if upcase(com_var_in) in ("YES","Y") and upcase(com_var) in ("YES","Y") and dsname^="ADFACMI" then 
var_order=var_order-1e5;
MPRINT(OPSETATTR):   if upcase(type) in ("CHAR","C","TEXT") then type='$';
MPRINT(OPSETATTR):   else do;
MPRINT(OPSETATTR):   type='';
MPRINT(OPSETATTR):   length=8;
MPRINT(OPSETATTR):   end;
MPRINT(OPSETATTR):   if prxmatch('/^[\$\d\.\s]+$/',format) then format='';
MPRINT(OPSETATTR):   else if prxmatch('/^[^.]+$/',format) then format=cats(format,'.');
MPRINT(OPSETATTR):   retain getDataInfo 0;
MPRINT(OPSETATTR):   if dsname="ADFACMI" and ^getDataInfo then do;
MPRINT(OPSETATTR):   getDataInfo=1;
MPRINT(OPSETATTR):   call symputx('opsa_dslabel',dslabel);
MPRINT(OPSETATTR):   call symputx('opsa_uid',uid);
MPRINT(OPSETATTR):   end;

NOTE: There were 39 observations read from the data set RPRTDSM.STUDY_ADAM_METADATA.
      WHERE (dsname='ADFACMI') and (var not = ' ');
NOTE: The data set WORK.OPSA_TEMP_META1 has 39 observations and 14 variables.
NOTE: DATA statement used (Total process time):
      real time           0.01 seconds
      cpu time            0.00 seconds
      

MPRINT(OPSETATTR):   proc sort;
MPRINT(OPSETATTR):   by var var_order;
NOTE: There were 39 observations read from the data set WORK.OPSA_TEMP_META1.
NOTE: The data set WORK.OPSA_TEMP_META1 has 39 observations and 14 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(OPSETATTR):   proc sort nodupkey;
MPRINT(OPSETATTR):   by var;
MPRINT(OPSETATTR):   run;

NOTE: There were 39 observations read from the data set WORK.OPSA_TEMP_META1.
NOTE: 0 observations with duplicate key values were deleted.
NOTE: The data set WORK.OPSA_TEMP_META1 has 39 observations and 14 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(OPSETATTR):   proc contents data=adfacmi_final out=opsa_temp_content1 noprint;
MPRINT(OPSETATTR):   run;

NOTE: The data set WORK.OPSA_TEMP_CONTENT1 has 101 observations and 41 variables.
NOTE: PROCEDURE CONTENTS used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(OPSETATTR):   data opsa_temp_content2;
MPRINT(OPSETATTR):   set opsa_temp_content1(keep=name type length rename=(name=var type=typen length=originLength)) 
end=eof;
101                                                        The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(OPSETATTR):   var=upcase(var);
MPRINT(OPSETATTR):   tempVarFlag=0;

NOTE: There were 101 observations read from the data set WORK.OPSA_TEMP_CONTENT1.
NOTE: The data set WORK.OPSA_TEMP_CONTENT2 has 101 observations and 4 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(OPSETATTR):   proc sort;
MPRINT(OPSETATTR):   by var;
MPRINT(OPSETATTR):   run;

NOTE: There were 101 observations read from the data set WORK.OPSA_TEMP_CONTENT2.
NOTE: The data set WORK.OPSA_TEMP_CONTENT2 has 101 observations and 4 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(OPSETATTR):   data opsa_temp_content3(drop=errn CharVars Vars tempVarFlag);
MPRINT(OPSETATTR):   merge opsa_temp_meta1(in=in_meta) opsa_temp_content2(in=in_content) end=eof;
MPRINT(OPSETATTR):   by var;
MPRINT(OPSETATTR):   retain errn 0;
MPRINT(OPSETATTR):   if in_meta and in_content and cats(type,typen) in ('$1','2') then do;
MPRINT(OPSETATTR):   if errn<20 then put "WARNING: [macro opSetAttr] Variable type is not consistent between 
RPRTDSM.study_adam_metadata and input dataset for variable " var +(-1) ".";
MPRINT(OPSETATTR):   if errn<20 then put "WARNING: [macro opSetAttr] The original variable type will be used.";
MPRINT(OPSETATTR):   type=ifc(typen=2,'$','');
MPRINT(OPSETATTR):   errn+1;
MPRINT(OPSETATTR):   end;
MPRINT(OPSETATTR):   else if in_meta and ^in_content then do;
MPRINT(OPSETATTR):   if errn<20 then put "WARNING: [macro opSetAttr] Variable " var "from RPRTDSM.study_adam_metadata 
do not exist in adfacmi_final.";
MPRINT(OPSETATTR):   errn+1;
MPRINT(OPSETATTR):   end;
MPRINT(OPSETATTR):   if errn=20 then put "WARNING: [macro opSetAttr] More WARNINGs for this point will not be printed.";
MPRINT(OPSETATTR):   if tempVarFlag then var_order=1e5;
MPRINT(OPSETATTR):   length CharVars Vars $4000;
MPRINT(OPSETATTR):   retain CharVars Vars " ";
MPRINT(OPSETATTR):   if in_content and (in_meta or tempVarFlag) then do;
MPRINT(OPSETATTR):   if type='$' then CharVars=catx(' ',CharVars,var);
MPRINT(OPSETATTR):   Vars=catx(' ',Vars,var);
MPRINT(OPSETATTR):   output;
MPRINT(OPSETATTR):   end;
MPRINT(OPSETATTR):   if eof then do;
MPRINT(OPSETATTR):   call symputx('opsa_CharVars',CharVars);
MPRINT(OPSETATTR):   call symputx('opsa_Vars',Vars);
MPRINT(OPSETATTR):   end;
MPRINT(OPSETATTR):   run;

WARNING: [macro opSetAttr] Variable ABLFL from RPRTDSM.study_adam_metadata do not exist in adfacmi_final.
WARNING: [macro opSetAttr] Variable ACAT1 from RPRTDSM.study_adam_metadata do not exist in adfacmi_final.
WARNING: [macro opSetAttr] Variable ACAT1N from RPRTDSM.study_adam_metadata do not exist in adfacmi_final.
WARNING: [macro opSetAttr] Variable ANL07DT from RPRTDSM.study_adam_metadata do not exist in adfacmi_final.
WARNING: [macro opSetAttr] Variable APERIOD from RPRTDSM.study_adam_metadata do not exist in adfacmi_final.
WARNING: [macro opSetAttr] Variable APERIODC from RPRTDSM.study_adam_metadata do not exist in adfacmi_final.
102                                                        The SAS System                            04:10 Wednesday, April 15, 2026

WARNING: [macro opSetAttr] Variable AVAL from RPRTDSM.study_adam_metadata do not exist in adfacmi_final.
WARNING: [macro opSetAttr] Variable AVISIT from RPRTDSM.study_adam_metadata do not exist in adfacmi_final.
WARNING: [macro opSetAttr] Variable AVISITN from RPRTDSM.study_adam_metadata do not exist in adfacmi_final.
WARNING: [macro opSetAttr] Variable CHG from RPRTDSM.study_adam_metadata do not exist in adfacmi_final.
WARNING: [macro opSetAttr] Variable IMPNUM from RPRTDSM.study_adam_metadata do not exist in adfacmi_final.
WARNING: [macro opSetAttr] Variable type is not consistent between RPRTDSM.study_adam_metadata and input dataset for var
iable IMPREAS.
WARNING: [macro opSetAttr] The original variable type will be used.
WARNING: [macro opSetAttr] Variable type is not consistent between RPRTDSM.study_adam_metadata and input dataset for var
iable PARAM.
WARNING: [macro opSetAttr] The original variable type will be used.
WARNING: [macro opSetAttr] Variable type is not consistent between RPRTDSM.study_adam_metadata and input dataset for var
iable PARAMCD.
WARNING: [macro opSetAttr] The original variable type will be used.
WARNING: [macro opSetAttr] Variable TRTP from RPRTDSM.study_adam_metadata do not exist in adfacmi_final.
WARNING: [macro opSetAttr] Variable TRTPN from RPRTDSM.study_adam_metadata do not exist in adfacmi_final.
NOTE: There were 39 observations read from the data set WORK.OPSA_TEMP_META1.
NOTE: There were 101 observations read from the data set WORK.OPSA_TEMP_CONTENT2.
NOTE: The data set WORK.OPSA_TEMP_CONTENT3 has 26 observations and 16 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(OPSETATTR):   proc sql;
MPRINT(OPSETATTR):   create table opsa_temp_content4(drop=opsa_temp_dummy_variable) as select 0 as 
opsa_temp_dummy_variable ,max(length(AEFLAG)) as AEFLAG ,max(length(ANL05DSC)) as ANL05DSC ,max(length(ANL05FL)) as 
ANL05FL ,max(length(ANL06DSC)) as ANL06DSC ,max(length(ANL06FL)) as ANL06FL ,max(length(ANL07DSC)) as ANL07DSC 
,max(length(ANL07FL)) as ANL07FL ,max(length(ASR)) as ASR ,max(length(CCS)) as CCS ,max(length(DTYPE)) as DTYPE 
,max(length(PROEVFL)) as PROEVFL ,max(length(SEX)) as SEX ,max(length(SITEID)) as SITEID ,max(length(STUDYID)) as 
STUDYID ,max(length(SUBJID)) as SUBJID ,max(length(SYSTRCRF)) as SYSTRCRF ,max(length(TRT01P)) as TRT01P 
,max(length(USUBJID)) as USUBJID from adfacmi_final(keep=AEFLAG ANL05DSC ANL05FL ANL06DSC ANL06FL ANL07DSC ANL07FL ASR 
CCS DTYPE PROEVFL SEX SITEID STUDYID SUBJID SYSTRCRF TRT01P USUBJID) ;
NOTE: Table WORK.OPSA_TEMP_CONTENT4 created, with 1 rows and 18 columns.

MPRINT(OPSETATTR):  quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(OPSETATTR):   proc transpose data=opsa_temp_content4 out=opsa_temp_content5(rename=(_name_=var col1=actLength));
MPRINT(OPSETATTR):   var _all_;

NOTE: There were 1 observations read from the data set WORK.OPSA_TEMP_CONTENT4.
NOTE: The data set WORK.OPSA_TEMP_CONTENT5 has 18 observations and 2 variables.
NOTE: PROCEDURE TRANSPOSE used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(OPSETATTR):   proc sort;
MPRINT(OPSETATTR):   by var;
MPRINT(OPSETATTR):   run;

NOTE: There were 18 observations read from the data set WORK.OPSA_TEMP_CONTENT5.
NOTE: The data set WORK.OPSA_TEMP_CONTENT5 has 18 observations and 2 variables.
NOTE: PROCEDURE SORT used (Total process time):
103                                                        The SAS System                            04:10 Wednesday, April 15, 2026

      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(OPSETATTR):   data opsa_temp_content6;
MPRINT(OPSETATTR):   merge opsa_temp_content3 opsa_temp_content5 end=eof;
MPRINT(OPSETATTR):   by var;
MPRINT(OPSETATTR):   retain errn 0;
MPRINT(OPSETATTR):   if length=. then length=originLength;
MPRINT(OPSETATTR):   else if actLength>length then do;
MPRINT(OPSETATTR):   if errn<10 then do;
MPRINT(OPSETATTR):   put "WARNING: [macro opSetAttr] Variable " var "has value longer than the length in 
RPRTDSM.study_adam_metadata.";
MPRINT(OPSETATTR):   put "WARNING: [macro opSetAttr] It will keep the original variable length.";
MPRINT(OPSETATTR):   errn+1;
MPRINT(OPSETATTR):   end;
MPRINT(OPSETATTR):   length=originLength;
MPRINT(OPSETATTR):   end;
MPRINT(OPSETATTR):   if eof and errn>=10 then put "WARNING: [macro opSetAttr] More WARNINGs for this point will not be 
printed.";

NOTE: There were 26 observations read from the data set WORK.OPSA_TEMP_CONTENT3.
NOTE: There were 18 observations read from the data set WORK.OPSA_TEMP_CONTENT5.
NOTE: The data set WORK.OPSA_TEMP_CONTENT6 has 26 observations and 18 variables.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(OPSETATTR):   proc sort;
MPRINT(OPSETATTR):   by var_order var;
MPRINT(OPSETATTR):   run;

NOTE: There were 26 observations read from the data set WORK.OPSA_TEMP_CONTENT6.
NOTE: The data set WORK.OPSA_TEMP_CONTENT6 has 26 observations and 18 variables.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(OPSETATTR):   proc sql noprint;
MPRINT(OPSETATTR):   select distinct var into: opsa_keepVars separated by " " from opsa_temp_content6;
MPRINT(OPSETATTR):   quit;
NOTE: PROCEDURE SQL used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

MPRINT(OPSETATTR):   data _null_;
MPRINT(OPSETATTR):   set opsa_temp_content6(in=in1) opsa_temp_content6(in=in2) end=eof;
MPRINT(OPSETATTR):   if _n_=1 then do;
MPRINT(OPSETATTR):   call execute("options varlenchk=nowarn;");
MPRINT(OPSETATTR):   call execute("data opsa_temp_content_data1;attrib");
MPRINT(OPSETATTR):   end;
MPRINT(OPSETATTR):   if in1 and var_order^=1e5 then do;
MPRINT(OPSETATTR):   call execute(var);
MPRINT(OPSETATTR):   call execute(cats('length=',type,length));
MPRINT(OPSETATTR):  ;
104                                                        The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(OPSETATTR):   call execute(cats('label="',label,'"'));
MPRINT(OPSETATTR):   end;
MPRINT(OPSETATTR):   if lag(in1) and in2 then call execute(";set adfacmi_final; format _all_; informat _all_;");
MPRINT(OPSETATTR):   if in2 and var_order^=1e5 and format^='' then call execute(catx(' ','format',var,format,';'));
MPRINT(OPSETATTR):   if eof then do;
MPRINT(OPSETATTR):   call execute("keep AEDCDT AEFLAG ANL05DSC ANL05DT ANL05FL ANL06DSC ANL06DT ANL06FL ANL07DSC 
ANL07FL ASR BASE CCS DTYPE IMPREAS PARAM PARAMCD PROEVFL SEX SITEID STUDYID SUBJID SYSTRCRF TRT01P TRT01PN USUBJID 
;run;");
MPRINT(OPSETATTR):   call execute("options varlenchk=warn;");
MPRINT(OPSETATTR):   end;
MPRINT(OPSETATTR):   run;

MPRINT(OPSETATTR):   options varlenchk=nowarn;
MPRINT(OPSETATTR):   data opsa_temp_content_data1;
MPRINT(OPSETATTR):   ;
MPRINT(OPSETATTR):  set adfacmi_final;
MPRINT(OPSETATTR):   format _all_;
MPRINT(OPSETATTR):   informat _all_;
MPRINT(OPSETATTR):   format ANL05DT DATE9. ;
MPRINT(OPSETATTR):   format ANL05FL Y. ;
MPRINT(OPSETATTR):   format ANL06DT DATE9. ;
MPRINT(OPSETATTR):   format ANL06FL Y. ;
MPRINT(OPSETATTR):   format ANL07FL Y. ;
MPRINT(OPSETATTR):   format AEDCDT DATE9. ;
MPRINT(OPSETATTR):   keep AEDCDT AEFLAG ANL05DSC ANL05DT ANL05FL ANL06DSC ANL06DT ANL06FL ANL07DSC ANL07FL ASR BASE CCS 
DTYPE IMPREAS PARAM PARAMCD PROEVFL SEX SITEID STUDYID SUBJID SYSTRCRF TRT01P TRT01PN USUBJID ;
MPRINT(OPSETATTR):  run;
MPRINT(OPSETATTR):   options varlenchk=warn;
NOTE: There were 26 observations read from the data set WORK.OPSA_TEMP_CONTENT6.
NOTE: There were 26 observations read from the data set WORK.OPSA_TEMP_CONTENT6.
NOTE: DATA statement used (Total process time):
      real time           0.00 seconds
      cpu time            0.00 seconds
      

NOTE: CALL EXECUTE generated line.
1      + options varlenchk=nowarn;
2      + data opsa_temp_content_data1;attrib
3      + STUDYID
4      + length=$1
5      + label="Study Identifier"
6      + USUBJID
7      + length=$1
8      + label="Unique Subject Identifier"
9      + SUBJID
10     + length=$1
11     + label="Subject Identifier for the Study"
12     + SITEID
13     + length=$1
14     + label="Study Site Identifier"
15     + SEX
16     + length=$1
17     + label="Sex"
18     + ASR
19     + length=$1
20     + label="Age/Sex/Race"
21     + CCS
22     + length=$1
105                                                        The SAS System                            04:10 Wednesday, April 15, 2026

23     + label="Country or Subdivision/Subject ID"
24     + TRT01P
25     + length=$1
26     + label="Planned Treatment for Period 01"
27     + TRT01PN
28     + length=8
29     + label="Planned Treatment for Period 01 (N)"
30     + PARAM
31     + length=8
32     + label="Parameter"
33     + PARAMCD
34     + length=8
35     + label="Parameter Code"
36     + DTYPE
37     + length=$1
38     + label="Derivation Type"
39     + IMPREAS
40     + length=8
41     + label="Imputation Rason"
42     + BASE
43     + length=8
44     + label="Baseline Value"
45     + SYSTRCRF
46     + length=$1
47     + label="Corti. or myco. acid trt. at rand. (CRF)"
48     + ANL05DT
49     + length=8
50     + label="Date of 1st anti-proteinuric therapies"
51     + ANL05FL
52     + length=$1
53     + label="Analysis Flag 05"
54     + ANL05DSC
55     + length=$1
56     + label="Analysis Flag 05 Description"
57     + ANL06DT
58     + length=8
59     + label="Date of 1st RRT"
60     + ANL06FL
61     + length=$1
62     + label="Analysis Flag 06"
63     + ANL06DSC
64     + length=$1
65     + label="Analysis Flag 06 Description"
66     + ANL07FL
67     + length=$1
68     + label="Analysis Flag 07"
69     + ANL07DSC
70     + length=$1
71     + label="Analysis Flag 07 Description"
72     + AEFLAG
73     + length=$1
74     + label="Study DC for AE or Renal Death Period 1"
75     + AEDCDT
76     + length=8
77     + label="Study DC due to AE or renal death Date"
78     + PROEVFL
79     + length=$1
80     + label="PRO Evaluable Population Flag"
106                                                        The SAS System                            04:10 Wednesday, April 15, 2026

81     + ;set adfacmi_final; format _all_; informat _all_;
MPRINT(OPSETATTR):  1 length=1 length=1 length=1 length=1 length=1 length=1 length=1 length= length= length= length=1 
length= length= length=1 length= length=1 length=1 length= length=1 length=1 length=1 length=1 length=1 length= length=1
82     + format ANL05DT DATE9. ;
NOTE: Line generated by the CALL EXECUTE routine.
83     + format ANL05FL Y. ;
                        --
                        484
NOTE 484-185: Format $Y was not found or could not be loaded.

84     + format ANL06DT DATE9. ;
NOTE: Line generated by the CALL EXECUTE routine.
85     + format ANL06FL Y. ;
                        --
                        484
NOTE: Line generated by the CALL EXECUTE routine.
86     + format ANL07FL Y. ;
                        --
                        484
NOTE 484-185: Format $Y was not found or could not be loaded.

87     + format AEDCDT DATE9. ;
88     + keep AEDCDT AEFLAG ANL05DSC ANL05DT ANL05FL ANL06DSC ANL06DT ANL06FL ANL07DSC ANL07FL ASR BASE CCS DTYPE 
IMPREAS PARAM PARAMCD PROEVFL SEX SITEID STUDYID SUBJID SYSTRCRF TRT01P TRT01PN USUBJID ;run;

NOTE: There were 0 observations read from the data set WORK.ADFACMI_FINAL.
NOTE: The data set WORK.OPSA_TEMP_CONTENT_DATA1 has 0 observations and 26 variables.
NOTE: DATA statement used (Total process time):
      real time           0.01 seconds
      cpu time            0.01 seconds
      

89     + options varlenchk=warn;
MPRINT(OPSETATTR):   proc sort data=opsa_temp_content_data1 out=ANALYSIS.ADFACMI(keep=AEDCDT AEFLAG ANL05DSC ANL05DT 
ANL05FL ANL06DSC ANL06DT ANL06FL ANL07DSC ANL07FL ASR BASE CCS DTYPE IMPREAS PARAM PARAMCD PROEVFL SEX SITEID STUDYID 
SUBJID SYSTRCRF TRT01P TRT01PN USUBJID label="FACIT Multi-Imputation Analysis Dataset");
ERROR: Variable ACAT1N not found.
ERROR: Variable AVISITN not found.
MPRINT(OPSETATTR):   by STUDYID USUBJID SUBJID ACAT1N PARAMCD AVISITN IMPNUM;
ERROR: Variable IMPNUM not found.
MPRINT(OPSETATTR):   run;

NOTE: The SAS System stopped processing this step because of errors.
WARNING: The data set ANALYSIS.ADFACMI may be incomplete.  When this step was stopped there were 0 observations and 0 
         variables.
WARNING: Data set ANALYSIS.ADFACMI was not replaced because this step was stopped.
NOTE: PROCEDURE SORT used (Total process time):
      real time           0.01 seconds
      cpu time            0.00 seconds
      


MPRINT(OPSETATTR):   proc datasets lib=work noprint;
MPRINT(OPSETATTR):   delete opsa_temp_:;
MPRINT(OPSETATTR):   quit;

NOTE: Deleting WORK.OPSA_TEMP_CONTENT1 (memtype=DATA).
NOTE: Deleting WORK.OPSA_TEMP_CONTENT2 (memtype=DATA).
107                                                        The SAS System                            04:10 Wednesday, April 15, 2026

NOTE: Deleting WORK.OPSA_TEMP_CONTENT3 (memtype=DATA).
NOTE: Deleting WORK.OPSA_TEMP_CONTENT4 (memtype=DATA).
NOTE: Deleting WORK.OPSA_TEMP_CONTENT5 (memtype=DATA).
NOTE: Deleting WORK.OPSA_TEMP_CONTENT6 (memtype=DATA).
NOTE: Deleting WORK.OPSA_TEMP_CONTENT_DATA1 (memtype=DATA).
NOTE: Deleting WORK.OPSA_TEMP_META1 (memtype=DATA).
NOTE: PROCEDURE DATASETS used (Total process time):
      real time           0.00 seconds
      cpu time            0.01 seconds
      

MPRINT(OPSETATTR):  ;
**********opSetAttr End************************************************************
MPRINT(OPSETATTR):  ;
NOTE: Remote submit to T1 complete.
39         
40         %LET _CLIENTTASKLABEL=;
41         %LET _CLIENTPROCESSFLOWNAME=;
42         %LET _CLIENTPROJECTPATH=;
43         %LET _CLIENTPROJECTPATHHOST=;
44         %LET _CLIENTPROJECTNAME=;
45         %LET _SASPROGRAMFILE=;
46         %LET _SASPROGRAMFILEHOST=;
47         
48         ;*';*";*/;quit;run;
49         ODS _ALL_ CLOSE;
50         
51         
52         QUIT; RUN;
53         
