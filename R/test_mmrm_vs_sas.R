# =============================================================================
# FILE        : test_mmrm_vs_sas.R
# DESCRIPTION : Step-by-step test of create_ard_mmrm.R vs SAS reference output
#               Run each numbered section in order.
#               All comparisons are against rprteff.anstat_PTL0035 (FACIT)
#               and rprteff.anstat_PTL0187 (eGFR) saved by the SAS programs.
# =============================================================================


# =============================================================================
# STEP 0: Setup — GPS connection and package loading
# =============================================================================

library(haven)
library(dplyr)
library(tidyr)
library(purrr)
library(mmrm)
library(emmeans)
library(tibble)

# GPS path — same as your existing setup
ra_root <- "/view/zhaibe1_view/vob/CLNP023A/CLNP023A2301/csr_7"

st <- list(
  ra       = ra_root,
  util     = file.path(ra_root, "util"),
  analysis = file.path(ra_root, "analysis_data"),
  rprteff  = file.path(ra_root, "reports", "eff")
)

# Source your new function file
# Option A: if you put it under pgm/eff/
source(file.path(ra_root, "pgm", "eff", "create_ard_mmrm.R"))

# Option B: if it's still local (e.g. while developing)
# source("create_ard_mmrm.R")


# =============================================================================
# STEP 1: Inspect the raw ADaM data before running anything
#   Goal: confirm variable names and ACAT1 / AVISIT values match spec exactly
# =============================================================================

adfacmi  <- haven::read_sas(file.path(st$analysis, "adfacmi.sas7bdat"))
adgfrmi2 <- haven::read_sas(file.path(st$analysis, "adgfrmi2.sas7bdat"))

# --- 1a. Check variable names exist ---
cat("=== FACIT variable names ===\n")
expected_facit <- c("FASFL", "ACAT1", "USUBJID", "SUBJID",
                    "TRT01P", "TRT01PN", "AVISIT", "AVISITN",
                    "CHG", "BASE", "IMPNUM", "DTYPE",
                    "STRVAL1", "STRVAL2", "STRVAL3")
cat("Present:  ", paste(intersect(expected_facit, names(adfacmi)), collapse = ", "), "\n")
cat("Missing:  ", paste(setdiff(expected_facit, names(adfacmi)), collapse = ", "), "\n\n")

# --- 1b. Check ACAT1 exact values ---
cat("=== FACIT ACAT1 values ===\n")
print(adfacmi |> distinct(ACAT1))

cat("\n=== eGFR ACAT1 values ===\n")
print(adgfrmi2 |> distinct(ACAT1))

# --- 1c. Check AVISIT exact values and numeric order ---
cat("\n=== FACIT AVISIT values (should not include Baseline after MI) ===\n")
print(adfacmi |> distinct(AVISIT, AVISITN) |> arrange(AVISITN))

cat("\n=== eGFR AVISIT values (Baseline will be excluded by spec) ===\n")
print(adgfrmi2 |> distinct(AVISIT, AVISITN) |> arrange(AVISITN))

# --- 1d. Check treatment labels ---
cat("\n=== FACIT treatment levels ===\n")
print(adfacmi |> distinct(TRT01P, TRT01PN) |> arrange(TRT01PN))

# ACTION REQUIRED: if AVISIT labels differ from spec (e.g. "Week 02" vs "Week 2"),
# update spec$visits_model and spec$visits_display accordingly before Step 2.
# Example fix:
#   spec_egfr_14_2_1_9_1$visits_model[1] <- "Week 02"
#   spec_egfr_14_2_1_9_1$visits_display[1] <- "Week 02"


# =============================================================================
# STEP 2: Run the prepare step only — confirm ana, subj_n, obs_n look correct
#   This is the fastest way to catch filter/rename problems
# =============================================================================

prep_facit <- prepare_mmrm_datasets(adfacmi, spec_facit_14_2_4_1)

cat("\n=== FACIT: ana dimensions ===\n")
cat("Rows:", nrow(prep_facit$ana), " | Imputations:", n_distinct(prep_facit$ana$IMPNUM), "\n")
cat("Visits in model:", paste(levels(prep_facit$ana$VISIT), collapse = ", "), "\n")

cat("\n=== FACIT: subj_n (should match SAS bigN) ===\n")
print(prep_facit$subj_n)

cat("\n=== FACIT: obs_n first 10 rows ===\n")
print(head(prep_facit$obs_n, 10))

cat("\n=== FACIT: strata present in model ===\n")
cat(paste(prep_facit$strata_present, collapse = ", "), "\n")


# =============================================================================
# STEP 3: Load SAS reference output
#   The SAS programs write rprteff.anstat_PTL0035 (FACIT) and
#   rprteff.anstat_PTL0187 (eGFR) which contain the final display dataset.
# =============================================================================

# Try the rprteff SAS7BDAT files
sas_facit <- tryCatch(
  haven::read_sas(file.path(st$rprteff, "anstat_PTL0035.sas7bdat")),
  error = function(e) {
    message("anstat_PTL0035.sas7bdat not found. Trying alternate path...")
    haven::read_sas(file.path(ra_root, "reports", "eff", "anstat_PTL0035.sas7bdat"))
  }
)

sas_egfr <- tryCatch(
  haven::read_sas(file.path(st$rprteff, "anstat_PTL0187.sas7bdat")),
  error = function(e) {
    message("anstat_PTL0187.sas7bdat not found.")
    NULL
  }
)

cat("\n=== SAS FACIT reference columns ===\n")
print(names(sas_facit))

cat("\n=== SAS FACIT reference (first 10 rows) ===\n")
print(head(sas_facit |> select(avisitn, avisit, trt01pn, trt01p,
                                bigN, nobs, chg_m, chg_m_diff, pval), 10))


# =============================================================================
# STEP 4: Run the full MMRM function for FACIT
#   Use debug = TRUE on first run to inspect intermediate objects
# =============================================================================

res_facit <- run_mmrm_ard(
  data  = adfacmi,
  spec  = spec_facit_14_2_4_1,
  debug = TRUE   # set FALSE after confirming results
)

cat("\n=== R result: fit_plan (which fallback each imputation used) ===\n")
print(res_facit$fit_plan |> count(covariance, use_strata, use_visit_base))

cat("\n=== R result: subj_n ===\n")
print(res_facit$subj_n)

cat("\n=== R result: lsm (display visits only) ===\n")
print(res_facit$lsm |> filter(VISIT %in% spec_facit_14_2_4_1$visits_display))

cat("\n=== R result: diff ===\n")
print(res_facit$diff |> filter(VISIT %in% spec_facit_14_2_4_1$visits_display))

cat("\n=== R result: ARD ===\n")
print(res_facit$ard)


# =============================================================================
# STEP 5: Numeric comparison — R vs SAS
#   Tolerance 0.001 for estimates (3 d.p. display), 0.0001 for p-values
# =============================================================================

tol_est <- 0.001
tol_p   <- 0.0001

# --- 5a. bigN comparison ---
cat("\n=== COMPARISON: bigN ===\n")
r_bigN <- res_facit$subj_n |>
  transmute(trt01pn = as.integer(TRTN), bigN_R = bigN)

s_bigN <- sas_facit |>
  distinct(trt01pn, bigN) |>
  rename(bigN_SAS = bigN)

bigN_cmp <- left_join(r_bigN, s_bigN, by = "trt01pn") |>
  mutate(diff = bigN_R - bigN_SAS,
         MATCH = diff == 0)
print(bigN_cmp)

# --- 5b. nobs comparison ---
cat("\n=== COMPARISON: nobs by visit x treatment ===\n")
r_nobs <- res_facit$obs_n |>
  transmute(avisitn = as.integer(VISITN),
            trt01pn = as.integer(TRTN),
            nobs_R  = nobs)

s_nobs <- sas_facit |>
  distinct(avisitn, trt01pn, nobs) |>
  rename(nobs_SAS = nobs)

nobs_cmp <- left_join(r_nobs, s_nobs, by = c("avisitn", "trt01pn")) |>
  mutate(diff  = nobs_R - nobs_SAS,
         MATCH = diff == 0)
print(nobs_cmp)

# --- 5c. Adjusted mean comparison ---
cat("\n=== COMPARISON: Adjusted mean (estimate) ===\n")

# Map visit labels to AVISITN using the visit_ref from prep
visit_map <- prep_facit$visit_ref |>
  mutate(VISIT = as.character(VISIT)) |>
  select(VISIT, avisitn = VISITN)

r_lsm <- res_facit$lsm |>
  filter(VISIT %in% spec_facit_14_2_4_1$visits_display) |>
  left_join(visit_map, by = "VISIT") |>
  left_join(res_facit$subj_n |> select(TRT, trt01pn = TRTN), by = "TRT") |>
  transmute(avisitn  = as.integer(avisitn),
            trt01pn  = as.integer(trt01pn),
            est_R    = round(estimate, 3),
            lcl_R    = round(lower, 3),
            ucl_R    = round(upper, 3))

# SAS has: Estimate, LCLMean, UCLMean from PROC MIANALYZE, then formatted to chg_m
# We need the numeric versions; they are stored in anstat_ if the SAS kept them
# (The SAS t_mmrm_egfr.sas kept Estimate_diff, LCLMean_diff for eGFR but not FACIT)
# So we parse chg_m string as fallback

parse_ci_str <- function(x) {
  # Parses "1.234 (0.567, 2.345)" into est, lcl, ucl
  # Returns NA row if format doesn't match
  m <- regmatches(x, regexpr(
    "(-?[0-9.]+)\\s*\\(\\s*(-?[0-9.]+),\\s*(-?[0-9.]+)\\)", x))
  if (length(m) == 0) return(c(NA, NA, NA))
  nums <- as.numeric(regmatches(m, gregexpr("-?[0-9.]+", m))[[1]])
  nums
}

s_lsm <- sas_facit |>
  filter(!is.na(chg_m)) |>
  rowwise() |>
  mutate(parsed = list(parse_ci_str(chg_m)),
         est_SAS = parsed[1],
         lcl_SAS = parsed[2],
         ucl_SAS = parsed[3]) |>
  ungroup() |>
  select(avisitn, trt01pn, est_SAS, lcl_SAS, ucl_SAS)

lsm_cmp <- left_join(r_lsm, s_lsm, by = c("avisitn", "trt01pn")) |>
  mutate(
    diff_est = abs(est_R - est_SAS),
    diff_lcl = abs(lcl_R - lcl_SAS),
    diff_ucl = abs(ucl_R - ucl_SAS),
    MATCH    = diff_est <= tol_est & diff_lcl <= tol_est & diff_ucl <= tol_est
  )
print(lsm_cmp |> select(avisitn, trt01pn, est_R, est_SAS, diff_est, MATCH))

# --- 5d. Treatment difference comparison ---
cat("\n=== COMPARISON: Adjusted mean difference ===\n")

r_diff <- res_facit$diff |>
  filter(VISIT %in% spec_facit_14_2_4_1$visits_display) |>
  left_join(visit_map, by = "VISIT") |>
  transmute(avisitn = as.integer(avisitn),
            est_R   = round(estimate, 3),
            lcl_R   = round(lower, 3),
            ucl_R   = round(upper, 3),
            p_R     = round(
              dplyr::case_when(estimate > 0 ~ p_two_sided / 2,
                               estimate < 0 ~ 1 - p_two_sided / 2,
                               TRUE ~ 0.5), 4))

s_diff <- sas_facit |>
  filter(!is.na(chg_m_diff)) |>
  distinct(avisitn, chg_m_diff, pval, pvaln) |>
  rowwise() |>
  mutate(parsed   = list(parse_ci_str(chg_m_diff)),
         est_SAS  = parsed[1],
         lcl_SAS  = parsed[2],
         ucl_SAS  = parsed[3],
         p_SAS    = round(pvaln, 4)) |>
  ungroup() |>
  select(avisitn, est_SAS, lcl_SAS, ucl_SAS, p_SAS)

diff_cmp <- left_join(r_diff, s_diff, by = "avisitn") |>
  mutate(
    diff_est = abs(est_R - est_SAS),
    diff_p   = abs(p_R - p_SAS),
    MATCH_est = diff_est <= tol_est,
    MATCH_p   = diff_p   <= tol_p | (is.na(p_R) & is.na(p_SAS))
  )
print(diff_cmp |> select(avisitn, est_R, est_SAS, diff_est, MATCH_est,
                          p_R, p_SAS, diff_p, MATCH_p))

# --- 5e. Summary pass/fail ---
cat("\n=== SUMMARY ===\n")
all_pass <- all(bigN_cmp$MATCH, na.rm = TRUE) &&
            all(nobs_cmp$MATCH, na.rm = TRUE) &&
            all(lsm_cmp$MATCH,  na.rm = TRUE) &&
            all(diff_cmp$MATCH_est, na.rm = TRUE) &&
            all(diff_cmp$MATCH_p,   na.rm = TRUE)

if (all_pass) {
  cat("ALL CHECKS PASSED: R output matches SAS within tolerance\n")
  cat("  Estimate tolerance: +/-", tol_est, "\n")
  cat("  P-value tolerance:  +/-", tol_p,   "\n")
} else {
  cat("SOME CHECKS FAILED:\n")
  if (!all(bigN_cmp$MATCH,       na.rm = TRUE)) cat("  [FAIL] bigN mismatch\n")
  if (!all(nobs_cmp$MATCH,       na.rm = TRUE)) cat("  [FAIL] nobs mismatch\n")
  if (!all(lsm_cmp$MATCH,        na.rm = TRUE)) cat("  [FAIL] LSM estimate mismatch\n")
  if (!all(diff_cmp$MATCH_est,   na.rm = TRUE)) cat("  [FAIL] Diff estimate mismatch\n")
  if (!all(diff_cmp$MATCH_p,     na.rm = TRUE)) cat("  [FAIL] P-value mismatch\n")
}


# =============================================================================
# STEP 6: Run eGFR and do quick sanity check
# =============================================================================

# First confirm eGFR visit labels
cat("\n=== eGFR: confirm visit labels before running ===\n")
print(adgfrmi2 |> distinct(AVISIT, AVISITN) |> arrange(AVISITN))

# If "Week 2" or "Month 1" labels differ, fix spec here:
# spec_egfr_14_2_1_9_1$visits_model[1] <- "Week 02"   # example
# spec_egfr_14_2_1_9_1$visits_display[1] <- "Week 02"

res_egfr <- run_mmrm_ard(
  data  = adgfrmi2,
  spec  = spec_egfr_14_2_1_9_1,
  debug = TRUE
)

cat("\n=== eGFR: fallback usage ===\n")
print(res_egfr$fit_plan |> count(covariance, use_strata, use_visit_base))

cat("\n=== eGFR: subj_n ===\n")
print(res_egfr$subj_n)

cat("\n=== eGFR: ARD p-value rows (Month 24 only) ===\n")
print(res_egfr$ard |> filter(stat_name == "pvalue_1sided"))

# If sas_egfr loaded successfully, do a quick numeric check
if (!is.null(sas_egfr)) {
  cat("\n=== eGFR: bigN comparison ===\n")
  r_en <- res_egfr$subj_n |> transmute(trt01pn = as.integer(TRTN), bigN_R = bigN)
  s_en <- sas_egfr |> distinct(trt01pn, bigN) |> rename(bigN_SAS = bigN)
  print(left_join(r_en, s_en, by = "trt01pn") |> mutate(MATCH = bigN_R == bigN_SAS))
}


# =============================================================================
# STEP 7: Known tolerance — why small differences from SAS are expected
# =============================================================================
#
# PROC MIANALYZE and R rubin_combine() use identical formulas, but may differ by
# ~1e-8 due to:
#   1. Floating-point order of operations in matrix inversion (UN covariance)
#   2. SAS uses 64-bit long double internally; R uses double (64-bit)
#   3. Kenward-Roger df approximation may differ by <0.01 df units
#
# Expected matching behaviour:
#   bigN, nobs         : exact integer match
#   estimates (3 d.p.) : |R - SAS| < 0.001 (within display rounding)
#   CI bounds  (3 d.p.) : |R - SAS| < 0.001
#   p-values   (4 d.p.) : |R - SAS| < 0.0001
#
# If differences exceed these tolerances:
#   - Check fit_plan: if any imputation used fallback (ar1/cs), the covariance
#     structure differs from SAS and larger differences are expected
#   - Check IMPNUM range: confirm R and SAS used the same imputations
#   - Check strata_present: confirm same strata entered the R and SAS models


# =============================================================================
# STEP 8: Quick visual check — side-by-side formatted output
# =============================================================================

cat("\n=== SIDE BY SIDE: FACIT Adjusted mean (95% CI) ===\n")
cat("Format: 'estimate (lcl, ucl)' at 3 d.p.\n\n")

r_fmt <- res_facit$ard |>
  filter(stat_name == "adj_mean_ci") |>
  select(group1_level, group2_level, stat_chr) |>
  rename(VISIT = group1_level, TRT = group2_level, R_value = stat_chr)

s_fmt <- sas_facit |>
  filter(!is.na(chg_m)) |>
  left_join(adfacmi |> distinct(AVISIT, AVISITN), by = c("avisit" = "AVISIT")) |>
  select(VISIT = avisit, TRT = trt01p, SAS_value = chg_m)

fmt_cmp <- left_join(r_fmt, s_fmt, by = c("VISIT", "TRT"))
print(fmt_cmp)

cat("\n=== SIDE BY SIDE: FACIT Difference + p-value ===\n")
r_dif <- res_facit$ard |>
  filter(stat_name %in% c("adj_diff_ci", "pvalue_1sided")) |>
  select(group1_level, stat_name, stat_chr) |>
  pivot_wider(names_from = stat_name, values_from = stat_chr) |>
  rename(VISIT = group1_level, R_diff = adj_diff_ci, R_pval = pvalue_1sided)

s_dif <- sas_facit |>
  filter(!is.na(chg_m_diff)) |>
  distinct(avisit, chg_m_diff, pval) |>
  rename(VISIT = avisit, SAS_diff = chg_m_diff, SAS_pval = pval)

print(left_join(r_dif, s_dif, by = "VISIT"))
