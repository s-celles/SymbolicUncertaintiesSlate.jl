# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-09-06

First release: seven Kaimon Slate notebooks teaching
`SymbolicUncertainties.jl` from a first `±` to compiled C, plus the
presentation helpers they are written against.

### Added

- **Notebooks**, in reading order, under `notebooks/`:
  - `uncertainty_intro.jl` — `±`, the arithmetic operators, Ohm's law,
    dimensional checking, and exact cancellation.
  - `sensitivity_and_budget.jl` — sensitivity coefficients and the EA-4/02
    §7.3 uncertainty budget, live over a voltage divider.
  - `sources_and_correlation.jl` — source provenance, the write-each-input-once
    trap, and `declare_correlated` / `covariance` / `correlation`.
  - `expanded_and_reporting.jl` — coverage factors, Welch–Satterthwaite, the
    four textual forms of JCGM 100:2008 §7.2.2, and a specimen calibration
    certificate in the shape ISO/IEC 17025 §7.8 requires.
  - `protocol_design.jl` — `infer_precision`, `infer_all_precisions`,
    `required_precision` and `budget_allocation`.
  - `beyond_first_order.jl` — `check_linearity`, `linearisation_bound`,
    `second_order_correction` and the JCGM 101:2008 §8.2 Monte Carlo
    cross-check.
  - `codegen_and_deployment.jl` — `build_evaluator` for Julia and C, `to_expr`,
    `latex`, and the `DataFrames` budget rendering.
- **`unit_of`** — the unit a measurement model computes for its measurand,
  derived through `SymbolicUncertainties.evaluate` rather than asserted.
  Accepts a `SymbolicMeasurement` or an `UncertaintyBudget`.
- **`sweep`** — one input moved across a range with every other held fixed,
  returning unit-carrying traces. The measurement form compiles the model once
  with `build_evaluator` and resolves the unit once; the bare-expression form
  takes a required `unit` keyword, since an expression has no measurand to
  derive one from. A swept value stated in another unit of the same dimension
  is converted, not stripped; one of the wrong dimension raises.
- **`budget_table`** — an `UncertaintyBudget` as display rows, symbolic or
  evaluated. The evaluated form gives every cell its own unit — `u(xᵢ)` in the
  unit of `xᵢ`, `cᵢ` in measurand-per-input, the contribution in the unit of
  the measurand — and the variance share as a bare number for an in-cell bar.
- **`contribution_series`** — the same budget as chart series, sorted largest
  first, with the unit of the magnitudes returned alongside them.
- **`tex`**, **`mathblock`**, **`measurement_tex`** — inline LaTeX fragments,
  aligned display blocks, and the two-row form a measurement deserves.
- **`markdown_table`** — a `Vector{NamedTuple}` as a Markdown table, which
  renders as a real table both in Slate and on the published site where a
  `slate_table` falls back to a dump of its own struct (`upstream-bugs.md`
  UB-002). Float cells are rounded for display; a `|` in a cell is escaped.
- Documentation built with
  [DocumenterSlate.jl](https://github.com/s-celles/DocumenterSlate.jl), split
  into a render job that executes notebooks without secrets in scope and a
  deploy job that executes nothing.
- `llms.txt` and `llms-full.txt`, generated into the built site from the page
  tree so they cannot drift.

[Unreleased]: https://github.com/s-celles/SymbolicUncertaintiesSlate.jl/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/s-celles/SymbolicUncertaintiesSlate.jl/releases/tag/v0.1.0
