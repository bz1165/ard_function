我在 Microsoft Edge 中使用 DevTools。我正在使用 Elements 工具检查元素。我将在下面提供我正在检查的元素所在的 DOM 结构。我将提供元素本身及其上级，就像它们在 DOM 中的显示一样。我将省略 DOM 的其余部分，以使其保持简短。我还将提供适用于我在 DOM 结构中提供的元素的 CSS 规则列表。我想询问你有关此内容的问题，以修复我遇到的 HTML/CSS 问题。请充当乐于帮助我调试问题的友好的 CSS 专家。尽可能为我面临的问题提供修补程序。n如果我有关元素的问题与所选元素不同，并且你无法回答，请告诉我。    当我说“此元素”、“该元素”或“当前元素”时，我指的是 DOM 树中最深元素的中间部分。nDOM structure:n`htmln    <body class="windows chrome ng-scope touch_scroll fixed-header" ng-class="[main.style, 'false' == 'true' ? 'has-agent-chat' : '', 'false' == 'true' ? 'dark-theme' : '' ]" ng-controller="spPageCtrl as main" accessibility="false" style=""><div class="flex-row sp-na-root-container"><div class="sp-page-root page flex-column sp-can-animate" id="sp-main-wrapper" ng-class="{'sp-loading': main.firstPage, 'sp-can-animate': main.doAnimate}" style=""><section ng-switch="page.has_custom_main_tag" class="flex-grow page sp-scroll flex-column" role="presentation" tabindex="-1"><main ng-switch-when="false" class="body padding-top flex-grow ng-scope leftnav-expanded" data-page-id="a487d4fc1ba575d0eed9caa16b4bcb9f" data-page-title="Request" role="main" style=""><div ng-switch="container.semantic_tag" ng-repeat="container in containers" ng-style="main.parseJSON(container.background)" ng-class="::[container.class_name, 'c' + container.sys_id]" class="ng-scope c608718b01be575d0eed9caa16b4bcb4b" style="background-size: initial; background-position: center center;"><div ng-switch-default="" ng-class="::main.getContainerClasses(container)" class="ng-scope container"><sp-page-row ng-repeat="row in ::container.rows track by row.sys_id" columns="::row.columns" row="::row" container="::container" class="ng-scope ng-isolate-scope"><div ng-if="row.semantic_tag !== 'main'" ng-include="'sp_page_row_content.xml'" class="sp-row-content  row"><div ng-repeat="column in columns track by column.sys_id" ng-switch="column.semantic_tag" class=" col-sm-12 col-md-12 col-lg-12 "><span ng-switch-default="" ng-repeat="rectangle in column.widgets track by rectangle.instance_id" class="ng-scope"><div id="x659b3f5a1b548e94eed9caa16b4bcbfb" class="v0cbad0c61b48ce90421d206fab4bcbc5 ng-scope" data="data" options="options" widget="widget" server="server" sn-atf-area="NVS_ECP_HRM_catalog_item"><div><div class="vd4a0a0ca1bc8ce90421d206fab4bcb6b ng-scope" data="data" options="options" widget="widget" server="server" sn-atf-area="NVS_ECP SC Catalog Item"><div id="sc_cat_item" ng-if="::(data.recordFound &amp;&amp; !data.not_for_mobile)" sn-atf-blacklist="IS_SERVICE_CATALOG" class="ng-scope" style=""><div class="row ng-scope" ng-if="::data.sc_cat_item" ng-class="{'native-mobile': options.native_mobile == 'true'}"><div class="col-sm-12 col-md-12" ng-class="{'col-md-9': options.display_cart_on_right === 'true', 'col-md-12': options.display_cart_on_right !== 'true', 'no-padder': options.native_mobile == 'true'}" id="catItemTop"><div class="panel panel-default"><div class="b-b wrapper-md" ng-show="!data.no_fields" aria-label="form" aria-hidden="false"><form id="catalog-form" class="ng-pristine ng-valid ng-valid-maxlength" style=""><div form-model="::data.sc_cat_item" mandatory="c.mandatory" class="ng-isolate-scope"><sp-variable-layout ng-if="!delayView" ng-attr-id="{{::formModel.table}}.do" embedded_in_modal="embeddedInModal" class="ng-scope" id="sc_cat_item.do"><!-- end ngRepeat: container in containers --><div ng-repeat="container in containers" class="sp-form-container ng-scope" ng-class="{'sp-form-documentation-container': container.id === documentationSectionId}" ng-show="paintForm(container)" ng-attr-role="{{(container.caption || container.captionDisplay) ? 'group' : undefined}}" ng-attr-aria-labelledby="{{(container.caption || container.captionDisplay) ? 'container_' + container.id : undefined}}" aria-hidden="false"></div><!-- end ngRepeat: container in containers --></sp-variable-layout></div></form></div></div></div></div></div></div></div></div></span></div></div></sp-page-row></div></div></main></section></div></div></body>`nCSS rules:n`cssn    /** For the <div ng-repeat="container in containers" class="sp-form-container ng-scope" ng-class="{'sp-form-documentation-container': container.id === documentationSectionId}" ng-show="paintForm(container)" ng-attr-role="{{(container.caption || container.captionDisplay) ? 'group' : undefined}}" ng-attr-aria-labelledby="{{(container.caption || container.captionDisplay) ? 'container_' + container.id : undefined}}" aria-hidden="false"> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
/** For the <sp-variable-layout ng-if="!delayView" ng-attr-id="{{::formModel.table}}.do" embedded_in_modal="embeddedInModal" class="ng-scope" id="sc_cat_item.do"> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
/** For the <div form-model="::data.sc_cat_item" mandatory="c.mandatory" class="ng-isolate-scope"> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
/** For the <form id="catalog-form" class="ng-pristine ng-valid ng-valid-maxlength" style=""> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
/** For the <div class="b-b wrapper-md" ng-show="!data.no_fields" aria-label="form" aria-hidden="false"> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
.b-b {
border-bottom: 1px solid #DADDE2;
}
.wrapper-md {
padding: 20px !important;
}
.b-b.wrapper-md {
margin-bottom: 1.5rem;
}
/** For the <div class="panel panel-default"> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
.panel {
margin-bottom: 22px;
background-color: #ffffff;
border: 1px solid transparent;
border-radius: 8px;
-webkit-box-shadow: 0 1px 1px rgba(0, 0, 0, .05);
box-shadow: 0 1px 1px rgba(0, 0, 0, .05);
}
.panel-default {
border-color: #DADDE2;
}
.panel-default, .panel, .widget {
border: 1px solid #DADADA !important;
}
/** For the <div class="col-sm-12 col-md-12" ng-class="{'col-md-9': options.display_cart_on_right === 'true', 'col-md-12': options.display_cart_on_right !== 'true', 'no-padder': options.native_mobile == 'true'}" id="catItemTop"> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
.col-xs-1, .col-sm-1, .col-md-1, .col-lg-1, .col-xs-1, .col-sm-1, .col-md-1, .col-lg-1, .col-xs-2, .col-sm-2, .col-md-2, .col-lg-2, .col-xs-3, .col-sm-3, .col-md-3, .col-lg-3, .col-xs-4, .col-sm-4, .col-md-4, .col-lg-4, .col-xs-5, .col-sm-5, .col-md-5, .col-lg-5, .col-xs-6, .col-sm-6, .col-md-6, .col-lg-6, .col-xs-7, .col-sm-7, .col-md-7, .col-lg-7, .col-xs-8, .col-sm-8, .col-md-8, .col-lg-8, .col-xs-9, .col-sm-9, .col-md-9, .col-lg-9, .col-xs-10, .col-sm-10, .col-md-10, .col-lg-10, .col-xs-11, .col-sm-11, .col-md-11, .col-lg-11, .col-xs-12, .col-sm-12, .col-md-12, .col-lg-12 {
position: relative;
min-height: 1px;
padding-left: 16px;
padding-right: 16px;
}
/** For the <div class="row ng-scope" ng-if="::data.sc_cat_item" ng-class="{'native-mobile': options.native_mobile == 'true'}"> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
.row {
margin-left: -16px;
margin-right: -16px;
}
/** For the <div id="sc_cat_item" ng-if="::(data.recordFound &amp;&amp; !data.not_for_mobile)" sn-atf-blacklist="IS_SERVICE_CATALOG" class="ng-scope" style=""> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
/** For the <div class="vd4a0a0ca1bc8ce90421d206fab4bcb6b ng-scope" data="data" options="options" widget="widget" server="server" sn-atf-area="NVS_ECP SC Catalog Item"> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
/** For the <div> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
/** For the <div id="x659b3f5a1b548e94eed9caa16b4bcbfb" class="v0cbad0c61b48ce90421d206fab4bcbc5 ng-scope" data="data" options="options" widget="widget" server="server" sn-atf-area="NVS_ECP_HRM_catalog_item"> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
/** For the <span ng-switch-default="" ng-repeat="rectangle in column.widgets track by rectangle.instance_id" class="ng-scope"> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
/** For the <div ng-repeat="column in columns track by column.sys_id" ng-switch="column.semantic_tag" class=" col-sm-12 col-md-12 col-lg-12 "> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
.col-xs-1, .col-sm-1, .col-md-1, .col-lg-1, .col-xs-1, .col-sm-1, .col-md-1, .col-lg-1, .col-xs-2, .col-sm-2, .col-md-2, .col-lg-2, .col-xs-3, .col-sm-3, .col-md-3, .col-lg-3, .col-xs-4, .col-sm-4, .col-md-4, .col-lg-4, .col-xs-5, .col-sm-5, .col-md-5, .col-lg-5, .col-xs-6, .col-sm-6, .col-md-6, .col-lg-6, .col-xs-7, .col-sm-7, .col-md-7, .col-lg-7, .col-xs-8, .col-sm-8, .col-md-8, .col-lg-8, .col-xs-9, .col-sm-9, .col-md-9, .col-lg-9, .col-xs-10, .col-sm-10, .col-md-10, .col-lg-10, .col-xs-11, .col-sm-11, .col-md-11, .col-lg-11, .col-xs-12, .col-sm-12, .col-md-12, .col-lg-12 {
position: relative;
min-height: 1px;
padding-left: 16px;
padding-right: 16px;
}
/** For the <div ng-if="row.semantic_tag !== 'main'" ng-include="'sp_page_row_content.xml'" class="sp-row-content  row"> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
.row {
margin-left: -16px;
margin-right: -16px;
}
/** For the <sp-page-row ng-repeat="row in ::container.rows track by row.sys_id" columns="::row.columns" row="::row" container="::container" class="ng-scope ng-isolate-scope"> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
/** For the <div ng-switch-default="" ng-class="::main.getContainerClasses(container)" class="ng-scope container"> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
.container {
margin-right: auto;
margin-left: auto;
padding-left: 16px;
padding-right: 16px;
}
.container {
max-width: 100%;
}
/** For the <div ng-switch="container.semantic_tag" ng-repeat="container in containers" ng-style="main.parseJSON(container.background)" ng-class="::[container.class_name, 'c' + container.sys_id]" class="ng-scope c608718b01be575d0eed9caa16b4bcb4b" style="background-size: initial; background-position: center center;"> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
/** For the <main ng-switch-when="false" class="body padding-top flex-grow ng-scope leftnav-expanded" data-page-id="a487d4fc1ba575d0eed9caa16b4bcb9f" data-page-title="Request" role="main" style=""> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
article, aside, details, figcaption, figure, footer, header, hgroup, main, menu, nav, section, summary {
display: block;
}
.flex-grow {
-ms-flex-positive: 1;
-moz-flex-grow: 1;
-webkit-box-flex: 1;
-webkit-flex-grow: 1;
flex-grow: 1;
}
body .padding-top {
padding-top: 1rem;
}
main.body {
padding-bottom: 16px;
}
section.page > main.body, section.page > section.body {
flex-grow: 1;
flex-shrink: 0;
-ms-flex-positive: 1;
}
/** For the <section ng-switch="page.has_custom_main_tag" class="flex-grow page sp-scroll flex-column" role="presentation" tabindex="-1"> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
article, aside, details, figcaption, figure, footer, header, hgroup, main, menu, nav, section, summary {
display: block;
}
.flex-column {
display: -ms-flexbox;
display: -moz-flex;
display: -webkit-box;
display: -webkit-flex;
display: flex;
-ms-flex-flow: column nowrap;
-moz-flex-flow: column nowrap;
-webkit-flex-flow: column nowrap;
flex-flow: column nowrap;
}
.flex-grow {
-ms-flex-positive: 1;
-moz-flex-grow: 1;
-webkit-box-flex: 1;
-webkit-flex-grow: 1;
flex-grow: 1;
}
div.page, section.page {
height: 100%;
width: 100%;
overflow: hidden;
}
section.page {
position: relative;
overflow: auto;
border: none !important;
box-shadow: none !important;
}
section.page {
display: flex;
flex-direction: column;
display: -ms-flexbox;
-ms-flex-direction: column;
}
.sp-na-root-container .sp-page-root  > section {
overflow: visible;
}
/** For the <div class="sp-page-root page flex-column sp-can-animate" id="sp-main-wrapper" ng-class="{'sp-loading': main.firstPage, 'sp-can-animate': main.doAnimate}" style=""> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
.flex-column {
display: -ms-flexbox;
display: -moz-flex;
display: -webkit-box;
display: -webkit-flex;
display: flex;
-ms-flex-flow: column nowrap;
-moz-flex-flow: column nowrap;
-webkit-flex-flow: column nowrap;
flex-flow: column nowrap;
}
.sp-page-root {
container-type: size;
background-color: #FFF !important;
}
.sp-page-root {
color: RGB(var(--now-color_text--primary, 22, 27, 28));
}
div.page, section.page {
height: 100%;
width: 100%;
overflow: hidden;
}
.sp-page-root.page {
height: auto;
min-height: 100%;
}
.sp-na-root-container .sp-page-root {
overflow: auto;
}
.sp-page-root.page {
height: 100%;
}
/** For the <div class="flex-row sp-na-root-container"> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
.flex-row {
display: -ms-flexbox;
display: -moz-flex;
display: -webkit-box;
display: -webkit-flex;
display: flex;
-ms-flex-flow: row nowrap;
-moz-flex-flow: row nowrap;
-webkit-flex-flow: row nowrap;
flex-flow: row nowrap;
}
.sp-na-root-container {
height: 100%;
}
/** For the <body class="windows chrome ng-scope touch_scroll fixed-header" ng-class="[main.style, 'false' == 'true' ? 'has-agent-chat' : '', 'false' == 'true' ? 'dark-theme' : '' ]" ng-controller="spPageCtrl as main" accessibility="false" style=""> element **/
* {
-webkit-box-sizing: border-box;
-moz-box-sizing: border-box;
box-sizing: border-box;
}
body {
margin: 0;
}
body {
font-family: "Arial", sans-serif;
font-size: 16px;
line-height: 1.4;
color: #002068;
background-color: #FFF;
}
body {
margin: 0;
position: relative;
min-height: 100%;
}
html, body {
min-width: 320px;
height: 100%;
}
html, body {
min-width: 310px;
}
body {
line-height: 1.42857143;
}
html, body {
color: #002068;
font-family: "Arial", sans-serif;
}
body {
color: #002068;
font-family: "Arial", sans-serif;
font-size: 1.6rem;
}
html, body {
background-color: RGB(var(--now-color_background--primary, 255, 255, 255));
color: RGB(var(--now-color_text--primary, 22, 27, 28));
}
body, html {
background-color: RGB(var(--now-color_background--primary,var(--now-color_background--primary,255,255,255)))!important;
color: RGB(var(--now-color_text--primary,var(--now-color_text--primary,22,27,28)))!important;
}
.touch_scroll {
overflow: auto;
-webkit-overflow-scrolling: touch;
}
.touch_scroll {
overflow: auto !important;
}
`  
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
