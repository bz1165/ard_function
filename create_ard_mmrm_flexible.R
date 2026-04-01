# =============================================================================
# FILE        : create_ard_mmrm_v3.R
# DESCRIPTION : MMRM ARD engine — registry-driven, auto-detect, output everything
#
# CORE PHILOSOPHY
# ─────────────────────────────────────────────────────────────────────────────
#   Registry  = pure data specification (filters, variables, visits)
#   Engine    = derives analysis type from spec; always outputs ALL stats
#   User      = filters $ard for what they need
#
# WHAT'S GONE vs v2
# ─────────────────────────────────────────────────────────────────────────────
#   mmrm_method_registry.csv    — eliminated entirely
#   method_id                   — eliminated from registry + ARD columns
#   result_profile              — eliminated from ARD columns
#   transform_profile           — eliminated
#   load_method_registry()      — eliminated
#   Family A / B / C / D names  — replaced by auto-detection flags
#   run_family_a/b/c/d          — kept as minimal backward-compat wrappers
#
# AUTO-DETECTION (from eff_mmrm_registry.csv columns, no user decision needed)
# ─────────────────────────────────────────────────────────────────────────────
#   use_mi         ← imputation_var   is non-empty        → run MI loop + Rubin
#   use_dummy_grid ← dummy_visit_var  is non-empty        → use observed dummy grid
#   use_tp         ← tp_penalty_values is non-empty       → run TP outer loop
#   response_scale ← registry column  (default "identity")→ controls back-transform
#
# REGISTRY CHANGE (eff_mmrm_registry.csv)
# ─────────────────────────────────────────────────────────────────────────────
#   REMOVE  : method_id, result_profile, transform_profile
#   ADD     : response_scale  ("identity" | "logratio")
#   (all other columns unchanged)
#
# ARD STAT_NAMES — always output everything applicable, user filters
# ─────────────────────────────────────────────────────────────────────────────
#   bigN, nobs                      always
#   adj_mean_ci, adj_diff_ci        always  (log-scale for logratio)
#   geo_mean_ci, geo_ratio_ci,
#     pct_reduction_ci              when response_scale = "logratio"
#   p_two_sided, p_one_pos,
#     p_one_neg                     when include_pvalue = TRUE
#   tipping_point (PENALTY dim)     when tp_penalty_values non-empty
#
# ARD COLUMNS
# ─────────────────────────────────────────────────────────────────────────────
#   output_id, response_scale, param_var, param,
#   row_type, group1, group1_level, group2, group2_level,
#   stat_name, stat_label, stat_num, stat_chr,
#   pvalue_display_default, pvalue_visit_default,
#   penalty_term, ord1, ord2
#
# BREAKING CHANGES vs v2
# ─────────────────────────────────────────────────────────────────────────────
#   - method_id / result_profile columns absent from ARD
#     → replace filter(method_id == "MMRM_LOGRATIO_MI_VISIT")
#       with    filter(response_scale == "logratio")
#   - logratio ARD now contains adj_mean_ci (log-scale) + geo_mean_ci (back-transform)
#   - create_ard_mmrm() drops meth_registry / meth_registry_path parameters
#
# PACKAGES: dplyr, purrr, tibble, stringr, tidyr, readr, mmrm, emmeans, tools
# =============================================================================

library(dplyr)
library(purrr)
library(tibble)
library(stringr)
library(tidyr)


# =============================================================================
# SECTION 1: SHARED FALLBACK SEQUENCE
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
# v3: adds .has_value() and .detect_analysis_flags()
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

# True if x is non-null, non-NA, non-empty-string
.has_value <- function(x) {
  !is.null(x) && length(x) > 0 && !is.na(x[[1]]) &&
    nchar(trimws(as.character(x[[1]]))) > 0
}

# ── v3: Auto-detect analysis flags from one registry row ─────────────────────
# No method_id needed. Reads the raw spec columns to determine what to run.
#
# Returns list:
#   use_mi         — TRUE if imputation_var is set (run MI loop + Rubin's rules)
#   use_dummy_grid — TRUE if dummy_visit_var is set (observed + dummy grid)
#   use_tp         — TRUE if tp_penalty_values is non-empty (tipping-point loop)
#   response_scale — "identity" | "logratio"  (controls back-transform and stats)
#
# All 13 rows in the current registry classify correctly from these three columns:
#   imputation_var  non-empty → use_mi  (FACIT / eGFR / urine)
#   dummy_visit_var non-empty → use_dummy_grid  (EQ VAS / EORTC)
#   tp_penalty_values non-empty → use_tp  (eGFR TP only)
.detect_analysis_flags <- function(out_row) {
  use_mi         <- .has_value(out_row$imputation_var)
  use_dummy_grid <- .has_value(out_row$dummy_visit_var)
  use_tp         <- {
    pv <- .split_pipe(out_row$tp_penalty_values %||% "")
    length(pv) > 0 && any(!is.na(suppressWarnings(as.numeric(pv))))
  }
  response_scale <- if (.has_value(out_row$response_scale)) {
    as.character(out_row$response_scale)
  } else {
    "identity"
  }

  if (use_mi && use_dummy_grid)
    warning("Both imputation_var and dummy_visit_var are set for output '",
            out_row$output_id, "'. MI path will be used; dummy_grid ignored.")

  list(use_mi         = use_mi,
       use_dummy_grid = use_dummy_grid,
       use_tp         = use_tp,
       response_scale = response_scale)
}

# ── Call-time spec overrides ──────────────────────────────────────────────────
.apply_spec_overrides <- function(spec, overrides) {
  if (length(overrides) == 0) return(spec)

  pipe_fields <- c(
    "visits_model", "visits_display", "visit_exclude",
    "pvalue_display_visits", "param_values", "dummy_visits",
    "treatment_levels", "tp_penalty_filter_fichypo"
  )

  for (nm in names(overrides)) {
    val <- overrides[[nm]]
    if (nm %in% pipe_fields && is.character(val) && length(val) == 1)
      val <- .split_pipe(val)
    if (nm == "tp_penalty_values" && is.character(val))
      val <- as.numeric(.split_pipe(val))
    if (nm == "strata_vars") {
      spec$vars$strata <- if (is.character(val) && length(val) == 1 && val == "") {
        character(0)
      } else {
        .split_pipe(val)
      }
      next
    }
    spec[[nm]] <- val
  }

  # Re-run flag detection if key columns were overridden
  flag_cols <- c("imputation_var", "dummy_visit_var",
                 "tp_penalty_values", "response_scale")
  if (any(names(overrides) %in% flag_cols)) {
    # Build a minimal row to re-detect flags
    proxy <- list(
      output_id       = spec$output_id,
      imputation_var  = spec$vars$imputation,
      dummy_visit_var = spec$dummy_visit_var,
      tp_penalty_values = paste(spec$tp_penalty_values, collapse = "|"),
      response_scale  = spec$response_scale
    )
    flags <- .detect_analysis_flags(proxy)
    spec$use_mi         <- flags$use_mi
    spec$use_dummy_grid <- flags$use_dummy_grid
    spec$use_tp         <- flags$use_tp
    spec$response_scale <- flags$response_scale
  }

  spec
}


# =============================================================================
# SECTION 3: REGISTRY READER
# v3: single registry only — no load_method_registry()
# =============================================================================

#' Load output registry
#'
#' v3 registry has response_scale instead of method_id / result_profile /
#' transform_profile. All other columns unchanged.
#'
#' @param path path to eff_mmrm_registry.csv or .xlsx
#' @export
load_mmrm_registry <- function(path) {
  reg <- .read_registry(path)

  required_cols <- c(
    "output_id", "idkey", "dataset_name",
    "population_var", "population_value",
    "trt_var", "trtn_var", "visit_var", "visitn_var",
    "response_var", "baseline_var",
    "treatment_levels", "control_label", "comparison_label",
    "visits_model"
  )
  miss <- setdiff(required_cols, names(reg))
  if (length(miss) > 0)
    stop("Registry missing required columns: ", paste(miss, collapse = ", "))

  optional_cols <- c(
    "response_scale",
    "pop_var2", "pop_val2",
    "category_var", "category_value",
    "paramcd_filter", "paramcd_filter_var",
    "imputation_var", "dtype_var", "strata_vars",
    "param_var", "param_values",
    "visits_display", "visit_exclude",
    "avisitn_var", "avisitn_gt", "avisitn_le",
    "pvalue_display_visits", "include_pvalue", "pvalue_rule",
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
    stop("Duplicate output_id: ", paste(dup, collapse = ", "))

  # Summary: detected flags per row
  flags <- purrr::map(purrr::transpose(as.list(reg)), .detect_analysis_flags)
  n_mi  <- sum(purrr::map_lgl(flags, "use_mi"))
  n_obs <- sum(!purrr::map_lgl(flags, "use_mi"))
  n_lr  <- sum(purrr::map_chr(flags, "response_scale") == "logratio")
  n_tp  <- sum(purrr::map_lgl(flags, "use_tp"))
  message("Registry: ", nrow(reg), " outputs | MI=", n_mi, " OBS=", n_obs,
          " | logratio=", n_lr, " | TP=", n_tp)
  reg
}


# =============================================================================
# SECTION 4: SPEC RESOLUTION
# v3: .row_to_spec() uses .detect_analysis_flags(); no meth_row parameter
# =============================================================================

#' Build spec from one registry row (no method registry needed)
.row_to_spec <- function(out_row) {

  flags <- .detect_analysis_flags(out_row)

  n_obs_dtype <- .split_pipe(out_row$n_obs_dtype_values %||% "")
  if (length(n_obs_dtype) == 0) n_obs_dtype <- c("", "TP")

  list(
    # Identity
    output_id    = out_row$output_id,
    idkey        = as.character(out_row$idkey %||% ""),
    dataset_name = out_row$dataset_name,

    # v3: auto-detected flags (replace method_id / family concept)
    use_mi         = flags$use_mi,
    use_dummy_grid = flags$use_dummy_grid,
    use_tp         = flags$use_tp,
    response_scale = flags$response_scale,

    # Population filters
    population_var   = out_row$population_var,
    population_value = out_row$population_value,
    pop_var2         = out_row$pop_var2 %||% NA_character_,
    pop_val2         = out_row$pop_val2 %||% NA_character_,

    # Category filter
    category_var   = out_row$category_var   %||% NA_character_,
    category_value = out_row$category_value %||% NA_character_,

    # Paramcd filter
    paramcd_filter_var = out_row$paramcd_filter_var %||% "PARAMCD",
    paramcd_filter     = out_row$paramcd_filter     %||% NA_character_,

    # AVISITN range filter
    avisitn_var = out_row$avisitn_var %||% "AVISITN",
    avisitn_gt  = .as_numeric_safe(out_row$avisitn_gt),
    avisitn_le  = .as_numeric_safe(out_row$avisitn_le),

    # Variable mapping
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

    # Multi-param (EORTC)
    param_values = .split_pipe(out_row$param_values %||% ""),

    # Visits
    visits_model  = .split_pipe(out_row$visits_model),
    visits_display = {
      vd <- .split_pipe(out_row$visits_display %||% "")
      if (length(vd) == 0) .split_pipe(out_row$visits_model) else vd
    },
    visit_exclude = .split_pipe(out_row$visit_exclude %||% ""),

    # P-value
    pvalue_display_visits = .split_pipe(out_row$pvalue_display_visits %||% ""),
    include_pvalue        = .as_logical_safe(out_row$include_pvalue %||% TRUE),
    pvalue_rule           = out_row$pvalue_rule %||% "better_positive",

    # n_obs filter
    n_obs_dtype_values = n_obs_dtype,

    # Runtime
    imp_max = .as_integer_safe(out_row$imp_max),
    digits  = list(
      est = as.integer(.as_numeric_safe(out_row$digits_est) %||% 3),
      p   = as.integer(.as_numeric_safe(out_row$digits_p)   %||% 4),
      pct = as.integer(.as_numeric_safe(out_row$digits_pct) %||% 1)
    ),

    # Dummy grid (EQ VAS / EORTC)
    dummy_visit_var  = out_row$dummy_visit_var  %||% NA_character_,
    dummy_visitn_var = out_row$dummy_visitn_var %||% NA_character_,
    dummy_visits     = .split_pipe(out_row$dummy_visits %||% ""),

    # Tipping point
    tp_penalty_values         = as.numeric(.split_pipe(out_row$tp_penalty_values %||% "")),
    tp_primary_visit          = out_row$tp_primary_visit %||% NA_character_,
    tp_penalty_arm            = out_row$tp_penalty_arm   %||% NA_character_,
    tp_penalty_mode           = out_row$tp_penalty_mode  %||% "multiply",
    tp_penalty_filter_dtype   = out_row$tp_penalty_filter_dtype   %||% NA_character_,
    tp_penalty_filter_impreas = out_row$tp_penalty_filter_impreas %||% NA_character_,
    tp_penalty_fichypo_var    = out_row$tp_penalty_fichypo_var    %||% "FICHYPO",
    tp_penalty_filter_fichypo = .split_pipe(out_row$tp_penalty_filter_fichypo %||% ""),
    tp_significance           = .as_numeric_safe(out_row$tp_significance %||% 0.025)
  )
}


#' Resolve spec from registry using output_id or idkey
#' @export
resolve_mmrm_spec <- function(output_id    = NULL,
                               idkey        = NULL,
                               out_registry) {
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

  spec <- .row_to_spec(as.list(hits[1, ]))
  message("Resolved: idkey=", spec$idkey,
          " | output_id=", spec$output_id,
          " | use_mi=",         spec$use_mi,
          " | use_dummy_grid=", spec$use_dummy_grid,
          " | use_tp=",         spec$use_tp,
          " | response_scale=", spec$response_scale)
  spec
}


# =============================================================================
# SECTION 5: VALIDATION
# v3: checks use_mi / use_dummy_grid / use_tp flags instead of method_id
# =============================================================================

validate_mmrm_spec <- function(spec) {
  req <- c("output_id", "dataset_name",
           "population_var", "population_value",
           "vars", "treatment_levels", "control_label",
           "visits_model", "digits",
           "use_mi", "use_dummy_grid", "use_tp", "response_scale")
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
         "' not in treatment_levels")

  if (isTRUE(spec$use_mi) &&
      (is.null(spec$vars$imputation) || is.na(spec$vars$imputation)))
    stop("[", spec$output_id, "] imputation_var required (use_mi detected TRUE)")

  if (isTRUE(spec$use_tp)) {
    if (length(spec$tp_penalty_values) == 0 || any(is.na(spec$tp_penalty_values)))
      stop("[", spec$output_id, "] tp_penalty_values required (use_tp detected TRUE)")
    if (is.na(spec$tp_primary_visit))
      stop("[", spec$output_id, "] tp_primary_visit required")
    if (is.na(spec$tp_penalty_arm) || !(spec$tp_penalty_arm %in% spec$treatment_levels))
      stop("[", spec$output_id, "] tp_penalty_arm must be in treatment_levels")
  }

  if (!spec$response_scale %in% c("identity", "logratio"))
    stop("[", spec$output_id, "] response_scale must be 'identity' or 'logratio'")

  invisible(spec)
}


# =============================================================================
# SECTION 6: DATA PREPARATION — SHARED BASE (unchanged)
# =============================================================================

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
    if (!is.null(spec$tp_penalty_filter_impreas) &&
        !is.na(spec$tp_penalty_filter_impreas)) "IMPREAS",
    if (!is.null(spec$tp_penalty_fichypo_var) &&
        !is.na(spec$tp_penalty_fichypo_var)) spec$tp_penalty_fichypo_var
  ))
  needed <- intersect(needed, names(data))

  ana <- data |>
    dplyr::select(dplyr::any_of(needed)) |>
    dplyr::distinct() |>
    dplyr::filter(.data[[spec$population_var]] == spec$population_value)

  if (.has_value(spec$pop_var2) && spec$pop_var2 %in% names(ana))
    ana <- dplyr::filter(ana, .data[[spec$pop_var2]] == spec$pop_val2)

  if (.has_value(spec$category_var) && spec$category_var %in% names(ana) &&
      .has_value(spec$category_value))
    ana <- dplyr::filter(ana, .data[[spec$category_var]] == spec$category_value)

  if (.has_value(spec$paramcd_filter) && spec$paramcd_filter_var %in% names(ana)) {
    pf <- .split_pipe(spec$paramcd_filter)
    if (length(pf) > 0)
      ana <- dplyr::filter(ana, .data[[spec$paramcd_filter_var]] %in% pf)
  }

  avisit_n_col <- spec$avisitn_var %||% "AVISITN"
  if (avisit_n_col %in% names(ana)) {
    if (!is.null(spec$avisitn_gt) && !is.na(spec$avisitn_gt)) {
      gt <- spec$avisitn_gt
      ana <- dplyr::filter(ana, .data[[avisit_n_col]] > gt)
    }
    if (!is.null(spec$avisitn_le) && !is.na(spec$avisitn_le)) {
      le <- spec$avisitn_le
      ana <- dplyr::filter(ana, .data[[avisit_n_col]] <= le)
    }
  }

  if (nrow(ana) == 0)
    stop("[", spec$output_id, "] 0 rows after filtering. Check population/category/paramcd filters.")

  src <- c(v$subject_id, v$subject_var, v$trt, v$trtn,
           v$visit, v$visitn, v$response, v$baseline)
  can <- c("USUBJID", "SUBJID", "TRT", "TRTN", "VISIT", "VISITN", "RESP", "BASE")
  rmap <- stats::setNames(src, can)
  rmap <- rmap[rmap %in% names(ana)]
  ana  <- dplyr::rename(ana, dplyr::any_of(rmap))

  if (.has_value(v$imputation) && v$imputation %in% names(ana))
    names(ana)[names(ana) == v$imputation] <- "IMPNUM"
  if (.has_value(v$dtype) && v$dtype %in% names(ana))
    names(ana)[names(ana) == v$dtype] <- "DTYPE"
  else if (!"DTYPE" %in% names(ana))
    ana$DTYPE <- NA_character_
  if (.has_value(v$param) && v$param %in% names(ana))
    names(ana)[names(ana) == v$param] <- "PARAM"

  for (i in seq_along(strata_src)) {
    old <- strata_src[i]; new <- paste0("STRATA", i)
    if (old %in% names(ana)) names(ana)[names(ana) == old] <- new
  }
  for (i in 1:3) {
    nm <- paste0("STRATA", i)
    if (!nm %in% names(ana)) ana[[nm]] <- NA_character_
  }

  ana
}


.compute_support_stats <- function(ana, spec) {
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

  dtype_ok <- spec$n_obs_dtype_values
  disp_vis <- spec$visits_display %||% spec$visits_model

  obs_n_pre <- ana |> dplyr::filter(VISIT %in% disp_vis, !is.na(RESP))

  if (!all(is.na(obs_n_pre$DTYPE)) && length(dtype_ok) > 0)
    obs_n_pre <- dplyr::filter(obs_n_pre, is.na(DTYPE) | DTYPE %in% dtype_ok)

  obs_n <- obs_n_pre |>
    dplyr::distinct(USUBJID, VISIT, VISITN, TRT, TRTN) |>
    dplyr::count(VISIT, VISITN, TRT, TRTN, name = "nobs") |>
    dplyr::arrange(match(as.character(VISIT), disp_vis), TRTN)

  list(subj_n = subj_n, obs_n = obs_n, strata_present = strata_present)
}


# =============================================================================
# SECTION 7: DATA PREP — MI (unchanged logic; also handles non-MI without grid)
# =============================================================================

prep_mi_visit <- function(data, spec) {
  ana <- .prep_base(data, spec)

  if (isTRUE(spec$use_mi)) {
    if (!"IMPNUM" %in% names(ana))
      stop("[", spec$output_id, "] IMPNUM not found. Check imputation_var in registry.")
    if (!is.na(spec$imp_max))
      ana <- dplyr::filter(ana, IMPNUM <= spec$imp_max)
  }

  if (length(spec$visit_exclude) > 0)
    ana <- dplyr::filter(ana, !VISIT %in% spec$visit_exclude)
  if (length(spec$visits_model) > 0)
    ana <- dplyr::filter(ana, VISIT %in% spec$visits_model)

  visit_levels <- if (length(spec$visits_model) > 0) {
    spec$visits_model
  } else {
    ana |> dplyr::distinct(VISIT, VISITN) |> dplyr::arrange(VISITN) |>
      dplyr::pull(VISIT) |> as.character()
  }
  if (length(spec$visits_display) == 0) spec$visits_display <- visit_levels

  ana <- ana |>
    dplyr::mutate(TRT   = factor(TRT,   levels = spec$treatment_levels),
                  VISIT = factor(VISIT, levels = visit_levels))

  if (isTRUE(spec$use_mi))
    ana <- dplyr::mutate(ana, IMPNUM = as.integer(IMPNUM))

  ana <- dplyr::arrange(ana,
    if (isTRUE(spec$use_mi)) IMPNUM else NULL, VISITN, TRTN, USUBJID)

  sup <- .compute_support_stats(ana, spec)
  c(list(ana = ana), sup,
    list(meta = list(output_id    = spec$output_id,
                     dataset_name = spec$dataset_name,
                     idkey        = spec$idkey)))
}


# =============================================================================
# SECTION 8: DATA PREP — OBSERVED + DUMMY GRID (unchanged logic)
# =============================================================================

prep_obs_dummy_visit <- function(data, spec) {
  spec_no_vm <- spec
  spec_no_vm$visits_model  <- character(0)
  spec_no_vm$visits_display <- character(0)
  spec_no_vm$visit_exclude  <- character(0)

  base_raw <- .prep_base(data, spec_no_vm)
  baseline_labels <- c("Baseline", "BASELINE", "baseline")

  base_records <- base_raw |>
    dplyr::filter(!is.na(BASE),
                  VISIT %in% baseline_labels |
                  (!is.na(VISITN) & VISITN == min(VISITN[VISIT %in% baseline_labels],
                                                   na.rm = TRUE))) |>
    dplyr::distinct(USUBJID, SUBJID, TRT, TRTN, BASE,
                    dplyr::across(dplyr::starts_with("STRATA")))

  if (nrow(base_records) == 0) {
    message("[", spec$output_id, "] No 'Baseline' visit found; using all subjects with non-missing BASE.")
    base_records <- base_raw |>
      dplyr::filter(!is.na(BASE)) |>
      dplyr::distinct(USUBJID, SUBJID, TRT, TRTN, BASE,
                      dplyr::across(dplyr::starts_with("STRATA")))
  }
  if (nrow(base_records) == 0)
    stop("[", spec$output_id, "] No subjects with non-missing BASE found.")

  obs_records <- base_raw |>
    dplyr::filter(!is.na(VISITN), !VISIT %in% baseline_labels, VISIT != "EOS") |>
    dplyr::select(USUBJID, dplyr::any_of(c("VISIT", "RESP", "DTYPE", "PARAM")))

  dummy_visits <- if (length(spec$dummy_visits) > 0) spec$dummy_visits else spec$visits_model

  actual_visitn <- base_raw |>
    dplyr::distinct(VISIT, VISITN) |>
    dplyr::filter(!is.na(VISITN)) |>
    dplyr::mutate(VISIT = as.character(VISIT))

  visit_grid <- tibble::tibble(VISIT = dummy_visits) |>
    dplyr::left_join(actual_visitn, by = "VISIT")

  has_param <- "PARAM" %in% names(base_raw) && length(spec$param_values) > 0

  if (has_param) {
    subj_param <- base_records |>
      dplyr::inner_join(
        base_raw |> dplyr::distinct(USUBJID, PARAM) |>
          dplyr::filter(PARAM %in% spec$param_values),
        by = "USUBJID"
      )
    grid <- tidyr::crossing(subj_param, visit_grid)
  } else {
    grid <- tidyr::crossing(base_records, visit_grid)
  }

  join_cols <- intersect(c("USUBJID", "VISIT", "PARAM"), names(obs_records))
  ana <- dplyr::left_join(grid, obs_records, by = join_cols) |>
    dplyr::mutate(TRT   = factor(TRT,   levels = spec$treatment_levels),
                  VISIT = factor(VISIT, levels = spec$visits_model)) |>
    dplyr::arrange(VISITN, TRTN, USUBJID)

  if (!"DTYPE" %in% names(ana)) ana$DTYPE <- NA_character_

  sup <- .compute_support_stats(ana, spec)
  c(list(ana = ana), sup,
    list(meta = list(output_id    = spec$output_id,
                     has_param    = has_param,
                     dataset_name = spec$dataset_name,
                     idkey        = spec$idkey)))
}


# =============================================================================
# SECTION 9: DATA PREP — TIPPING POINT (unchanged)
# =============================================================================

.apply_tp_penalty <- function(ana, penalty, spec) {
  mode <- spec$tp_penalty_mode %||% "multiply"

  is_pen_arm <- as.character(ana$TRT) == spec$tp_penalty_arm
  dtype_col  <- "DTYPE"
  is_dtype <- if (.has_value(spec$tp_penalty_filter_dtype) && dtype_col %in% names(ana))
    ana[[dtype_col]] == spec$tp_penalty_filter_dtype
  else rep(TRUE, nrow(ana))

  impreas_col <- spec$tp_impreas_var %||% "IMPREAS"
  is_impreas <- if (.has_value(spec$tp_penalty_filter_impreas) && impreas_col %in% names(ana))
    ana[[impreas_col]] == spec$tp_penalty_filter_impreas
  else rep(TRUE, nrow(ana))

  fichypo_col <- spec$tp_penalty_fichypo_var %||% "FICHYPO"
  is_fichypo <- if (length(spec$tp_penalty_filter_fichypo) > 0 && fichypo_col %in% names(ana))
    ana[[fichypo_col]] %in% spec$tp_penalty_filter_fichypo
  else rep(TRUE, nrow(ana))

  pen_rows <- is_pen_arm & is_dtype & is_impreas & is_fichypo
  if (!any(pen_rows))
    warning("[", spec$output_id, "] penalty=", penalty, ": no rows matched filter")

  if (mode == "multiply") {
    if ("AVAL" %in% names(ana)) {
      ana$AVAL[pen_rows] <- ana$AVAL[pen_rows] * penalty
      ana$RESP[pen_rows] <- ana$AVAL[pen_rows] - ana$BASE[pen_rows]
    } else {
      aval_new <- (ana$RESP[pen_rows] + ana$BASE[pen_rows]) * penalty
      ana$RESP[pen_rows] <- aval_new - ana$BASE[pen_rows]
    }
  } else {
    ana$RESP[pen_rows] <- ana$RESP[pen_rows] + penalty
  }
  ana
}

prep_tp_penalty <- function(data, spec) prep_mi_visit(data, spec)


# =============================================================================
# SECTION 10: SHARED MODEL FITTING (unchanged)
# =============================================================================

.build_cov_term <- function(cov = c("us", "ar1", "cs")) {
  switch(match.arg(cov),
    us = "us(VISIT | USUBJID)", ar1 = "ar1(VISIT | USUBJID)", cs = "cs(VISIT | USUBJID)")
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
  fit  <- mmrm::mmrm(formula = form, data = dat_imp, reml = TRUE,
                     control = mmrm::mmrm_control(method = "Kenward-Roger",
                                                   drop_visit_levels = FALSE))
  emm     <- emmeans::emmeans(fit, specs = ~ TRT | VISIT)
  ref_idx <- which(levels(dat_imp$TRT) == spec$control_label)

  lsm <- as.data.frame(summary(emm, infer = TRUE, level = 0.95)) |>
    dplyr::transmute(VISIT = as.character(VISIT), TRT = as.character(TRT),
                     estimate = emmean, SE = SE, lower = lower.CL, upper = upper.CL)

  diff <- as.data.frame(
    summary(emmeans::contrast(emm, method = "trt.vs.ctrl", ref = ref_idx),
            infer = TRUE, level = 0.95)
  ) |>
    dplyr::transmute(VISIT = as.character(VISIT),
                     comparison = spec$comparison_label,
                     estimate = estimate, SE = SE,
                     lower = lower.CL, upper = upper.CL,
                     p_two_sided = p.value)

  list(lsm = lsm, diff = diff)
}

.apply_fallback_loop <- function(dat_imp, spec, strata_present) {
  for (plan in .FALLBACK_PLANS) {
    res <- tryCatch(.fit_one_imp(dat_imp, spec, plan, strata_present),
                    error = function(e) NULL)
    if (!is.null(res)) return(list(res = res, plan = plan))
  }
  list(res = NULL, plan = NULL)
}

.map_imps <- function(imputations, fn, parallel, n_workers) {
  if (parallel && requireNamespace("furrr", quietly = TRUE)) {
    furrr::plan(furrr::multisession, workers = n_workers)
    furrr::future_imap(imputations, fn)
  } else {
    purrr::imap(imputations, fn)
  }
}


# =============================================================================
# SECTION 11: RUBIN'S RULES + FORMATTERS (unchanged)
# =============================================================================

rubin_combine <- function(df, by_cols, est_col = "estimate", se_col = "SE",
                           conf_level = 0.95) {
  alpha <- 1 - conf_level
  df |>
    dplyr::group_by(dplyr::across(dplyr::all_of(by_cols))) |>
    dplyr::summarise(
      m    = dplyr::n(),
      qbar = mean(.data[[est_col]], na.rm = TRUE),
      ubar = mean(.data[[se_col]]^2, na.rm = TRUE),
      b    = { vv <- stats::var(.data[[est_col]], na.rm = TRUE); if (is.na(vv)) 0 else vv },
      .groups = "drop"
    ) |>
    dplyr::mutate(
      tvar        = ubar + (1 + 1/pmax(m, 1)) * b,
      SE          = sqrt(tvar),
      df_mi       = dplyr::case_when(m <= 1 | b <= 0 ~ 1e6,
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

.one_sided_p <- function(estimate, p_two_sided, pvalue_rule) {
  dplyr::case_when(
    pvalue_rule == "better_positive" & estimate > 0 ~ p_two_sided / 2,
    pvalue_rule == "better_positive" & estimate < 0 ~ 1 - p_two_sided / 2,
    pvalue_rule == "better_negative" & estimate < 0 ~ p_two_sided / 2,
    pvalue_rule == "better_negative" & estimate > 0 ~ 1 - p_two_sided / 2,
    TRUE ~ 0.5
  )
}

# Emits 3 p-value stat_name rows per visit/penalty (unchanged from v2)
.ard_pvalue_block <- function(diff_d, spec, param = NA_character_,
                               group1_dim  = "VISIT",
                               group1_col  = "VISIT",
                               ord1_levels = NULL,
                               ord_offset  = 100L) {
  prule        <- spec$pvalue_rule %||% "better_positive"
  pv_vis       <- spec$pvalue_display_visits
  d_p          <- spec$digits$p
  default_stat <- switch(prule,
    better_positive = "p_one_pos",
    better_negative = "p_one_neg",
    two_sided       = "p_two_sided",
    "p_two_sided")

  diff_d |>
    dplyr::mutate(
      .g1_val   = as.character(.data[[group1_col]]),
      p_one_pos = dplyr::case_when(
        estimate > 0 ~ p_two_sided / 2, estimate < 0 ~ 1 - p_two_sided / 2, TRUE ~ 0.5),
      p_one_neg = dplyr::case_when(
        estimate < 0 ~ p_two_sided / 2, estimate > 0 ~ 1 - p_two_sided / 2, TRUE ~ 0.5)
    ) |>
    tidyr::pivot_longer(cols = c(p_two_sided, p_one_pos, p_one_neg),
                        names_to = "stat_name", values_to = "stat_num") |>
    dplyr::transmute(
      output_id      = spec$output_id,
      response_scale = spec$response_scale,
      param_var      = spec$vars$param %||% NA_character_,
      param          = param,
      row_type       = "comparison",
      group1         = group1_dim,
      group1_level   = .g1_val,
      group2         = "COMPARISON",
      group2_level   = comparison,
      stat_name,
      stat_label = dplyr::case_match(stat_name,
        "p_two_sided" ~ "2-sided p-value",
        "p_one_pos"   ~ "1-sided p-value (better=positive)",
        "p_one_neg"   ~ "1-sided p-value (better=negative)"),
      stat_num,
      stat_chr = format_p(stat_num, d_p),
      pvalue_display_default = (stat_name == default_stat),
      pvalue_visit_default   = if (length(pv_vis) > 0) .g1_val %in% as.character(pv_vis) else TRUE,
      penalty_term = NA_real_,
      ord1 = if (!is.null(ord1_levels)) match(.g1_val, as.character(ord1_levels)) else NA_integer_,
      ord2 = dplyr::case_match(stat_name,
        "p_two_sided" ~ as.integer(ord_offset),
        "p_one_pos"   ~ as.integer(ord_offset + 1L),
        "p_one_neg"   ~ as.integer(ord_offset + 2L))
    )
}


# =============================================================================
# SECTION 12: ARD ASSEMBLY — COUNTS (uses response_scale instead of method_id)
# =============================================================================

.ard_counts <- function(prep, spec, param = NA_character_, group1_dim = "VISIT") {
  vd <- spec$visits_display %||% spec$visits_model

  ard_bigN <- prep$subj_n |>
    dplyr::transmute(
      output_id = spec$output_id, response_scale = spec$response_scale,
      param_var = spec$vars$param %||% NA_character_, param = param,
      row_type = "arm", group1 = group1_dim, group1_level = NA_character_,
      group2 = "TRT", group2_level = as.character(TRT),
      stat_name = "bigN", stat_label = "N",
      stat_num = bigN, stat_chr = as.character(bigN),
      penalty_term = NA_real_, ord1 = 0L, ord2 = as.integer(TRTN)
    )

  ard_nobs <- prep$obs_n |>
    dplyr::transmute(
      output_id = spec$output_id, response_scale = spec$response_scale,
      param_var = spec$vars$param %||% NA_character_, param = param,
      row_type = "arm", group1 = group1_dim, group1_level = as.character(VISIT),
      group2 = "TRT", group2_level = as.character(TRT),
      stat_name = "nobs", stat_label = "n",
      stat_num = nobs, stat_chr = as.character(nobs),
      penalty_term = NA_real_,
      ord1 = match(as.character(VISIT), vd), ord2 = as.integer(TRTN)
    )

  dplyr::bind_rows(ard_bigN, ard_nobs)
}


# =============================================================================
# SECTION 13: ARD ASSEMBLY — IDENTITY SCALE STATS
# v3: also used for the raw log-scale rows in logratio analyses
#     stat_label adapts to response_scale so user knows what scale they're seeing
# =============================================================================

.ard_identity_rows <- function(prep, lsm_comb, diff_comb, spec,
                                param = NA_character_) {
  d_est <- spec$digits$est
  vd    <- spec$visits_display %||% spec$visits_model

  lsm_d  <- dplyr::filter(lsm_comb,  VISIT %in% vd)
  diff_d <- dplyr::filter(diff_comb, VISIT %in% vd)

  is_log <- spec$response_scale == "logratio"

  add_meta <- function(df)
    dplyr::mutate(df,
      output_id = spec$output_id, response_scale = spec$response_scale,
      param_var = spec$vars$param %||% NA_character_, param = param,
      penalty_term = NA_real_)

  ard_lsm <- add_meta(
    lsm_d |> dplyr::left_join(prep$subj_n |> dplyr::select(TRT, TRTN), by = "TRT")
  ) |>
    dplyr::transmute(
      output_id, response_scale, param_var, param, penalty_term,
      row_type = "arm",
      group1 = "VISIT", group1_level = VISIT,
      group2 = "TRT",   group2_level = as.character(TRT),
      stat_name = "adj_mean_ci",
      stat_label = if (is_log) "Log-scale adjusted mean (95% CI)"
                   else         "Adjusted mean (95% CI)",
      stat_num = estimate,
      stat_chr = format_ci(estimate, lower, upper, d_est),
      ord1 = match(VISIT, vd), ord2 = as.integer(TRTN)
    )

  ard_diff <- add_meta(diff_d) |>
    dplyr::transmute(
      output_id, response_scale, param_var, param, penalty_term,
      row_type = "comparison",
      group1 = "VISIT",      group1_level = VISIT,
      group2 = "COMPARISON", group2_level = comparison,
      stat_name = "adj_diff_ci",
      stat_label = if (is_log) "Log-scale adjusted mean difference (95% CI)"
                   else         "Adjusted mean difference (95% CI)",
      stat_num = estimate,
      stat_chr = format_ci(estimate, lower, upper, d_est),
      ord1 = match(VISIT, vd), ord2 = 99L
    )

  list(lsm = ard_lsm, diff = ard_diff, diff_d = diff_d)
}


# =============================================================================
# SECTION 14: ARD ASSEMBLY — LOGRATIO BACK-TRANSFORM STATS
# v3: geo_mean_ci / geo_ratio_ci / pct_reduction_ci (appended AFTER identity rows)
# =============================================================================

.ard_logratio_rows <- function(prep, lsm_comb, diff_comb, spec,
                                param = NA_character_) {
  d_est  <- spec$digits$est
  d_pct  <- spec$digits$pct
  vd     <- spec$visits_display %||% spec$visits_model

  lsm_d  <- dplyr::filter(lsm_comb,  VISIT %in% vd)
  diff_d <- dplyr::filter(diff_comb, VISIT %in% vd)

  lsm_bt <- lsm_d |>
    dplyr::mutate(geo_mean = exp(estimate), geo_lcl = exp(lower), geo_ucl = exp(upper))

  diff_bt <- diff_d |>
    dplyr::mutate(
      geo_ratio   = exp(estimate),
      geo_r_lcl   = exp(lower),
      geo_r_ucl   = exp(upper),
      pct_red     = (1 - exp(estimate)) * 100,
      pct_red_lcl = (1 - exp(upper))    * 100,
      pct_red_ucl = (1 - exp(lower))    * 100
    )

  add_meta <- function(df)
    dplyr::mutate(df,
      output_id = spec$output_id, response_scale = spec$response_scale,
      param_var = spec$vars$param %||% NA_character_, param = param,
      penalty_term = NA_real_)

  ard_geo_mean <- add_meta(
    lsm_bt |> dplyr::left_join(prep$subj_n |> dplyr::select(TRT, TRTN), by = "TRT")
  ) |>
    dplyr::transmute(
      output_id, response_scale, param_var, param, penalty_term,
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
      output_id, response_scale, param_var, param, penalty_term,
      row_type = "comparison",
      group1 = "VISIT",      group1_level = VISIT,
      group2 = "COMPARISON", group2_level = comparison,
      stat_name = "geo_ratio_ci",
      stat_label = "Geometric mean ratio (95% CI)",
      stat_num = geo_ratio,
      stat_chr = format_ci(geo_ratio, geo_r_lcl, geo_r_ucl, d_est),
      ord1 = match(VISIT, vd), ord2 = 100L
    )

  ard_pct_red <- add_meta(diff_bt) |>
    dplyr::transmute(
      output_id, response_scale, param_var, param, penalty_term,
      row_type = "comparison",
      group1 = "VISIT",      group1_level = VISIT,
      group2 = "COMPARISON", group2_level = comparison,
      stat_name = "pct_reduction_ci",
      stat_label = "% Reduction (95% CI)",
      stat_num = pct_red,
      stat_chr = format_ci(pct_red, pct_red_lcl, pct_red_ucl, d_pct),
      ord1 = match(VISIT, vd), ord2 = 101L
    )

  list(geo_mean = ard_geo_mean, geo_ratio = ard_geo_ratio, pct_red = ard_pct_red)
}


# =============================================================================
# SECTION 15: ARD ASSEMBLY — UNIFIED ASSEMBLER
# v3: always outputs all applicable stats; user filters $ard for what they need
#
#   Always:   bigN, nobs, adj_mean_ci, adj_diff_ci
#   logratio: + geo_mean_ci, geo_ratio_ci, pct_reduction_ci
#   pvalue:   + p_two_sided, p_one_pos, p_one_neg  (when include_pvalue=TRUE)
# =============================================================================

.assemble_ard <- function(prep, lsm_comb, diff_comb, spec,
                           param = NA_character_) {
  vd <- spec$visits_display %||% spec$visits_model

  # ── Counts ────────────────────────────────────────────────────────────────
  rows <- list(counts = .ard_counts(prep, spec, param))

  # ── Identity / log-scale stats (always) ──────────────────────────────────
  id_rows <- .ard_identity_rows(prep, lsm_comb, diff_comb, spec, param)
  rows$adj_lsm  <- id_rows$lsm
  rows$adj_diff <- id_rows$diff
  diff_d        <- id_rows$diff_d   # filtered to visits_display

  # ── Logratio back-transform (when response_scale = "logratio") ────────────
  if (spec$response_scale == "logratio") {
    lr <- .ard_logratio_rows(prep, lsm_comb, diff_comb, spec, param)
    rows$geo_mean  <- lr$geo_mean
    rows$geo_ratio <- lr$geo_ratio
    rows$pct_red   <- lr$pct_red
    pval_ord_offset <- 102L   # after pct_reduction ord2=101
  } else {
    pval_ord_offset <- 100L
  }

  # ── P-values (all 3 variants, when include_pvalue = TRUE) ────────────────
  if (isTRUE(spec$include_pvalue)) {
    rows$pvalues <- .ard_pvalue_block(
      diff_d, spec, param,
      group1_dim  = "VISIT",
      group1_col  = "VISIT",
      ord1_levels = vd,
      ord_offset  = pval_ord_offset
    )
  }

  dplyr::bind_rows(rows) |> dplyr::arrange(ord1, ord2, stat_name)
}


# =============================================================================
# SECTION 16: ARD ASSEMBLY — TIPPING POINT
# =============================================================================

.assemble_ard_tp <- function(prep, tp_results, spec) {
  d_est  <- spec$digits$est
  sig    <- spec$tp_significance %||% 0.025
  pv     <- spec$tp_primary_visit
  prule  <- spec$pvalue_rule %||% "better_positive"
  pen_ord <- sort(unique(tp_results$penalty))

  tp_ann <- tp_results |>
    dplyr::arrange(penalty) |>
    dplyr::mutate(
      p_one        = .one_sided_p(estimate, p_two_sided, prule),
      sig_flag     = p_one < sig,
      tipping_flag = !sig_flag & dplyr::lag(sig_flag, default = TRUE)
    )

  add_meta <- function(df)
    dplyr::mutate(df,
      output_id = spec$output_id, response_scale = spec$response_scale,
      param_var = NA_character_, param = NA_character_)

  ard_bigN <- prep$subj_n |>
    dplyr::transmute(
      output_id = spec$output_id, response_scale = spec$response_scale,
      param_var = NA_character_, param = NA_character_,
      row_type = "arm", group1 = "PENALTY", group1_level = NA_character_,
      group2 = "TRT", group2_level = as.character(TRT),
      stat_name = "bigN", stat_label = "N",
      stat_num = bigN, stat_chr = as.character(bigN),
      penalty_term = NA_real_, ord1 = 0L, ord2 = as.integer(TRTN)
    )

  ard_nobs <- prep$obs_n |>
    dplyr::filter(as.character(VISIT) == pv) |>
    dplyr::transmute(
      output_id = spec$output_id, response_scale = spec$response_scale,
      param_var = NA_character_, param = NA_character_,
      row_type = "arm", group1 = "PENALTY", group1_level = NA_character_,
      group2 = "TRT", group2_level = as.character(TRT),
      stat_name = "nobs", stat_label = paste0("n (", pv, ")"),
      stat_num = nobs, stat_chr = as.character(nobs),
      penalty_term = NA_real_, ord1 = 0L, ord2 = as.integer(TRTN)
    )

  ard_diff <- add_meta(tp_ann) |>
    dplyr::transmute(
      output_id, response_scale, param_var, param,
      row_type = "comparison",
      group1 = "PENALTY", group1_level = as.character(penalty),
      group2 = "COMPARISON", group2_level = comparison,
      stat_name = "adj_diff_ci",
      stat_label = "Adjusted mean difference (95% CI)",
      stat_num = estimate,
      stat_chr = format_ci(estimate, lower, upper, d_est),
      penalty_term = penalty, ord1 = match(penalty, pen_ord), ord2 = 99L
    )

  # All 3 p-value variants by penalty
  ard_pval <- .ard_pvalue_block(
    tp_ann, spec,
    group1_dim  = "PENALTY",
    group1_col  = "penalty",
    ord1_levels = as.character(pen_ord),
    ord_offset  = 100L
  ) |>
    dplyr::left_join(
      tp_ann |> dplyr::transmute(group1_level = as.character(penalty), .pt = penalty),
      by = "group1_level"
    ) |>
    dplyr::mutate(penalty_term = .pt) |>
    dplyr::select(-.pt)

  ard_tp_flag <- add_meta(dplyr::filter(tp_ann, tipping_flag)) |>
    dplyr::transmute(
      output_id, response_scale, param_var, param,
      row_type = "comparison",
      group1 = "PENALTY", group1_level = as.character(penalty),
      group2 = "COMPARISON", group2_level = comparison,
      stat_name = "tipping_point",
      stat_label = paste0("Tipping point (1-sided alpha=", sig, ")"),
      stat_num = 1L, stat_chr = paste0("penalty=", penalty),
      penalty_term = penalty, ord1 = match(penalty, pen_ord), ord2 = 103L
    )

  dplyr::bind_rows(ard_bigN, ard_nobs, ard_diff, ard_pval, ard_tp_flag) |>
    dplyr::arrange(ord1, ord2, stat_name)
}


# =============================================================================
# SECTION 17: UNIFIED RUNNER
# v3: one .run_mmrm() dispatches internally on use_mi / use_dummy_grid / use_tp
# =============================================================================

#' Unified MMRM runner — dispatches on auto-detected flags
.run_mmrm <- function(data, spec, parallel = FALSE, n_workers = 4, debug = FALSE) {
  pfx <- paste0("[", spec$output_id, "] ")
  message(pfx,
    if (spec$use_mi) "MI" else "OBS", " | ",
    spec$response_scale,
    if (spec$use_dummy_grid) " | dummy_grid" else "",
    if (spec$use_tp) " | TP" else "")

  # ── Step 1: Prep ────────────────────────────────────────────────────────────
  message(pfx, "Step 1: Prep...")
  prep <- if (spec$use_dummy_grid) {
    prep_obs_dummy_visit(data, spec)
  } else {
    prep_mi_visit(data, spec)
  }

  # ── TP path ─────────────────────────────────────────────────────────────────
  if (spec$use_tp) {
    n_pen <- length(spec$tp_penalty_values)
    n_imp <- max(prep$ana$IMPNUM, na.rm = TRUE)
    message(pfx, "Step 2: TP fitting (", n_pen, " penalties × ", n_imp, " imps)...")

    tp_results <- purrr::map(spec$tp_penalty_values, function(pen) {
      message("  penalty = ", pen)
      ana_pen   <- .apply_tp_penalty(prep$ana, pen, spec)
      diff_list <- purrr::imap(split(ana_pen, ana_pen$IMPNUM), function(d, id) {
        r <- .apply_fallback_loop(d, spec, prep$strata_present)
        if (is.null(r$res)) { warning(pfx, "IMPNUM=", id, " penalty=", pen, ": failed"); return(NULL) }
        dplyr::filter(r$res$diff, VISIT == spec$tp_primary_visit) |>
          dplyr::mutate(IMPNUM = as.integer(id))
      })
      valid <- dplyr::bind_rows(purrr::compact(diff_list))
      if (nrow(valid) == 0) { warning(pfx, "penalty=", pen, ": no valid results"); return(NULL) }
      rubin_combine(dplyr::select(valid, -p_two_sided),
                    by_cols = c("VISIT", "comparison")) |>
        dplyr::mutate(penalty = pen)
    })

    tp_all <- dplyr::bind_rows(purrr::compact(tp_results))
    if (nrow(tp_all) == 0) stop(pfx, "No TP results — check tp_penalty_filter_* in registry")

    message(pfx, "Step 3: Assembling TP ARD...")
    ard <- .assemble_ard_tp(prep, tp_all, spec)

    tp_value <- tp_all |>
      dplyr::arrange(penalty) |>
      dplyr::mutate(p_one = .one_sided_p(estimate, p_two_sided,
                                          spec$pvalue_rule %||% "better_positive")) |>
      dplyr::filter(p_one >= (spec$tp_significance %||% 0.025)) |>
      dplyr::slice(1) |> dplyr::pull(penalty)

    out <- list(ard = ard, subj_n = prep$subj_n, obs_n = prep$obs_n,
                diff = tp_all,
                meta = c(prep$meta, list(n_imp = n_imp, n_penalties = n_pen,
                                         tipping_point = tp_value, run_time = Sys.time())))
    if (debug) out$ana <- prep$ana
    message(pfx, "Tipping point at penalty = ", tp_value, ". Done.")
    return(out)
  }

  # ── Standard path ────────────────────────────────────────────────────────────
  params <- if (length(spec$param_values) > 0) spec$param_values else NA_character_

  if (spec$use_mi) {
    # MI: loop over imputations + Rubin's rules
    n_imp <- max(prep$ana$IMPNUM, na.rm = TRUE)
    message(pfx, "Step 2: MI fitting (", n_imp, " imps)...")

    fits <- .map_imps(split(prep$ana, prep$ana$IMPNUM),
      function(d, id) {
        r <- .apply_fallback_loop(d, spec, prep$strata_present)
        if (is.null(r$res)) stop(pfx, "All fallbacks failed IMPNUM=", id)
        list(lsm  = dplyr::mutate(r$res$lsm,  IMPNUM = as.integer(id)),
             diff = dplyr::mutate(r$res$diff, IMPNUM = as.integer(id)),
             plan = tibble::tibble(IMPNUM = as.integer(id),
                                   covariance = r$plan$covariance,
                                   use_strata = r$plan$use_strata,
                                   use_visit_base = r$plan$use_visit_base))
      }, parallel, n_workers)

    message(pfx, "Step 3: Rubin's rules...")
    lsm_comb <- rubin_combine(dplyr::bind_rows(purrr::map(fits, "lsm")),
                               by_cols = c("VISIT", "TRT")) |>
      dplyr::mutate(TRT = factor(TRT, levels = spec$treatment_levels)) |>
      dplyr::arrange(match(VISIT, spec$visits_model), TRT)
    diff_comb <- rubin_combine(
      dplyr::bind_rows(purrr::map(fits, "diff")) |> dplyr::select(-p_two_sided),
      by_cols = c("VISIT", "comparison")
    ) |> dplyr::arrange(match(VISIT, spec$visits_model))

    # For avisitn_range (urine): derive visit order from data when visits_model empty
    if (length(spec$visits_model) == 0) {
      vo <- prep$obs_n |> dplyr::distinct(VISIT, VISITN) |> dplyr::arrange(VISITN) |>
        dplyr::pull(VISIT) |> as.character()
      spec$visits_model   <- vo
      spec$visits_display <- vo
      lsm_comb  <- dplyr::arrange(lsm_comb,  match(VISIT, vo), TRT)
      diff_comb <- dplyr::arrange(diff_comb, match(VISIT, vo))
    }

    message(pfx, "Step 4: Assembling ARD (", spec$response_scale, ")...")
    ard <- dplyr::bind_rows(purrr::map(params, function(param) {
      lp <- if (!is.na(param) && "PARAM" %in% names(lsm_comb))
        dplyr::filter(lsm_comb,  PARAM == param) else lsm_comb
      dp <- if (!is.na(param) && "PARAM" %in% names(diff_comb))
        dplyr::filter(diff_comb, PARAM == param) else diff_comb
      .assemble_ard(prep, lp, dp, spec, param)
    }))

    fit_plan <- if (debug) dplyr::bind_rows(purrr::map(fits, "plan")) else NULL
    out <- list(ard = ard, subj_n = prep$subj_n, obs_n = prep$obs_n,
                lsm = lsm_comb, diff = diff_comb,
                meta = c(prep$meta, list(n_imp = n_imp, run_time = Sys.time())))
    if (debug) { out$ana <- prep$ana; if (!is.null(fit_plan)) out$fit_plan <- fit_plan }

  } else {
    # Observed single fit per param (EQ VAS / EORTC)
    n_imp <- 0L
    message(pfx, "Step 2: Observed fit (", length(params), " param(s))...")

    ard <- dplyr::bind_rows(purrr::map(params, function(param) {
      ana_p <- if (!is.na(param) && "PARAM" %in% names(prep$ana))
        dplyr::filter(prep$ana, PARAM == param) else prep$ana
      ana_p <- ana_p |>
        dplyr::mutate(TRT   = factor(TRT,   levels = spec$treatment_levels),
                      VISIT = factor(VISIT, levels = spec$visits_model))
      ana_model <- dplyr::filter(ana_p, !is.na(RESP))
      if (nrow(ana_model) == 0)
        stop(pfx, "No observed RESP rows for param=", param)
      message("  observed visits: ",
              paste(sort(as.character(unique(ana_model$VISIT))), collapse = ", "))
      r <- .apply_fallback_loop(ana_model, spec, prep$strata_present)
      if (is.null(r$res)) stop(pfx, "All fallbacks failed (param=", param, ")")
      lsm_p  <- dplyr::mutate(r$res$lsm, TRT = factor(TRT, levels = spec$treatment_levels))
      .assemble_ard(prep, lsm_p, r$res$diff, spec, param)
    }))

    out <- list(ard = ard, subj_n = prep$subj_n, obs_n = prep$obs_n,
                meta = c(prep$meta, list(n_imp = n_imp, n_params = length(params),
                                         run_time = Sys.time())))
    if (debug) out$ana <- prep$ana
  }

  message(pfx, "Done.")
  out
}

# Backward-compatible wrappers (call .run_mmrm internally)
run_family_a <- function(data, spec, parallel = FALSE, n_workers = 4, debug = FALSE)
  .run_mmrm(data, spec, parallel = parallel, n_workers = n_workers, debug = debug)
run_family_b <- function(data, spec, parallel = FALSE, n_workers = 4, debug = FALSE)
  .run_mmrm(data, spec, parallel = parallel, n_workers = n_workers, debug = debug)
run_family_c <- function(data, spec, parallel = FALSE, n_workers = 4, debug = FALSE)
  .run_mmrm(data, spec, parallel = parallel, n_workers = n_workers, debug = debug)
run_family_d <- function(data, spec, parallel = FALSE, n_workers = 4, debug = FALSE)
  .run_mmrm(data, spec, parallel = parallel, n_workers = n_workers, debug = debug)


# =============================================================================
# SECTION 18: PUBLIC API
# v3: no meth_registry parameter; spec_overrides for call-time tweaks
# =============================================================================

#' Create MMRM ARD for one output
#'
#' USAGE (unchanged from v1 for trail programmer):
#'   out_reg <- load_mmrm_registry("eff_mmrm_registry.csv")
#'   res <- create_ard_mmrm("14.2-4.1", data = adfacmi, out_registry = out_reg)
#'   res$ard   # filter for what you need
#'
#' FILTERING THE ARD:
#'   # Display table (identity outputs)
#'   res$ard |> filter(stat_name %in% c("bigN","nobs","adj_mean_ci","adj_diff_ci"))
#'
#'   # Display table (logratio outputs)
#'   res$ard |> filter(stat_name %in% c("bigN","nobs","geo_mean_ci","pct_reduction_ci"))
#'
#'   # Recommended p-value (equiv to old pvalue_1sided)
#'   res$ard |> filter(pvalue_display_default, pvalue_visit_default)
#'
#'   # Force two-sided p-value
#'   res$ard |> filter(stat_name == "p_two_sided", pvalue_visit_default)
#'
#' CALL-TIME OVERRIDES (no CSV edit needed):
#'   create_ard_mmrm("14.2-4.1", data = adfacmi, out_registry = out_reg,
#'     spec_overrides = list(pvalue_display_visits = "Month 24",
#'                           visits_display = "Month 6|Month 9|Month 24"))
#'
#' @param output_id      character — e.g. "14.2-4.1"
#' @param idkey          character — e.g. "PTL0035"
#' @param data           data.frame — ADaM dataset
#' @param out_registry   tibble — from load_mmrm_registry()
#' @param out_registry_path  character — path if out_registry not pre-loaded
#' @param spec_overrides named list — call-time registry field overrides
#' @param imp_max        integer — shortcut for quick testing
#' @param parallel       logical — use furrr for parallel MI
#' @param n_workers      integer — parallel workers
#' @param debug          logical — include $ana + $fit_plan in return
#' @param trakdata       character — path triggers Phase 2 TrakData attachment
#'
#' @return list: $ard $subj_n $obs_n $lsm $diff $meta
#' @export
create_ard_mmrm <- function(output_id         = NULL,
                             idkey             = NULL,
                             data,
                             out_registry      = NULL,
                             out_registry_path = NULL,
                             spec_overrides    = list(),
                             imp_max           = NULL,
                             parallel          = FALSE,
                             n_workers         = 4,
                             debug             = FALSE,
                             trakdata          = NULL) {

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
      stop("Registry not found. Provide out_registry= or out_registry_path=")
    out_registry <- load_mmrm_registry(path)
  }

  spec <- resolve_mmrm_spec(output_id    = output_id,
                             idkey        = idkey,
                             out_registry = out_registry)

  if (length(spec_overrides) > 0) {
    spec <- .apply_spec_overrides(spec, spec_overrides)
    message("[", spec$output_id, "] spec_overrides applied: ",
            paste(names(spec_overrides), collapse = ", "))
  }

  if (!is.null(imp_max)) {
    spec$imp_max <- as.integer(imp_max)
    message("[", spec$output_id, "] imp_max=", imp_max)
  }

  validate_mmrm_spec(spec)

  result <- .run_mmrm(data = data, spec = spec,
                      parallel = parallel, n_workers = n_workers, debug = debug)

  if (!is.null(trakdata) && nchar(spec$idkey %||% "") > 0)
    result <- attach_trakdata(result, idkey = spec$idkey, trakdata = trakdata)

  result
}


# =============================================================================
# SECTION 19: BATCH RUNNER
# v3: no meth_registry; .run_mmrm() handles all dispatch
# =============================================================================

#' Run all outputs in the registry
#' @export
run_all_mmrm <- function(out_registry,
                          datasets,
                          output_ids = NULL,
                          imp_max    = NULL,
                          parallel   = FALSE,
                          n_workers  = 4) {

  reg_run <- if (!is.null(output_ids))
    dplyr::filter(out_registry, output_id %in% output_ids)
  else out_registry

  if (nrow(reg_run) == 0) stop("No outputs to run.")

  miss_ds <- setdiff(reg_run$dataset_name, names(datasets))
  if (length(miss_ds) > 0)
    stop("datasets list missing: ", paste(miss_ds, collapse = ", "))

  # Summary by response_scale
  n_by_scale <- table(reg_run$response_scale %||% "identity")
  message("Batch run: ", nrow(reg_run), " outputs | ",
          paste(n_by_scale, names(n_by_scale), sep = " x ", collapse = " | "))

  results <- purrr::map(purrr::transpose(as.list(reg_run)), function(row) {
    spec <- .row_to_spec(row)
    if (!is.null(imp_max)) spec$imp_max <- as.integer(imp_max)
    .run_mmrm(data = datasets[[row$dataset_name]], spec = spec,
              parallel = parallel, n_workers = n_workers)
  })

  names(results) <- reg_run$output_id
  results
}


# =============================================================================
# SECTION 20: TRAKDATA ADAPTER (unchanged)
# =============================================================================

#' Attach TrakData metadata to a run result
#' @export
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
    return(list(ard = ard_out, subj_N = subj_N,
                shell = report$shell, title = report$title, footnote = report$footnote))
  }
  list(ard = ard_out, subj_N = subj_N)
}


# =============================================================================
# SECTION 21: FLEXIBLE SPEC / RESULT OVERLAY
# -----------------------------------------------------------------------------
# This overlay keeps the validated v3 fitting core, but revises the public
# architecture toward a composition-driven model:
#   - registry provides defaults, not the only source of truth
#   - user can override analysis / result / display choices at call time
#   - engine returns canonical ARD with all applicable MMRM statistics
#   - downstream users choose blocks/statistics from the ARD they need
# =============================================================================

.list_default <- function(a, b) if (!is.null(a) && length(a) > 0) a else b

.legacy_pvalue_default <- function(pvalue_rule) {
  if (is.null(pvalue_rule) || all(is.na(pvalue_rule)) || pvalue_rule[[1]] == "")
    return(NA_character_)
  switch(as.character(pvalue_rule[[1]]),
         better_positive = "p_one_pos",
         better_negative = "p_one_neg",
         two_sided       = "p_two_sided",
         NA_character_)
}

.normalize_result_blocks <- function(x, default = "all") {
  if (is.null(x) || length(x) == 0 || all(is.na(x)) || all(trimws(as.character(x)) == "")) {
    return(default)
  }
  out <- if (length(x) == 1) .split_pipe(x) else as.character(x)
  out <- unique(trimws(out))
  out[out != ""]
}

.normalize_pvalue_default <- function(x, pvalue_rule = NA_character_) {
  if (!is.null(x) && length(x) > 0 && !all(is.na(x)) && trimws(as.character(x[[1]])) != "") {
    return(as.character(x[[1]]))
  }
  .legacy_pvalue_default(pvalue_rule)
}

.standardize_result_block_names <- function(blocks) {
  if (is.null(blocks) || length(blocks) == 0) return("all")
  b <- tolower(trimws(as.character(blocks)))
  map <- c(
    counts = "counts",
    count = "counts",
    n = "counts",
    lsm = "lsm",
    means = "lsm",
    adj_mean = "lsm",
    contrast = "contrast",
    diff = "contrast",
    adj_diff = "contrast",
    transform = "transform",
    backtransform = "transform",
    geometric = "transform",
    pvalue = "pvalue",
    pvalues = "pvalue",
    p = "pvalue",
    tipping = "tipping_point",
    tipping_point = "tipping_point",
    tp = "tipping_point",
    all = "all"
  )
  out <- unname(ifelse(b %in% names(map), map[b], b))
  unique(out)
}

.apply_analysis_overrides <- function(spec, analysis = list()) {
  if (length(analysis) == 0) return(spec)

  pipe_fields <- c(
    "treatment_levels", "param_values", "visits_model", "visits_display",
    "visit_exclude", "pvalue_display_visits", "dummy_visits",
    "tp_penalty_filter_fichypo"
  )
  scalar_fields <- c(
    "response_scale", "population_var", "population_value", "pop_var2", "pop_val2",
    "category_var", "category_value", "paramcd_filter_var", "paramcd_filter",
    "avisitn_var", "avisitn_gt", "avisitn_le", "control_label",
    "comparison_label", "dummy_visit_var", "dummy_visitn_var",
    "tp_primary_visit", "tp_penalty_arm", "tp_penalty_mode",
    "tp_penalty_filter_dtype", "tp_penalty_filter_impreas",
    "tp_penalty_fichypo_var", "tp_significance"
  )

  for (nm in names(analysis)) {
    val <- analysis[[nm]]

    if (nm == "vars" && is.list(val)) {
      spec$vars <- utils::modifyList(.list_default(spec$vars, list()), val)
      next
    }

    if (nm %in% pipe_fields) {
      spec[[nm]] <- if (is.character(val) && length(val) == 1) .split_pipe(val) else val
      next
    }

    if (nm == "tp_penalty_values") {
      spec$tp_penalty_values <- if (is.character(val)) as.numeric(.split_pipe(val)) else as.numeric(val)
      next
    }

    if (nm == "missing_strategy") {
      spec$use_mi <- identical(as.character(val), "mi")
      next
    }

    if (nm == "visit_strategy") {
      spec$use_dummy_grid <- identical(as.character(val), "dummy_grid")
      next
    }

    if (nm == "tp") {
      if (is.logical(val) && length(val) == 1) {
        spec$use_tp <- isTRUE(val)
      } else if (is.list(val)) {
        if (!is.null(val$enable)) spec$use_tp <- isTRUE(val$enable)
        tp_scalar <- c("primary_visit", "penalty_arm", "mode",
                       "filter_dtype", "filter_impreas",
                       "fichypo_var", "significance")
        for (tp_nm in tp_scalar) {
          if (!is.null(val[[tp_nm]])) {
            target <- switch(tp_nm,
                             primary_visit = "tp_primary_visit",
                             penalty_arm   = "tp_penalty_arm",
                             mode          = "tp_penalty_mode",
                             filter_dtype  = "tp_penalty_filter_dtype",
                             filter_impreas= "tp_penalty_filter_impreas",
                             fichypo_var   = "tp_penalty_fichypo_var",
                             significance  = "tp_significance")
            spec[[target]] <- val[[tp_nm]]
          }
        }
        if (!is.null(val$values))
          spec$tp_penalty_values <- if (is.character(val$values)) as.numeric(.split_pipe(val$values)) else as.numeric(val$values)
        if (!is.null(val$filter_fichypo))
          spec$tp_penalty_filter_fichypo <- if (length(val$filter_fichypo) == 1) .split_pipe(val$filter_fichypo) else as.character(val$filter_fichypo)
      }
      next
    }

    if (nm %in% scalar_fields) {
      spec[[nm]] <- val
      next
    }
  }

  # Reconcile flags after overrides
  proxy <- list(
    output_id         = spec$output_id,
    imputation_var    = spec$vars$imputation,
    dummy_visit_var   = spec$dummy_visit_var,
    tp_penalty_values = if (length(spec$tp_penalty_values) > 0) paste(spec$tp_penalty_values, collapse = "|") else "",
    response_scale    = spec$response_scale
  )
  flags <- .detect_analysis_flags(proxy)
  spec$use_mi         <- flags$use_mi
  spec$use_dummy_grid <- flags$use_dummy_grid
  spec$use_tp         <- flags$use_tp
  spec$response_scale <- flags$response_scale
  spec$missing_strategy <- if (isTRUE(spec$use_mi)) "mi" else "observed"
  spec$visit_strategy   <- if (isTRUE(spec$use_dummy_grid)) "dummy_grid" else "observed"

  spec
}

.apply_result_overrides <- function(spec, results = list()) {
  if (length(results) == 0) return(spec)

  if (!is.null(results$emit_pvalues))
    spec$emit_pvalues <- isTRUE(results$emit_pvalues)

  if (!is.null(results$blocks))
    spec$result_blocks <- .standardize_result_block_names(.normalize_result_blocks(results$blocks))

  if (!is.null(results$stat_names))
    spec$selected_stat_names <- unique(as.character(results$stat_names))

  spec
}

.apply_display_overrides <- function(spec, display = list()) {
  if (length(display) == 0) return(spec)

  if (!is.null(display$pvalue_default))
    spec$pvalue_default <- as.character(display$pvalue_default[[1]])

  if (!is.null(display$pvalue_display_visits))
    spec$pvalue_display_visits <- if (length(display$pvalue_display_visits) == 1) {
      .split_pipe(display$pvalue_display_visits)
    } else {
      as.character(display$pvalue_display_visits)
    }

  if (!is.null(display$digits) && is.list(display$digits)) {
    spec$digits <- utils::modifyList(spec$digits, display$digits)
  } else {
    if (!is.null(display$digits_est)) spec$digits$est <- as.integer(display$digits_est)
    if (!is.null(display$digits_p))   spec$digits$p   <- as.integer(display$digits_p)
    if (!is.null(display$digits_pct)) spec$digits$pct <- as.integer(display$digits_pct)
  }

  spec
}

.compose_direct_spec <- function(analysis = list(), results = list(), display = list(),
                                 output_id = NULL, idkey = NULL) {
  spec <- analysis
  spec$output_id <- spec$output_id %||% output_id %||% "ADHOC_MMRM"
  spec$idkey     <- spec$idkey %||% idkey %||% ""
  spec$dataset_name <- spec$dataset_name %||% "adhoc_dataset"

  if (is.null(spec$vars))
    stop("Direct analysis spec must include nested vars=list(...).")

  spec$population_var   <- spec$population_var   %||% "FASFL"
  spec$population_value <- spec$population_value %||% "Y"
  spec$pop_var2         <- spec$pop_var2         %||% NA_character_
  spec$pop_val2         <- spec$pop_val2         %||% NA_character_
  spec$category_var     <- spec$category_var     %||% NA_character_
  spec$category_value   <- spec$category_value   %||% NA_character_
  spec$paramcd_filter_var <- spec$paramcd_filter_var %||% "PARAMCD"
  spec$paramcd_filter   <- spec$paramcd_filter   %||% NA_character_
  spec$avisitn_var      <- spec$avisitn_var      %||% "AVISITN"
  spec$avisitn_gt       <- spec$avisitn_gt       %||% NA_real_
  spec$avisitn_le       <- spec$avisitn_le       %||% NA_real_
  spec$dummy_visit_var  <- spec$dummy_visit_var  %||% NA_character_
  spec$dummy_visitn_var <- spec$dummy_visitn_var %||% NA_character_
  spec$dummy_visits     <- spec$dummy_visits     %||% character(0)
  spec$visits_model     <- spec$visits_model     %||% character(0)
  spec$visits_display   <- spec$visits_display   %||% spec$visits_model
  spec$visit_exclude    <- spec$visit_exclude    %||% character(0)
  spec$treatment_levels <- spec$treatment_levels %||% character(0)
  spec$control_label    <- spec$control_label    %||% NA_character_
  spec$comparison_label <- spec$comparison_label %||% NA_character_
  spec$param_values     <- spec$param_values     %||% character(0)
  spec$n_obs_dtype_values <- spec$n_obs_dtype_values %||% c("", "TP")
  spec$tp_penalty_values         <- spec$tp_penalty_values         %||% numeric(0)
  spec$tp_primary_visit          <- spec$tp_primary_visit          %||% NA_character_
  spec$tp_penalty_arm            <- spec$tp_penalty_arm            %||% NA_character_
  spec$tp_penalty_mode           <- spec$tp_penalty_mode           %||% "multiply"
  spec$tp_penalty_filter_dtype   <- spec$tp_penalty_filter_dtype   %||% NA_character_
  spec$tp_penalty_filter_impreas <- spec$tp_penalty_filter_impreas %||% NA_character_
  spec$tp_penalty_fichypo_var    <- spec$tp_penalty_fichypo_var    %||% "FICHYPO"
  spec$tp_penalty_filter_fichypo <- spec$tp_penalty_filter_fichypo %||% character(0)
  spec$tp_significance           <- spec$tp_significance           %||% 0.025
  spec$imp_max                   <- spec$imp_max                   %||% NA_integer_
  spec$digits <- .list_default(spec$digits, list(est = 3L, p = 4L, pct = 1L))
  spec$response_scale <- spec$response_scale %||% "identity"

  proxy <- list(
    output_id         = spec$output_id,
    imputation_var    = spec$vars$imputation,
    dummy_visit_var   = spec$dummy_visit_var,
    tp_penalty_values = if (length(spec$tp_penalty_values) > 0) paste(spec$tp_penalty_values, collapse = "|") else "",
    response_scale    = spec$response_scale
  )
  flags <- .detect_analysis_flags(proxy)

  spec$use_mi           <- spec$use_mi           %||% flags$use_mi
  spec$use_dummy_grid   <- spec$use_dummy_grid   %||% flags$use_dummy_grid
  spec$use_tp           <- spec$use_tp           %||% flags$use_tp
  spec$response_scale   <- flags$response_scale
  spec$missing_strategy <- if (isTRUE(spec$use_mi)) "mi" else "observed"
  spec$visit_strategy   <- if (isTRUE(spec$use_dummy_grid)) "dummy_grid" else "observed"
  spec$analysis_type    <- "mmrm"

  spec$emit_pvalues      <- spec$emit_pvalues %||% TRUE
  spec$result_blocks     <- .standardize_result_block_names(.normalize_result_blocks(spec$result_blocks %||% "all"))
  spec$pvalue_default    <- .normalize_pvalue_default(spec$pvalue_default %||% NA_character_, spec$pvalue_rule %||% NA_character_)
  spec$pvalue_display_visits <- spec$pvalue_display_visits %||% character(0)
  spec$selected_stat_names   <- spec$selected_stat_names %||% NULL

  spec <- .apply_result_overrides(spec, results)
  spec <- .apply_display_overrides(spec, display)
  spec
}

compose_mmrm_spec <- function(output_id = NULL, idkey = NULL,
                              out_registry = NULL, out_registry_path = NULL,
                              analysis = list(), results = list(),
                              display = list(), spec_overrides = list()) {
  has_lookup <- !is.null(out_registry) || !is.null(out_registry_path) || !is.null(output_id) || !is.null(idkey)

  if (!is.null(out_registry) || !is.null(out_registry_path)) {
    if (is.null(out_registry)) {
      path <- out_registry_path %||% "eff_mmrm_registry.csv"
      out_registry <- load_mmrm_registry(path)
    }
    spec <- resolve_mmrm_spec(output_id = output_id, idkey = idkey, out_registry = out_registry)
  } else if (has_lookup && (is.null(output_id) && is.null(idkey))) {
    stop("If using registry lookup, provide output_id or idkey.")
  } else {
    spec <- .compose_direct_spec(analysis = analysis, results = results, display = display,
                                 output_id = output_id, idkey = idkey)
  }

  if (length(analysis) > 0) spec <- .apply_analysis_overrides(spec, analysis)
  if (length(results)  > 0) spec <- .apply_result_overrides(spec, results)
  if (length(display)  > 0) spec <- .apply_display_overrides(spec, display)
  if (length(spec_overrides) > 0) spec <- .apply_spec_overrides(spec, spec_overrides)

  spec
}

# -----------------------------------------------------------------------------
# Flexible registry loader (supports both current wide registry and a leaner
# default-oriented registry by auto-adding missing optional columns)
# -----------------------------------------------------------------------------
load_mmrm_registry <- function(path) {
  reg <- .read_registry(path)

  if (!"response_scale" %in% names(reg)) {
    reg$response_scale <- dplyr::case_when(
      "transform_profile" %in% names(reg) &
        !is.na(reg$transform_profile) &
        tolower(reg$transform_profile) == "logratio" ~ "logratio",
      TRUE ~ "identity"
    )
  }

  required_cols <- c(
    "output_id", "idkey", "dataset_name",
    "population_var", "population_value",
    "trt_var", "trtn_var", "visit_var", "visitn_var",
    "response_var", "baseline_var",
    "treatment_levels", "control_label", "comparison_label"
  )
  miss <- setdiff(required_cols, names(reg))
  if (length(miss) > 0)
    stop("Registry missing required columns: ", paste(miss, collapse = ", "))

  optional_cols <- c(
    "response_scale",
    "pop_var2", "pop_val2",
    "category_var", "category_value",
    "paramcd_filter", "paramcd_filter_var",
    "imputation_var", "dtype_var", "strata_vars",
    "param_var", "param_values",
    "visits_model", "visits_display", "visit_exclude",
    "avisitn_var", "avisitn_gt", "avisitn_le",
    "pvalue_display_visits", "include_pvalue", "pvalue_rule",
    "emit_pvalues", "pvalue_default", "default_result_blocks",
    "n_obs_dtype_values",
    "imp_max", "digits_est", "digits_p", "digits_pct",
    "tp_penalty_values", "tp_primary_visit", "tp_penalty_arm",
    "tp_penalty_mode", "tp_penalty_filter_dtype",
    "tp_penalty_filter_impreas", "tp_penalty_filter_fichypo",
    "tp_penalty_fichypo_var", "tp_significance",
    "dummy_visit_var", "dummy_visitn_var", "dummy_visits",
    "notes"
  )
  for (col in optional_cols)
    if (!col %in% names(reg)) reg[[col]] <- NA_character_

  if (!"visits_model" %in% names(reg)) reg$visits_model <- NA_character_

  dup <- reg$output_id[duplicated(reg$output_id)]
  if (length(dup) > 0)
    stop("Duplicate output_id: ", paste(dup, collapse = ", "))

  flags <- purrr::map(purrr::transpose(as.list(reg)), .detect_analysis_flags)
  n_mi  <- sum(purrr::map_lgl(flags, "use_mi"))
  n_obs <- sum(!purrr::map_lgl(flags, "use_mi"))
  n_lr  <- sum(purrr::map_chr(flags, "response_scale") == "logratio")
  n_tp  <- sum(purrr::map_lgl(flags, "use_tp"))
  message("Registry: ", nrow(reg), " outputs | MI=", n_mi, " OBS=", n_obs,
          " | logratio=", n_lr, " | TP=", n_tp)
  reg
}

.row_to_spec <- function(out_row) {
  flags <- .detect_analysis_flags(out_row)

  n_obs_dtype <- .split_pipe(out_row$n_obs_dtype_values %||% "")
  if (length(n_obs_dtype) == 0) n_obs_dtype <- c("", "TP")

  list(
    output_id    = out_row$output_id,
    idkey        = as.character(out_row$idkey %||% ""),
    dataset_name = out_row$dataset_name,
    analysis_type    = "mmrm",
    use_mi           = flags$use_mi,
    use_dummy_grid   = flags$use_dummy_grid,
    use_tp           = flags$use_tp,
    missing_strategy = if (flags$use_mi) "mi" else "observed",
    visit_strategy   = if (flags$use_dummy_grid) "dummy_grid" else "observed",
    response_scale   = flags$response_scale,

    population_var   = out_row$population_var,
    population_value = out_row$population_value,
    pop_var2         = out_row$pop_var2 %||% NA_character_,
    pop_val2         = out_row$pop_val2 %||% NA_character_,
    category_var     = out_row$category_var %||% NA_character_,
    category_value   = out_row$category_value %||% NA_character_,
    paramcd_filter_var = out_row$paramcd_filter_var %||% "PARAMCD",
    paramcd_filter     = out_row$paramcd_filter %||% NA_character_,
    avisitn_var      = out_row$avisitn_var %||% "AVISITN",
    avisitn_gt       = .as_numeric_safe(out_row$avisitn_gt),
    avisitn_le       = .as_numeric_safe(out_row$avisitn_le),

    vars = list(
      subject_id  = out_row$subject_id_var %||% "USUBJID",
      subject_var = out_row$subject_var    %||% "SUBJID",
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

    treatment_levels = .split_pipe(out_row$treatment_levels),
    control_label    = out_row$control_label,
    comparison_label = out_row$comparison_label,
    param_values     = .split_pipe(out_row$param_values %||% ""),

    visits_model = .split_pipe(out_row$visits_model %||% ""),
    visits_display = {
      vd <- .split_pipe(out_row$visits_display %||% "")
      vm <- .split_pipe(out_row$visits_model %||% "")
      if (length(vd) == 0) vm else vd
    },
    visit_exclude          = .split_pipe(out_row$visit_exclude %||% ""),
    pvalue_display_visits  = .split_pipe(out_row$pvalue_display_visits %||% ""),
    include_pvalue         = .as_logical_safe(out_row$include_pvalue %||% TRUE),
    emit_pvalues           = .as_logical_safe(out_row$emit_pvalues %||% TRUE),
    pvalue_rule            = out_row$pvalue_rule %||% NA_character_,
    pvalue_default         = .normalize_pvalue_default(out_row$pvalue_default %||% NA_character_,
                                                       out_row$pvalue_rule %||% NA_character_),
    result_blocks          = .standardize_result_block_names(
                               .normalize_result_blocks(out_row$default_result_blocks %||% "all")),
    selected_stat_names    = NULL,
    n_obs_dtype_values     = n_obs_dtype,

    imp_max = .as_integer_safe(out_row$imp_max),
    digits  = list(
      est = as.integer(.as_numeric_safe(out_row$digits_est) %||% 3),
      p   = as.integer(.as_numeric_safe(out_row$digits_p)   %||% 4),
      pct = as.integer(.as_numeric_safe(out_row$digits_pct) %||% 1)
    ),

    dummy_visit_var  = out_row$dummy_visit_var  %||% NA_character_,
    dummy_visitn_var = out_row$dummy_visitn_var %||% NA_character_,
    dummy_visits     = .split_pipe(out_row$dummy_visits %||% ""),

    tp_penalty_values         = as.numeric(.split_pipe(out_row$tp_penalty_values %||% "")),
    tp_primary_visit          = out_row$tp_primary_visit %||% NA_character_,
    tp_penalty_arm            = out_row$tp_penalty_arm   %||% NA_character_,
    tp_penalty_mode           = out_row$tp_penalty_mode  %||% "multiply",
    tp_penalty_filter_dtype   = out_row$tp_penalty_filter_dtype   %||% NA_character_,
    tp_penalty_filter_impreas = out_row$tp_penalty_filter_impreas %||% NA_character_,
    tp_penalty_fichypo_var    = out_row$tp_penalty_fichypo_var    %||% "FICHYPO",
    tp_penalty_filter_fichypo = .split_pipe(out_row$tp_penalty_filter_fichypo %||% ""),
    tp_significance           = .as_numeric_safe(out_row$tp_significance %||% 0.025)
  )
}

resolve_mmrm_spec <- function(output_id = NULL, idkey = NULL, out_registry) {
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

  spec <- .row_to_spec(as.list(hits[1, ]))
  message("Resolved: idkey=", spec$idkey,
          " | output_id=", spec$output_id,
          " | missing=", spec$missing_strategy,
          " | visit=", spec$visit_strategy,
          " | tp=", spec$use_tp,
          " | scale=", spec$response_scale)
  spec
}

validate_mmrm_spec <- function(spec) {
  req <- c("output_id", "dataset_name",
           "population_var", "population_value",
           "vars", "treatment_levels", "control_label",
           "digits", "use_mi", "use_dummy_grid", "use_tp",
           "response_scale", "emit_pvalues", "result_blocks")
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
    stop("[", spec$output_id, "] control_label '", spec$control_label, "' not in treatment_levels")

  if (isTRUE(spec$use_mi) &&
      (is.null(spec$vars$imputation) || is.na(spec$vars$imputation) || spec$vars$imputation == ""))
    stop("[", spec$output_id, "] imputation_var required (use_mi detected TRUE)")

  if (isTRUE(spec$use_dummy_grid) && isTRUE(spec$use_mi))
    warning("[", spec$output_id, "] Both use_dummy_grid and use_mi are TRUE. MI path will take precedence if the data prep path is not explicitly split.")

  if (isTRUE(spec$use_tp)) {
    if (length(spec$tp_penalty_values) == 0 || any(is.na(spec$tp_penalty_values)))
      stop("[", spec$output_id, "] tp_penalty_values required (use_tp detected TRUE)")
    if (is.na(spec$tp_primary_visit))
      stop("[", spec$output_id, "] tp_primary_visit required")
    if (is.na(spec$tp_penalty_arm) || !(spec$tp_penalty_arm %in% spec$treatment_levels))
      stop("[", spec$output_id, "] tp_penalty_arm must be in treatment_levels")
  }

  if (!spec$response_scale %in% c("identity", "logratio"))
    stop("[", spec$output_id, "] response_scale must be 'identity' or 'logratio'")

  invisible(spec)
}

.default_pvalue_flag <- function(stat_name, spec) {
  default_stat <- spec$pvalue_default %||% NA_character_
  if (is.null(default_stat) || length(default_stat) == 0 || all(is.na(default_stat)))
    return(rep(NA, length(stat_name)))
  stat_name == default_stat[[1]]
}

.ard_pvalue_block <- function(diff_d, spec, param = NA_character_,
                              group1_dim  = "VISIT",
                              group1_col  = "VISIT",
                              ord1_levels = NULL,
                              ord_offset  = 100L) {
  pv_vis <- spec$pvalue_display_visits
  d_p    <- spec$digits$p

  diff_d |>
    dplyr::mutate(
      .g1_val   = as.character(.data[[group1_col]]),
      p_one_pos = dplyr::case_when(
        estimate > 0 ~ p_two_sided / 2, estimate < 0 ~ 1 - p_two_sided / 2, TRUE ~ 0.5),
      p_one_neg = dplyr::case_when(
        estimate < 0 ~ p_two_sided / 2, estimate > 0 ~ 1 - p_two_sided / 2, TRUE ~ 0.5)
    ) |>
    tidyr::pivot_longer(cols = c(p_two_sided, p_one_pos, p_one_neg),
                        names_to = "stat_name", values_to = "stat_num") |>
    dplyr::transmute(
      output_id      = spec$output_id,
      response_scale = spec$response_scale,
      result_block   = "pvalue",
      param_var      = spec$vars$param %||% NA_character_,
      param          = param,
      row_type       = "comparison",
      group1         = group1_dim,
      group1_level   = .g1_val,
      group2         = "COMPARISON",
      group2_level   = comparison,
      stat_name,
      stat_label = dplyr::case_match(stat_name,
        "p_two_sided" ~ "2-sided p-value",
        "p_one_pos"   ~ "1-sided p-value (better=positive)",
        "p_one_neg"   ~ "1-sided p-value (better=negative)"),
      stat_num,
      stat_chr = format_p(stat_num, d_p),
      pvalue_display_default = .default_pvalue_flag(stat_name, spec),
      pvalue_visit_default   = if (length(pv_vis) > 0) .g1_val %in% as.character(pv_vis) else TRUE,
      penalty_term = NA_real_,
      ord1 = if (!is.null(ord1_levels)) match(.g1_val, as.character(ord1_levels)) else NA_integer_,
      ord2 = dplyr::case_match(stat_name,
        "p_two_sided" ~ as.integer(ord_offset),
        "p_one_pos"   ~ as.integer(ord_offset + 1L),
        "p_one_neg"   ~ as.integer(ord_offset + 2L))
    )
}

.ard_counts <- function(prep, spec, param = NA_character_, group1_dim = "VISIT") {
  vd <- spec$visits_display %||% spec$visits_model

  ard_bigN <- prep$subj_n |>
    dplyr::transmute(
      output_id = spec$output_id, response_scale = spec$response_scale,
      result_block = "counts",
      param_var = spec$vars$param %||% NA_character_, param = param,
      row_type = "arm", group1 = group1_dim, group1_level = NA_character_,
      group2 = "TRT", group2_level = as.character(TRT),
      stat_name = "bigN", stat_label = "N",
      stat_num = bigN, stat_chr = as.character(bigN),
      pvalue_display_default = NA,
      pvalue_visit_default = NA,
      penalty_term = NA_real_, ord1 = 0L, ord2 = as.integer(TRTN)
    )

  ard_nobs <- prep$obs_n |>
    dplyr::transmute(
      output_id = spec$output_id, response_scale = spec$response_scale,
      result_block = "counts",
      param_var = spec$vars$param %||% NA_character_, param = param,
      row_type = "arm", group1 = group1_dim, group1_level = as.character(VISIT),
      group2 = "TRT", group2_level = as.character(TRT),
      stat_name = "nobs", stat_label = "n",
      stat_num = nobs, stat_chr = as.character(nobs),
      pvalue_display_default = NA,
      pvalue_visit_default = NA,
      penalty_term = NA_real_,
      ord1 = match(as.character(VISIT), vd), ord2 = as.integer(TRTN)
    )

  dplyr::bind_rows(ard_bigN, ard_nobs)
}

.ard_identity_rows <- function(prep, lsm_comb, diff_comb, spec, param = NA_character_) {
  d_est <- spec$digits$est
  vd    <- spec$visits_display %||% spec$visits_model

  lsm_d  <- dplyr::filter(lsm_comb,  VISIT %in% vd)
  diff_d <- dplyr::filter(diff_comb, VISIT %in% vd)

  is_log <- spec$response_scale == "logratio"

  add_meta <- function(df)
    dplyr::mutate(df,
      output_id = spec$output_id, response_scale = spec$response_scale,
      param_var = spec$vars$param %||% NA_character_, param = param,
      pvalue_display_default = NA,
      pvalue_visit_default = NA,
      penalty_term = NA_real_)

  ard_lsm <- add_meta(
    lsm_d |> dplyr::left_join(prep$subj_n |> dplyr::select(TRT, TRTN), by = "TRT")
  ) |>
    dplyr::transmute(
      output_id, response_scale,
      result_block = "lsm",
      param_var, param,
      row_type = "arm",
      group1 = "VISIT", group1_level = VISIT,
      group2 = "TRT",   group2_level = as.character(TRT),
      stat_name = "adj_mean_ci",
      stat_label = if (is_log) "Log-scale adjusted mean (95% CI)"
                   else         "Adjusted mean (95% CI)",
      stat_num = estimate,
      stat_chr = format_ci(estimate, lower, upper, d_est),
      pvalue_display_default, pvalue_visit_default,
      penalty_term,
      ord1 = match(VISIT, vd), ord2 = as.integer(TRTN)
    )

  ard_diff <- add_meta(diff_d) |>
    dplyr::transmute(
      output_id, response_scale,
      result_block = "contrast",
      param_var, param,
      row_type = "comparison",
      group1 = "VISIT",      group1_level = VISIT,
      group2 = "COMPARISON", group2_level = comparison,
      stat_name = "adj_diff_ci",
      stat_label = if (is_log) "Log-scale adjusted mean difference (95% CI)"
                   else         "Adjusted mean difference (95% CI)",
      stat_num = estimate,
      stat_chr = format_ci(estimate, lower, upper, d_est),
      pvalue_display_default, pvalue_visit_default,
      penalty_term,
      ord1 = match(VISIT, vd), ord2 = 99L
    )

  list(lsm = ard_lsm, diff = ard_diff, diff_d = diff_d)
}

.ard_logratio_rows <- function(prep, lsm_comb, diff_comb, spec, param = NA_character_) {
  d_est  <- spec$digits$est
  d_pct  <- spec$digits$pct
  vd     <- spec$visits_display %||% spec$visits_model

  lsm_d  <- dplyr::filter(lsm_comb,  VISIT %in% vd)
  diff_d <- dplyr::filter(diff_comb, VISIT %in% vd)

  lsm_bt <- lsm_d |>
    dplyr::mutate(geo_mean = exp(estimate), geo_lcl = exp(lower), geo_ucl = exp(upper))

  diff_bt <- diff_d |>
    dplyr::mutate(
      geo_ratio   = exp(estimate),
      geo_r_lcl   = exp(lower),
      geo_r_ucl   = exp(upper),
      pct_red     = (1 - exp(estimate)) * 100,
      pct_red_lcl = (1 - exp(upper))    * 100,
      pct_red_ucl = (1 - exp(lower))    * 100
    )

  add_meta <- function(df)
    dplyr::mutate(df,
      output_id = spec$output_id, response_scale = spec$response_scale,
      param_var = spec$vars$param %||% NA_character_, param = param,
      pvalue_display_default = NA,
      pvalue_visit_default = NA,
      penalty_term = NA_real_)

  ard_geo_mean <- add_meta(
    lsm_bt |> dplyr::left_join(prep$subj_n |> dplyr::select(TRT, TRTN), by = "TRT")
  ) |>
    dplyr::transmute(
      output_id, response_scale,
      result_block = "transform",
      param_var, param,
      row_type = "arm",
      group1 = "VISIT", group1_level = VISIT,
      group2 = "TRT",   group2_level = as.character(TRT),
      stat_name = "geo_mean_ci",
      stat_label = "Geometric adjusted mean (95% CI)",
      stat_num = geo_mean,
      stat_chr = format_ci(geo_mean, geo_lcl, geo_ucl, d_est),
      pvalue_display_default, pvalue_visit_default,
      penalty_term,
      ord1 = match(VISIT, vd), ord2 = as.integer(TRTN)
    )

  ard_geo_ratio <- add_meta(diff_bt) |>
    dplyr::transmute(
      output_id, response_scale,
      result_block = "transform",
      param_var, param,
      row_type = "comparison",
      group1 = "VISIT",      group1_level = VISIT,
      group2 = "COMPARISON", group2_level = comparison,
      stat_name = "geo_ratio_ci",
      stat_label = "Geometric mean ratio (95% CI)",
      stat_num = geo_ratio,
      stat_chr = format_ci(geo_ratio, geo_r_lcl, geo_r_ucl, d_est),
      pvalue_display_default, pvalue_visit_default,
      penalty_term,
      ord1 = match(VISIT, vd), ord2 = 100L
    )

  ard_pct_red <- add_meta(diff_bt) |>
    dplyr::transmute(
      output_id, response_scale,
      result_block = "transform",
      param_var, param,
      row_type = "comparison",
      group1 = "VISIT",      group1_level = VISIT,
      group2 = "COMPARISON", group2_level = comparison,
      stat_name = "pct_reduction_ci",
      stat_label = "% Reduction (95% CI)",
      stat_num = pct_red,
      stat_chr = format_ci(pct_red, pct_red_lcl, pct_red_ucl, d_pct),
      pvalue_display_default, pvalue_visit_default,
      penalty_term,
      ord1 = match(VISIT, vd), ord2 = 101L
    )

  list(geo_mean = ard_geo_mean, geo_ratio = ard_geo_ratio, pct_red = ard_pct_red)
}

.assemble_ard <- function(prep, lsm_comb, diff_comb, spec, param = NA_character_) {
  vd <- spec$visits_display %||% spec$visits_model

  rows <- list(counts = .ard_counts(prep, spec, param))

  id_rows <- .ard_identity_rows(prep, lsm_comb, diff_comb, spec, param)
  rows$adj_lsm  <- id_rows$lsm
  rows$adj_diff <- id_rows$diff
  diff_d        <- id_rows$diff_d

  if (spec$response_scale == "logratio") {
    lr <- .ard_logratio_rows(prep, lsm_comb, diff_comb, spec, param)
    rows$geo_mean  <- lr$geo_mean
    rows$geo_ratio <- lr$geo_ratio
    rows$pct_red   <- lr$pct_red
    pval_ord_offset <- 102L
  } else {
    pval_ord_offset <- 100L
  }

  if (isTRUE(spec$emit_pvalues)) {
    rows$pvalues <- .ard_pvalue_block(
      diff_d, spec, param,
      group1_dim  = "VISIT",
      group1_col  = "VISIT",
      ord1_levels = vd,
      ord_offset  = pval_ord_offset
    )
  }

  dplyr::bind_rows(rows) |>
    dplyr::arrange(ord1, ord2, stat_name)
}

.assemble_ard_tp <- function(prep, tp_results, spec) {
  d_est  <- spec$digits$est
  sig    <- spec$tp_significance %||% 0.025
  pv     <- spec$tp_primary_visit
  pen_ord <- sort(unique(tp_results$penalty))

  tp_ann <- tp_results |>
    dplyr::arrange(penalty) |>
    dplyr::mutate(
      p_one        = dplyr::case_when(
        estimate > 0 ~ p_two_sided / 2, estimate < 0 ~ 1 - p_two_sided / 2, TRUE ~ 0.5),
      sig_flag     = p_one < sig,
      tipping_flag = !sig_flag & dplyr::lag(sig_flag, default = TRUE)
    )

  add_meta <- function(df)
    dplyr::mutate(df,
      output_id = spec$output_id, response_scale = spec$response_scale,
      param_var = NA_character_, param = NA_character_)

  ard_bigN <- prep$subj_n |>
    dplyr::transmute(
      output_id = spec$output_id, response_scale = spec$response_scale,
      result_block = "counts",
      param_var = NA_character_, param = NA_character_,
      row_type = "arm", group1 = "PENALTY", group1_level = NA_character_,
      group2 = "TRT", group2_level = as.character(TRT),
      stat_name = "bigN", stat_label = "N",
      stat_num = bigN, stat_chr = as.character(bigN),
      pvalue_display_default = NA, pvalue_visit_default = NA,
      penalty_term = NA_real_, ord1 = 0L, ord2 = as.integer(TRTN)
    )

  ard_nobs <- prep$obs_n |>
    dplyr::filter(as.character(VISIT) == pv) |>
    dplyr::transmute(
      output_id = spec$output_id, response_scale = spec$response_scale,
      result_block = "counts",
      param_var = NA_character_, param = NA_character_,
      row_type = "arm", group1 = "PENALTY", group1_level = NA_character_,
      group2 = "TRT", group2_level = as.character(TRT),
      stat_name = "nobs", stat_label = paste0("n (", pv, ")"),
      stat_num = nobs, stat_chr = as.character(nobs),
      pvalue_display_default = NA, pvalue_visit_default = NA,
      penalty_term = NA_real_, ord1 = 0L, ord2 = as.integer(TRTN)
    )

  ard_diff <- add_meta(tp_ann) |>
    dplyr::transmute(
      output_id, response_scale,
      result_block = "contrast",
      param_var, param,
      row_type = "comparison",
      group1 = "PENALTY", group1_level = as.character(penalty),
      group2 = "COMPARISON", group2_level = comparison,
      stat_name = "adj_diff_ci",
      stat_label = "Adjusted mean difference (95% CI)",
      stat_num = estimate,
      stat_chr = format_ci(estimate, lower, upper, d_est),
      pvalue_display_default = NA, pvalue_visit_default = NA,
      penalty_term = penalty, ord1 = match(penalty, pen_ord), ord2 = 99L
    )

  ard_pval <- if (isTRUE(spec$emit_pvalues)) {
    .ard_pvalue_block(
      tp_ann, spec,
      group1_dim  = "PENALTY",
      group1_col  = "penalty",
      ord1_levels = as.character(pen_ord),
      ord_offset  = 100L
    ) |>
      dplyr::left_join(
        tp_ann |> dplyr::transmute(group1_level = as.character(penalty), .pt = penalty),
        by = "group1_level"
      ) |>
      dplyr::mutate(penalty_term = .pt) |>
      dplyr::select(-.pt)
  } else {
    NULL
  }

  ard_tp_flag <- add_meta(dplyr::filter(tp_ann, tipping_flag)) |>
    dplyr::transmute(
      output_id, response_scale,
      result_block = "tipping_point",
      param_var, param,
      row_type = "comparison",
      group1 = "PENALTY", group1_level = as.character(penalty),
      group2 = "COMPARISON", group2_level = comparison,
      stat_name = "tipping_point",
      stat_label = paste0("Tipping point (1-sided alpha=", sig, ")"),
      stat_num = 1L, stat_chr = paste0("penalty=", penalty),
      pvalue_display_default = NA, pvalue_visit_default = NA,
      penalty_term = penalty, ord1 = match(penalty, pen_ord), ord2 = 103L
    )

  dplyr::bind_rows(ard_bigN, ard_nobs, ard_diff, ard_pval, ard_tp_flag) |>
    dplyr::arrange(ord1, ord2, stat_name)
}

select_mmrm_ard <- function(ard,
                            blocks = NULL,
                            stat_names = NULL,
                            default_pvalues_only = FALSE,
                            default_visits_only = FALSE) {
  out <- ard
  if (!is.null(blocks) && !("all" %in% tolower(blocks))) {
    b <- .standardize_result_block_names(blocks)
    out <- dplyr::filter(out, result_block %in% b)
  }
  if (!is.null(stat_names))
    out <- dplyr::filter(out, stat_name %in% stat_names)
  if (isTRUE(default_pvalues_only)) {
    out <- dplyr::filter(out, is.na(pvalue_display_default) | pvalue_display_default)
  }
  if (isTRUE(default_visits_only)) {
    out <- dplyr::filter(out, is.na(pvalue_visit_default) | pvalue_visit_default)
  }
  out
}

create_ard_mmrm <- function(output_id = NULL,
                            idkey = NULL,
                            data,
                            out_registry = NULL,
                            out_registry_path = NULL,
                            analysis = list(),
                            results = list(),
                            display = list(),
                            spec_overrides = list(),
                            imp_max = NULL,
                            parallel = FALSE,
                            n_workers = 4,
                            debug = FALSE,
                            trakdata = NULL) {

  if (is.null(out_registry) && !is.null(out_registry_path))
    out_registry <- load_mmrm_registry(out_registry_path)

  spec <- compose_mmrm_spec(
    output_id = output_id, idkey = idkey,
    out_registry = out_registry, out_registry_path = NULL,
    analysis = analysis, results = results, display = display,
    spec_overrides = spec_overrides
  )

  if (!is.null(imp_max)) {
    spec$imp_max <- as.integer(imp_max)
    message("[", spec$output_id, "] imp_max=", imp_max)
  }

  validate_mmrm_spec(spec)

  result <- .run_mmrm(data = data, spec = spec,
                      parallel = parallel, n_workers = n_workers, debug = debug)

  result$ard_selected <- select_mmrm_ard(
    result$ard,
    blocks     = spec$result_blocks,
    stat_names = spec$selected_stat_names
  )
  result$meta <- c(result$meta, list(
    analysis_type    = spec$analysis_type %||% "mmrm",
    missing_strategy = spec$missing_strategy,
    visit_strategy   = spec$visit_strategy,
    response_scale   = spec$response_scale,
    emit_pvalues     = spec$emit_pvalues,
    result_blocks    = paste(spec$result_blocks, collapse = "|"),
    pvalue_default   = spec$pvalue_default %||% NA_character_
  ))

  if (!is.null(trakdata) && nchar(spec$idkey %||% "") > 0)
    result <- attach_trakdata(result, idkey = spec$idkey, trakdata = trakdata)

  result
}

run_all_mmrm <- function(out_registry,
                         datasets,
                         output_ids = NULL,
                         imp_max = NULL,
                         parallel = FALSE,
                         n_workers = 4,
                         analysis = list(),
                         results = list(),
                         display = list()) {

  reg_run <- if (!is.null(output_ids))
    dplyr::filter(out_registry, output_id %in% output_ids)
  else out_registry

  if (nrow(reg_run) == 0) stop("No outputs to run.")

  miss_ds <- setdiff(reg_run$dataset_name, names(datasets))
  if (length(miss_ds) > 0)
    stop("datasets list missing: ", paste(miss_ds, collapse = ", "))

  scale_vec <- if ("response_scale" %in% names(reg_run)) {
    dplyr::coalesce(as.character(reg_run$response_scale), "identity")
  } else {
    rep("identity", nrow(reg_run))
  }
  n_by_scale <- table(scale_vec)
  message("Batch run: ", nrow(reg_run), " outputs | ",
          paste(n_by_scale, names(n_by_scale), sep = " x ", collapse = " | "))

  results_list <- purrr::map(purrr::transpose(as.list(reg_run)), function(row) {
    spec <- .row_to_spec(row)
    if (length(analysis) > 0) spec <- .apply_analysis_overrides(spec, analysis)
    if (length(results)  > 0) spec <- .apply_result_overrides(spec, results)
    if (length(display)  > 0) spec <- .apply_display_overrides(spec, display)
    if (!is.null(imp_max)) spec$imp_max <- as.integer(imp_max)
    validate_mmrm_spec(spec)
    res <- .run_mmrm(data = datasets[[row$dataset_name]], spec = spec,
                     parallel = parallel, n_workers = n_workers)
    res$ard_selected <- select_mmrm_ard(
      res$ard,
      blocks     = spec$result_blocks,
      stat_names = spec$selected_stat_names
    )
    res
  })

  names(results_list) <- reg_run$output_id
  results_list
}

# Convenience projector for ARS-ready subsets
as_ars_mmrm <- function(result,
                        blocks = c("counts", "lsm", "contrast"),
                        stat_names = NULL,
                        default_pvalues_only = FALSE,
                        default_visits_only = FALSE) {
  select_mmrm_ard(
    ard = result$ard,
    blocks = blocks,
    stat_names = stat_names,
    default_pvalues_only = default_pvalues_only,
    default_visits_only = default_visits_only
  )
}
