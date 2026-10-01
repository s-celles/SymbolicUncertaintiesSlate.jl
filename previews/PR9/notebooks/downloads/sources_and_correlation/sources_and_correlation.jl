try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% code id=setup hidecode
using Symbolics
using SymbolicUncertainties
using SymbolicUncertaintiesSlate
using DynamicQuantities
using Markdown
using Logging

@variables V σV R σR
@variables Vin σVin R1 σR1 R2 σR2
@variables Va σVa Vb σVb ρ

quiet(f) = with_logger(f, NullLogger())

"Ready — symbols for a divider, a pair of voltmeters, and a correlation coefficient ρ."

#%% md id=title title
@md"""
# Sources & Correlation

## Where an uncertainty comes from, and what it shares

A bare uncertainty number cannot answer two questions that matter constantly
in practice:

1. Is `x - x` zero? Two numbers cannot say — the operands are
   indistinguishable once reduced to a pair of values.
2. Are these two results correlated *because they descend from the same
   measurement*? Again, numbers alone cannot say. And this is precisely the
   case where nobody can hand you a covariance matrix, because the person
   writing the model is the person who does not know it.

`SymbolicUncertainties.jl` answers both from one structure: a quantity
carries the **independent sources** it derives from, and with what
sensitivity. Everything else — `u_c`, the budget, covariance — is derived
from that.
"""

#%% md id=provenance_md
@md"""
## 1. What a measurement actually carries

Each `±` mints a **fresh** source. The descriptors live in the quantity, not
in a global registry — which is what keeps `Symbolics.substitute` purely
local, since replacing `σV` with a number has somewhere to land.
"""

#%% code id=provenance_demo
v = V ± σV

# `terms_of` maps each source to this quantity's sensitivity to it;
# `sources_of` maps the same key to the source itself — its name, the input
# variable it came from, and its standard uncertainty.
terms = SymbolicUncertainties.terms_of(v)
srcs = SymbolicUncertainties.sources_of(v)

markdown_table([
    (
        source = string(srcs[id].name),
        variable = srcs[id].variable === nothing ? "—" : "\$" * tex(srcs[id].variable) * "\$",
        u = "\$" * tex(srcs[id].u) * "\$",
        sensitivity = "\$" * tex(c) * "\$",
    ) for (id, c) in terms
])

#%% md id=err_md
@md"""
So `m.err` is a **computed property**, not a stored field: the combined
standard uncertainty is the quadratic form over the source covariance
structure. With independent sources it reduces to §5.1.2 equation (10); when
covariances are declared, the cross terms of §5.2.2 equation (13) appear. Two
GUM formulas, one expression — not two code paths.
"""

#%% code id=err_demo
mathblock(["u_c(V) &= " * tex(v.err)])

#%% md id=cancel_md
@md"""
## 2. Cancellation is exact

Because identity lives in the object, an expression that reuses the same
measurement cancels through the **plain operators**. There is no special
"exact" mode to opt into.
"""

#%% code id=cancel_demo
x = 8.4 ± 0.7

Markdown.parse("""
| expression | result |
|---|---|
| `x - x` | $(repr(x - x)) |
| `x / x` | $(repr(x / x)) |
| `x + x` | $(repr(x + x)) |
| `x^2 / x` | $(repr(x^2 / x)) |
""")

#%% md id=cancel_note_md
@md"""
`x + x` is `2x` with uncertainty `2u`, **not** `u√2`. That distinction is
worth a moment: adding a quantity to itself is not the same experiment as
adding two independently measured quantities of the same size, and a package
that stored only numbers would give the second answer to the first question.
"""

#%% md id=shared_md
@md"""
## 3. Shared sources correlate, with no matrix from anyone

Power and current, measured on the same voltmeter and the same resistor:

$$P = \\frac{V^2}{R}, \\qquad I = \\frac{V}{R}, \\qquad \\frac{P}{I} = V$$

Divide them and the answer must be exactly the voltage measurement you
started from — `R` cancels, and `V` keeps its own uncertainty and nothing
more. That only works if the machinery *knows* both descend from the same
two sources.
"""

#%% code id=shared_demo
vm = V ± σV
rm = R ± σR

p = quiet() do
    vm * vm / rm
end
i = quiet() do
    vm / rm
end

# Exactly the voltage measurement we started from: R cancels, V keeps its own
# uncertainty and gains nothing.
mathblock([measurement_tex(quiet() do
    p / i
end; symbol = "P/I")])

#%% md id=trap_md
@md"""
## 4. The trap: identity is the object, never the name

Here is the flip side, and it costs real money in real budgets.

A voltage divider has **three** physical inputs. Write `R2 ± σR2` twice and
you have declared *two* independent resistors that happen to share a
tolerance symbol — which is exactly what two nominally identical resistors
from the same reel look like, so nothing warns you.
"""

#%% code id=trap_demo
wrong = quiet() do
    (Vin ± σVin) * (R2 ± σR2) / ((R1 ± σR1) + (R2 ± σR2))
end

# One object per physical input, reused wherever it appears.
vin_m, r1_m, r2_m = (Vin ± σVin), (R1 ± σR1), (R2 ± σR2)
right = quiet() do
    vin_m * r2_m / (r1_m + r2_m)
end

(wrong = length(uncertainty_budget(wrong)), right = length(uncertainty_budget(right)))

#%% md id=trap_cost_md
@md"""
Four budget rows for three inputs is the visible symptom. The invisible one
is the number:
"""

#%% code id=trap_cost
divider = Dict(
    Vin => 5.0us"V",     σVin => 0.01us"V",
    R1  => 1000.0us"Ω",  σR1  => 10.0us"Ω",
    R2  => 3000.0us"Ω",  σR2  => 20.0us"Ω",
)

Markdown.parse("""
| model | u_c(Vout) |
|---|---|
| `R2 ± σR2` written twice | $(round(ustrip(evaluate(wrong, divider).err); sigdigits = 3)) V |
| one object per input | $(round(ustrip(evaluate(right, divider).err); sigdigits = 3)) V |
""")

#%% md id=trap_rule_md
@md"""
The correct value is the second. The first double-counts `R₂` instead of
combining its two sensitivities — which partially cancel, since `R₂` appears
in both numerator and denominator — and overstates `u_c` by a factor of about
2.5.

**The rule is one line: bind each physical input to a variable once, then use
that variable everywhere it appears in the model.**
"""

#%% md id=declared_md
@md"""
## 5. Correlation between sources that are *not* shared

Two instruments calibrated against the same reference standard are correlated
without descending from a common measurement in your model.
`declare_correlated` states it, returns **new** quantities, and mutates
nothing — so two hypotheses can live in one session.
"""

#%% code id=declared_demo
a, b = declare_correlated(Va ± σVa, Vb ± σVb, ρ)

mathblock([
    "u_c(a + b) &= " * tex((a + b).err),
    "u_c(a - b) &= " * tex((a - b).err),
])

#%% md id=declared_note_md
@md"""
Those are the cross terms of equation (13): `± 2ρ·u(a)·u(b)`. With `ρ = 0`
the expression collapses onto equation (10). One implementation, two regimes.

And the covariance JCGM 102:2011 §6 asks for — the fact a downstream user
needs in order to combine two outputs further — falls out of the same
structure:
"""

#%% code id=cov_demo
mathblock([
    "\\operatorname{cov}(a, b) &= " * tex(covariance(a, b)),
    "\\rho(a, b) &= " * tex(Symbolics.simplify(correlation(a, b))),
])

#%% md id=live_md
@md"""
## 6. Live — why a matched pair beats two good resistors

Two nominally identical instruments, each with `u = 0.5 V`. Sweep their
correlation from perfectly anti-correlated to perfectly correlated, and watch
what happens to their **sum** and their **difference**.
"""

#%% code id=live_chart
# ρ is dimensionless, so it enters the dictionary as a plain real — the one
# kind of input that carries no unit, because a ratio of two quantities of
# the same dimension has none.
pair = Dict(
    Va => 10.0us"V", σVa => 0.5us"V",
    Vb => 4.0us"V",  σVb => 0.5us"V",
    ρ => 0.0,
)
rhos = range(-0.99, 0.99; length = 199)

# `.err` rather than the measurement itself: it is the combined uncertainty
# that is being swept, and a bare expression takes its unit from the caller.
sum_band  = sweep((a + b).err, pair, ρ, rhos; unit = us"V")
diff_band = sweep((a - b).err, pair, ρ, rhos; unit = us"V")

echart(
    series(:line, collect(rhos), ustrip.(sum_band);
           name = "u_c(a + b)", smooth = true, symbol = "none"),
    series(:line, collect(rhos), ustrip.(diff_band);
           name = "u_c(a − b)", smooth = true, symbol = "none");
    title = "Correlation is not a nuisance — it is a design variable",
    xAxis = (name = "ρ", type = "value"),
    yAxis = (name = "u_c  [V]", type = "value"),
    legend = true,
    height = 360,
)

#%% md id=live_note_md
@md"""
At `ρ = 0` both curves sit at `0.5·√2 ≈ 0.707 V`, the uncorrelated answer.
Push `ρ → +1` and the **difference** collapses toward zero while the sum
inflates to `1.0 V`; push `ρ → −1` and they swap.

This is not an artefact. It is the reason a divider built from a matched pair
on one substrate beats a divider built from two separately excellent
resistors: what the pair shares — the same reel, the same oven, the same
thermal drift — cancels in the ratio. A budget that assumes independence
cannot see that, and will quote you a worse instrument than you built.
"""

#%% md id=refusal_md
@md"""
Note also what `declare_correlated` does not let you do. A correlation matrix
that is not positive semi-definite has no joint distribution behind it, and
pairwise coefficients assigned by hand produce one easily —
`ρ(x,y) = ρ(x,z) = 0.9` with `ρ(y,z) = −0.9` asks two inputs to track a third
closely while opposing each other. The Monte Carlo cross-check in
**[Beyond First Order](/n/beyond_first_order)** refuses such a matrix rather
than sampling something that cannot exist.
"""

#%% md id=next_md
@md"""
## Where next

- **[Expanded Uncertainty & Reporting](/n/expanded_and_reporting)** — turning
  `u_c` into a number a certificate can carry.
- **[Beyond First Order](/n/beyond_first_order)** — sampling the correlated
  model to check the framework itself.
"""

# ╔═╡ Slate.config · per-notebook settings (Settings panel)
#   docid = 5a3d81f7-2c64-4e0b-b8d9-6f47a20c3e58
# ╚═╡
