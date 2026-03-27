# =============================================================================
# FILE        : create_ard_mmrm.R
# DESCRIPTION : MMRM (Change from Baseline by Visit) ARD generation
#               Covers: FACIT 14.2-4.1/4.2, eGFR 14.2-1.9.1/1.10.1
#               Produces compact ARD only (no RTF/TrakData bind)
# PACKAGES    : dplyr, tidyr, purrr, mmrm, emmeans
# KEY FIX     : visits_model (enters MMRM) vs visits_display (shown in ARD)
#               are now separate spec fields so model data is never truncated
# =============================================================================


# =============================================================================
# SECTION 1: METHOD SPEC
# =============================================================================

method_spec_mmrm_by_visit <- list(

  method_id   = "MMRM_CFB_BY_VISIT",
  family      = "mmrm_change_from_baseline_by_visit",
  description = paste(
    "MMRM for change from baseline by visit.",
    "Fixed: TRT, VISIT, STRATA1-3, BASE, TRT*VISIT, VISIT*BASE.",
    "Repeated: unstructured on VISIT | SUBJECT.",
    "REML, Kenward-Roger df. MI combined via Rubin's rules."
  ),

  # SAP Appendix non-convergence fallback order
  fallback = list(
    list(covariance = "us",  use_strata = TRUE,  use_visit_base = TRUE),
    list(covariance = "ar1", use_strata = TRUE,  use_visit_base = TRUE),
    list(covariance = "ar1", use_strata = FALSE, use_visit_base = TRUE),
    list(covariance = "ar1", use_strata = FALSE, use_visit_base = FALSE),
    list(covariance = "cs",  use_strata = FALSE, use_visit_base = FALSE)
  )
)


# =============================================================================
# SECTION 2: OUTPUT SPECS
#
# KEY DESIGN: visits_model vs visits_display are SEPARATE
#   visits_model   = all visits that enter the MMRM (controls which rows of
#                    ana are kept; must match SAS where clause exactly)
#   visits_display = subset shown in ARD / table (must be subset of visits_model)
#
# Why this matters: UN covariance matrix dimension = length(visits_model).
# If you filter ana to only display-visits, you fit a smaller UN matrix
# and get different LSMs and differences than SAS.
# =============================================================================

# --- FACIT 14.2-4.1 (Secondary estimand 4) -----------------------------------
# SAS: where FASFL="Y" and acat1="Secondary estimand 4/Exploratory estimand"
# SAS: no additional visit filter; adfacmi is already post-baseline
# Shell: Month 3, 6, 9, 18, 24 displayed; p-value at Month 9 only
spec_facit_14_2_4_1 <- list(

  output_id    = "14.2-4.1",
  method_id    = "MMRM_CFB_BY_VISIT",
  dataset_name = "adfacmi",

  population_var   = "FASFL",
  population_value = "Y",
  category_var     = "ACAT1",
  category_value   = "Secondary estimand 4/Exploratory estimand",

  vars = list(
    subject_id  = "USUBJID",
    subject_var = "SUBJID",
    trt         = "TRT01P",
    trtn        = "TRT01PN",
    visit       = "AVISIT",
    visitn      = "AVISITN",
    response    = "CHG",
    baseline    = "BASE",
    imputation  = "IMPNUM",
    dtype       = "DTYPE",
    strata      = c("STRVAL1", "STRVAL2", "STRVAL3")
  ),

  treatment_levels = c("Placebo", "LNP023 200 mg"),
  control_label    = "Placebo",
  comparison_label = "LNP023 200mg b.i.d. vs Placebo",

  # ALL visits that enter the MMRM model
  # Verify with: distinct(adfacmi, AVISIT, AVISITN) |> arrange(AVISITN)
  visits_model   = c("Month 3", "Month 6", "Month 9", "Month 18", "Month 24"),
  visits_display = c("Month 3", "Month 6", "Month 9", "Month 18", "Month 24"),

  visit_exclude         = NULL,
  pvalue_display_visits = c("Month 9"),
  n_obs_dtype_values    = c("", "TP"),
  digits = list(est = 3, p = 4)
)

# --- FACIT 14.2-4.2 (Supplementary estimand 4.1) ----------------------------
spec_facit_14_2_4_2 <- modifyList(
  spec_facit_14_2_4_1,
  list(output_id = "14.2-4.2",
       category_value = "Supplementary estimand 4.1")
)

# --- eGFR 14.2-1.9.1 (Supplementary 3) --------------------------------------
# SAS: where MAINPFL="Y" and acat1="Sensitivity 0.6/Supplementary 3"
#      and avisit ne "Baseline"
# Shell programming note: scheduled assessments Week 2, Month 1, 3, 6, 9,
#      12, 15, 18, 21, 24 — ALL must enter the model
# p-value displayed at Month 24 only
#
# IMPORTANT: verify exact AVISIT labels with:
#   distinct(adgfrmi2, AVISIT, AVISITN) |> arrange(AVISITN)
# Common variants: "Week 2"/"Week 02", "Month 1"/"Month 01"
spec_egfr_14_2_1_9_1 <- list(

  output_id    = "14.2-1.9.1",
  method_id    = "MMRM_CFB_BY_VISIT",
  dataset_name = "adgfrmi2",

  population_var   = "MAINPFL",
  population_value = "Y",
  category_var     = "ACAT1",
  category_value   = "Sensitivity 0.6/Supplementary 3",

  vars = list(
    subject_id  = "USUBJID",
    subject_var = "SUBJID",
    trt         = "TRT01P",
    trtn        = "TRT01PN",
    visit       = "AVISIT",
    visitn      = "AVISITN",
    response    = "CHG",
    baseline    = "BASE",
    imputation  = "IMPNUM",
    dtype       = "DTYPE",
    strata      = c("STRVAL1", "STRVAL2", "STRVAL3")
  ),

  treatment_levels = c("Placebo", "LNP023 200 mg"),
  control_label    = "Placebo",
  comparison_label = "LNP023 200mg b.i.d. vs Placebo",

  # ALL 10 scheduled visits enter the model (SAS only excludes "Baseline")
  visits_model = c("Week 2", "Month 1",
                   "Month 3", "Month 6", "Month 9", "Month 12",
                   "Month 15", "Month 18", "Month 21", "Month 24"),

  visits_display = c("Week 2", "Month 1",
                     "Month 3", "Month 6", "Month 9", "Month 12",
                     "Month 15", "Month 18", "Month 21", "Month 24"),

  visit_exclude         = "Baseline",
  pvalue_display_visits = c("Month 24"),
  n_obs_dtype_values    = c("", "TP"),
  digits = list(est = 3, p = 4)
)

# --- eGFR 14.2-1.10.1 (Supplementary 4) -------------------------------------
spec_egfr_14_2_1_10_1 <- modifyList(
  spec_egfr_14_2_1_9_1,
  list(output_id      = "14.2-1.10.1",
       dataset_name   = "adgfrmi3",
       category_value = "Supplementary 4")
)


# =============================================================================
# SECTION 3: VALIDATION
# =============================================================================

`%||%` <- function(a, b) if (!is.null(a)) a else b

validate_mmrm_spec <- function(spec) {

  req_top <- c("output_id", "method_id", "dataset_name",
               "population_var", "population_value",
               "category_var", "category_value",
               "vars", "treatment_levels", "control_label", "comparison_label",
               "visits_model", "visits_display",
               "pvalue_display_visits", "digits")
  miss <- setdiff(req_top, names(spec))
  if (length(miss) > 0)
    stop("[", spec$output_id %||% "?", "] Missing spec fields: ",
         paste(miss, collapse = ", "))

  req_vars <- c("subject_id", "subject_var", "trt", "trtn",
                "visit", "visitn", "response", "baseline", "imputation")
  miss_v <- setdiff(req_vars, names(spec$vars))
  if (length(miss_v) > 0)
    stop("[", spec$output_id, "] Missing spec$vars: ",
         paste(miss_v, collapse = ", "))

  if (!(spec$control_label %in% spec$treatment_levels))
    stop("[", spec$output_id, "] control_label '", spec$control_label,
         "' not in treatment_levels")

  bad_disp <- setdiff(spec$visits_display, spec$visits_model)
  if (length(bad_disp) > 0)
    stop("[", spec$output_id, "] visits_display has visits not in visits_model: ",
         paste(bad_disp, collapse = ", "))

  bad_pv <- setdiff(spec$pvalue_display_visits, spec$visits_display)
  if (length(bad_pv) > 0)
    stop("[", spec$output_id, "] pvalue_display_visits not in visits_display: ",
         paste(bad_pv, collapse = ", "))

  invisible(spec)
}


# =============================================================================
# SECTION 4: DATA PREPARATION
# =============================================================================

#' Standardise, filter and reshape analysis data
#'
#' Uses visits_model for ana filtering (all visits that enter MMRM).
#' Uses visits_display for obs_n and ARD row ordering.
prepare_mmrm_datasets <- function(data, spec) {

  v          <- spec$vars
  strata_src <- v$strata %||% character(0)
  dtype_src  <- v$dtype

  needed <- unique(c(
    spec$population_var, spec$category_var,
    v$subject_id, v$subject_var,
    v$trt, v$trtn,
    v$visit, v$visitn,
    v$response, v$baseline, v$imputation,
    strata_src,
    if (!is.null(dtype_src)) dtype_src
  ))
  needed <- intersect(needed, names(data))

  # --- 1. Population + category filter ---
  ana <- data |>
    dplyr::filter(
      .data[[spec$population_var]] == spec$population_value,
      .data[[spec$category_var]]   == spec$category_value
    ) |>
    dplyr::select(dplyr::any_of(needed)) |>
    dplyr::distinct()

  # --- 2. Rename to canonical names ---
  src <- c(v$subject_id, v$subject_var, v$trt, v$trtn,
           v$visit, v$visitn, v$response, v$baseline, v$imputation)
  can <- c("USUBJID", "SUBJID", "TRT", "TRTN",
           "VISIT", "VISITN", "RESP", "BASE", "IMPNUM")
  rmap <- stats::setNames(src, can)
  rmap <- rmap[rmap %in% names(ana)]
  ana  <- dplyr::rename(ana, dplyr::any_of(rmap))

  for (i in seq_along(strata_src)) {
    old <- strata_src[i]; new <- paste0("STRATA", i)
    if (old %in% names(ana)) names(ana)[names(ana) == old] <- new
  }
  for (i in 1:3) {
    nm <- paste0("STRATA", i)
    if (!nm %in% names(ana)) ana[[nm]] <- NA_character_
  }

  if (!is.null(dtype_src) && dtype_src %in% names(ana)) {
    names(ana)[names(ana) == dtype_src] <- "DTYPE"
  } else {
    ana$DTYPE <- NA_character_
  }

  # --- 3. Visit filters ---
  # First remove explicitly excluded visits (e.g. "Baseline")
  if (!is.null(spec$visit_exclude) && length(spec$visit_exclude) > 0)
    ana <- ana |> dplyr::filter(!VISIT %in% spec$visit_exclude)

  # Then keep only visits_model — this controls UN covariance matrix size
  ana <- ana |> dplyr::filter(VISIT %in% spec$visits_model)

  if (nrow(ana) == 0)
    stop("[", spec$output_id, "] ana has 0 rows after filtering.\n",
         "  Check: population_var/value, category_var/value, visit names.\n",
         "  Run distinct(data, AVISIT) to see actual visit labels.")

  # --- 4. Factor and type setup ---
  ana <- ana |>
    dplyr::mutate(
      TRT    = factor(TRT,   levels = spec$treatment_levels),
      VISIT  = factor(VISIT, levels = spec$visits_model),
      IMPNUM = as.integer(IMPNUM)
    ) |>
    dplyr::arrange(IMPNUM, VISITN, TRTN, USUBJID)

  # --- 5. Active strata ---
  strata_present <- paste0("STRATA", 1:3)[
    vapply(paste0("STRATA", 1:3),
           function(x) x %in% names(ana) && any(!is.na(ana[[x]])),
           logical(1))
  ]

  # --- 6. bigN: subjects with non-missing baseline + covariates ---
  covar_cols <- c("BASE", strata_present)
  subj_n <- ana |>
    dplyr::distinct(USUBJID, TRT, TRTN,
                    dplyr::across(dplyr::all_of(covar_cols))) |>
    dplyr::filter(dplyr::if_all(dplyr::all_of(covar_cols), ~ !is.na(.x))) |>
    dplyr::count(TRT, TRTN, name = "bigN") |>
    dplyr::arrange(TRTN)

  # --- 7. nobs: using display visits only, dtype filter ---
  dtype_ok <- spec$n_obs_dtype_values %||% c("", "TP")

  obs_n <- ana |>
    dplyr::filter(VISIT %in% spec$visits_display, !is.na(RESP)) |>
    {
      d <- .
      if (!all(is.na(d$DTYPE)))
        dplyr::filter(d, is.na(DTYPE) | DTYPE %in% dtype_ok)
      else d
    } |>
    dplyr::distinct(USUBJID, VISIT, VISITN, TRT, TRTN) |>
    dplyr::count(VISIT, VISITN, TRT, TRTN, name = "nobs") |>
    dplyr::arrange(match(as.character(VISIT), spec$visits_display), TRTN)

  # --- 8. Visit reference ---
  visit_ref <- ana |>
    dplyr::filter(VISIT %in% spec$visits_display) |>
    dplyr::distinct(VISIT, VISITN) |>
    dplyr::mutate(
      visit_order = match(as.character(VISIT), spec$visits_display),
      pvalue_flag = as.character(VISIT) %in% spec$pvalue_display_visits
    ) |>
    dplyr::arrange(visit_order)

  list(
    ana            = ana,
    subj_n         = subj_n,
    obs_n          = obs_n,
    visit_ref      = visit_ref,
    strata_present = strata_present,
    meta = list(output_id    = spec$output_id,
                method_id    = spec$method_id,
                dataset_name = spec$dataset_name)
  )
}


# =============================================================================
# SECTION 5: MODEL FITTING
# =============================================================================

.build_cov_term <- function(covariance = c("us", "ar1", "cs")) {
  switch(match.arg(covariance),
    us  = "us(VISIT | USUBJID)",
    ar1 = "ar1(VISIT | USUBJID)",
    cs  = "cs(VISIT | USUBJID)"
  )
}

.build_mmrm_formula <- function(strata_present, plan) {
  rhs <- c(
    "TRT", "VISIT",
    if (plan$use_strata && length(strata_present) > 0) strata_present,
    "BASE", "TRT:VISIT",
    if (plan$use_visit_base) "VISIT:BASE",
    .build_cov_term(plan$covariance)
  )
  stats::as.formula(paste("RESP ~", paste(rhs, collapse = " + ")))
}

.fit_one_imp <- function(dat_imp, spec, plan, strata_present) {

  form <- .build_mmrm_formula(strata_present, plan)

  fit <- mmrm::mmrm(
    formula = form,
    data    = dat_imp,
    reml    = TRUE,
    control = mmrm::mmrm_control(method = "Kenward-Roger")
  )

  emm <- emmeans::emmeans(fit, specs = ~ TRT | VISIT)

  lsm <- as.data.frame(summary(emm, infer = TRUE, level = 0.95)) |>
    dplyr::transmute(
      VISIT    = as.character(VISIT),
      TRT      = as.character(TRT),
      estimate = emmean,
      SE       = SE,
      lower    = lower.CL,
      upper    = upper.CL
    )

  ref_idx  <- which(levels(dat_imp$TRT) == spec$control_label)
  diff_raw <- emmeans::contrast(emm, method = "trt.vs.ctrl", ref = ref_idx)

  diff <- as.data.frame(summary(diff_raw, infer = TRUE, level = 0.95)) |>
    dplyr::transmute(
      VISIT       = as.character(VISIT),
      comparison  = spec$comparison_label,
      estimate    = estimate,
      SE          = SE,
      lower       = lower.CL,
      upper       = upper.CL,
      p_two_sided = p.value
    )

  list(lsm = lsm, diff = diff)
}


# =============================================================================
# SECTION 6: FITTING LOOP + RUBIN'S RULES
# =============================================================================

fit_mmrm_models <- function(prep, spec, method_spec) {

  imputations    <- split(prep$ana, prep$ana$IMPNUM)
  strata_present <- prep$strata_present

  results <- purrr::imap(imputations, function(dat_imp, imp_id) {
    res <- NULL; used_plan <- NULL

    for (plan in method_spec$fallback) {
      try_res <- tryCatch(
        .fit_one_imp(dat_imp, spec, plan, strata_present),
        error = function(e) NULL
      )
      if (!is.null(try_res)) { res <- try_res; used_plan <- plan; break }
    }

    if (is.null(res))
      stop("[", spec$output_id, "] All fallback plans failed for IMPNUM = ", imp_id)

    list(
      lsm  = dplyr::mutate(res$lsm,  IMPNUM = as.integer(imp_id)),
      diff = dplyr::mutate(res$diff, IMPNUM = as.integer(imp_id)),
      plan = tibble::tibble(
        IMPNUM         = as.integer(imp_id),
        covariance     = used_plan$covariance,
        use_strata     = used_plan$use_strata,
        use_visit_base = used_plan$use_visit_base
      )
    )
  })

  list(
    lsm_all  = dplyr::bind_rows(purrr::map(results, "lsm")),
    diff_all = dplyr::bind_rows(purrr::map(results, "diff")),
    fit_plan = dplyr::bind_rows(purrr::map(results, "plan"))
  )
}


#' Rubin's rules — mirrors SAS PROC MIANALYZE ParameterEstimates output
#'
#' Results should match SAS to within floating-point rounding (~1e-6).
rubin_combine <- function(df,
                          by_cols,
                          est_col    = "estimate",
                          se_col     = "SE",
                          conf_level = 0.95) {
  alpha <- 1 - conf_level

  df |>
    dplyr::group_by(dplyr::across(dplyr::all_of(by_cols))) |>
    dplyr::summarise(
      m    = dplyr::n(),
      qbar = mean(.data[[est_col]], na.rm = TRUE),
      ubar = mean(.data[[se_col]]^2, na.rm = TRUE),
      b    = { vv <- stats::var(.data[[est_col]], na.rm = TRUE)
               if (is.na(vv)) 0 else vv },
      .groups = "drop"
    ) |>
    dplyr::mutate(
      tvar        = ubar + (1 + 1 / pmax(m, 1)) * b,
      SE          = sqrt(tvar),
      df_mi       = dplyr::case_when(
                      m <= 1 | b <= 0 ~ 1e6,
                      TRUE ~ (m - 1) * (1 + ubar / ((1 + 1/m) * b))^2),
      crit        = stats::qt(1 - alpha / 2, df = df_mi),
      lower       = qbar - crit * SE,
      upper       = qbar + crit * SE,
      t_stat      = qbar / SE,
      p_two_sided = 2 * (1 - stats::pt(abs(t_stat), df = df_mi))
    ) |>
    dplyr::rename(estimate = qbar) |>
    dplyr::select(dplyr::all_of(by_cols), estimate, SE, lower, upper, p_two_sided)
}


# =============================================================================
# SECTION 7: ARD ASSEMBLY
# =============================================================================

format_ci <- function(est, lcl, ucl, digits = 3) {
  fmt <- paste0("%.", digits, "f")
  sprintf(paste0(fmt, " (", fmt, ", ", fmt, ")"), est, lcl, ucl)
}

format_p <- function(p, digits = 4) {
  dplyr::case_when(
    is.na(p)    ~ NA_character_,
    p <= 0.0001 ~ "<0.0001",
    p >= 0.9999 ~ ">0.9999",
    TRUE        ~ sprintf(paste0("%.", digits, "f"), round(p, digits))
  )
}

build_mmrm_ard <- function(prep, lsm_comb, diff_comb, spec) {

  d_est <- spec$digits$est
  d_p   <- spec$digits$p
  vd    <- spec$visits_display

  lsm_disp  <- lsm_comb  |> dplyr::filter(VISIT %in% vd)
  diff_disp <- diff_comb |> dplyr::filter(VISIT %in% vd)

  ard_bigN <- prep$subj_n |>
    dplyr::transmute(
      output_id = spec$output_id, method_id = spec$method_id,
      row_type = "arm",
      group1 = "VISIT",       group1_level = NA_character_,
      group2 = "TRT",         group2_level = as.character(TRT),
      stat_name = "bigN",     stat_label = "N",
      stat_num = bigN,        stat_chr = as.character(bigN),
      ord1 = 0L,              ord2 = as.integer(TRTN)
    )

  ard_nobs <- prep$obs_n |>
    dplyr::transmute(
      output_id = spec$output_id, method_id = spec$method_id,
      row_type = "arm",
      group1 = "VISIT",       group1_level = as.character(VISIT),
      group2 = "TRT",         group2_level = as.character(TRT),
      stat_name = "nobs",     stat_label = "n",
      stat_num = nobs,        stat_chr = as.character(nobs),
      ord1 = match(as.character(VISIT), vd),
      ord2 = as.integer(TRTN)
    )

  ard_lsm <- lsm_disp |>
    dplyr::left_join(prep$subj_n |> dplyr::select(TRT, TRTN), by = "TRT") |>
    dplyr::transmute(
      output_id = spec$output_id, method_id = spec$method_id,
      row_type = "arm",
      group1 = "VISIT",       group1_level = VISIT,
      group2 = "TRT",         group2_level = as.character(TRT),
      stat_name = "adj_mean_ci",
      stat_label = "Adjusted mean (95% CI)",
      stat_num = estimate,
      stat_chr = format_ci(estimate, lower, upper, d_est),
      ord1 = match(VISIT, vd),
      ord2 = as.integer(TRTN)
    )

  ard_diff_ci <- diff_disp |>
    dplyr::transmute(
      output_id = spec$output_id, method_id = spec$method_id,
      row_type = "comparison",
      group1 = "VISIT",       group1_level = VISIT,
      group2 = "COMPARISON",  group2_level = comparison,
      stat_name = "adj_diff_ci",
      stat_label = "Adjusted mean difference (95% CI)",
      stat_num = estimate,
      stat_chr = format_ci(estimate, lower, upper, d_est),
      ord1 = match(VISIT, vd),
      ord2 = 99L
    )

  # Mirrors SAS: if estimate > 0 then probt = probt_/2; else 1 - probt_/2
  # Blanked for non-primary visits (mirrors: if avisitn ne 206 then call missing(pval))
  ard_pval <- diff_disp |>
    dplyr::mutate(
      p_one = dplyr::case_when(
        estimate > 0 ~ p_two_sided / 2,
        estimate < 0 ~ 1 - p_two_sided / 2,
        TRUE         ~ 0.5
      ),
      p_one = ifelse(VISIT %in% spec$pvalue_display_visits, p_one, NA_real_)
    ) |>
    dplyr::transmute(
      output_id = spec$output_id, method_id = spec$method_id,
      row_type = "comparison",
      group1 = "VISIT",       group1_level = VISIT,
      group2 = "COMPARISON",  group2_level = comparison,
      stat_name = "pvalue_1sided",
      stat_label = "1-sided p-value",
      stat_num = p_one,
      stat_chr = format_p(p_one, d_p),
      ord1 = match(VISIT, vd),
      ord2 = 100L
    )

  dplyr::bind_rows(ard_bigN, ard_nobs, ard_lsm, ard_diff_ci, ard_pval) |>
    dplyr::arrange(ord1, ord2, stat_name)
}


# =============================================================================
# SECTION 8: MAIN FUNCTION
# =============================================================================

#' Run MMRM and produce compact ARD
#'
#' @param data        data.frame — Analysis ADaM (e.g. read via haven::read_sas)
#' @param spec        list       — Output spec (e.g. spec_facit_14_2_4_1)
#' @param method_spec list       — Method spec (default: method_spec_mmrm_by_visit)
#' @param debug       logical    — TRUE includes ana + fit_plan in return
#'
#' @return list: $ard, $subj_n, $obs_n, $lsm, $diff, $meta,
#'               $ana (debug), $fit_plan (debug)
#' @export
run_mmrm_ard <- function(data,
                         spec,
                         method_spec = method_spec_mmrm_by_visit,
                         debug       = FALSE) {

  validate_mmrm_spec(spec)

  if (spec$method_id != method_spec$method_id)
    stop("[", spec$output_id, "] spec$method_id '", spec$method_id,
         "' != method_spec$method_id '", method_spec$method_id, "'")

  message("[", spec$output_id, "] Step 1/4: Preparing datasets...")
  prep  <- prepare_mmrm_datasets(data, spec)
  n_imp <- max(prep$ana$IMPNUM, na.rm = TRUE)

  message("[", spec$output_id, "] Step 2/4: Fitting MMRM across ",
          n_imp, " imputation(s) with fallback...")
  fits <- fit_mmrm_models(prep, spec, method_spec)

  message("[", spec$output_id, "] Step 3/4: Rubin's rules...")
  lsm_comb <- rubin_combine(fits$lsm_all, by_cols = c("VISIT", "TRT")) |>
    dplyr::mutate(TRT = factor(TRT, levels = spec$treatment_levels)) |>
    dplyr::arrange(match(VISIT, spec$visits_model), TRT)

  diff_comb <- rubin_combine(
    fits$diff_all |> dplyr::select(-p_two_sided),
    by_cols = c("VISIT", "comparison")
  ) |>
    dplyr::arrange(match(VISIT, spec$visits_model))

  message("[", spec$output_id, "] Step 4/4: Building ARD...")
  ard <- build_mmrm_ard(prep, lsm_comb, diff_comb, spec)

  out <- list(
    ard    = ard,
    subj_n = prep$subj_n,
    obs_n  = prep$obs_n,
    lsm    = lsm_comb,
    diff   = diff_comb,
    meta   = c(prep$meta, list(n_imp     = n_imp,
                               n_records = nrow(prep$ana),
                               run_time  = Sys.time()))
  )
  if (debug) { out$ana <- prep$ana; out$fit_plan <- fits$fit_plan }

  message("[", spec$output_id, "] Done.")
  out
}
