try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% code id=setup hidecode
using Symbolics
using SymbolicUncertainties
using SymbolicUncertaintiesSlate
using DynamicQuantities
using Markdown
using Logging

@variables Vin σVin R1 σR1 R2 σR2

# The REQ-140 / REQ-141 safety warnings fire on every division by a symbol
# whose value cannot be proven nonzero. The intro notebook shows one; from
# here on they would be noise, so model construction is wrapped.
quiet(f) = with_logger(f, NullLogger())

"Ready — symbols Vin, σVin, R1, σR1, R2, σR2; `quiet(f)` silences the build-time safety warnings."

#%% md id=title title
@md"""
# Sensitivity & the Uncertainty Budget

## Which input is costing you the precision?

A combined standard uncertainty is one number, and one number cannot be
acted on. The **uncertainty budget** — EA-4/02 §7.3, built on the sensitivity
coefficients of JCGM 100:2008 §5.1.3 — breaks it into one row per input, and
that table is what tells you where the next euro of calibration effort should
go.

Here we build it for a voltage divider, read it, and then move the circuit
around underneath it.
"""

#%% md id=model_md
@md"""
## 1. The model

$$V_{out} = V_{in}\,\frac{R_2}{R_1 + R_2}$$

Three inputs, non-linear in two of them. `propagate` evaluates the function
symbolically on the input estimates, differentiates it with respect to each
input, and assembles equation (10):
"""

#%% code id=model_build
Vout = quiet() do
    propagate(
        (v, r1, r2) -> v * r2 / (r1 + r2),
        [Vin ± σVin, R1 ± σR1, R2 ± σR2],
    )
end

mathblock(["V_{out} &= " * tex(Vout.val)])

#%% md id=sens_md
@md"""
## 2. Sensitivity coefficients

`cᵢ = ∂f/∂xᵢ` is the whole content of §5.1.3: how much the measurand moves
when one input moves. `sensitivity_coefficient` differentiates the model
symbolically — you never write a derivative by hand, and never approximate
one with a finite difference.
"""

#%% code id=sens_demo
mathblock([
    "\\frac{\\partial V_{out}}{\\partial V_{in}} &= " *
        tex(sensitivity_coefficient(Vout, Vin)),
    "\\frac{\\partial V_{out}}{\\partial R_1} &= " *
        tex(sensitivity_coefficient(Vout, R1)),
    "\\frac{\\partial V_{out}}{\\partial R_2} &= " *
        tex(sensitivity_coefficient(Vout, R2)),
])

#%% md id=sens_note_md
@md"""
Read them physically. The sensitivity to `Vin` is the divider ratio itself.
The two resistor sensitivities are equal in magnitude and **opposite in
sign** at `R₁ = R₂` — raising either resistor moves `Vout` the other way from
raising the other, which is why a divider built from a matched pair rejects
what they share. We come back to that in the correlation notebook.
"""

#%% md id=budget_md
@md"""
## 3. The budget, in closed form

`uncertainty_budget(m)` needs no list of variables: the quantity already
knows which independent sources it descends from and with what sensitivity.
A source that cancelled produces no row at all.

The EA-4/02 §7.3 columns are `u(xᵢ)`, `cᵢ`, the contribution
`uᵢ(y) = |cᵢ|·u(xᵢ)`, and its share of the variance.
"""

#%% code id=budget_symbolic
budget = uncertainty_budget(Vout)
slate_table(budget_table(budget))

#%% md id=budget_num_md
@md"""
## 4. The budget, evaluated — with the units kept on

A budget is the one table whose columns are deliberately **heterogeneous in
unit**: `u(R₁)` is in ohms, `∂Vout/∂R₁` is in volts per ohm, and the
contribution is in volts, like the measurand. Stripping the units is exactly
what makes a budget unreadable, so `budget_table` keeps them on every cell
and hands over only the variance share as a bare number, for the bar.
"""

#%% code id=budget_numeric
divider = Dict(
    Vin => 5.000us"V",   σVin => 0.010us"V",
    R1  => 1000.0us"Ω",  σR1  => 10.0us"Ω",
    R2  => 3000.0us"Ω",  σR2  => 20.0us"Ω",
)

slate_table(
    budget_table(budget, divider);
    format = (percent = (kind = :fixed, digits = 1),),
    viz = (percent = :bar,),
)

#%% code id=budget_result
evaluate(Vout, divider)

#%% md id=chart_md
@md"""
## 5. The same table as a picture

`contribution_series` sorts the sources by contribution and hands back
magnitudes plus the unit they are in — the one place a bare number is the
right answer, and naming its unit alongside is the price.
"""

#%% code id=chart_demo
s = contribution_series(budget, divider)

echart(
    series(:bar, s.labels, s.contributions; name = "uᵢ(Vout)");
    title = "Contributions to u_c(Vout)   [$(s.unit)]",
    yAxis = (name = "uᵢ  [V]", type = "value"),
    height = 320,
)

#%% md id=dominant_md
@md"""
`dominant_source` answers the same question in one call — *where should the
effort go?* — and says how it ranked. Contributions all share the measurand's
unit, so the ranking is a comparison of magnitudes and the values are stripped
where it needs them.
"""

#%% code id=dominant_demo
dom = quiet() do
    dominant_source(
        Vout, [Vin, R1, R2], [σVin, σR1, σR2];
        values = Dict(k => ustrip(v) for (k, v) in divider),
    )
end

Markdown.parse("""
The effort belongs on **$(dom.variable)** — budget row $(dom.index), ranked
`$(dom.ranked_by)`.
""")

#%% md id=live_md
@md"""
## 6. Live — the budget is not a property of the instrument

Move the two resistors. The uncertainties on them do not change; which one
dominates does. A budget describes a **model at an operating point**, and
reading it as a fixed property of the hardware is the most common way to
misuse one.
"""

#%% code id=live_controls
@bind r1_k Slider(0.1, 10.0, 1.0; step = 0.1, label = "R₁  [kΩ]")
@bind r2_k Slider(0.1, 10.0, 3.0; step = 0.1, label = "R₂  [kΩ]")
@bind tol  Slider(1.0, 50.0, 10.0; step = 1.0, label = "resistor tolerance u(R)  [Ω]")

live = Dict(
    Vin => 5.000us"V",        σVin => 0.010us"V",
    R1  => r1_k * 1000us"Ω",  σR1  => tol * us"Ω",
    R2  => r2_k * 1000us"Ω",  σR2  => tol * us"Ω",
)

live_series = contribution_series(uncertainty_budget(Vout), live)
out = evaluate(Vout, live)

echart(
    :pie, live_series.labels, live_series.percent;
    title = "Variance share — Vout = $(round(ustrip(out.val); digits = 4)) V, " *
            "u_c = $(round(ustrip(out.err); sigdigits = 2)) V",
    height = 340,
)

#%% code id=live_table
slate_table(
    budget_table(uncertainty_budget(Vout), live);
    format = (percent = (kind = :fixed, digits = 1),),
    viz = (percent = :bar,),
)

#%% md id=live_note_md
@md"""
Two things to try.

**Set `R₁ = R₂`.** The two resistor sensitivities become equal and opposite,
and each takes the same share. **Now make `R₂` ten times `R₁`.** The divider
ratio approaches 1, `∂Vout/∂R₂` collapses toward zero, and the budget becomes
almost entirely the source voltage — the resistors have stopped mattering,
because a divider that barely divides barely cares what it is built from.

**Then push the tolerance up.** Watch `Vin`'s share fall — not because the
voltmeter got better, but because everything else got worse. A percentage is a
share of a total, and a budget row read without its absolute contribution says
much less than it appears to.
"""

#%% md id=invariant_md
@md"""
## 7. The invariant worth knowing

For **uncorrelated** inputs the shares are a genuine variance decomposition:
they sum to one, exactly, symbolically.
"""

#%% code id=invariant_demo
filtered = uncertainty_budget(Vout, [Vin, R1, R2], [σVin, σR1, σR2])

mathblock([
    "\\sum_i \\frac{(c_i u_i)^2}{u_c^2} &= " *
        tex(Symbolics.simplify(sum(row.relative for row in filtered))),
])

#%% md id=invariant_note_md
@md"""
Under a **declared correlation** it stops being one. The JCGM 100:2008 §5.2.2
equation (13) cross terms belong to no single row, so the fractions no longer
sum to 1 and a negative cross term can push one row past 100 %. That is what
`budget.correlated` reports, and why it sits on the budget rather than being
left for the reader to infer:
"""

#%% code id=correlated_flag
(length(budget), budget.correlated)

#%% md id=next_md
@md"""
## Where next

- **[Sources & Correlation](/n/sources_and_correlation)** — what happens to
  this table when two inputs are not independent.
- **[Protocol Design](/n/protocol_design)** — the budget run backwards: given
  a target, what precision must each input have?
"""

# ╔═╡ Slate.config · per-notebook settings (Settings panel)
#   docid = 7c58a2e1-4b90-4d6f-9c31-8e2a4f6b0d73
# ╚═╡
