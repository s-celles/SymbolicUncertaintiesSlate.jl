```@meta
CurrentModule = SymbolicUncertaintiesSlate
```

# SymbolicUncertaintiesSlate.jl

Interactive [Kaimon Slate](https://github.com/kahliburke/KaimonSlate.jl)
notebooks for
[`SymbolicUncertainties.jl`](https://github.com/s-celles/SymbolicUncertainties.jl)
— purely symbolic propagation of measurement uncertainty under
**JCGM 100:2008** (the GUM), taken from a first `±` through to compiled C.

Seven notebooks, in reading order, each one a live document you can move the
inputs of:

| # | Notebook | What it answers |
|---|---|---|
| 1 | [Measurement Uncertainty, Symbolically](notebooks/uncertainty_intro.md) | What does `±` build, and why is the answer a formula? |
| 2 | [Sensitivity & the Uncertainty Budget](notebooks/sensitivity_and_budget.md) | Which input is costing me the precision? |
| 3 | [Sources & Correlation](notebooks/sources_and_correlation.md) | Why is `x - x` exactly zero, and what correlates with what? |
| 4 | [Expanded Uncertainty & Reporting](notebooks/expanded_and_reporting.md) | How do I write the result down? |
| 5 | [Protocol Design](notebooks/protocol_design.md) | Given a target, what must I buy? |
| 6 | [Beyond First Order](notebooks/beyond_first_order.md) | Is the linearisation adequate here? |
| 7 | [Code Generation & Deployment](notebooks/codegen_and_deployment.md) | How does the model reach an instrument? |

The [Overview](notebooks.md) page describes the arc; each notebook page below
is the notebook itself, executed at build time with every cell's real output.

## Every quantity carries its unit

The notebooks state values as `DynamicQuantities` quantities —
`5.000us"V"`, `0.5000us"A"` — and never as bare numbers. That is not
decoration. A unit is an annotation of a *symbol*, supplied in a dictionary,
so `check_units` can verify the model holds together (including that `u_c`
carries the dimension of its own measurand, §4.3.1) and `evaluate` can
**derive** the unit of the answer rather than take it on trust.

Bare numbers appear in exactly one place: at the boundary of a plotting
library, which takes `Float64`s. The unit goes in the axis label, and
[`contribution_series`](@ref) hands both over together so the two cannot
drift apart.

## What this package contains

Almost no metrology. Every number comes from `SymbolicUncertainties.jl`;
what lives here is the last mile a notebook needs and a library has no
business carrying:

- [`unit_of`](@ref) — the unit the model computes for its measurand;
- [`sweep`](@ref) — one input moved across a range, units kept on both traces;
- [`budget_table`](@ref) — an EA-4/02 §7.3 budget a table widget can render;
- [`contribution_series`](@ref) — the same budget as chart series;
- [`tex`](@ref), [`mathblock`](@ref), [`measurement_tex`](@ref) — typesetting.

See the [API reference](api.md).

!!! warning "Regulated-use disclaimer"
    `SymbolicUncertainties.jl` implements the methodology of JCGM 100:2008 but
    is **not** GUM-conformant in an accreditation sense, and neither is
    anything on this site. Use in regulated, safety-critical or
    ISO/IEC 17025 contexts requires independent software validation per
    ISO/IEC 17025 §6.4.7. The calibration certificates the notebooks produce
    are specimens, watermarked as such.

## Installation

Neither package is registered yet, so install from the repositories:

```julia
using Pkg
Pkg.add(url = "https://github.com/s-celles/SymbolicUncertainties.jl")
Pkg.add(url = "https://github.com/s-celles/SymbolicUncertaintiesSlate.jl")
```

To run the notebooks live, see [Getting started](getting-started.md).
