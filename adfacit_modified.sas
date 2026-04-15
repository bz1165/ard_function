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
49                                                         The SAS System                            04:10 Wednesday, April 15, 2026

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
50                                                         The SAS System                            04:10 Wednesday, April 15, 2026

MPRINT(PART2A):   super_mar[itime]=A[itime]+MyCov[itime];
MPRINT(PART2A):   end;
MPRINT(PART2A):   output;
MPRINT(PART2A):   end;
MPRINT(PART2A):   end;
MPRINT(PART2A):   run;

NOTE: Numeric values have been converted to character values at the places given by: (Line):(Column).
      126411:2   
ERROR: In otherwise clause
ERROR: Trying to use Method <  >
NOTE: There were 2200 observations read from the data set WORK.FACIT_MI_POSTLP.
NOTE: There were 21 observations read from the data set WORK.FACIT_MI_DATAP.
NOTE: There were 1 observations read from the data set WORK.FACIT_MI_SEC_TEMP42.
NOTE: The data set WORK.FACIT_MI_SEC_DATAPM has 0 observations and 22 variables.
NOTE: DATA statement used (Total process time):
      real time           0.03 seconds
      cpu time            0.01 seconds
      

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
      real time           0.01 seconds
      cpu time            0.00 seconds
51                                                         The SAS System                            04:10 Wednesday, April 15, 2026

      

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
      cpu time            0.01 seconds
      

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
52                                                         The SAS System                            04:10 Wednesday, April 15, 2026

      


MPRINT(FACIT_MI):   data facit_mi_sec;
MPRINT(FACIT_MI):   set facit_mi_sec_full;
ERROR: File WORK.FACIT_MI_SEC_FULL.DATA does not exist.
MPRINT(FACIT_MI):   chg=aval-base;
MPRINT(FACIT_MI):   if imp_method="ALMCF" then do;
MPRINT(FACIT_MI):   chg=.;
MPRINT(FACIT_MI):   aval=.;
MPRINT(FACIT_MI):   imp_method='';
MPRINT(FACIT_MI):   end;
MPRINT(FACIT_MI):   run;

NOTE: The SAS System stopped processing this step because of errors.
