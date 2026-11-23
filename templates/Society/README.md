---
display_name: "Society of Actuaries"
icon: "https://raw.githubusercontent.com/Actuary-LLC/coder-templates-society-of-actuaries/main/icon/SOA.svg"
---

# Society of Actuaries

A workspace for Society of Actuaries exams that involve coding — **ATPA**
(Advanced Topics in Predictive Analytics), **PA** (Predictive Analytics), and
**SRM** (Statistics for Risk Modeling). It boots from a prebuilt image with:

- **Python, R, and Julia** preinstalled with the packages used across the
  syllabi (see [What's included](#whats-included))
- **[RStudio Server](https://posit.co/download/rstudio-server/)** in the
  browser (the PA exam toolchain is R + RStudio)
- **[code-server](https://github.com/coder/code-server)** (VS Code in the
  browser) with the Python, R, and Julia extensions
- **[OpenCode](https://opencode.ai)** wired to your **LiteLLM** instance
  (model picker auto-populates from the proxy's `/v1/models` catalog)
- **Databases**: [DuckDB](https://duckdb.org) and SQLite for CSV → SQL work,
  plus ODBC/SQL clients in all three languages for external databases
- a **`csv2db` helper** (and raw commands below) to pull `.csv` files into a
  database you can query from SQL or any of the languages
- an optional **GitHub repository** cloned into the workspace on start
- a persistent home (`/home/coder`) that survives workspace rebuilds

## Parameters

| Parameter | Default | Mutable | Description |
|-----------|---------|---------|-------------|
| `docker_image` | `ghcr.io/actuary-llc/coder-templates-society-of-actuaries:latest` | yes | Workspace image (Python/R/Julia + tooling, built by CI from `image/Dockerfile`). |
| `cpu` | `2` | yes | Relative CPU weight (`cpu_shares`). |
| `memory` | `8` | yes | Memory limit in GB (8 GB is a comfortable floor for R/Julia/PyTorch). |
| `git_repo_url` | *(empty)* | yes | Optional HTTPS GitHub URL to clone into `~/<repo>` on every start; supports `/tree/<branch>`. Empty = no clone. |
| `litellm_base_url` | `http://litellm_main:4000` | yes | LiteLLM base URL without `/v1`. Default uses the shared `litellm` overlay network. |

*Mutable* parameters can be changed after workspace creation (triggering a rebuild).

Build-time variables (set at `coder templates push` time, not in the form):

| Variable | Default | Description |
|----------|---------|-------------|
| `github_auth_id` | *(empty)* | ID of the deployment's GitHub external auth provider (empty auto-detects `github`, then `coder-github-oauth`). |
| `litellm_api_key` | *(empty)* | Fallback LiteLLM API key when user secrets are not used. Prefer the secret (below). |

## Secrets

```sh
# LiteLLM API key — injected into the workspace environment at runtime.
coder secret create LITELLM_API_KEY --env LITELLM_API_KEY

# Optional: protect the OpenCode web UI with a fixed password
# (otherwise a generated one is kept in ~/.config/opencode/web-password).
coder secret create OPENCODE_PASSWORD --env OPENCODE_PASSWORD
```

Secrets are per-user and never stored in the template. Nothing in this
template hardcodes credentials.

## LiteLLM

The workspace connects to your LiteLLM instance over the shared **`litellm`
overlay network** (the service publishes no ports). Prerequisite on the Docker
host — the network must exist and be attachable:

```sh
docker network create -d overlay --attachable litellm
```

Consumers wired up out of the box (all reading `LITELLM_BASE_URL` +
`LITELLM_API_KEY` from the environment):

| Tool | How it connects |
|------|-----------------|
| **OpenCode** (web + CLI apps) | OpenAI-compatible provider at `<base>/v1`; every model from `/v1/models` is registered in the model picker. |
| **code-server** | [Continue](https://continue.dev) extension preconfigured (`~/.continue/config.yaml`) against `<base>/v1`. |
| **R / RStudio** | the [`ellmer`](https://ellmer.tidyverse.org) package (example below). |
| anything else | the `LITELLM_BASE_URL` / `LITELLM_API_KEY` environment variables are available in every shell and session. |

Quick check from the terminal:

```sh
curl -H "Authorization: Bearer $LITELLM_API_KEY" "$LITELLM_BASE_URL/v1/models"
```

Use a different gateway by changing the `litellm_base_url` parameter.

## GitHub repository cloning

Set the **Repository** parameter to an HTTPS GitHub URL (optionally with
`/tree/<branch>`); it is cloned into `~/<repo>` on every workspace start and
code-server, RStudio, and OpenCode all open in that folder. Authentication
uses the deployment's GitHub external auth (see the `github_auth_id`
variable) — git and `gh` are signed in automatically. For **private**
repositories, link GitHub under **Account → External Authentication** first.

## CSV → database

### The `csv2db` helper

```sh
csv2db import data.csv                            # -> data.duckdb, table "data"
csv2db import data.csv --table policies           # name the table
csv2db import a.csv b.csv --db study.duckdb        # several files, one database
csv2db import data.csv --db local.sqlite           # or SQLite instead of DuckDB
csv2db tables --db data.duckdb                     # list tables
csv2db query "SELECT * FROM policies LIMIT 5" --db data.duckdb
```

### Raw commands (same result, no helper)

**DuckDB CLI** — create a database and import a CSV:

```sh
duckdb data.duckdb
```

```sql
CREATE TABLE policies AS SELECT * FROM read_csv_auto('data.csv', HEADER=TRUE);
SELECT * FROM policies LIMIT 5;
-- or query the CSV directly, without importing:
SELECT count(*) FROM 'data.csv';
```

**Python:**

```python
import duckdb, pandas as pd

# DuckDB: import, then query with SQL
duckdb.sql("CREATE TABLE policies AS SELECT * FROM read_csv_auto('data.csv')")
print(duckdb.sql("SELECT * FROM policies LIMIT 5").df())

# or work in a DataFrame, then persist
df = pd.read_csv("data.csv")
duckdb.sql("CREATE TABLE policies AS SELECT * FROM df")

# SQLite
import sqlite3
with sqlite3.connect("data.sqlite") as con:
    df.to_sql("policies", con, if_exists="replace", index=False)
```

**R:**

```r
library(duckdb); library(DBI)

con <- dbConnect(duckdb(), "data.duckdb")
dbWriteTable(con, "policies", readr::read_csv("data.csv"))   # or read.csv
dbGetQuery(con, "SELECT * FROM policies LIMIT 5")
dbDisconnect(con, shutdown = TRUE)

# SQLite instead
con <- dbConnect(RSQLite::SQLite(), "data.sqlite")
```

**Julia:**

```julia
using CSV, DataFrames, DuckDB, SQLite

df = CSV.read("data.csv", DataFrame)

con = DBInterface.connect(DuckDB.DB, "data.duckdb")
DuckDB.execute(con, "CREATE TABLE policies AS SELECT * FROM df")
DBInterface.execute(con, "SELECT * FROM policies LIMIT 5")

scon = SQLite.DB("local.sqlite")
SQLite.load!(scon, df, "policies")
```

## SQL connections

Local databases need no credentials (DuckDB files, SQLite files). For
**external** SQL databases, every language has a client installed:

```python
# Python — any SQLAlchemy URL
import pandas as pd
from sqlalchemy import create_engine
eng = create_engine("postgresql+psycopg2://user:pass@host:5432/dbname")
pd.read_sql("SELECT * FROM policies", eng)
# DuckDB and SQLite also work through SQLAlchemy:
#   create_engine("duckdb:///data.duckdb")  /  create_engine("sqlite:///data.sqlite")
```

```r
# R — DBI drivers: odbc (any ODBC DSN), RPostgres, RSQLite, duckdb
library(DBI); library(odbc)
con <- dbConnect(odbc::odbc(), dsn = "my_dsn", uid = "user", pwd = "pass")
dbGetQuery(con, "SELECT * FROM policies LIMIT 5")
# PostgreSQL without ODBC:
#   con <- dbConnect(RPostgres::Postgres(), host = "host", dbname = "dbname", ...)
```

```julia
# Julia — ODBC.jl-style DSNs are not bundled; use native drivers:
using SQLite, DuckDB   # local
# External PostgreSQL: add with  import Pkg; Pkg.add("LibPQ")  (persistent depot)
```

**ODBC DSNs** (for the `odbc` R package / `pyodbc`-style access):
`unixodbc` and the PostgreSQL driver are installed. Add a DSN in
`~/.odbc.ini`:

```ini
[my_dsn]
Driver = PostgreSQL Unicode
Servername = host
Database = dbname
Port = 5432
```

## LLM access from R / RStudio

```r
library(ellmer)

chat <- chat_openai(
  base_url = paste0(Sys.getenv("LITELLM_BASE_URL"), "/v1"),
  api_key  = Sys.getenv("LITELLM_API_KEY"),
  model    = "mimo-v2.6-pro"          # any model your LiteLLM catalog exposes
)
chat$chat("Explain the bias-variance tradeoff for a data science report.")
```

## Adding more packages

The image packages are installed system-wide (versions pinned in
`image/python-requirements.txt`). User additions live in the persistent home:

```sh
pip install --user <package>          # Python -> ~/.local (persistent)
```

```r
install.packages("<package>")         # R -> user library in ~ (persistent)
```

```julia
import Pkg; Pkg.add("<package>")      # Julia -> ~/.julia (persistent);
                                      # the image's /opt/julia-depot stays available
```

## What's included

Exam provenance: **[named]** = explicitly named in a syllabus PDF;
otherwise the package covers a syllabus topic.

| Area | Python | R | Julia | Exam topics |
|------|--------|---|-------|-------------|
| Core data wrangling | numpy, pandas, scipy | tidyverse **[named]** | DataFrames, CSV | ATPA: ETL, joins, data pipelines |
| GLMs / regression | statsmodels, scikit-learn | glm, mgcv, lme4 | GLM, StatsModels, MixedModels | PA, SRM, ATPA |
| Regularized regression | scikit-learn | glmnet | GLMNet | PA, SRM |
| Trees / forests / boosting | scikit-learn, xgboost **[named]** | rpart **[named]**, caret **[named]**, xgboost **[named]**, randomForest, gbm | DecisionTree, XGBoost | PA, SRM, ATPA |
| Clustering / PCA | scikit-learn | cluster, stats | Clustering, MultivariateStats | PA, SRM |
| Neural networks | torch | nnet | Flux | ATPA |
| Bayesian | pymc, arviz | brms | Turing | ATPA |
| Additive / mixed models | pygam | mgcv, lme4 | MixedModels | ATPA |
| Model interpretation | shap, mlxtend | iml, pdp, DALEX, caretEnsemble | MLJ | ATPA: Shapley values, PDP/ICE, stacking |
| Time series / ARCH | pmdarima, arch | forecast, rugarch, tseries | TimeSeries, ARCHModels | SRM |
| Visualization | matplotlib, seaborn, plotly | ggplot2 **[named]** | Plots | PA |
| Metrics / validation | scikit-learn | pROC, ModelMetrics, caret | StatsBase | PA, SRM, ATPA |
| Imputation / unbalanced data | pandas | mice, themis | — | ATPA |
| Reports | python-docx | officer, rmarkdown, knitr | — | ATPA Word deliverable |
| Databases / SQL | sqlalchemy, duckdb, psycopg2 | DBI, odbc, duckdb, RSQLite, RPostgres | DuckDB, SQLite | ATPA: relational databases |
| **Actuarial (JuliaActuary)** | — | — | LifeContingencies, MortalityTables, ActuaryUtilities, FinanceModels, FinanceCore, EconomicScenarioGenerators, ExperienceAnalysis, ChainLadder | Life contingencies, mortality, yields, reserving |

Notes:

- The PA module topics name only **ggplot2, rpart, caret, xgboost**
  (tidyverse "not required"); everything else is topic-driven from the
  ATPA/PA/SRM syllabi. `fastshap` is no longer on CRAN — `iml` provides
  Shapley values instead.
- Julia is not required by any of the syllabi — it is here for the
  [JuliaActuary](https://github.com/JuliaActuary) ecosystem
  (`ChainLadder.jl` is alpha upstream). The unregistered `TermLife.jl` is not
  installed; add it with `Pkg.add(url="https://github.com/JuliaActuary/TermLife.jl")`.
- R package versions are current, while the PA exam environment is pinned to
  R 4.2-era packages — outputs can differ slightly from exam screenshots.

## How it works

The workspace is a `docker_container` that runs `coder_agent`'s init script as
its entrypoint. The image (`image/Dockerfile`, built by
`.github/workflows/build-image.yml`) carries all languages and tools;
`scripts/startup.sh` only starts services (code-server, RStudio Server,
OpenCode), wires LiteLLM, and signs in `gh`. Stopping the workspace destroys
the container; a NAS bind mount holds `/home/coder` so files, user-installed
packages, and git credentials persist.

## Troubleshooting

- **RStudio won't open**: startup runs
  `rserver --www-port=8787 --auth-none=1 --server-user=coder`; logs are in
  `/var/log/rstudio/rstudio-server/rserver.log` inside the workspace. The
  workspace shows "Preparing…" until the startup script exits.
- **OpenCode/Continue can't reach the model**: check
  `curl "$LITELLM_BASE_URL/v1/models"` with your key — the workspace must be
  able to reach the LiteLLM service (default: `litellm` overlay network) and
  the `LITELLM_API_KEY` secret must exist.
- **Private repo clone fails**: link GitHub under **Account → External
  Authentication**; `gh auth status` should list your account.
- **code-server won't open**: `/tmp/code-server.log` inside the workspace has
  its logs.
- **A Julia package needs re-precompiling on first use**: expected when a
  user-added package shadows the baked depot — it happens once.

See [`../../context/coder-template-guide.md`](../../context/coder-template-guide.md)
for the full template anatomy and
[`../../context/common-pitfalls.md`](../../context/common-pitfalls.md) before
restructuring.
