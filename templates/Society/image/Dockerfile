# Workspace image for the Society of Actuaries Coder template.
#
# Bakes in Python, R (plus RStudio Server), Julia (plus JuliaActuary),
# code-server, OpenCode, and database tooling (DuckDB, SQLite, ODBC) so
# workspace startup stays fast. Built and pushed to GHCR by
# .github/workflows/build-image.yml (image name = this repository).
# Build context is templates/Society (see the workflow).
#
# Everything outside /home/coder is rebuilt when the workspace container is
# recreated, so anything a user must keep belongs in the home directory.

FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG JULIA_SERIES=1.12
ARG JULIA_VERSION=1.12.7
ARG DUCKDB_VERSION=2.0.1
ARG CODE_SERVER_VERSION=4.146.0
ARG RSTUDIO_SERVER_VERSION=2026.11.0-203

# --- base system -------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git jq unzip zip sudo less \
      build-essential gfortran cmake pkg-config \
      python3 python3-pip python3-venv python3-dev \
      libcurl4-openssl-dev libssl-dev libxml2-dev libgit2-dev \
      libfontconfig1-dev libharfbuzz-dev libfribidi-dev \
      libfreetype6-dev libpng-dev libtiff-dev libjpeg-dev \
      unixodbc unixodbc-dev odbcinst odbc-postgresql sqlite3 gh \
    && rm -rf /var/lib/apt/lists/*

# Workspace user; the template bind-mounts the persistent home over /home/coder.
# The stock ubuntu image ships an "ubuntu" user (and group) on UID/GID 1000,
# so they are removed first — the container must run as uid 1000 to match the
# NAS home directory's expectations.
RUN userdel -r ubuntu 2>/dev/null; groupdel ubuntu 2>/dev/null; \
    useradd -m -s /bin/bash -u 1000 coder \
    && echo 'coder ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/coder

# --- Python ------------------------------------------------------------------
COPY image/python-requirements.txt /tmp/python-requirements.txt
# Upgrade pip first (the distro pip's resolver backtracks into ancient
# sdists) and allow wheels only — every pinned package has Python 3.12
# wheels, and sdist builds break on modern setuptools (no pkg_resources).
RUN pip3 install --break-system-packages --no-cache-dir --upgrade pip \
    && pip3 install --break-system-packages --no-cache-dir --only-binary=:all: \
         -r /tmp/python-requirements.txt \
    && pip3 install --break-system-packages --no-cache-dir torch \
         --index-url https://download.pytorch.org/whl/cpu

# Lets users `pip install --user <pkg>` into the persistent home without
# fighting Ubuntu's externally-managed Python policy.
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# --- R + RStudio Server ------------------------------------------------------
RUN curl -fsSL https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc \
      | gpg --dearmor > /etc/apt/trusted.gpg.d/cran_ubuntu_key.gpg \
    && echo "deb https://cloud.r-project.org/bin/linux/ubuntu noble-cran40/" \
      > /etc/apt/sources.list.d/cran.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends r-base r-base-dev \
    && rm -rf /var/lib/apt/lists/*

COPY image/install-r-packages.R /tmp/install-r-packages.R
RUN Rscript /tmp/install-r-packages.R

# Open-source RStudio Server (Posit Workbench community build). The jammy
# build runs fine on noble. Single-user mode: rserver is started as the
# workspace user with --auth-none (see scripts/startup.sh).
RUN curl -fsSL -o /tmp/rstudio-server.deb \
      "https://s3.amazonaws.com/rstudio-server/server/jammy/amd64/rstudio-server-${RSTUDIO_SERVER_VERSION}-amd64.deb" \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/rstudio-server.deb \
    && rm -rf /tmp/rstudio-server.deb /var/lib/apt/lists/* \
    && printf 'www-port=8787\nauth-none=1\nrsession-which-r=/usr/bin/R\n' > /etc/rstudio/rserver.conf

# --- Julia (plus JuliaActuary) ----------------------------------------------
RUN curl -fsSL \
      "https://julialang-s3.julialang.org/bin/linux/x64/${JULIA_SERIES}/julia-${JULIA_VERSION}-linux-x86_64.tar.gz" \
      | tar -xz -C /opt \
    && ln -s "/opt/julia-${JULIA_VERSION}/bin/julia" /usr/local/bin/julia

# Packages are baked into /opt/julia-depot. At runtime the template also puts
# the persistent ~/.julia first in JULIA_DEPOT_PATH so user-added packages
# survive container rebuilds while the baked depot stays available.
ENV JULIA_DEPOT_PATH=/opt/julia-depot
COPY image/install-julia-packages.jl /tmp/install-julia-packages.jl
RUN julia /tmp/install-julia-packages.jl \
    && chmod -R a+rX /opt/julia-depot

# --- DuckDB CLI --------------------------------------------------------------
RUN curl -fsSL \
      "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb-cli-linux-amd64.tar.gz" \
      | tar -xz -C /usr/local/bin duckdb

# --- code-server -------------------------------------------------------------
RUN curl -fsSL -o /tmp/code-server.tar.gz \
      "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" \
    && tar -xzf /tmp/code-server.tar.gz -C /opt \
    && ln -s "/opt/code-server-${CODE_SERVER_VERSION}-linux-amd64/bin/code-server" /usr/local/bin/code-server \
    && rm /tmp/code-server.tar.gz

# --- OpenCode (AI assistant wired to LiteLLM at startup) ---------------------
RUN curl -fsSL https://opencode.ai/v2/install | bash -s -- --no-modify-path \
    && mv /root/.opencode /opt/opencode \
    && ln -s /opt/opencode/bin/opencode /usr/local/bin/opencode \
    && ln -s /opt/opencode/bin/opencode2 /usr/local/bin/opencode2

# --- CSV -> database helper --------------------------------------------------
COPY scripts/csv2db /usr/local/bin/csv2db
RUN chmod 0755 /usr/local/bin/csv2db

USER coder
WORKDIR /home/coder
