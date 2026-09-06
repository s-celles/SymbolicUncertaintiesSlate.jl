# Getting started

## Reading the notebooks

Every notebook is rendered as a page on this site, executed at build time
with all of its real output. If you only want to read, start at
[Measurement Uncertainty, Symbolically](notebooks/uncertainty_intro.md) and
work down the sidebar — the order is deliberate.

## Running them

The notebooks are interactive: sliders, live charts, tables that recompute.
None of that survives the trip to a static page, so run them locally to get
the part the site cannot show.

You need the `slate` CLI (see
[KaimonSlate.jl](https://github.com/kahliburke/KaimonSlate.jl)) and Julia
≥ 1.11.

```sh
git clone https://github.com/s-celles/SymbolicUncertaintiesSlate.jl.git
cd SymbolicUncertaintiesSlate.jl
just instantiate            # or: julia --project=notebooks -e 'using Pkg; Pkg.instantiate()'
slate notebooks/uncertainty_intro.jl
```

`just slate uncertainty_intro` is the same thing in one word. `just` with no
arguments lists every entry point.

## The notebook environment

`notebooks/Project.toml` is what `slate` and the documentation build both
activate. It carries `SymbolicUncertainties`, this package, `KaimonSlate`,
`DynamicQuantities`, and the optional packages individual notebooks need —
`MonteCarloMeasurements` and `Distributions` for the cross-validation
notebook, `DataFrames` and `Latexify` for the code-generation one.

Both unregistered packages resolve through `[sources]`: this one from the
adjacent working copy, `SymbolicUncertainties` from its repository.

## Two things that will bite you

**`Distributions` breaks `±`.** It re-exports the operator through
`IntervalSets`, so a session with both loaded resolves neither and every
`V ± σV` fails. Build measurements with `SymbolicMeasurement(V, σV)` there
instead. `Measurements.jl` collides the same way. The
[Beyond First Order](notebooks/beyond_first_order.md) notebook does this
throughout and says why.

**Safety warnings are the package working.** Dividing by a symbol whose value
cannot be proven nonzero raises a REQ-140 warning at build time, and
`sqrt`/`log` of a symbol raises REQ-141. Both are advisory — the returned
measurement is valid. The notebooks show one, then wrap subsequent model
construction in a `quiet(f)` helper so the rest of the output stays readable.

## Building the documentation

The build is split in two, as DocumenterSlate intends: one job executes the
notebooks and fills a cache, a second consumes only that cache and never runs
notebook code. That way the half of the build that runs arbitrary Julia never
has the deploy key in scope.

```sh
just render     # executes the notebooks, fills docs/slate_cache
just docs       # render, then build the site (deploydocs no-ops locally)
just serve      # serve docs/build
```
