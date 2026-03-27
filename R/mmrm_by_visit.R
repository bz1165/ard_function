# MMRM-by-visit utilities

# helper: null-coalescing without importing rlang
`%||%` <- function(x, y) if (is.null(x)) y else x

#' Create default method specification for MMRM by visit
#'
#' @return list
method_spec_mmrm_by_visit <- function() {
  list(
    method_id = "MMRM_CFB_BY_VISIT",
    family = "mmrm_change_from_baseline_by_visit",
    model = list(
      reml = TRUE,
      ddf_method = "Kenward-Roger",
      covariance = "us",
      fixed_core = c("TRT", "VISIT", "BASE"),
      fixed_optional = c("STRATA1", "STRATA2", "STRATA3"),
      interactions = c("TRT:VISIT", "VISIT:BASE"),
      by_imputation = TRUE,
      combine = "Rubin"
    ),
    fallback = list(
      list(covariance = "us", use_strata = TRUE, use_visit_base = TRUE),
      list(covariance = "ar1", use_strata = TRUE, use_visit_base = TRUE),
      list(covariance = "ar1", use_strata = FALSE, use_visit_base = TRUE),
      list(covariance = "ar1", use_strata = FALSE, use_visit_base = FALSE),
      list(covariance = "cs", use_strata = FALSE, use_visit_base = FALSE)
    ),
    return_datasets = c("ana", "subj_n", "obs_n", "lsm", "diff", "ard")
  )
}

validate_mmrm_spec <- function(spec) {
  req <- c(
    "output_id", "method_id", "dataset_name", "endpoint_label",
    "population_var", "population_value",
    "category_var", "category_value",
    "subject_id", "subject_var",
    "treatment_var", "treatmentn_var", "treatment_levels",
    "control_label", "comparison_label",
    "visit_var", "visitn_var", "visit_include",
    "response_var", "baseline_var", "imputation_var", "strata_vars"
  )

  miss <- setdiff(req, names(spec))
  if (length(miss) > 0) {
    stop("Missing spec fields: ", paste(miss, collapse = ", "))
  }

  if (length(spec$treatment_levels) < 2) {
    stop("spec$treatment_levels must include at least two levels.")
  }

  invisible(spec)
}

prepare_mmrm_datasets <- function(data, spec) {
  validate_mmrm_spec(spec)

  needed_cols <- unique(c(
    spec$population_var,
    spec$category_var,
    spec$subject_id,
    spec$subject_var,
    spec$treatment_var,
    spec$treatmentn_var,
    spec$visit_var,
    spec$visitn_var,
    spec$response_var,
    spec$baseline_var,
    spec$imputation_var,
    spec$dtype_var,
    spec$strata_vars
  ))

  ana <- data |>
    dplyr::filter(
      .data[[spec$population_var]] == spec$population_value,
      .data[[spec$category_var]] == spec$category_value
    ) |>
    dplyr::select(dplyr::any_of(needed_cols)) |>
    dplyr::distinct()

  names(ana)[names(ana) == spec$subject_id] <- "USUBJID"
  names(ana)[names(ana) == spec$subject_var] <- "SUBJID"
  names(ana)[names(ana) == spec$treatment_var] <- "TRT"
  names(ana)[names(ana) == spec$treatmentn_var] <- "TRTN"
  names(ana)[names(ana) == spec$visit_var] <- "VISIT"
  names(ana)[names(ana) == spec$visitn_var] <- "VISITN"
  names(ana)[names(ana) == spec$response_var] <- "RESP"
  names(ana)[names(ana) == spec$baseline_var] <- "BASE"
  names(ana)[names(ana) == spec$imputation_var] <- "IMPNUM"

  if (!is.null(spec$dtype_var) && spec$dtype_var %in% names(ana)) {
    names(ana)[names(ana) == spec$dtype_var] <- "DTYPE"
  } else {
    ana$DTYPE <- NA_character_
  }

  for (i in seq_along(spec$strata_vars)) {
    old <- spec$strata_vars[i]
    new <- paste0("STRATA", i)
    if (old %in% names(ana)) {
      names(ana)[names(ana) == old] <- new
    }
  }

  for (i in seq_len(3)) {
    nm <- paste0("STRATA", i)
    if (!nm %in% names(ana)) ana[[nm]] <- NA_character_
  }

  if (!is.null(spec$visit_exclude)) {
    ana <- ana |> dplyr::filter(!VISIT %in% spec$visit_exclude)
  }

  ana <- ana |>
    dplyr::filter(VISIT %in% spec$visit_include) |>
    dplyr::mutate(
      TRT = factor(TRT, levels = spec$treatment_levels),
      VISIT = factor(VISIT, levels = spec$visit_include),
      IMPNUM = dplyr::coalesce(as.integer(IMPNUM), 1L)
    ) |>
    dplyr::arrange(IMPNUM, VISIT, TRTN, USUBJID)

  strata_present <- c("STRATA1", "STRATA2", "STRATA3")[
    vapply(c("STRATA1", "STRATA2", "STRATA3"),
      function(x) any(!is.na(ana[[x]])),
      logical(1)
    )
  ]

  covar_cols <- c("BASE", strata_present)

  subj_n <- ana |>
    dplyr::distinct(USUBJID, TRT, TRTN, dplyr::across(dplyr::all_of(covar_cols))) |>
    dplyr::filter(dplyr::if_all(dplyr::all_of(covar_cols), ~ !is.na(.x))) |>
    dplyr::count(TRT, TRTN, name = "bigN") |>
    dplyr::arrange(TRTN)

  obs_n <- ana |>
    dplyr::filter(!is.na(RESP)) |>
    {
      if ("DTYPE" %in% names(.) && !all(is.na(.$DTYPE)) && !is.null(spec$n_obs_dtype_values)) {
        dplyr::filter(., is.na(DTYPE) | DTYPE %in% spec$n_obs_dtype_values)
      } else {
        .
      }
    } |>
    dplyr::distinct(USUBJID, VISIT, VISITN, TRT, TRTN) |>
    dplyr::count(VISIT, VISITN, TRT, TRTN, name = "nobs") |>
    dplyr::arrange(VISIT, TRTN)

  visit_ref <- ana |>
    dplyr::distinct(VISIT, VISITN) |>
    dplyr::mutate(
      visit_order = match(as.character(VISIT), spec$visit_include),
      pvalue_flag = as.character(VISIT) %in% spec$pvalue_display_visits
    ) |>
    dplyr::arrange(visit_order, VISITN)

  list(
    ana = ana,
    subj_n = subj_n,
    obs_n = obs_n,
    visit_ref = visit_ref,
    meta = list(
      output_id = spec$output_id,
      method_id = spec$method_id,
      dataset_name = spec$dataset_name,
      endpoint_label = spec$endpoint_label
    )
  )
}

rubin_combine <- function(df, by_cols, est_col = "estimate", se_col = "SE", conf_level = 0.95) {
  alpha <- 1 - conf_level

  df |>
    dplyr::group_by(dplyr::across(dplyr::all_of(by_cols))) |>
    dplyr::summarise(
      m = dplyr::n(),
      qbar = mean(.data[[est_col]], na.rm = TRUE),
      ubar = mean((.data[[se_col]])^2, na.rm = TRUE),
      b = stats::var(.data[[est_col]], na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      b = dplyr::coalesce(b, 0),
      tvar = ubar + (1 + 1 / pmax(m, 1)) * b,
      se_total = sqrt(tvar),
      df = dplyr::case_when(
        m <= 1 ~ 1e6,
        b <= 0 ~ 1e6,
        TRUE ~ (m - 1) * (1 + ubar / ((1 + 1 / m) * b))^2
      ),
      crit = stats::qt(1 - alpha / 2, df = df),
      lower = qbar - crit * se_total,
      upper = qbar + crit * se_total,
      t_stat = qbar / se_total,
      p_two_sided = 2 * (1 - stats::pt(abs(t_stat), df = df)),
      estimate = qbar,
      SE = se_total
    )
}

.build_cov_term <- function(covariance = c("us", "ar1", "cs")) {
  covariance <- match.arg(covariance)
  switch(
    covariance,
    us = "us(VISIT | USUBJID)",
    ar1 = "ar1(VISIT | USUBJID)",
    cs = "cs(VISIT | USUBJID)"
  )
}

.build_mmrm_formula <- function(data, covariance = "us", use_strata = TRUE, use_visit_base = TRUE) {
  strata_terms <- c("STRATA1", "STRATA2", "STRATA3")[
    vapply(c("STRATA1", "STRATA2", "STRATA3"),
      function(x) x %in% names(data) && any(!is.na(data[[x]])),
      logical(1)
    )
  ]

  rhs <- c(
    "TRT",
    "VISIT",
    if (use_strata) strata_terms else NULL,
    "BASE",
    "TRT:VISIT",
    if (use_visit_base) "VISIT:BASE" else NULL,
    .build_cov_term(covariance)
  )

  stats::as.formula(paste("RESP ~", paste(rhs, collapse = " + ")))
}

.fit_one_imp <- function(dat_imp, spec, plan) {
  form <- .build_mmrm_formula(
    data = dat_imp,
    covariance = plan$covariance,
    use_strata = plan$use_strata,
    use_visit_base = plan$use_visit_base
  )

  fit <- mmrm::mmrm(
    formula = form,
    data = dat_imp,
    reml = TRUE,
    method = "Kenward-Roger"
  )

  emm <- emmeans::emmeans(fit, specs = ~TRT | VISIT)

  lsm <- summary(emm, infer = c(TRUE, TRUE)) |>
    tibble::as_tibble() |>
    dplyr::transmute(
      VISIT = as.character(VISIT),
      TRT = as.character(TRT),
      estimate = emmean,
      SE = SE,
      lower = lower.CL,
      upper = upper.CL
    )

  ref_idx <- match(spec$control_label, levels(dat_imp$TRT))
  if (is.na(ref_idx)) {
    stop("control_label not found in treatment levels: ", spec$control_label)
  }

  diff <- emmeans::contrast(emm, method = "trt.vs.ctrl", ref = ref_idx) |>
    summary(infer = c(TRUE, TRUE)) |>
    tibble::as_tibble() |>
    dplyr::transmute(
      VISIT = as.character(VISIT),
      comparison = spec$comparison_label,
      estimate = estimate,
      SE = SE,
      lower = lower.CL,
      upper = upper.CL,
      p_two_sided = p.value
    )

  list(lsm = lsm, diff = diff)
}

fit_mmrm_models <- function(prep, spec, method_spec) {
  plans <- method_spec$fallback
  fits <- purrr::imap(split(prep$ana, prep$ana$IMPNUM), function(dat_imp, imp_id) {
    res <- NULL
    used_plan <- NULL

    for (plan in plans) {
      try_res <- try(.fit_one_imp(dat_imp, spec, plan), silent = TRUE)
      if (!inherits(try_res, "try-error")) {
        res <- try_res
        used_plan <- plan
        break
      }
    }

    if (is.null(res)) {
      stop("All fallback plans failed for IMPNUM = ", imp_id)
    }

    list(
      lsm = dplyr::mutate(res$lsm, IMPNUM = as.integer(imp_id)),
      diff = dplyr::mutate(res$diff, IMPNUM = as.integer(imp_id)),
      plan = tibble::tibble(
        IMPNUM = as.integer(imp_id),
        covariance = used_plan$covariance,
        use_strata = used_plan$use_strata,
        use_visit_base = used_plan$use_visit_base
      )
    )
  })

  list(
    lsm_all = dplyr::bind_rows(purrr::map(fits, "lsm")),
    diff_all = dplyr::bind_rows(purrr::map(fits, "diff")),
    fit_plan = dplyr::bind_rows(purrr::map(fits, "plan"))
  )
}

format_ci <- function(est, lcl, ucl, digits = 3) {
  sprintf(paste0("%.", digits, "f (%.", digits, "f, %.", digits, "f)"), est, lcl, ucl)
}

format_p <- function(p, digits = 4) {
  dplyr::case_when(
    is.na(p) ~ NA_character_,
    p <= 1e-4 ~ "<0.0001",
    p >= 0.9999 ~ ">0.9999",
    TRUE ~ sprintf(paste0("%.", digits, "f"), round(p, digits))
  )
}

build_mmrm_ard <- function(prep, lsm_comb, diff_comb, spec) {
  digits_est <- spec$digits$est %||% 3
  digits_p <- spec$digits$p %||% 4

  subj_n <- prep$subj_n |>
    dplyr::transmute(
      output_id = spec$output_id,
      method_id = spec$method_id,
      group1 = NA_character_,
      group1_level = NA_character_,
      group2 = "TRT",
      group2_level = as.character(TRT),
      variable = spec$endpoint_label,
      context = "mmrm",
      stat_name = "bigN",
      stat_label = "N",
      stat_num = bigN,
      stat_chr = as.character(bigN),
      ord1 = 0L,
      ord2 = TRTN
    )

  obs_n <- prep$obs_n |>
    dplyr::transmute(
      output_id = spec$output_id,
      method_id = spec$method_id,
      group1 = "VISIT",
      group1_level = as.character(VISIT),
      group2 = "TRT",
      group2_level = as.character(TRT),
      variable = spec$endpoint_label,
      context = "mmrm",
      stat_name = "nobs",
      stat_label = "n",
      stat_num = nobs,
      stat_chr = as.character(nobs),
      ord1 = match(as.character(VISIT), spec$visit_include),
      ord2 = TRTN
    )

  lsm_ard <- lsm_comb |>
    dplyr::left_join(dplyr::select(prep$subj_n, TRT, TRTN), by = "TRT") |>
    dplyr::transmute(
      output_id = spec$output_id,
      method_id = spec$method_id,
      group1 = "VISIT",
      group1_level = VISIT,
      group2 = "TRT",
      group2_level = TRT,
      variable = spec$endpoint_label,
      context = "mmrm",
      stat_name = "adj_mean_ci",
      stat_label = "Adjusted mean (95% CI)",
      stat_num = estimate,
      stat_chr = format_ci(estimate, lower, upper, digits = digits_est),
      ord1 = match(VISIT, spec$visit_include),
      ord2 = TRTN
    )

  diff_ard <- diff_comb |>
    dplyr::mutate(
      p_one_sided = dplyr::case_when(
        estimate > 0 ~ p_two_sided / 2,
        estimate < 0 ~ 1 - p_two_sided / 2,
        TRUE ~ 0.5
      ),
      p_one_sided = ifelse(VISIT %in% spec$pvalue_display_visits, p_one_sided, NA_real_)
    )

  diff_ard1 <- diff_ard |>
    dplyr::transmute(
      output_id = spec$output_id,
      method_id = spec$method_id,
      group1 = "VISIT",
      group1_level = VISIT,
      group2 = "COMPARISON",
      group2_level = comparison,
      variable = spec$endpoint_label,
      context = "mmrm",
      stat_name = "adj_diff_ci",
      stat_label = "Adjusted mean difference (95% CI)",
      stat_num = estimate,
      stat_chr = format_ci(estimate, lower, upper, digits = digits_est),
      ord1 = match(VISIT, spec$visit_include),
      ord2 = 99L
    )

  diff_ard2 <- diff_ard |>
    dplyr::transmute(
      output_id = spec$output_id,
      method_id = spec$method_id,
      group1 = "VISIT",
      group1_level = VISIT,
      group2 = "COMPARISON",
      group2_level = comparison,
      variable = spec$endpoint_label,
      context = "mmrm",
      stat_name = "pvalue_1sided",
      stat_label = "1-sided p-value",
      stat_num = p_one_sided,
      stat_chr = format_p(p_one_sided, digits = digits_p),
      ord1 = match(VISIT, spec$visit_include),
      ord2 = 100L
    )

  dplyr::bind_rows(subj_n, obs_n, lsm_ard, diff_ard1, diff_ard2) |>
    dplyr::arrange(ord1, ord2, stat_name)
}

run_mmrm_ard <- function(data, spec, method_spec = method_spec_mmrm_by_visit(), debug = FALSE) {
  prep <- prepare_mmrm_datasets(data, spec)
  fits <- fit_mmrm_models(prep, spec, method_spec)

  lsm_comb <- rubin_combine(fits$lsm_all, by_cols = c("VISIT", "TRT")) |>
    dplyr::mutate(TRT = factor(TRT, levels = spec$treatment_levels)) |>
    dplyr::arrange(VISIT, TRT)

  diff_comb <- rubin_combine(
    dplyr::select(fits$diff_all, -dplyr::any_of("p_two_sided")),
    by_cols = c("VISIT", "comparison")
  ) |>
    dplyr::arrange(VISIT)

  ard <- build_mmrm_ard(prep, lsm_comb, diff_comb, spec)

  out <- list(
    ana = prep$ana,
    subj_n = prep$subj_n,
    obs_n = prep$obs_n,
    lsm = lsm_comb,
    diff = diff_comb,
    ard = ard,
    fit_plan = fits$fit_plan
  )

  if (!debug) {
    out$ana <- out$ana |>
      dplyr::select(USUBJID, TRT, TRTN, VISIT, VISITN, RESP, BASE, IMPNUM, dplyr::starts_with("STRATA"), DTYPE)
  }

  out
}
