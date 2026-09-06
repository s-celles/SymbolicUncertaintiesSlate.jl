try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% code id=setup hidecode
using Symbolics
using SymbolicUncertainties
using SymbolicUncertaintiesSlate
using DynamicQuantities
using DataFrames
using Latexify
using Markdown
using Logging

@variables V I σV σI

quiet(f) = with_logger(f, NullLogger())

R_m = quiet() do
    (V ± σV) / (I ± σI)
end

ohm = Dict(
    V => 5.000us"V",  σV => 0.010us"V",
    I => 0.5000us"A", σI => 0.0010us"A",
)

"Ready — R = V/I, plus DataFrames and Latexify for the two rendering extensions."

#%% md id=title title
@md"""
# Code Generation & Deployment

## The formula, as something that runs

A symbolic result is where the metrology ends and the engineering begins. The
same expression that was differentiated, budgeted and inverted can be emitted
as a **compiled Julia function** for a hot loop, or as **C source** for an
instrument's firmware — with the GUM formula visible in the artefact an audit
will read.

This notebook is the last mile in the other direction: out of the notebook,
into a system.
"""

#%% md id=julia_md
@md"""
## 1. A compiled evaluator

`build_evaluator` compiles `(val, err)` through `Symbolics.build_function`
with `expression = Val{false}` — runtime-compiled, sub-100 ns per call on
typical GUM measurements, two orders of magnitude faster than the
`substitute → toexpr → eval` round trip.
"""

#%% code id=julia_demo
g = build_evaluator(R_m, [V, I, σV, σI])

g(5.0, 0.5, 0.01, 0.001)

#%% md id=julia_units_md
@md"""
### A compiled evaluator takes plain numbers — and that is the point

A unit check has no place in an inner loop. But the unit of what it returns
still belongs to the **model**, so it is resolved once, outside the loop,
rather than asserted in a comment.

That is the division of labour worth internalising: `evaluate` for the
answer with its unit, `build_evaluator` for a million answers, and
`unit_of` as the bridge that puts the unit back on.
"""

#%% code id=julia_units
R_unit = unit_of(R_m, ohm)
val, err = g(
    ustrip(ohm[V]), ustrip(ohm[I]), ustrip(ohm[σV]), ustrip(ohm[σI]),
)

(val * R_unit, err * R_unit)

#%% code id=julia_check
# The same numbers the unit-carrying path gives, as they must be.
evaluate(R_m, ohm)

#%% md id=timing_md
@md"""
### What the compilation buys

Both paths below produce the identical pair. One walks the expression tree
and compiles on every call; the other was compiled once.
"""

#%% code id=timing_demo
# Warm both paths, then time a thousand evaluations of each.
g(5.0, 0.5, 0.01, 0.001)
evaluate(R_m, ohm)

t_compiled = @elapsed for _ in 1:1000
    g(5.0, 0.5, 0.01, 0.001)
end
t_walked = @elapsed for _ in 1:10
    evaluate(R_m, ohm)
end

Markdown.parse("""
| path | per call |
|---|---|
| `build_evaluator` (compiled once) | $(round(t_compiled * 1e6 / 1000; sigdigits = 3)) µs |
| `evaluate` (walks + compiles each time) | $(round(t_walked * 1e3 / 10; sigdigits = 3)) ms |

The gap is what makes a Monte Carlo loop or a calibration batch feasible.
Neither number is CI-gated — this is a live measurement on whatever machine
rendered this page, so read the ratio rather than the values.
""")

#%% md id=c_md
@md"""
## 2. C source, for an instrument

`CTarget()` emits C that compiles into firmware, a PLC toolchain, or a
regulated-industry build where the audit trail needs the GUM formula in an
approved artefact.
"""

#%% code id=c_demo
c_source = build_evaluator(
    R_m, [V, I, σV, σI];
    target = CTarget(),
    fname = :ohms_law_evaluator,
)

Markdown.parse("```c\n" * c_source * "\n```")

#%% md id=hypot_md
@md"""
### Why the emitted code says `hypot`, not `sqrt`

The symbolic form of `u_c` is a square root of a sum of squares — the form
every GUM text writes, and the readable one. Evaluated in double precision it
is fragile: the squares overflow once a contribution passes about `1e154` and
underflow to zero below about `1e-150`, so `u_c` comes back as `Inf` or `0`
where `hypot` returns the right number. `hypot` is in `math.h` and in Julia's
`Base`, so the fix costs nothing.

Only the emitted code changes; `m.err` keeps its `sqrt` form. The rewrite
applies exactly when every addend under the root is a square, which is the
uncorrelated regime — under a declared correlation the variance carries
`2·cᵢcⱼ·u(xᵢ,xⱼ)`, not a square and possibly negative, and `hypot` has
nowhere to put it. The emitter falls back to `sqrt` rather than dropping the
cross term.

`FortranTarget` is **not** supported: Symbolics 7 does not export it
(`upstream-bugs.md` UB-004). Wrap the C through `iso_c_binding` if you need
Fortran bindings.
"""

#%% md id=toexpr_md
@md"""
## 3. `to_expr` — the escape hatch

The `(val, err)` pair as plain `Symbolics.Num`s, for a downstream pipeline
this package knows nothing about: `ModelingToolkit`, a hand-written LaTeX
template, your own code generator.

Note that `dof` is deliberately **not** included — read `m.dof` directly if
you need it, so that a two-element tuple never silently becomes three.
"""

#%% code id=toexpr_demo
v_expr, e_expr = to_expr(R_m)

Markdown.parse("""
`to_expr` returns a `$(typeof(v_expr))` pair — the estimate and the combined
standard uncertainty, ready for any consumer of `Symbolics` expressions.
""")

#%% md id=latex_md
@md"""
## 4. LaTeX, through the Latexify extension

`latex(m)` renders a measurement for a certificate. It is provided by the
`SymbolicUncertaintiesLatexifyExt` package extension, so it needs
`Latexify.jl` in the session — and raises a message naming that package
rather than an `UndefVarError` when it is missing.

!!! note "`Markdown` exports `latex` too"
    A session with both `Markdown` and `SymbolicUncertainties` loaded — this
    one — makes the bare name ambiguous, and Julia resolves neither. Qualify
    it. This is the same shape of trap as `±` against `Distributions`, and
    the same fix: name the module you mean.
"""

#%% code id=latex_demo
Markdown.parse("```latex\n" * SymbolicUncertainties.latex(R_m) * "\n```")

#%% md id=tex_note_md
@md"""
That output wraps itself in `\begin{equation}`, which is right for a document
and wrong for a notebook: an equation environment cannot be nested or set
inline. The `tex` helper in this repository strips it back to a fragment, so
the same expression can go in a markdown sentence or a `mathblock` row:
"""

#%% code id=tex_demo
mathblock([measurement_tex(R_m; symbol = "R")])

#%% md id=df_md
@md"""
## 5. The budget as a `DataFrame`

`uncertainty_budget` returns an `AbstractVector` of its rows, so it composes
with every Julia table library **without the package depending on one**. The
`as = :dataframe` keyword routes through the `DataFrames.jl` extension when
that is what you want — for a CSV export, a join against other tabular data,
or a filter.
"""

#%% code id=df_demo
df = uncertainty_budget(R_m, [V, I], [σV, σI]; as = :dataframe)

# A real `DataFrame` — join it, filter it, write it to CSV. Its cells are
# `Symbolics.Num`s, so they are typeset here rather than printed; the
# `relative` column is left out of the display only because the closed form
# runs to a paragraph.
markdown_table([
    (
        variable = "\$" * tex(r.variable) * "\$",
        u = "\$" * tex(r.sigma) * "\$",
        c = "\$" * tex(r.sensitivity) * "\$",
        contribution = "\$" * tex(r.contribution) * "\$",
    ) for r in eachrow(df)
])

#%% md id=df_note_md
@md"""
The runtime has **no** hard dependency on `DataFrames` or on any table
renderer. Requesting `as = :dataframe` without it loaded raises an
`ArgumentError` naming the package — the same posture as `latex`.
"""

#%% md id=pipeline_md
@md"""
## 6. The whole pipeline, in one cell

Model, dimensional check, budget, report, compiled evaluator, C source. Each
step is a call; none of them repeats work another one did.
"""

#%% code id=pipeline_demo
pipeline = quiet() do
    model    = (V ± σV) / (I ± σI)
    units    = check_units(model, Dict(V => us"V", σV => us"V", I => us"A", σI => us"A"))
    budget   = uncertainty_budget(model)
    answer   = evaluate(model, ohm)
    stated   = report(model, ohm; symbol = "R", k = 2, coverage_probability = 0.95)
    compiled = build_evaluator(model, [V, I, σV, σI])
    embedded = build_evaluator(model, [V, I, σV, σI]; target = CTarget())

    (
        dimensionally_consistent = SymbolicUncertainties.is_consistent(units),
        budget_rows = length(budget),
        answer = answer,
        reported = stated.forms[2],
        expanded = stated.expanded,
        compiled_at_bench = compiled(5.0, 0.5, 0.01, 0.001),
        c_lines = count(==('\n'), embedded) + 1,
    )
end

pipeline

#%% md id=closing_md
@md"""
## What you have, at the end of it

The same closed-form expression, in six shapes: a dimensional verdict, a
per-source budget, a number with its unit, a §7.2.2 statement, a machine-code
function, and C for a device.

None of them was transcribed by hand from another, which is the point. A
worked example that ends in a number can only be checked by re-deriving it; a
model that ends in an expression can be *asked* — how sensitive, how much per
source, what precision would I need, is the linearisation adequate, what does
the instrument compute — and every answer stays consistent with all the
others because they came from one object.

!!! warning "Regulated use"
    None of this makes the output GUM-conformant in an accreditation sense.
    `SymbolicUncertainties.jl` implements the methodology; ISO/IEC 17025
    §6.4.7 asks for independent software validation, which is a separate
    activity that this package does not perform and cannot claim.
"""

#%% md id=next_md
@md"""
## Back to the start

- **[Measurement Uncertainty, Symbolically](/n/uncertainty_intro)** — the
  five-minute introduction.
- **[Sensitivity & the Uncertainty Budget](/n/sensitivity_and_budget)** —
  where the precision is going.
- **[Beyond First Order](/n/beyond_first_order)** — whether any of it is
  trustworthy at your operating point.
"""

# ╔═╡ Slate.config · per-notebook settings (Settings panel)
#   docid = 8f92a1c7-3d40-4e75-b16a-2c05d8f4e396
# ╚═╡
