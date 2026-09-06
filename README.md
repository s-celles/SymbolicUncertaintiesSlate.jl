# SymbolicUncertaintiesSlate.jl

[![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://s-celles.github.io/SymbolicUncertaintiesSlate.jl/)
[![CI](https://github.com/s-celles/SymbolicUncertaintiesSlate.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/s-celles/SymbolicUncertaintiesSlate.jl/actions/workflows/CI.yml)
[![Documentation](https://github.com/s-celles/SymbolicUncertaintiesSlate.jl/actions/workflows/Documentation.yml/badge.svg)](https://s-celles.github.io/SymbolicUncertaintiesSlate.jl/)
[![License: BSD-3-Clause](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](LICENSE.md)

A set of interactive [Kaimon Slate](https://github.com/kahliburke/KaimonSlate.jl)
notebooks that teach
[`SymbolicUncertainties.jl`](https://github.com/s-celles/SymbolicUncertainties.jl)
— purely symbolic propagation of measurement uncertainty under
**JCGM 100:2008** (the GUM) — from a first `±` through to compiled C.

📖 **[Read the notebooks](https://s-celles.github.io/SymbolicUncertaintiesSlate.jl/)**
— every one rendered as a page, executed at build time with its real output.

## The notebooks

Seven, in reading order. The order is the point.

| # | Notebook | What it answers |
|---|---|---|
| 1 | `uncertainty_intro.jl` | What does `±` build, and why is the answer a formula? |
| 2 | `sensitivity_and_budget.jl` | Which input is costing me the precision? |
| 3 | `sources_and_correlation.jl` | Why is `x - x` exactly zero, and what correlates with what? |
| 4 | `expanded_and_reporting.jl` | How do I write the result down — `k`, §7.2.2, ISO/IEC 17025 §7.8? |
| 5 | `protocol_design.jl` | Given a target `u_c`, what must I buy? |
| 6 | `beyond_first_order.jl` | Is the GUM's linearisation adequate at this operating point? |
| 7 | `codegen_and_deployment.jl` | How does the model reach an instrument? |

Each is a live document: sliders, charts that recompute, tables you can sort.
The rendered site shows the output; running them locally gives you the
controls.

## Running them

Requires the `slate` CLI and Julia ≥ 1.11.

```sh
git clone https://github.com/s-celles/SymbolicUncertaintiesSlate.jl.git
cd SymbolicUncertaintiesSlate.jl
just instantiate
just slate uncertainty_intro          # or: slate notebooks/uncertainty_intro.jl
```

`just` with no arguments lists every entry point.

## Every quantity carries its unit

The notebooks state values as `DynamicQuantities` quantities — `5.000us"V"`,
`0.5000us"A"`, `1000.0us"Ω"` — never as bare numbers. That is not decoration.

A unit annotates a **symbol**, supplied in a dictionary rather than living
inside the expression tree, which is what lets `check_units` verify the model
holds together — including the check nothing else makes, that `u_c` carries
the dimension of its own measurand (§4.3.1) — and lets `evaluate` **derive**
the unit of the answer instead of taking it on trust from a comment.

Bare numbers appear in exactly one place: the boundary of a plotting library,
which takes `Float64`s. The unit then goes in the axis label, and
`contribution_series` hands both over together so they cannot drift apart.

## The package

Almost no metrology lives here. Every number comes from
`SymbolicUncertainties.jl` through its public API; this package is the last
mile a notebook needs and a library has no business carrying.

| Function | Purpose |
|---|---|
| `unit_of` | the unit the model computes for its measurand |
| `sweep` | one input moved across a range, units kept on both traces |
| `budget_table` | an EA-4/02 §7.3 budget a table widget can render |
| `contribution_series` | the same budget as chart series, with its unit |
| `tex` / `mathblock` / `measurement_tex` | typesetting for notebook cells |

## Documentation

Built with [DocumenterSlate.jl](https://github.com/s-celles/DocumenterSlate.jl),
which executes each notebook in an isolated worker and renders it as a
Documenter page. The build is split in two, as DocumenterSlate intends: one
job executes the notebooks and fills a cache, a second consumes only that
cache and never runs notebook code — so the half of the build that runs
arbitrary Julia never has the deploy key in scope.

```sh
just docs      # render the notebooks, then build the site
just serve     # serve docs/build
```

`llms.txt` and `llms-full.txt` are generated into the built site.

## Disclaimer

`SymbolicUncertainties.jl` implements the methodology of JCGM 100:2008 but is
**not** GUM-conformant in an accreditation sense, and neither is anything
here. Use in regulated, safety-critical or ISO/IEC 17025 contexts requires
independent software validation per ISO/IEC 17025 §6.4.7. The calibration
certificates the notebooks produce are specimens, watermarked as such.

## Licence

BSD 3-Clause — see [`LICENSE.md`](LICENSE.md), matching the package these
notebooks document.
