# Julia packages for SOA actuarial and data-science work.
#
# The depot is baked into the image at /opt/julia-depot (see Dockerfile).
# Versions are current at image build time.

using Pkg

pkgs = [
    # General data-science / statistics stack
    "DataFrames", "CSV", "StatsBase", "StatsModels", "GLM", "MixedModels",
    "DecisionTree", "XGBoost", "Clustering", "MultivariateStats", "GLMNet",
    "TimeSeries", "ARCHModels", "Flux", "Turing", "Plots", "MLJ",
    # Databases / SQL
    "DuckDB", "SQLite",
    # JuliaActuary ecosystem (https://github.com/JuliaActuary)
    # ChainLadder.jl is alpha-quality upstream; included anyway for reserving.
    "LifeContingencies", "MortalityTables", "ActuaryUtilities",
    "FinanceModels", "FinanceCore", "EconomicScenarioGenerators",
    "ExperienceAnalysis", "ChainLadder",
]

Pkg.add(pkgs)
Pkg.precompile()
