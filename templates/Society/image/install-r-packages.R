# R packages for SOA ATPA / PA / SRM exam work.
#
# Binaries come from Posit Package Manager for the matching Ubuntu release so
# the image build stays fast; versions are current at image build time.

options(
  repos = c(P3M = "https://packagemanager.posit.co/cran/__linux__/noble/latest"),
  HTTPUserAgent = sprintf(
    "R/%s R (%s)",
    getRversion(),
    paste(getRversion(), R.version$platform, R.version$arch, R.version$os)
  )
)

pkgs <- c(
  # Named in the PA module topics syllabus
  "ggplot2", "rpart", "caret", "xgboost", "tidyverse",
  # PA syllabus topics: regularized regression, trees/forests/boosting, metrics
  "glmnet", "randomForest", "gbm", "pROC", "ModelMetrics",
  # SRM syllabus topics: time series, KNN, clustering
  "forecast", "rugarch", "tseries", "class", "MASS", "cluster",
  # ATPA learning objectives: additive/mixed models, neural nets, Bayesian,
  # stacking/blending, Shapley values, PDP/ICE, imputation, unbalanced data
  "mgcv", "lme4", "nnet", "brms", "iml", "pdp", "DALEX",
  "caretEnsemble", "mice", "themis", "officer",
  # Databases / SQL
  "DBI", "odbc", "duckdb", "RSQLite", "RPostgres",
  # Reports (ATPA deliverable) and the LLM client used from RStudio
  "rmarkdown", "knitr", "ellmer"
)

install.packages(pkgs, Ncpus = max(1L, parallel::detectCores()))

missing <- setdiff(pkgs, rownames(installed.packages()))
if (length(missing) > 0) {
  stop("Failed to install R packages: ", paste(missing, collapse = ", "))
}
