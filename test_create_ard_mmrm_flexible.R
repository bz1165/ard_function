ClearCollect(
    colSelections,
    AddColumns(
        Filter(
            Employees,
            Lower(Trim(ManagerEmail)) = Lower(Trim(User().Email))
        ),
        "SelectedAction",
        "No Change"
    )
);
Set(
    varCurrentTA,
    First(colSelections).TAGroup
)



Set(
    varBatchID,
    "BATCH-" & Text(Now(), "yyyymmdd-hhmmss")
);

Patch(
    Batches,
    Defaults(Batches),
    {
        BatchID:      varBatchID,
        ManagerEmail: User().Email,
        ManagerName:  User().FullName,
        TAGroup:      varCurrentTA,
        SubmittedAt:  Now(),
        Status:       "Pending",
        AddCount:     CountIf(colSelections, SelectedAction = "Add"),
        DropCount:    CountIf(colSelections, SelectedAction = "Drop")
    }
);

ForAll(
    Filter(colSelections, SelectedAction <> "No Change"),
    Patch(
        GPS_Changes,
        Defaults(GPS_Changes),
        {
            BatchID:      varBatchID,
            EmployeeName: ThisRecord.EmployeeName,
            EmployeeID:   ThisRecord.EmployeeID,
            EmailID:      ThisRecord.Email,
            Action:       ThisRecord.SelectedAction,
            TAGroup:      ThisRecord.TAGroup,
            Environment:  "Production",
            ManagerEmail: User().Email,
            Status:       "Pending"
        }
    )
);

Notify(
    "Submitted! " &
    Text(CountIf(colSelections, SelectedAction <> "No Change")) &
    " changes sent to Xiaoran.",
    NotificationType.Success
);

ClearCollect(
    colSelections,
    AddColumns(
        Filter(
            Employees,
            Lower(Trim(ManagerEmail)) = Lower(Trim(User().Email))
        ),
        "SelectedAction",
        "No Change"
    )
)
 
# -------------------------------------------------------------------------
# test_create_ard_mmrm_flexible.R
# Purpose: practical smoke / regression / flexibility tests for the revised
#          create_ard_mmrm_flexible.R implementation
# -------------------------------------------------------------------------

library(dplyr)
library(purrr)

source("create_ard_mmrm_flexible.R")

# 1) Load registry
out_reg <- load_mmrm_registry("eff_mmrm_registry_flexible.csv")

# 2) Prepare datasets list in your study environment
# Example:
# datasets <- list(
#   adfacmi  = haven::read_sas(file.path(st$analysis, "adfacmi.sas7bdat")),
#   adgfrmi2 = haven::read_sas(file.path(st$analysis, "adgfrmi2.sas7bdat")),
#   adupcrmi = haven::read_sas(file.path(st$analysis, "adupcrmi.sas7bdat")),
#   adqs     = haven::read_sas(file.path(st$analysis, "adqs.sas7bdat")),
#   adgfrmi4 = haven::read_sas(file.path(st$analysis, "adgfrmi4.sas7bdat"))
# )

# Replace this with your real datasets object before running the tests.
stopifnot(exists("datasets"))

# -------------------------------------------------------------------------
# A. Single-output smoke tests
# -------------------------------------------------------------------------

# Identity + MI example
res_4241 <- create_ard_mmrm(
  output_id    = "14.2-4.1",
  data         = datasets[["adfacmi"]],
  out_registry = out_reg,
  imp_max      = 10
)

stopifnot(is.data.frame(res_4241$ard))
stopifnot(all(c("result_block", "response_scale", "stat_name") %in% names(res_4241$ard)))
stopifnot(any(res_4241$ard$stat_name == "adj_mean_ci"))
stopifnot(any(res_4241$ard$stat_name == "adj_diff_ci"))
stopifnot(any(res_4241$ard$stat_name == "p_two_sided"))
stopifnot(any(res_4241$ard$stat_name == "p_one_pos"))
stopifnot(any(res_4241$ard$stat_name == "p_one_neg"))

# Logratio example
res_14821 <- create_ard_mmrm(
  output_id    = "14.2-8.2.1",
  data         = datasets[["adupcrmi"]],
  out_registry = out_reg,
  imp_max      = 10
)

stopifnot(all(c("geo_mean_ci", "geo_ratio_ci", "pct_reduction_ci") %in% res_14821$ard$stat_name))
stopifnot(any(res_14821$ard$response_scale == "logratio"))

# TP example
res_tp <- create_ard_mmrm(
  output_id    = "14.2-1.10.3",
  data         = datasets[["adgfrmi2"]],
  out_registry = out_reg,
  imp_max      = 10
)

stopifnot(any(res_tp$ard$stat_name == "tipping_point"))
stopifnot(any(!is.na(res_tp$ard$penalty_term)))

# -------------------------------------------------------------------------
# B. Flexibility tests: no registry edit required
# -------------------------------------------------------------------------

# Example: keep all stats in canonical ARD, but select a lightweight display subset
res_sel <- create_ard_mmrm(
  output_id    = "14.2-4.1",
  data         = datasets[["adfacmi"]],
  out_registry = out_reg,
  results = list(blocks = c("counts", "lsm", "contrast")),
  display = list(pvalue_default = "p_two_sided"),
  imp_max = 10
)

stopifnot(all(unique(res_sel$ard_selected$result_block) %in% c("counts", "lsm", "contrast")))

# Example: temporarily force Month 24 as default display visit
res_override <- create_ard_mmrm(
  output_id    = "14.2-4.1",
  data         = datasets[["adfacmi"]],
  out_registry = out_reg,
  display      = list(pvalue_display_visits = "Month 24"),
  imp_max      = 10
)

stopifnot(any(res_override$ard$group1_level == "Month 24" &
                res_override$ard$stat_name == "p_two_sided" &
                res_override$ard$pvalue_visit_default %in% TRUE))

# -------------------------------------------------------------------------
# C. Batch regression test across all registry rows
# -------------------------------------------------------------------------

all_results <- run_all_mmrm(
  out_registry = out_reg,
  datasets     = datasets,
  imp_max      = 10
)

stopifnot(length(all_results) == nrow(out_reg))

all_ard <- bind_rows(map(all_results, "ard"))
stopifnot(all(c("output_id", "result_block", "stat_name", "response_scale") %in% names(all_ard)))
stopifnot(!any(c("method_id", "result_profile") %in% names(all_ard)))

# Optional: compare to old v3 outputs if you have a saved reference object
# old_results <- readRDS("reference_mmrm_v3_imp10.rds")
# Compare bigN / nobs / adj_mean_ci / adj_diff_ci numerically within tolerance

message("All flexible MMRM smoke/regression tests passed.")
