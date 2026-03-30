# =============================================================================
# FILE        : create_ard_mmrm.R
# DESCRIPTION : General MMRM ARD engine — cross-study, registry-driven
#
# GENERALITY DESIGN
# ─────────────────
# Like SAF create_ard_freq() / create_ard_summary():
#   - Function logic is fixed and study-agnostic
#   - All study-specific information lives in the registry CSV
#   - Switching studies = providing a different registry file
#   - No hardcoded variable names, filter values, or study identifiers
#
# TWO-REGISTRY ARCHITECTURE
# ─────────────────────────
#   mmrm_method_registry.csv  — family-level defaults, one row per family
#   eff_mmrm_registry.csv     — output-level params, one row per output
#
# FOUR METHOD FAMILIES
# ────────────────────
#   MMRM_CFB_MI_VISIT       Family A  CFB + MI + by-visit + identity scale
#   MMRM_CFB_OBS_VISIT      Family B  CFB + observed + dummy visit grid
#   MMRM_LOGRATIO_MI_VISIT  Family C  Log-ratio + MI + back-transform
#   MMRM_TP_MI_VISIT        Family D  Tipping-point wrapper
#
# WHAT create_ard_mmrm() RETURNS
# ───────────────────────────────
# $ard        compact ARD tibble — one row per statistic — the main deliverable
# $subj_n     bigN by treatment (for table column headers downstream)
# $obs_n      nobs by visit × treatment
# $lsm        Rubin-combined LSM (Families A/C) or single-fit LSM (Family B)
# $diff       Rubin-combined differences
# $meta       run metadata (dataset, method, timing, n_imp, ...)
# $ana        (debug=TRUE only) model-ready dataset
# $fit_plan   (debug=TRUE only) which fallback each imputation used
#
# SWITCHING STUDIES
# ─────────────────
# 1. Create new eff_mmrm_registry.csv for the new study
# 2. source("create_ard_mmrm.R")  — unchanged
# 3. out_reg <- load_mmrm_registry("path/to/new/eff_mmrm_registry.csv")
# 4. create_ard_mmrm("output_id", data = ..., out_registry = out_reg)
#
# PIPE: |> (base R >= 4.1). No { d <- . } dot-placeholder patterns.
# PACKAGES: dplyr, purrr, tibble, stringr, readr, mmrm, emmeans, tools
# =============================================================================

library(dplyr)
library(purrr)
library(tibble)
library(stringr)
library(tidyr)


# =============================================================================
# SECTION 1: SHARED FALLBACK SEQUENCE
# All families use the same SAP Appendix non-convergence fallback order
# =============================================================================

.FALLBACK_PLANS <- list(
  list(covariance = "us",  use_strata = TRUE,  use_visit_base = TRUE),
  list(covariance = "ar1", use_strata = TRUE,  use_visit_base = TRUE),
  list(covariance = "ar1", use_strata = FALSE, use_visit_base = TRUE),
  list(covariance = "ar1", use_strata = FALSE, use_visit_base = FALSE),
  list(covariance = "cs",  use_strata = FALSE, use_visit_base = FALSE)
)


# =============================================================================
# SECTION 2: UTILITY HELPERS
# =============================================================================

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !all(is.na(a))) a else b

.split_pipe <- function(x) {
  x <- x %||% ""
  if (length(x) == 0 || is.na(x) || x == "") return(character(0))
  stringr::str_split_1(as.character(x[[1]]), "\\|")
}

.as_logical_safe <- function(x, default = TRUE) {
  if (is.null(x) || is.na(x) || x == "") return(default)
  v <- suppressWarnings(as.logical(x))
  if (is.na(v)) default else v
}

.as_integer_safe <- function(x) {
  if (is.null(x) || is.na(x) || x == "") return(NA_integer_)
  suppressWarnings(as.integer(x))
}

.as_numeric_safe <- function(x) {
  if (is.null(x) || is.na(x) || x == "") return(NA_real_)
  suppressWarnings(as.numeric(x))
}

.read_registry <- function(path) {
  ext <- tools::file_ext(path)
  if (ext %in% c("xlsx", "xls")) {
    if (!requireNamespace("readxl", quietly = TRUE))
      stop("readxl needed for .xlsx. install.packages('readxl')")
    readxl::read_excel(path, na = c("", "NA"))
  } else {
    readr::read_csv(path, show_col_types = FALSE, na = c("", "NA"))
  }
}


# =============================================================================
# SECTION 3: REGISTRY READERS
# =============================================================================

#' Load method registry (family-level defaults)
#'
#' One row per method family. Provides defaults that eff_mmrm_registry can
#' override on a per-output basis.
#'
#' @param path path to mmrm_method_registry.csv or .xlsx
#' @export
load_method_registry <- function(path) {
  reg <- .read_registry(path)
  required <- c("method_id", "runner_fun", "prep_fun", "result_profile",
                "mi_enabled", "has_pvalue", "pvalue_rule_default",
                "transform_profile")
  miss <- setdiff(required, names(reg))
  if (length(miss) > 0)
    stop("Method registry missing columns: ", paste(miss, collapse = ", "))
  message("Method registry: ", nrow(reg), " families: ",
          paste(reg$method_id, collapse = ", "))
  reg
}


#' Load output registry (one row per deliverable output)
#'
#' Required columns are checked. Optional columns are created with NA if absent,
#' ensuring backward compatibility when new columns are added.
#'
#' @param path path to eff_mmrm_registry.csv or .xlsx
#' @export
load_mmrm_registry <- function(path) {
  reg <- .read_registry(path)

  required_cols <- c(
    "output_id", "idkey", "dataset_name", "method_id",
    "population_var", "population_value",
    "trt_var", "trtn_var", "visit_var", "visitn_var",
    "response_var", "baseline_var",
    "treatment_levels", "control_label", "comparison_label",
    "visits_model"
  )
  miss <- setdiff(required_cols, names(reg))
  if (length(miss) > 0)
    stop("Output registry missing required columns: ", paste(miss, collapse = ", "))

  # Ensure all optional columns exist (adds NA column if absent)
  # This allows old registries to work with new code
  optional_cols <- c(
    "pop_var2", "pop_val2",
    "category_var", "category_value",
    "paramcd_filter", "paramcd_filter_var",
    "imputation_var", "dtype_var", "strata_vars",
    "param_var", "param_values",
    "visits_display", "visit_exclude",
    "avisitn_var", "avisitn_gt", "avisitn_le",
    "pvalue_display_visits", "include_pvalue", "pvalue_rule",
    "result_profile", "transform_profile",
    "n_obs_dtype_values",
    "imp_max", "digits_est", "digits_p", "digits_pct",
    "tp_penalty_values", "tp_primary_visit", "tp_penalty_arm",
    "tp_penalty_mode", "tp_penalty_filter_dtype",
    "tp_penalty_filter_impreas", "tp_penalty_filter_fichypo",
    "tp_penalty_fichypo_var",
    "dummy_visit_var", "dummy_visitn_var", "dummy_visits"
  )
  for (col in optional_cols)
    if (!col %in% names(reg)) reg[[col]] <- NA_character_

  dup <- reg$output_id[duplicated(reg$output_id)]
  if (length(dup) > 0)
    stop("Duplicate output_id in registry: ", paste(dup, collapse = ", "))

  n_by_method <- table(reg$method_id)
  message("Output registry: ", nrow(reg), " outputs | ",
          paste(n_by_method, names(n_by_method), sep = " x ", collapse = " | "))
  reg
}


# =============================================================================
# SECTION 4: SPEC RESOLUTION
# =============================================================================

#' Build complete spec from one output registry row + optional method row
#'
#' All study-specific information is read from registry fields.
#' No hardcoded variable names or filter values.
.row_to_spec <- function(out_row, meth_row = NULL) {

  # Method-level defaults (can be overridden by output registry)
  meth_defaults <- list(
    result_profile    = meth_row$result_profile    %||% "RESULT_CFB_IDENTITY",
    transform_profile = meth_row$transform_profile %||% "identity",
    pvalue_rule       = meth_row$pvalue_rule_default %||% "better_positive",
    mi_enabled        = .as_logical_safe(meth_row$mi_enabled %||% TRUE),
    has_pvalue        = .as_logical_safe(meth_row$has_pvalue %||% TRUE)
  )

  # Output-level values (override method defaults when present)
  result_profile    <- out_row$result_profile    %||% meth_defaults$result_profile
  transform_profile <- out_row$transform_profile %||% meth_defaults$transform_profile
  pvalue_rule       <- out_row$pvalue_rule       %||% meth_defaults$pvalue_rule
  include_pvalue    <- .as_logical_safe(out_row$include_pvalue %||%
                                          meth_defaults$has_pvalue)

  # n_obs dtype filter: from registry; default c("","TP") if not specified
  n_obs_dtype <- .split_pipe(out_row$n_obs_dtype_values %||% "")
  if (length(n_obs_dtype) == 0) n_obs_dtype <- c("", "TP")

  list(
    # Identity
    output_id        = out_row$output_id,
    method_id        = out_row$method_id %||% "MMRM_CFB_MI_VISIT",
    idkey            = as.character(out_row$idkey %||% ""),
    dataset_name     = out_row$dataset_name,

    # Population filters (supports dual population filter)
    population_var   = out_row$population_var,
    population_value = out_row$population_value,
    pop_var2         = out_row$pop_var2 %||% NA_character_,
    pop_val2         = out_row$pop_val2 %||% NA_character_,

    # Category filter (optional)
    category_var     = out_row$category_var   %||% NA_character_,
    category_value   = out_row$category_value %||% NA_character_,

    # Paramcd filter (optional — for urine outputs and multi-param)
    paramcd_filter_var = out_row$paramcd_filter_var %||% "PARAMCD",
    paramcd_filter     = out_row$paramcd_filter     %||% NA_character_,

    # AVISITN numeric range filter (optional — for urine: 101<avisitn<=211)
    avisitn_var = out_row$avisitn_var %||% "AVISITN",
    avisitn_gt  = .as_numeric_safe(out_row$avisitn_gt),
    avisitn_le  = .as_numeric_safe(out_row$avisitn_le),

    # Variable mapping (all names come from registry)
    vars = list(
      subject_id  = "USUBJID",
      subject_var = "SUBJID",
      trt         = out_row$trt_var,
      trtn        = out_row$trtn_var,
      visit       = out_row$visit_var,
      visitn      = out_row$visitn_var,
      response    = out_row$response_var,
      baseline    = out_row$baseline_var,
      imputation  = out_row$imputation_var %||% NA_character_,
      dtype       = out_row$dtype_var      %||% NA_character_,
      strata      = .split_pipe(out_row$strata_vars %||% "STRVAL1|STRVAL2|STRVAL3"),
      param       = out_row$param_var %||% NA_character_
    ),

    # Treatment
    treatment_levels = .split_pipe(out_row$treatment_levels),
    control_label    = out_row$control_label,
    comparison_label = out_row$comparison_label,

    # Multi-param (Family B EORTC: loop over param_values)
    param_values = .split_pipe(out_row$param_values %||% ""),

    # Visit specification
    visits_model  = .split_pipe(out_row$visits_model),
    visits_display = {
      vd <- .split_pipe(out_row$visits_display %||% "")
      if (length(vd) == 0) .split_pipe(out_row$visits_model) else vd
    },
    visit_exclude  = .split_pipe(out_row$visit_exclude %||% ""),

    # P-value control
    pvalue_display_visits = .split_pipe(out_row$pvalue_display_visits %||% ""),
    include_pvalue        = include_pvalue,
    pvalue_rule           = pvalue_rule,

    # Result and transform profiles
    result_profile    = result_profile,
    transform_profile = transform_profile,

    # MI
    mi_enabled = meth_defaults$mi_enabled,

    # n_obs filter (from registry, not hardcoded)
    n_obs_dtype_values = n_obs_dtype,

    # Runtime
    imp_max    = .as_integer_safe(out_row$imp_max),
    digits = list(
      est = as.integer(.as_numeric_safe(out_row$digits_est) %||% 3),
      p   = as.integer(.as_numeric_safe(out_row$digits_p)   %||% 4),
      pct = as.integer(.as_numeric_safe(out_row$digits_pct) %||% 1)
    ),

    idkey = as.character(out_row$idkey %||% ""),

    # Family B: dummy visit grid
    dummy_visit_var  = out_row$dummy_visit_var  %||% NA_character_,
    dummy_visitn_var = out_row$dummy_visitn_var %||% NA_character_,
    dummy_visits     = .split_pipe(out_row$dummy_visits %||% ""),

    # Family D: tipping point
    # All names and values come from registry — no hardcoding
    tp_penalty_values      = as.numeric(.split_pipe(out_row$tp_penalty_values %||% "")),
    tp_primary_visit       = out_row$tp_primary_visit %||% NA_character_,
    tp_penalty_arm         = out_row$tp_penalty_arm   %||% NA_character_,
    tp_penalty_mode        = out_row$tp_penalty_mode  %||% "multiply",
    tp_penalty_filter_dtype   = out_row$tp_penalty_filter_dtype   %||% NA_character_,
    tp_penalty_filter_impreas = out_row$tp_penalty_filter_impreas %||% NA_character_,
    # fichypo: multi-value filter, pipe-separated in registry
    tp_penalty_fichypo_var    = out_row$tp_penalty_fichypo_var    %||% "FICHYPO",
    tp_penalty_filter_fichypo = .split_pipe(out_row$tp_penalty_filter_fichypo %||% ""),
    # significance threshold
    tp_significance = .as_numeric_safe(out_row$tp_significance %||% 0.025)
  )
}


#' Resolve spec from registries using output_id or idkey
#' @export
resolve_mmrm_spec <- function(output_id     = NULL,
                               idkey         = NULL,
                               out_registry,
                               meth_registry = NULL) {
  if (is.null(output_id) && is.null(idkey))
    stop("Provide output_id or idkey.")

  if (!is.null(output_id)) {
    hits <- dplyr::filter(out_registry, .data$output_id == .env$output_id)
    key  <- output_id
  } else {
    hits <- dplyr::filter(out_registry, .data$idkey == .env$idkey)
    key  <- idkey
  }
  if (nrow(hits) == 0)
    stop("No registry entry for '", key, "'\n  Available: ",
         paste(out_registry$output_id, collapse = ", "))

  out_row  <- as.list(hits[1, ])
  meth_row <- if (!is.null(meth_registry)) {
    mr <- dplyr::filter(meth_registry, method_id == out_row$method_id)
    if (nrow(mr) > 0) as.list(mr[1, ]) else NULL
  } else NULL

  .row_to_spec(out_row, meth_row)
}


# =============================================================================
# SECTION 5: VALIDATION
# =============================================================================

validate_mmrm_spec <- function(spec) {
  req <- c("output_id", "method_id", "dataset_name",
           "population_var", "population_value",
           "vars", "treatment_levels", "control_label",
           "visits_model", "digits")
  miss <- setdiff(req, names(spec))
  if (length(miss) > 0)
    stop("[", spec$output_id, "] Missing spec fields: ", paste(miss, collapse = ", "))

  req_vars <- c("subject_id", "subject_var", "trt", "trtn",
                "visit", "visitn", "response", "baseline")
  miss_v <- setdiff(req_vars, names(spec$vars))
  if (length(miss_v) > 0)
    stop("[", spec$output_id, "] Missing vars: ", paste(miss_v, collapse = ", "))

  if (length(spec$treatment_levels) < 2)
    stop("[", spec$output_id, "] treatment_levels needs >= 2 values")
  if (!(spec$control_label %in% spec$treatment_levels))
    stop("[", spec$output_id, "] control_label '", spec$control_label,
         "' not in: ", paste(spec$treatment_levels, collapse = ", "))

  # Family A / C: need imputation_var
  if (spec$method_id %in% c("MMRM_CFB_MI_VISIT", "MMRM_LOGRATIO_MI_VISIT") &&
      (is.null(spec$vars$imputation) || is.na(spec$vars$imputation)))
    stop("[", spec$output_id, "] imputation_var required for MI families")

  # Family D: TP fields
  if (spec$method_id == "MMRM_TP_MI_VISIT") {
    if (length(spec$tp_penalty_values) == 0 || any(is.na(spec$tp_penalty_values)))
      stop("[", spec$output_id, "] tp_penalty_values required")
    if (is.na(spec$tp_primary_visit))
      stop("[", spec$output_id, "] tp_primary_visit required")
    if (is.na(spec$tp_penalty_arm) || !(spec$tp_penalty_arm %in% spec$treatment_levels))
      stop("[", spec$output_id, "] tp_penalty_arm must be in treatment_levels")
  }

  invisible(spec)
}


# =============================================================================
# SECTION 6: DATA PREPARATION — SHARED BASE
# =============================================================================

#' Apply all registry-driven filters to data
#'
#' Handles: population, optional second population, optional category,
#' optional paramcd filter, optional avisitn range, visit name filters.
#' All filter column names come from spec (registry), never hardcoded.
.prep_base <- function(data, spec) {
  v          <- spec$vars
  strata_src <- v$strata %||% character(0)

  needed <- unique(c(
    spec$population_var,
    if (!is.null(spec$pop_var2) && !is.na(spec$pop_var2)) spec$pop_var2,
    if (!is.null(spec$category_var) && !is.na(spec$category_var)) spec$category_var,
    spec$paramcd_filter_var,
    spec$avisitn_var,
    v$subject_id, v$subject_var, v$trt, v$trtn,
    v$visit, v$visitn, v$response, v$baseline,
    if (!is.null(v$imputation) && !is.na(v$imputation)) v$imputation,
    strata_src,
    if (!is.null(v$dtype) && !is.na(v$dtype)) v$dtype,
    if (!is.null(v$param) && !is.na(v$param)) v$param,
    # TP: need impreas and fichypo for penalty filter (if present in data)
    if (!is.null(spec$tp_penalty_filter_impreas) &&
        !is.na(spec$tp_penalty_filter_impreas)) "IMPREAS",
    if (!is.null(spec$tp_penalty_fichypo_var) &&
        !is.na(spec$tp_penalty_fichypo_var))
      spec$tp_penalty_fichypo_var
  ))
  needed <- intersect(needed, names(data))

  ana <- data |>
    dplyr::select(dplyr::any_of(needed)) |>
    dplyr::distinct()

  # --- Filter 1: primary population ---
  ana <- ana |>
    dplyr::filter(.data[[spec$population_var]] == spec$population_value)

  # --- Filter 2: optional second population (e.g. MAINPFL=Y for EQ VAS) ---
  if (!is.null(spec$pop_var2) && !is.na(spec$pop_var2) &&
      spec$pop_var2 %in% names(ana)) {
    ana <- ana |>
      dplyr::filter(.data[[spec$pop_var2]] == spec$pop_val2)
  }

  # --- Filter 3: optional category (ACAT1) ---
  if (!is.null(spec$category_var) && !is.na(spec$category_var) &&
      spec$category_var %in% names(ana) &&
      !is.null(spec$category_value) && !is.na(spec$category_value)) {
    ana <- ana |>
      dplyr::filter(.data[[spec$category_var]] == spec$category_value)
  }

  # --- Filter 4: optional paramcd filter (urine: paramcd='LGUTOTPR') ---
  if (!is.null(spec$paramcd_filter) && !is.na(spec$paramcd_filter) &&
      spec$paramcd_filter_var %in% names(ana)) {
    pf <- .split_pipe(spec$paramcd_filter)
    if (length(pf) > 0)
      ana <- ana |>
        dplyr::filter(.data[[spec$paramcd_filter_var]] %in% pf)
  }

  # --- Filter 5: optional avisitn range (urine: 101 < AVISITN <= 211) ---
  avisit_n_col <- spec$avisitn_var %||% "AVISITN"
  if (avisit_n_col %in% names(ana)) {
    if (!is.null(spec$avisitn_gt) && !is.na(spec$avisitn_gt)) {
      gt <- spec$avisitn_gt
      ana <- ana |> dplyr::filter(.data[[avisit_n_col]] > gt)
    }
    if (!is.null(spec$avisitn_le) && !is.na(spec$avisitn_le)) {
      le <- spec$avisitn_le
      ana <- ana |> dplyr::filter(.data[[avisit_n_col]] <= le)
    }
  }

  if (nrow(ana) == 0)
    stop("[", spec$output_id, "] 0 rows after filtering.\n",
         "  Check population_var/value, category_var/value, paramcd_filter, ",
         "avisitn range, visit names.\n",
         "  Debug: distinct(data, AVISIT, AVISITN); distinct(data, ACAT1)")

  # --- Rename to canonical internal names ---
  src <- c(v$subject_id, v$subject_var, v$trt, v$trtn,
           v$visit, v$visitn, v$response, v$baseline)
  can <- c("USUBJID", "SUBJID", "TRT", "TRTN", "VISIT", "VISITN", "RESP", "BASE")
  rmap <- stats::setNames(src, can)
  rmap <- rmap[rmap %in% names(ana)]
  ana  <- dplyr::rename(ana, dplyr::any_of(rmap))

  # Rename optional columns
  if (!is.null(v$imputation) && !is.na(v$imputation) && v$imputation %in% names(ana))
    names(ana)[names(ana) == v$imputation] <- "IMPNUM"
  if (!is.null(v$dtype) && !is.na(v$dtype) && v$dtype %in% names(ana))
    names(ana)[names(ana) == v$dtype] <- "DTYPE"
  else if (!"DTYPE" %in% names(ana))
    ana$DTYPE <- NA_character_
  if (!is.null(v$param) && !is.na(v$param) && v$param %in% names(ana))
    names(ana)[names(ana) == v$param] <- "PARAM"

  # Rename strata
  for (i in seq_along(strata_src)) {
    old <- strata_src[i]; new <- paste0("STRATA", i)
    if (old %in% names(ana)) names(ana)[names(ana) == old] <- new
  }
  # Ensure STRATA1-3 exist (fill NA if fewer strata in this study)
  for (i in 1:3) {
    nm <- paste0("STRATA", i)
    if (!nm %in% names(ana)) ana[[nm]] <- NA_character_
  }

  ana
}


#' Compute subj_n (bigN), obs_n (nobs), and active strata from prepped ana
.compute_support_stats <- function(ana, spec) {

  # Active strata: only strata with non-missing values in this dataset
  strata_present <- paste0("STRATA", 1:3)[
    vapply(paste0("STRATA", 1:3),
           function(x) x %in% names(ana) && any(!is.na(ana[[x]])),
           logical(1))
  ]

  covar_cols <- c("BASE", strata_present)
  subj_n <- ana |>
    dplyr::distinct(USUBJID, TRT, TRTN,
                    dplyr::across(dplyr::all_of(covar_cols))) |>
    dplyr::filter(dplyr::if_all(dplyr::all_of(covar_cols), ~ !is.na(.x))) |>
    dplyr::count(TRT, TRTN, name = "bigN") |>
    dplyr::arrange(TRTN)

  # nobs: from registry n_obs_dtype_values (not hardcoded)
  dtype_ok  <- spec$n_obs_dtype_values
  disp_vis  <- spec$visits_display %||% spec$visits_model

  obs_n_pre <- ana |>
    dplyr::filter(VISIT %in% disp_vis, !is.na(RESP))

  # Apply dtype filter only if DTYPE column has non-NA values
  if (!all(is.na(obs_n_pre$DTYPE)) && length(dtype_ok) > 0)
    obs_n_pre <- dplyr::filter(obs_n_pre,
                               is.na(DTYPE) | DTYPE %in% dtype_ok)

  obs_n <- obs_n_pre |>
    dplyr::distinct(USUBJID, VISIT, VISITN, TRT, TRTN) |>
    dplyr::count(VISIT, VISITN, TRT, TRTN, name = "nobs") |>
    dplyr::arrange(match(as.character(VISIT), disp_vis), TRTN)

  list(subj_n = subj_n, obs_n = obs_n, strata_present = strata_present)
}


# =============================================================================
# SECTION 7: DATA PREP — FAMILY A/C (MI)
# =============================================================================

prep_mi_visit <- function(data, spec) {
  ana <- .prep_base(data, spec)

  if (!"IMPNUM" %in% names(ana))
    stop("[", spec$output_id, "] IMPNUM not found. Check imputation_var in registry.")

  # imp_max: from registry (supports testing with fewer imputations)
  if (!is.na(spec$imp_max)) {
    ana <- ana |> dplyr::filter(IMPNUM <= spec$imp_max)
    message("[", spec$output_id, "] imp_max=", spec$imp_max,
            " (using imputations 1-", spec$imp_max, ")")
  }

  # Visit filters
  if (length(spec$visit_exclude) > 0)
    ana <- ana |> dplyr::filter(!VISIT %in% spec$visit_exclude)
  if (length(spec$visits_model) > 0)
    ana <- ana |> dplyr::filter(VISIT %in% spec$visits_model)

  # FIX (Family C): when visits_model is empty (urine uses avisitn_gt range not
  # named visits), derive ordered factor levels from actual data.
  # Without this, factor(VISIT, levels=character(0)) makes all VISIT values NA.
  visit_levels <- if (length(spec$visits_model) > 0) {
    spec$visits_model
  } else {
    ana |>
      dplyr::distinct(VISIT, VISITN) |>
      dplyr::arrange(VISITN) |>
      dplyr::pull(VISIT) |>
      as.character()
  }
  if (length(spec$visits_display) == 0)
    spec$visits_display <- visit_levels

  ana <- ana |>
    dplyr::mutate(TRT    = factor(TRT,   levels = spec$treatment_levels),
                  VISIT  = factor(VISIT, levels = visit_levels),
                  IMPNUM = as.integer(IMPNUM)) |>
    dplyr::arrange(IMPNUM, VISITN, TRTN, USUBJID)

  sup <- .compute_support_stats(ana, spec)
  c(list(ana = ana), sup,
    list(meta = list(output_id    = spec$output_id,
                     method_id    = spec$method_id,
                     dataset_name = spec$dataset_name,
                     idkey        = spec$idkey)))
}


# =============================================================================
# SECTION 8: DATA PREP — FAMILY B (Observed + dummy visit grid)
# =============================================================================

#' Build dummy scheduled visit grid and left-join observed values
#' Mirrors SAS: create dummy grid of all subjects x scheduled visits,
#' then merge observed post-baseline records.
prep_obs_dummy_visit <- function(data, spec) {
  # FIX (Family B): we need two separate views of the data.
  # (1) base_raw: no visits_model filter — needed so Baseline visit is available
  #     for building the subject list (SAS: ana1_a where avisit="Baseline")
  # (2) ana_raw: visits_model filter applied for obs_records
  #
  # If we ran .prep_base() with visits_model, "Baseline" would be excluded
  # (it's not in Month3-24), so base_records would be empty.
  # Solution: temporarily clear visits_model for the baseline subject extraction.

  spec_no_vm <- spec
  spec_no_vm$visits_model  <- character(0)  # skip visit name filter
  spec_no_vm$visits_display <- character(0)
  spec_no_vm$visit_exclude  <- character(0)  # keep all visits including Baseline

  base_raw <- .prep_base(data, spec_no_vm)

  # Baseline records: subjects at Baseline with non-missing BASE
  # Mirrors SAS: where avisit="Baseline" and base ne .
  visit_var_raw <- spec$vars$visit %||% "AVISIT"
  baseline_labels <- c("Baseline", "BASELINE", "baseline")

  base_records <- base_raw |>
    dplyr::filter(!is.na(BASE),
                  VISIT %in% baseline_labels |
                  (!is.na(VISITN) & VISITN == min(VISITN[VISIT %in% baseline_labels],
                                                   na.rm = TRUE))) |>
    dplyr::distinct(USUBJID, SUBJID, TRT, TRTN, BASE,
                    dplyr::across(dplyr::starts_with("STRATA")))

  # Fallback: if no "Baseline" label found, use subjects with any non-missing BASE
  if (nrow(base_records) == 0) {
    message("[", spec$output_id, "] No 'Baseline' visit found; ",
            "using all subjects with non-missing BASE.")
    base_records <- base_raw |>
      dplyr::filter(!is.na(BASE)) |>
      dplyr::distinct(USUBJID, SUBJID, TRT, TRTN, BASE,
                      dplyr::across(dplyr::starts_with("STRATA")))
  }

  if (nrow(base_records) == 0)
    stop("[", spec$output_id, "] No subjects with non-missing BASE found.")

  # Post-baseline observed records — from full data (no visits_model restriction)
  # to ensure all observed visits are available for merging into dummy grid.
  # NOTE: VISITN excluded — visit_grid carries it (avoids VISITN.x / VISITN.y).
  obs_records <- base_raw |>
    dplyr::filter(!is.na(VISITN),
                  !VISIT %in% baseline_labels,
                  VISIT != "EOS") |>
    dplyr::select(USUBJID,
                  dplyr::any_of(c("VISIT", "RESP", "DTYPE", "PARAM")))

  # Build dummy visit grid: subjects x scheduled visits
  dummy_visits <- spec$dummy_visits
  if (length(dummy_visits) == 0)
    dummy_visits <- spec$visits_model

  # Get actual VISITN from data to attach to dummy grid
  actual_visitn <- ana_raw |>
    dplyr::distinct(VISIT, VISITN) |>
    dplyr::filter(!is.na(VISITN)) |>
    dplyr::mutate(VISIT = as.character(VISIT))

  visit_grid <- tibble::tibble(VISIT = dummy_visits) |>
    dplyr::left_join(actual_visitn, by = "VISIT")

  # Multi-param (EORTC): cross-join with param values
  has_param <- "PARAM" %in% names(ana_raw) && length(spec$param_values) > 0

  if (has_param) {
    subj_param <- base_records |>
      dplyr::inner_join(
        ana_raw |> dplyr::distinct(USUBJID, PARAM) |>
          dplyr::filter(PARAM %in% spec$param_values),
        by = "USUBJID"
      )
    grid <- tidyr::crossing(subj_param, visit_grid)
  } else {
    grid <- tidyr::crossing(base_records, visit_grid)
  }

  # Left-join observed RESP onto dummy grid (grid already has VISITN)
  join_cols <- intersect(c("USUBJID", "VISIT", "PARAM"), names(obs_records))
  ana <- dplyr::left_join(grid, obs_records, by = join_cols) |>
    dplyr::mutate(TRT   = factor(TRT,   levels = spec$treatment_levels),
                  VISIT = factor(VISIT, levels = spec$visits_model)) |>
    dplyr::arrange(VISITN, TRTN, USUBJID)

  if (!"DTYPE" %in% names(ana)) ana$DTYPE <- NA_character_

  sup <- .compute_support_stats(ana, spec)
  c(list(ana = ana), sup,
    list(meta = list(output_id    = spec$output_id,
                     method_id    = spec$method_id,
                     has_param    = has_param,
                     dataset_name = spec$dataset_name,
                     idkey        = spec$idkey)))
}


# =============================================================================
# SECTION 9: DATA PREP — FAMILY D (Tipping point)
# =============================================================================

#' Apply multiplicative or additive penalty to specific imputed rows
#'
#' Which rows get penalised is fully controlled by registry fields:
#'   tp_penalty_arm              : treatment arm label
#'   tp_penalty_filter_dtype     : DTYPE value (e.g. "MAR")
#'   tp_penalty_filter_impreas   : IMPREAS value (e.g. "Post I/C event")
#'   tp_penalty_fichypo_var      : column name for fichypo-like filter
#'   tp_penalty_filter_fichypo   : allowed values (pipe-separated in registry)
#'   tp_penalty_mode             : "multiply" or "add"
#'
#' No column names are hardcoded — all come from registry.
.apply_tp_penalty <- function(ana, penalty, spec) {
  mode <- spec$tp_penalty_mode %||% "multiply"

  # Identify rows to penalise
  is_pen_arm <- as.character(ana$TRT) == spec$tp_penalty_arm

  # Optional: dtype filter (from registry field, not hardcoded "MAR")
  dtype_col <- "DTYPE"
  is_dtype <- if (!is.null(spec$tp_penalty_filter_dtype) &&
                  !is.na(spec$tp_penalty_filter_dtype) &&
                  dtype_col %in% names(ana)) {
    ana[[dtype_col]] == spec$tp_penalty_filter_dtype
  } else rep(TRUE, nrow(ana))

  # Optional: impreas filter (column name from registry)
  # IMPREAS column name: ADaM standard default, overridable via tp_impreas_var in registry
  impreas_col <- spec$tp_impreas_var %||% "IMPREAS"
  is_impreas <- if (!is.null(spec$tp_penalty_filter_impreas) &&
                    !is.na(spec$tp_penalty_filter_impreas) &&
                    impreas_col %in% names(ana)) {
    ana[[impreas_col]] == spec$tp_penalty_filter_impreas
  } else rep(TRUE, nrow(ana))

  # Optional: fichypo-style filter (multi-value, column name from registry)
  fichypo_col <- spec$tp_penalty_fichypo_var %||% "FICHYPO"
  is_fichypo <- if (length(spec$tp_penalty_filter_fichypo) > 0 &&
                    fichypo_col %in% names(ana)) {
    ana[[fichypo_col]] %in% spec$tp_penalty_filter_fichypo
  } else rep(TRUE, nrow(ana))

  pen_rows <- is_pen_arm & is_dtype & is_impreas & is_fichypo

  if (!any(pen_rows))
    warning("[", spec$output_id, "] penalty=", penalty,
            ": no rows matched penalty filter — check tp_penalty_filter_* in registry")

  if (mode == "multiply") {
    # SAS: aval = aval * penalty_term; chg = aval - base
    # In ADaM where RESP = CHG: multiply the underlying AVAL then recompute CHG
    # If AVAL is available, use it; otherwise approximate via CHG + BASE
    if ("AVAL" %in% names(ana)) {
      ana$AVAL[pen_rows] <- ana$AVAL[pen_rows] * penalty
      ana$RESP[pen_rows] <- ana$AVAL[pen_rows] - ana$BASE[pen_rows]
    } else {
      # Approximate: RESP = CHG, so AVAL ≈ CHG + BASE
      aval_approx <- ana$RESP[pen_rows] + ana$BASE[pen_rows]
      aval_new    <- aval_approx * penalty
      ana$RESP[pen_rows] <- aval_new - ana$BASE[pen_rows]
    }
  } else {
    # Additive penalty (fallback)
    ana$RESP[pen_rows] <- ana$RESP[pen_rows] + penalty
  }

  ana
}

prep_tp_penalty <- function(data, spec) {
  # Same MI prep; penalty applied inside the runner loop
  prep_mi_visit(data, spec)
}


# =============================================================================
# SECTION 10: SHARED MODEL FITTING
# =============================================================================

.build_cov_term <- function(cov = c("us", "ar1", "cs")) {
  switch(match.arg(cov),
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

#' Fit one imputation slice; return lsm + diff for all visits
.fit_one_imp <- function(dat_imp, spec, plan, strata_present) {
  form    <- .build_mmrm_formula(strata_present, plan)
  fit     <- mmrm::mmrm(formula = form, data = dat_imp, reml = TRUE,
                        control = mmrm::mmrm_control(method = "Kenward-Roger"))
  emm     <- emmeans::emmeans(fit, specs = ~ TRT | VISIT)
  ref_idx <- which(levels(dat_imp$TRT) == spec$control_label)

  lsm <- as.data.frame(summary(emm, infer = TRUE, level = 0.95)) |>
    dplyr::transmute(VISIT = as.character(VISIT), TRT = as.character(TRT),
                     estimate = emmean, SE = SE,
                     lower = lower.CL, upper = upper.CL)

  diff <- as.data.frame(
    summary(emmeans::contrast(emm, method = "trt.vs.ctrl", ref = ref_idx),
            infer = TRUE, level = 0.95)
  ) |>
    dplyr::transmute(VISIT = as.character(VISIT),
                     comparison  = spec$comparison_label,
                     estimate    = estimate, SE = SE,
                     lower = lower.CL, upper = upper.CL,
                     p_two_sided = p.value)

  list(lsm = lsm, diff = diff)
}

#' Try each fallback plan; return first successful result + plan used
.apply_fallback_loop <- function(dat_imp, spec, strata_present) {
  for (plan in .FALLBACK_PLANS) {
    res <- tryCatch(.fit_one_imp(dat_imp, spec, plan, strata_present),
                    error = function(e) NULL)
    if (!is.null(res)) return(list(res = res, plan = plan))
  }
  list(res = NULL, plan = NULL)
}

#' Map over imputations with optional furrr parallelism
.map_imps <- function(imputations, fn, parallel, n_workers) {
  if (parallel && requireNamespace("furrr", quietly = TRUE)) {
    furrr::plan(furrr::multisession, workers = n_workers)
    furrr::future_imap(imputations, fn)
  } else {
    purrr::imap(imputations, fn)
  }
}


# =============================================================================
# SECTION 11: RUBIN'S RULES + FORMATTERS (shared across all families)
# =============================================================================

#' Rubin's rules — mirrors SAS PROC MIANALYZE ParameterEstimates
#' Results match SAS within floating-point rounding tolerance (~1e-6)
rubin_combine <- function(df, by_cols,
                           est_col = "estimate", se_col = "SE",
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
      tvar        = ubar + (1 + 1/pmax(m, 1)) * b,
      SE          = sqrt(tvar),
      df_mi       = dplyr::case_when(
                      m <= 1 | b <= 0 ~ 1e6,
                      TRUE ~ (m-1) * (1 + ubar/((1+1/m)*b))^2),
      crit        = stats::qt(1 - alpha/2, df = df_mi),
      lower       = qbar - crit * SE,
      upper       = qbar + crit * SE,
      p_two_sided = 2 * (1 - stats::pt(abs(qbar/SE), df = df_mi))
    ) |>
    dplyr::rename(estimate = qbar) |>
    dplyr::select(dplyr::all_of(by_cols), estimate, SE, lower, upper, p_two_sided)
}

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

#' One-sided p from two-sided p and estimate direction
#' pvalue_rule = "better_positive": active > control = benefit (FACIT, eGFR)
#' pvalue_rule = "better_negative": active < control = benefit (urine, EQ VAS)
.one_sided_p <- function(estimate, p_two_sided, pvalue_rule) {
  dplyr::case_when(
    pvalue_rule == "better_positive" & estimate > 0 ~ p_two_sided / 2,
    pvalue_rule == "better_positive" & estimate < 0 ~ 1 - p_two_sided / 2,
    pvalue_rule == "better_negative" & estimate < 0 ~ p_two_sided / 2,
    pvalue_rule == "better_negative" & estimate > 0 ~ 1 - p_two_sided / 2,
    TRUE ~ 0.5
  )
}


# =============================================================================
# SECTION 12: ARD ASSEMBLY — SHARED COUNT ROWS (bigN / nobs)
# =============================================================================

.ard_counts <- function(prep, spec, param = NA_character_,
                         group1_dim = "VISIT") {
  vd <- spec$visits_display %||% spec$visits_model

  ard_bigN <- prep$subj_n |>
    dplyr::transmute(
      output_id = spec$output_id, method_id = spec$method_id,
      result_profile = spec$result_profile,
      param_var = spec$vars$param %||% NA_character_, param = param,
      row_type = "arm",
      group1 = group1_dim, group1_level = NA_character_,
      group2 = "TRT",     group2_level = as.character(TRT),
      stat_name = "bigN", stat_label = "N",
      stat_num = bigN, stat_chr = as.character(bigN),
      penalty_term = NA_real_, ord1 = 0L, ord2 = as.integer(TRTN)
    )

  ard_nobs <- prep$obs_n |>
    dplyr::transmute(
      output_id = spec$output_id, method_id = spec$method_id,
      result_profile = spec$result_profile,
      param_var = spec$vars$param %||% NA_character_, param = param,
      row_type = "arm",
      group1 = group1_dim, group1_level = as.character(VISIT),
      group2 = "TRT",     group2_level = as.character(TRT),
      stat_name = "nobs", stat_label = "n",
      stat_num = nobs, stat_chr = as.character(nobs),
      penalty_term = NA_real_,
      ord1 = match(as.character(VISIT), vd), ord2 = as.integer(TRTN)
    )

  dplyr::bind_rows(ard_bigN, ard_nobs)
}


# =============================================================================
# SECTION 13: ARD ASSEMBLY — RESULT_CFB_IDENTITY (Families A + B)
# =============================================================================

.ard_cfb_identity <- function(prep, lsm_comb, diff_comb, spec,
                               param = NA_character_) {
  d_est  <- spec$digits$est
  d_p    <- spec$digits$p
  vd     <- spec$visits_display %||% spec$visits_model
  prule  <- spec$pvalue_rule %||% "better_positive"
  pv_vis <- spec$pvalue_display_visits

  lsm_d  <- dplyr::filter(lsm_comb,  VISIT %in% vd)
  diff_d <- dplyr::filter(diff_comb, VISIT %in% vd)

  add_meta <- function(df)
    dplyr::mutate(df,
      output_id = spec$output_id, method_id = spec$method_id,
      result_profile = spec$result_profile,
      param_var = spec$vars$param %||% NA_character_, param = param,
      penalty_term = NA_real_)

  ard_lsm <- add_meta(
    lsm_d |> dplyr::left_join(prep$subj_n |> dplyr::select(TRT, TRTN), by = "TRT")
  ) |>
    dplyr::transmute(
      output_id, method_id, result_profile, param_var, param, penalty_term,
      row_type = "arm",
      group1 = "VISIT", group1_level = VISIT,
      group2 = "TRT",   group2_level = as.character(TRT),
      stat_name = "adj_mean_ci",
      stat_label = "Adjusted mean (95% CI)",
      stat_num = estimate,
      stat_chr = format_ci(estimate, lower, upper, d_est),
      ord1 = match(VISIT, vd), ord2 = as.integer(TRTN)
    )

  ard_diff <- add_meta(diff_d) |>
    dplyr::transmute(
      output_id, method_id, result_profile, param_var, param, penalty_term,
      row_type = "comparison",
      group1 = "VISIT",      group1_level = VISIT,
      group2 = "COMPARISON", group2_level = comparison,
      stat_name = "adj_diff_ci",
      stat_label = "Adjusted mean difference (95% CI)",
      stat_num = estimate,
      stat_chr = format_ci(estimate, lower, upper, d_est),
      ord1 = match(VISIT, vd), ord2 = 99L
    )

  ard_rows <- dplyr::bind_rows(.ard_counts(prep, spec, param), ard_lsm, ard_diff)

  if (isTRUE(spec$include_pvalue) && length(pv_vis) > 0) {
    ard_pval <- add_meta(diff_d) |>
      dplyr::mutate(
        p_one = .one_sided_p(estimate, p_two_sided, prule),
        p_one = ifelse(VISIT %in% pv_vis, p_one, NA_real_)
      ) |>
      dplyr::transmute(
        output_id, method_id, result_profile, param_var, param, penalty_term,
        row_type = "comparison",
        group1 = "VISIT",      group1_level = VISIT,
        group2 = "COMPARISON", group2_level = comparison,
        stat_name = "pvalue_1sided", stat_label = "1-sided p-value",
        stat_num = p_one, stat_chr = format_p(p_one, d_p),
        ord1 = match(VISIT, vd), ord2 = 100L
      )
    ard_rows <- dplyr::bind_rows(ard_rows, ard_pval)
  }

  dplyr::arrange(ard_rows, ord1, ord2, stat_name)
}


# =============================================================================
# SECTION 14: ARD ASSEMBLY — RESULT_LOGRATIO_GEOMEAN (Family C)
# =============================================================================

.ard_logratio_geomean <- function(prep, lsm_comb, diff_comb, spec,
                                   param = NA_character_) {
  d_est  <- spec$digits$est
  d_p    <- spec$digits$p
  d_pct  <- spec$digits$pct  # from registry: digits_pct (default 1)
  vd     <- spec$visits_display %||% spec$visits_model
  prule  <- spec$pvalue_rule %||% "better_negative"
  pv_vis <- spec$pvalue_display_visits

  lsm_d  <- dplyr::filter(lsm_comb,  VISIT %in% vd)
  diff_d <- dplyr::filter(diff_comb, VISIT %in% vd)

  # Back-transform: exp() on log-scale estimates
  lsm_bt <- lsm_d |>
    dplyr::mutate(geo_mean = exp(estimate),
                  geo_lcl  = exp(lower),
                  geo_ucl  = exp(upper))

  diff_bt <- diff_d |>
    dplyr::mutate(
      geo_ratio = exp(estimate),
      geo_r_lcl = exp(lower),
      geo_r_ucl = exp(upper),
      # % reduction: (1 - ratio) * 100; CI bounds reversed
      pct_red     = (1 - exp(estimate)) * 100,
      pct_red_lcl = (1 - exp(upper))    * 100,
      pct_red_ucl = (1 - exp(lower))    * 100
    )

  add_meta <- function(df)
    dplyr::mutate(df,
      output_id = spec$output_id, method_id = spec$method_id,
      result_profile = spec$result_profile,
      param_var = spec$vars$param %||% NA_character_, param = param,
      penalty_term = NA_real_)

  ard_geo_mean <- add_meta(
    lsm_bt |> dplyr::left_join(prep$subj_n |> dplyr::select(TRT, TRTN), by = "TRT")
  ) |>
    dplyr::transmute(
      output_id, method_id, result_profile, param_var, param, penalty_term,
      row_type = "arm",
      group1 = "VISIT", group1_level = VISIT,
      group2 = "TRT",   group2_level = as.character(TRT),
      stat_name = "geo_mean_ci",
      stat_label = "Geometric adjusted mean (95% CI)",
      stat_num = geo_mean,
      stat_chr = format_ci(geo_mean, geo_lcl, geo_ucl, d_est),
      ord1 = match(VISIT, vd), ord2 = as.integer(TRTN)
    )

  ard_geo_ratio <- add_meta(diff_bt) |>
    dplyr::transmute(
      output_id, method_id, result_profile, param_var, param, penalty_term,
      row_type = "comparison",
      group1 = "VISIT",      group1_level = VISIT,
      group2 = "COMPARISON", group2_level = comparison,
      stat_name = "geo_ratio_ci",
      stat_label = "Geometric mean ratio (95% CI)",
      stat_num = geo_ratio,
      stat_chr = format_ci(geo_ratio, geo_r_lcl, geo_r_ucl, d_est),
      ord1 = match(VISIT, vd), ord2 = 99L
    )

  # % reduction — uses digits_pct from registry, not digits_est
  ard_pct_red <- add_meta(diff_bt) |>
    dplyr::transmute(
      output_id, method_id, result_profile, param_var, param, penalty_term,
      row_type = "comparison",
      group1 = "VISIT",      group1_level = VISIT,
      group2 = "COMPARISON", group2_level = comparison,
      stat_name = "pct_reduction_ci",
      stat_label = "% Reduction (95% CI)",
      stat_num = pct_red,
      stat_chr = format_ci(pct_red, pct_red_lcl, pct_red_ucl, d_pct),
      ord1 = match(VISIT, vd), ord2 = 100L
    )

  ard_rows <- dplyr::bind_rows(.ard_counts(prep, spec, param),
                                ard_geo_mean, ard_geo_ratio, ard_pct_red)

  if (isTRUE(spec$include_pvalue) && length(pv_vis) > 0) {
    ard_pval <- add_meta(diff_d) |>
      dplyr::mutate(
        p_one = .one_sided_p(estimate, p_two_sided, prule),
        p_one = ifelse(VISIT %in% pv_vis, p_one, NA_real_)
      ) |>
      dplyr::transmute(
        output_id, method_id, result_profile, param_var, param, penalty_term,
        row_type = "comparison",
        group1 = "VISIT",      group1_level = VISIT,
        group2 = "COMPARISON", group2_level = comparison,
        stat_name = "pvalue_1sided", stat_label = "1-sided p-value",
        stat_num = p_one, stat_chr = format_p(p_one, d_p),
        ord1 = match(VISIT, vd), ord2 = 101L
      )
    ard_rows <- dplyr::bind_rows(ard_rows, ard_pval)
  }

  dplyr::arrange(ard_rows, ord1, ord2, stat_name)
}


# =============================================================================
# SECTION 15: ARD ASSEMBLY — RESULT_TP_MONTH (Family D)
# =============================================================================

.ard_tp_month <- function(prep, tp_results, spec) {
  d_est  <- spec$digits$est
  d_p    <- spec$digits$p
  sig    <- spec$tp_significance %||% 0.025
  pv     <- spec$tp_primary_visit
  prule  <- spec$pvalue_rule %||% "better_positive"
  pen_ord <- sort(unique(tp_results$penalty))

  tp_ann <- tp_results |>
    dplyr::arrange(penalty) |>
    dplyr::mutate(
      p_one = .one_sided_p(estimate, p_two_sided, prule),
      sig_flag     = p_one < sig,
      tipping_flag = !sig_flag & dplyr::lag(sig_flag, default = TRUE)
    )

  add_meta <- function(df)
    dplyr::mutate(df,
      output_id = spec$output_id, method_id = spec$method_id,
      result_profile = spec$result_profile,
      param_var = NA_character_, param = NA_character_)

  ard_bigN <- prep$subj_n |>
    dplyr::transmute(
      output_id = spec$output_id, method_id = spec$method_id,
      result_profile = spec$result_profile,
      param_var = NA_character_, param = NA_character_,
      row_type = "arm",
      group1 = "PENALTY", group1_level = NA_character_,
      group2 = "TRT",     group2_level = as.character(TRT),
      stat_name = "bigN", stat_label = "N",
      stat_num = bigN, stat_chr = as.character(bigN),
      penalty_term = NA_real_, ord1 = 0L, ord2 = as.integer(TRTN)
    )

  ard_nobs <- prep$obs_n |>
    dplyr::filter(as.character(VISIT) == pv) |>
    dplyr::transmute(
      output_id = spec$output_id, method_id = spec$method_id,
      result_profile = spec$result_profile,
      param_var = NA_character_, param = NA_character_,
      row_type = "arm",
      group1 = "PENALTY", group1_level = NA_character_,
      group2 = "TRT",     group2_level = as.character(TRT),
      stat_name = "nobs", stat_label = paste0("n (", pv, ")"),
      stat_num = nobs, stat_chr = as.character(nobs),
      penalty_term = NA_real_, ord1 = 0L, ord2 = as.integer(TRTN)
    )

  ard_diff <- add_meta(tp_ann) |>
    dplyr::transmute(
      output_id, method_id, result_profile, param_var, param,
      row_type = "comparison",
      group1 = "PENALTY",    group1_level = as.character(penalty),
      group2 = "COMPARISON", group2_level = comparison,
      stat_name = "adj_diff_ci",
      stat_label = "Adjusted mean difference (95% CI)",
      stat_num = estimate,
      stat_chr = format_ci(estimate, lower, upper, d_est),
      penalty_term = penalty, ord1 = match(penalty, pen_ord), ord2 = 99L
    )

  ard_pval <- add_meta(tp_ann) |>
    dplyr::transmute(
      output_id, method_id, result_profile, param_var, param,
      row_type = "comparison",
      group1 = "PENALTY",    group1_level = as.character(penalty),
      group2 = "COMPARISON", group2_level = comparison,
      stat_name = "pvalue_1sided", stat_label = "1-sided p-value",
      stat_num = p_one, stat_chr = format_p(p_one, d_p),
      penalty_term = penalty, ord1 = match(penalty, pen_ord), ord2 = 100L
    )

  ard_tp_flag <- add_meta(dplyr::filter(tp_ann, tipping_flag)) |>
    dplyr::transmute(
      output_id, method_id, result_profile, param_var, param,
      row_type = "comparison",
      group1 = "PENALTY",    group1_level = as.character(penalty),
      group2 = "COMPARISON", group2_level = comparison,
      stat_name = "tipping_point",
      stat_label = paste0("Tipping point (1-sided alpha=", sig, ")"),
      stat_num = 1L, stat_chr = paste0("penalty=", penalty),
      penalty_term = penalty, ord1 = match(penalty, pen_ord), ord2 = 101L
    )

  dplyr::bind_rows(ard_bigN, ard_nobs, ard_diff, ard_pval, ard_tp_flag) |>
    dplyr::arrange(ord1, ord2, stat_name)
}


# =============================================================================
# SECTION 16: FAMILY RUNNERS
# =============================================================================

#' Family A: CFB + MI + by-visit + identity scale
run_family_a <- function(data, spec, parallel = FALSE, n_workers = 4,
                          debug = FALSE) {
  message("[", spec$output_id, "] [A] Step 1/4: Preparing (MI visit)...")
  prep  <- prep_mi_visit(data, spec)
  n_imp <- max(prep$ana$IMPNUM, na.rm = TRUE)

  message("[", spec$output_id, "] [A] Step 2/4: Fitting (", n_imp, " imps)...")
  fits <- .map_imps(split(prep$ana, prep$ana$IMPNUM),
    function(d, id) {
      r <- .apply_fallback_loop(d, spec, prep$strata_present)
      if (is.null(r$res))
        stop("[", spec$output_id, "] All fallbacks failed IMPNUM=", id)
      list(lsm  = dplyr::mutate(r$res$lsm,  IMPNUM = as.integer(id)),
           diff = dplyr::mutate(r$res$diff, IMPNUM = as.integer(id)),
           plan = tibble::tibble(IMPNUM = as.integer(id),
                                 covariance     = r$plan$covariance,
                                 use_strata     = r$plan$use_strata,
                                 use_visit_base = r$plan$use_visit_base))
    }, parallel, n_workers)

  message("[", spec$output_id, "] [A] Step 3/4: Rubin's rules...")
  lsm_comb <- rubin_combine(dplyr::bind_rows(purrr::map(fits, "lsm")),
                              by_cols = c("VISIT", "TRT")) |>
    dplyr::mutate(TRT = factor(TRT, levels = spec$treatment_levels)) |>
    dplyr::arrange(match(VISIT, spec$visits_model), TRT)

  diff_comb <- rubin_combine(
    dplyr::bind_rows(purrr::map(fits, "diff")) |> dplyr::select(-p_two_sided),
    by_cols = c("VISIT", "comparison")
  ) |> dplyr::arrange(match(VISIT, spec$visits_model))

  message("[", spec$output_id, "] [A] Step 4/4: Building ARD (identity)...")
  ard <- .ard_cfb_identity(prep, lsm_comb, diff_comb, spec)

  out <- list(ard = ard, subj_n = prep$subj_n, obs_n = prep$obs_n,
              lsm = lsm_comb, diff = diff_comb,
              meta = c(prep$meta, list(n_imp = n_imp, run_time = Sys.time())))
  if (debug) { out$ana <- prep$ana; out$fit_plan <- dplyr::bind_rows(purrr::map(fits, "plan")) }
  message("[", spec$output_id, "] Done.")
  out
}


#' Family B: CFB + observed + dummy visit grid (no MI, optional multi-param)
run_family_b <- function(data, spec, parallel = FALSE, n_workers = 4,
                          debug = FALSE) {
  message("[", spec$output_id, "] [B] Step 1/3: Preparing (observed + dummy grid)...")
  prep <- prep_obs_dummy_visit(data, spec)

  params <- if (length(spec$param_values) > 0) spec$param_values else list(NA_character_)
  message("[", spec$output_id, "] [B] Step 2/3: Fitting (",
          length(params), " param(s))...")

  ard_list <- purrr::map(params, function(param) {
    ana_p <- if (!is.na(param) && "PARAM" %in% names(prep$ana)) {
      dplyr::filter(prep$ana, PARAM == param)
    } else {
      prep$ana
    }
    ana_p <- ana_p |>
      dplyr::mutate(TRT   = factor(TRT,   levels = spec$treatment_levels),
                    VISIT = factor(VISIT, levels = spec$visits_model))

    r <- .apply_fallback_loop(ana_p, spec, prep$strata_present)
    if (is.null(r$res))
      stop("[", spec$output_id, "] All fallbacks failed (param=", param, ")")

    lsm_comb  <- r$res$lsm |>
      dplyr::mutate(TRT = factor(TRT, levels = spec$treatment_levels))
    diff_comb <- r$res$diff

    .ard_cfb_identity(prep, lsm_comb, diff_comb, spec, param = param)
  })

  message("[", spec$output_id, "] [B] Step 3/3: Building ARD...")
  ard <- dplyr::bind_rows(ard_list)

  out <- list(ard = ard, subj_n = prep$subj_n, obs_n = prep$obs_n,
              meta = c(prep$meta, list(n_params = length(params), run_time = Sys.time())))
  if (debug) out$ana <- prep$ana
  message("[", spec$output_id, "] Done.")
  out
}


#' Family C: log-ratio + MI + by-visit + back-transform to geometric means
run_family_c <- function(data, spec, parallel = FALSE, n_workers = 4,
                          debug = FALSE) {
  message("[", spec$output_id, "] [C] Step 1/4: Preparing (MI, log-ratio)...")
  prep  <- prep_mi_visit(data, spec)
  n_imp <- max(prep$ana$IMPNUM, na.rm = TRUE)

  message("[", spec$output_id, "] [C] Step 2/4: Fitting (", n_imp, " imps)...")
  fits <- .map_imps(split(prep$ana, prep$ana$IMPNUM),
    function(d, id) {
      r <- .apply_fallback_loop(d, spec, prep$strata_present)
      if (is.null(r$res))
        stop("[", spec$output_id, "] All fallbacks failed IMPNUM=", id)
      list(lsm  = dplyr::mutate(r$res$lsm,  IMPNUM = as.integer(id)),
           diff = dplyr::mutate(r$res$diff, IMPNUM = as.integer(id)),
           plan = tibble::tibble(IMPNUM = as.integer(id),
                                 covariance = r$plan$covariance))
    }, parallel, n_workers)

  message("[", spec$output_id, "] [C] Step 3/4: Rubin's rules...")
  lsm_comb <- rubin_combine(dplyr::bind_rows(purrr::map(fits, "lsm")),
                              by_cols = c("VISIT", "TRT")) |>
    dplyr::mutate(TRT = factor(TRT, levels = spec$treatment_levels)) |>
    dplyr::arrange(match(VISIT, spec$visits_model), TRT)

  diff_comb <- rubin_combine(
    dplyr::bind_rows(purrr::map(fits, "diff")) |> dplyr::select(-p_two_sided),
    by_cols = c("VISIT", "comparison")
  ) |> dplyr::arrange(match(VISIT, spec$visits_model))

  message("[", spec$output_id, "] [C] Step 4/4: Building ARD (back-transform)...")
  ard <- .ard_logratio_geomean(prep, lsm_comb, diff_comb, spec)

  out <- list(ard = ard, subj_n = prep$subj_n, obs_n = prep$obs_n,
              lsm = lsm_comb, diff = diff_comb,
              meta = c(prep$meta, list(n_imp = n_imp, run_time = Sys.time())))
  if (debug) { out$ana <- prep$ana; out$fit_plan <- dplyr::bind_rows(purrr::map(fits, "plan")) }
  message("[", spec$output_id, "] Done.")
  out
}


#' Family D: tipping point wrapper (registry-driven penalty filter)
run_family_d <- function(data, spec, parallel = FALSE, n_workers = 4,
                          debug = FALSE) {
  n_pen <- length(spec$tp_penalty_values)
  message("[", spec$output_id, "] [D] Step 1/3: Preparing (TP)...")
  prep  <- prep_tp_penalty(data, spec)
  n_imp <- max(prep$ana$IMPNUM, na.rm = TRUE)

  message("[", spec$output_id, "] [D] Step 2/3: Fitting across ",
          n_pen, " penalties x ", n_imp, " imputations...")

  tp_results <- purrr::map(spec$tp_penalty_values, function(pen) {
    message("  penalty = ", pen)
    ana_pen <- .apply_tp_penalty(prep$ana, pen, spec)
    imps    <- split(ana_pen, ana_pen$IMPNUM)

    diff_list <- purrr::imap(imps, function(d, id) {
      r <- .apply_fallback_loop(d, spec, prep$strata_present)
      if (is.null(r$res)) {
        warning("penalty=", pen, " IMPNUM=", id, ": all plans failed — skipped")
        return(NULL)
      }
      dplyr::filter(r$res$diff, VISIT == spec$tp_primary_visit) |>
        dplyr::mutate(IMPNUM = as.integer(id))
    })

    valid <- dplyr::bind_rows(purrr::compact(diff_list))
    if (nrow(valid) == 0) { warning("penalty=", pen, ": no valid results"); return(NULL) }

    rubin_combine(valid |> dplyr::select(-p_two_sided),
                  by_cols = c("VISIT", "comparison")) |>
      dplyr::mutate(penalty = pen)
  })

  tp_all <- dplyr::bind_rows(purrr::compact(tp_results))
  if (nrow(tp_all) == 0)
    stop("[", spec$output_id, "] No TP results — check tp_penalty_filter_* fields")

  message("[", spec$output_id, "] [D] Step 3/3: Building TP ARD...")
  ard <- .ard_tp_month(prep, tp_all, spec)

  tp_value <- tp_all |>
    dplyr::arrange(penalty) |>
    dplyr::mutate(p_one = .one_sided_p(estimate, p_two_sided,
                                        spec$pvalue_rule %||% "better_positive")) |>
    dplyr::filter(p_one >= (spec$tp_significance %||% 0.025)) |>
    dplyr::slice(1) |>
    dplyr::pull(penalty)

  out <- list(ard = ard, subj_n = prep$subj_n, obs_n = prep$obs_n,
              diff = tp_all,
              meta = c(prep$meta, list(n_imp = n_imp, n_penalties = n_pen,
                                       tipping_point = tp_value,
                                       run_time = Sys.time())))
  if (debug) out$ana <- prep$ana
  message("[", spec$output_id, "] Tipping point at penalty = ", tp_value)
  message("[", spec$output_id, "] Done.")
  out
}


# =============================================================================
# SECTION 17: DISPATCH TABLE
# =============================================================================

.RUNNER_MAP <- list(
  MMRM_CFB_MI_VISIT      = run_family_a,
  MMRM_CFB_OBS_VISIT     = run_family_b,
  MMRM_LOGRATIO_MI_VISIT = run_family_c,
  MMRM_TP_MI_VISIT       = run_family_d
)


# =============================================================================
# SECTION 18: PUBLIC API  create_ard_mmrm()
# =============================================================================

#' Create MMRM ARD for one output — main user-facing function
#'
#' Dispatches to the correct family runner based on method_id in registry.
#' All study-specific information comes from the registry files.
#'
#' USAGE IN A NEW STUDY
#' ─────────────────────
#' 1. Create eff_mmrm_registry.csv for the new study
#' 2. out_reg  <- load_mmrm_registry("path/to/eff_mmrm_registry.csv")
#' 3. meth_reg <- load_method_registry("mmrm_method_registry.csv")  # shared
#' 4. data     <- haven::read_sas(file.path(st$analysis, "adamdata.sas7bdat"))
#' 5. res      <- create_ard_mmrm("output_id", data = data,
#'                                 out_registry = out_reg,
#'                                 meth_registry = meth_reg)
#' 6. res$ard  # the analysis result dataset
#'
#' @param output_id      character — e.g. "14.2-4.1"
#' @param idkey          character — e.g. "PTL0035"
#' @param data           data.frame — ADaM dataset
#' @param out_registry   tibble — from load_mmrm_registry() (pre-load once per session)
#' @param meth_registry  tibble — from load_method_registry() (optional, shared across studies)
#' @param out_registry_path  character — path to CSV/xlsx (used if out_registry=NULL)
#' @param meth_registry_path character — path to method registry CSV/xlsx
#' @param imp_max        integer — override at call time for quick testing
#' @param parallel       logical — use furrr for parallel imputation fitting
#' @param n_workers      integer — parallel workers
#' @param debug          logical — include ana + fit_plan in return
#' @param trakdata       character — NULL = Phase 1 (ARD only); path = Phase 2
#'
#' @return list: $ard $subj_n $obs_n $lsm $diff $meta
#'         + $shell $title $footnote when trakdata provided
#'
#' @examples
#' # --- Load once per session ---
#' out_reg  <- load_mmrm_registry(file.path(st$util, "eff_mmrm_registry.csv"))
#' meth_reg <- load_method_registry(file.path(st$util, "mmrm_method_registry.csv"))
#'
#' # --- Normal production run ---
#' adfacmi <- haven::read_sas(file.path(st$analysis, "adfacmi.sas7bdat"))
#' res <- create_ard_mmrm("14.2-4.1", data = adfacmi,
#'                         out_registry = out_reg, meth_registry = meth_reg)
#' res$ard
#'
#' # --- Quick test: 10 imputations ---
#' res_test <- create_ard_mmrm("14.2-4.1", data = adfacmi,
#'                              out_registry = out_reg, imp_max = 10)
#'
#' # --- Batch: all outputs ---
#' datasets <- list(
#'   adfacmi  = adfacmi,
#'   adgfrmi2 = haven::read_sas(file.path(st$analysis, "adgfrmi2.sas7bdat")),
#'   adupcrmi = haven::read_sas(file.path(st$analysis, "adupcrmi.sas7bdat"))
#' )
#' all_results <- run_all_mmrm(out_reg, datasets, meth_registry = meth_reg)
#' all_ard <- purrr::map(all_results, "ard") |> dplyr::bind_rows()
#'
#' @export
create_ard_mmrm <- function(output_id          = NULL,
                             idkey              = NULL,
                             data,
                             out_registry       = NULL,
                             meth_registry      = NULL,
                             out_registry_path  = NULL,
                             meth_registry_path = NULL,
                             imp_max            = NULL,
                             parallel           = FALSE,
                             n_workers          = 4,
                             debug              = FALSE,
                             trakdata           = NULL) {

  # 1. Load registries if not pre-loaded
  if (is.null(out_registry)) {
    path <- out_registry_path %||% {
      cands <- c(
        if (exists("st") && !is.null(st$util))
          file.path(st$util, "eff_mmrm_registry.csv"),
        "eff_mmrm_registry.csv"
      )
      cands[file.exists(cands)][1]
    }
    if (is.null(path) || is.na(path))
      stop("Output registry not found. Provide out_registry= or out_registry_path=")
    out_registry <- load_mmrm_registry(path)
  }
  if (is.null(meth_registry) && !is.null(meth_registry_path))
    meth_registry <- load_method_registry(meth_registry_path)

  # 2. Resolve spec (all study-specific info comes from registry)
  spec <- resolve_mmrm_spec(output_id     = output_id,
                             idkey         = idkey,
                             out_registry  = out_registry,
                             meth_registry = meth_registry)

  # 3. Override imp_max at call time (test vs production)
  if (!is.null(imp_max)) {
    spec$imp_max <- as.integer(imp_max)
    message("[", spec$output_id, "] imp_max overridden to ", imp_max,
            " (registry value ignored for this run)")
  }

  validate_mmrm_spec(spec)

  # 4. Dispatch to correct family runner
  runner <- .RUNNER_MAP[[spec$method_id]]
  if (is.null(runner))
    stop("[", spec$output_id, "] Unknown method_id: '", spec$method_id,
         "'\n  Registered families: ", paste(names(.RUNNER_MAP), collapse = ", "))

  result <- runner(data = data, spec = spec,
                   parallel = parallel, n_workers = n_workers, debug = debug)

  # 5. Phase 2: attach TrakData metadata (optional)
  if (!is.null(trakdata) && nchar(spec$idkey %||% "") > 0)
    result <- attach_trakdata(result, idkey = spec$idkey, trakdata = trakdata)

  result
}


# =============================================================================
# SECTION 19: BATCH RUNNER
# =============================================================================

#' Run all outputs in registry — handles all 4 families automatically
#'
#' Tip: pre-load all datasets into a named list. Each dataset is used for
#' all outputs that share it without re-reading.
#'
#' @param out_registry   tibble — from load_mmrm_registry()
#' @param datasets       named list of data.frames (names = dataset_name values)
#' @param meth_registry  tibble — optional
#' @param output_ids     character vector — subset; NULL = all rows
#' @param imp_max        integer — global test override
#' @param parallel       logical
#' @param n_workers      integer
#'
#' @export
run_all_mmrm <- function(out_registry,
                          datasets,
                          meth_registry = NULL,
                          output_ids    = NULL,
                          imp_max       = NULL,
                          parallel      = FALSE,
                          n_workers     = 4) {

  reg_run <- if (!is.null(output_ids))
    dplyr::filter(out_registry, output_id %in% output_ids)
  else
    out_registry

  if (nrow(reg_run) == 0) stop("No outputs to run.")

  miss_ds <- setdiff(reg_run$dataset_name, names(datasets))
  if (length(miss_ds) > 0)
    stop("datasets list missing: ", paste(miss_ds, collapse = ", "),
         "\n  Provide all datasets as named list: list(adfacmi = ..., adgfrmi2 = ...)")

  n_by_method <- table(reg_run$method_id)
  message("Batch run: ", nrow(reg_run), " outputs | ",
          paste(n_by_method, names(n_by_method), sep = " x ", collapse = " | "))

  results <- purrr::map(purrr::transpose(as.list(reg_run)), function(row) {
    meth_row <- if (!is.null(meth_registry)) {
      mr <- dplyr::filter(meth_registry, method_id == row$method_id)
      if (nrow(mr) > 0) as.list(mr[1, ]) else NULL
    } else NULL

    spec <- .row_to_spec(row, meth_row)
    if (!is.null(imp_max)) spec$imp_max <- as.integer(imp_max)

    runner <- .RUNNER_MAP[[spec$method_id]]
    if (is.null(runner))
      stop("Unknown method_id '", spec$method_id, "' for ", row$output_id)

    runner(data = datasets[[row$dataset_name]], spec = spec,
           parallel = parallel, n_workers = n_workers)
  })

  names(results) <- reg_run$output_id
  results
}


# =============================================================================
# SECTION 20: TRAKDATA ADAPTER (Phase 2 — connect to company pipeline)
# =============================================================================

#' Attach TrakData metadata to a run result
#'
#' Mirrors return_ard() in company funcs_ars.R. Returns same structure as
#' create_ard_freq() so downstream RTF code works without modification.
#'
#' Requires funcs_general.R to be sourced (provides create_report2()).
#'
#' @param result   list — from create_ard_mmrm() or run_family_*()
#' @param idkey    character — PDT idkey
#' @param trakdata character — TrakData filename
attach_trakdata <- function(result, idkey = "", trakdata = "TrakData.csv") {
  idkey <- stringr::str_trim(idkey)

  ard_out <- result$ard |>
    dplyr::mutate(trakdata = trakdata, idkey = idkey) |>
    dplyr::relocate(trakdata, idkey)

  subj_N <- result$subj_n

  if (nchar(idkey) > 0) {
    report   <- create_report2(idkey, trakdata = trakdata)
    rds_path <- paste0(dirname(report$shell$file_path), "/", idkey, "_ard.rds")

    if (!interactive() || isTRUE(st$interactive_write_ard %||% FALSE)) {
      readr::write_rds(ard_out, rds_path)
      message("ARD written: ", rds_path)
    }

    return(list(ard      = ard_out,
                subj_N   = subj_N,
                shell    = report$shell,
                title    = report$title,
                footnote = report$footnote))
  }

  list(ard = ard_out, subj_N = subj_N)
}
