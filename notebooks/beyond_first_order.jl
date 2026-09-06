try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% code id=setup hidecode
using Symbolics
using SymbolicUncertainties
using SymbolicUncertaintiesSlate
using DynamicQuantities
using MonteCarloMeasurements
using Distributions
using Markdown
using Logging

@variables V σV I σI
@variables x σx a σa b σb

quiet(f) = with_logger(f, NullLogger())

"Ready — note that `±` is unusable in this session; see the first section."

#%% md id=title title
@md"""
# Beyond First Order

## Where the GUM's linearisation stops being safe

Every result so far rests on one approximation, stated plainly in
JCGM 100:2008 §5.1.1: the law of propagation of uncertainty is a **first-order
Taylor expansion** of the model about the input estimates, valid when the
higher-order terms are negligible.

"Negligible" is a judgement, and this notebook is about making it rather than
assuming it. Four tools, in increasing strength:

| tool | question | answer |
|---|---|---|
| `check_linearity` | is the model curved here? | an indicator, diagonal only |
| `linearisation_bound` | by how much can `u_c` be wrong? | a rigorous bound, mixed partials included |
| `second_order_correction` | does the **estimate** need a correction? | the Amd.1:2026 term |
| `monte_carlo` | does the whole framework hold? | the JCGM 101:2008 §8.2 verdict |

**None of them changes a propagated result.** They report; they never apply.
"""

#%% md id=pm_md
@md"""
## 0. A namespace trap worth knowing

`Distributions.jl` re-exports `±` through `IntervalSets`, so loading it
alongside this package makes the operator **ambiguous** — Julia resolves
neither, and any `V ± σV` in this notebook would fail.

A Monte Carlo cross-check needs `Distributions` by construction, since
JCGM 101:2008 §6.4 wants a density per input. So in a session like this one,
build measurements with the constructor instead. `Measurements.jl` collides
the same way.
"""

#%% code id=pm_demo
# `SymbolicMeasurement(V, σV)`, never `V ± σV`, for the rest of this notebook.
R_m = quiet() do
    SymbolicMeasurement(V, σV) / SymbolicMeasurement(I, σI)
end

mathblock([measurement_tex(R_m; symbol = "R")])

#%% md id=eta_md
@md"""
## 1. `check_linearity` — the curvature indicator

The dimensionless indicator is the ratio of the neglected second-order term
to the retained first-order one:

$$\eta_i = \frac{\partial^2 f/\partial x_i^2 \cdot \sigma_i^2}
                {2 \cdot \partial f/\partial x_i \cdot \sigma_i}$$

`|ηᵢ| ≪ 1` means the linear propagation is safe. Past `0.1` the package
warns and points at Monte Carlo.
"""

#%% code id=eta_demo
η_linear = quiet() do
    check_linearity(t -> 2t + 3, [SymbolicMeasurement(x, σx)])
end
η_exp = quiet() do
    check_linearity(exp, [SymbolicMeasurement(x, σx)])
end

mathblock([
    "\\eta \\;\\text{for}\\; f(x) = 2x + 3 &= " * tex(Symbolics.simplify(η_linear[σx])),
    "\\eta \\;\\text{for}\\; f(x) = e^{x} &= " * tex(η_exp[σx]),
])

#%% md id=eta_note_md
@md"""
Exactly zero for the affine model — a straight line has no second derivative
to neglect — and `σx/2` for the exponential, which grows with the input's own
uncertainty. That is the honest shape of the answer: **nonlinearity is not a
property of the function alone**, but of the function over the region the
uncertainty spans.

The argument of `exp` must be dimensionless — `exp(1 V)` is not a quantity —
so `x` here genuinely carries no unit, and neither does `η`, being a ratio of
two terms of the same dimension.
"""

#%% md id=eta_gap_md
@md"""
### Where the indicator under-reports

`check_linearity` tracks the **diagonal** `∂²f/∂xᵢ²` only. For a product,
every diagonal second derivative is zero while all of the nonlinearity sits
in the mixed partial `∂²(ab)/∂a∂b = 1`:
"""

#%% code id=eta_gap
η_product = quiet() do
    check_linearity(*, [SymbolicMeasurement(a, σa), SymbolicMeasurement(b, σb)])
end

markdown_table([(input = "\$" * tex(k) * "\$", η = "\$" * tex(v) * "\$") for (k, v) in η_product])

#%% md id=bound_md
@md"""
## 2. `linearisation_bound` — a certified answer, not an indicator

`η` evaluates a ratio at a point and warns past a threshold.
`linearisation_bound` answers the question the indicator only gestures at —
*by how much can the first-order result be wrong?* — and answers it
rigorously.

Taylor's theorem with the Lagrange remainder bounds the error by
`½ Σᵢⱼ max|Hᵢⱼ| · (k·uᵢ)(k·uⱼ)`, with each Hessian entry bounded by interval
arithmetic over the whole coverage region. Mixed partials included.
"""

#%% code id=bound_demo
quiet() do
    linearisation_bound(
        exp, [SymbolicMeasurement(x, σx)];
        coverage_factor = 2,
        values = Dict(x => 1.0, σx => 0.1),
    )
end

#%% md id=bound_note_md
@md"""
The claim this supports is **stronger than a Monte Carlo check's**. Sampling
validates by drawing points, so it can only speak for the points it drew; a
bounded symbolic Hessian certifies the entire coverage region at once.

Where no rigorous bound exists — a denominator whose interval spans zero, a
`log` reaching zero, an operation with no interval extension — it raises
rather than returning a number that cannot be trusted. An unsound bound is
worse than none.
"""

#%% md id=correction_md
@md"""
## 3. `second_order_correction` — the Amendment 1:2026 term

`linearisation_bound` bounds the error the first-order law makes in `u_c`.
Whether the **estimate itself** needs a correction is a separate question, and
JCGM 100:2008/Amd.1:2026 answers it: where the nonlinearity is significant,
either use Monte Carlo or include

$$\tfrac{1}{2} \sum_i \frac{\partial^2 f}{\partial x_i^2}\, u^2(x_i)$$

in the expression for `y`.
"""

#%% code id=correction_demo
mathblock([
    "\\text{for } f(x) = x^2:\\quad \\delta y &= " *
        tex(quiet() do
            second_order_correction(t -> t^2, [SymbolicMeasurement(x, σx)])
        end),
])

#%% md id=correction_note_md
@md"""
For `f = x²` the correction is exactly `u²(x)` — the familiar
`E[X²] = μ² + σ²`. For a product of *independent* inputs it is zero, the
Hessian diagonal vanishing; for correlated inputs it is `cov(a,b)`, since
`E[AB] − E[A]E[B]` is precisely the covariance.

The correction is **returned, never applied**. `val` stays the first-order
estimate until you add it yourself: REQ-182 forbids silent higher-order
corrections, and the amendment asks for the term to be included *knowingly*.

Note that the two functions answer different questions, and a model may need
one without the other — a product has an exact estimate and an inexact
combined uncertainty.
"""

#%% md id=mc_md
@md"""
## 4. `monte_carlo` — validating the framework itself

JCGM 101:2008 propagates the input **distributions** by sampling rather than
linearising, and its §8 is explicit that a GUM user would want this to
*validate* the framework's result. `monte_carlo` runs both and compares them.

You must state each input's distribution; it is **never defaulted**. A
standard uncertainty is not a distribution — §6.4 assigns a rectangular
density to a Type B evaluation stated as a half-width and a normal one to a
Type A evaluation, and the choice changes the answer. Defaulting to normal
would also make the exercise circular: a run that assumes normality cannot
discover that normality was the wrong assumption.
"""

#%% code id=mc_demo
quiet() do
    monte_carlo(
        R_m,
        Dict(V => Normal(5.0, 0.01), I => Normal(0.5, 0.001));
        n = 20_000,
    )
end

#%% md id=mc_test_md
@md"""
### What the §8.2 test actually compares

**Coverage intervals, not `u_c`.** Express `u_c` to `ndig` significant
digits; the tolerance `δ` is half a unit in the last of them; the framework
is validated when both interval endpoints agree to within `δ`.

That distinction has teeth. Take an exactly **linear** model — a sum, which
has no higher-order terms at all — with rectangular inputs:
"""

#%% code id=mc_rect
S = quiet() do
    SymbolicMeasurement(V, σV) + SymbolicMeasurement(I, σI)
end

quiet() do
    monte_carlo(
        S,
        Dict(V => Uniform(4.98, 5.02), I => Uniform(0.496, 0.504));
        n = 20_000,
    )
end

#%% md id=mc_rect_note_md
@md"""
The two `u_c` agree and the test still fails. The sum of two uniforms is
**trapezoidal**, so `y ± 1.96·u_c` is the wrong interval even though the
linearisation is perfect.

**"GUM validated" and "the model is linear" are different statements**, and
this is the case that separates them. The same model with normal inputs
passes, because then the output really is normal.
"""

#%% code id=mc_normal
quiet() do
    monte_carlo(
        S,
        Dict(V => Normal(5.0, 0.01), I => Normal(0.5, 0.002));
        n = 20_000,
    )
end

#%% md id=live_md
@md"""
## 5. Live — adequacy is a property of the operating point

Nothing about `R = V/I` changes below. Only the **relative** input
uncertainty does. A quotient of normals is skewed with heavier tails, and at
some point the sampled interval departs from `y ± k·u_c` by more than the
tolerance — while `u_c` itself still agrees to four digits.
"""

#%% code id=live_controls
@bind rel_pct Slider(0.05, 5.0, 1.0; step = 0.05, label = "relative u on both inputs  [%]")
@bind trials  Slider(5_000, 100_000, 20_000; step = 5_000, label = "Monte Carlo trials n")

V_val, I_val = 5.0, 0.5
rel = rel_pct / 100

comparison = quiet() do
    monte_carlo(
        R_m,
        Dict(V => Normal(V_val, rel * V_val), I => Normal(I_val, rel * I_val));
        n = Int(trials),
    )
end

comparison

#%% code id=live_chart
echart(
    series(:bar, ["GUM  y ± k·u_c", "Monte Carlo"],
           [comparison.interval_gum[1], comparison.interval_mc[1]]; name = "lower"),
    series(:bar, ["GUM  y ± k·u_c", "Monte Carlo"],
           [comparison.interval_gum[2], comparison.interval_mc[2]]; name = "upper");
    title = comparison.validated ?
            "VALIDATED at $(rel_pct) % relative input uncertainty" :
            "NOT VALIDATED at $(rel_pct) % — the linearisation is inadequate here",
    yAxis = (name = "R  [Ω]", type = "value"),
    legend = true,
    height = 320,
)

#%% md id=live_note_md
@md"""
Drag the relative uncertainty down to a few tenths of a percent and the
verdict flips to validated; push it up and it fails. **Nothing about the
expression changed** — the operating point did.

That is the practical lesson. "Is the GUM adequate for this measurement?" is
not a question about `V/I`; it is a question about `V/I` *at these
uncertainties*, and it has to be re-asked whenever the bench changes.

Watch the trials slider too. A tail quantile's standard error falls only as
`1/√n`, so a verdict computed near the tolerance boundary can flip on a
rerun. When the discrepancy lands within 25 % of `δ`, `monte_carlo` warns —
read that as "increase `n`", not as a property of the model.
`adaptive = true` removes the guesswork entirely, drawing blocks until the
estimate, `u(y)` and **both interval endpoints** have stabilised, which is
the procedure of §7.9.
"""

#%% md id=finding_md
@md"""
## 6. A finding: the GUM's own §H.1 does not pass

Worth knowing, because it shows what a cross-check is *for*.

The end-gauge example of JCGM 100:2008 Annex H.1 is not validated by the §8.2
test. Its model contains the product `ls·δα·θ`, and the Annex estimates
`δα = 0`. The first-order sensitivity to `θ` is therefore `−ls·δα = 0` — the
framework assigns `θ` **no contribution at all**. Sampling multiplies a
non-zero `δα` by a non-zero `θ` and recovers a variance the linearisation
cannot see, about 12 nm, appearing in quadrature:

```
u_c (first order) = 31.7 nm
missed term       = 11.9 nm
√(31.7² + 11.9²)  = 33.9 nm   = the sampled value
```

The package's first-order result is *correct*: it computes what the GUM
prescribes and reproduces the Annex's published 32 nm. The GUM is the one
neglecting the term.

And that is the whole argument for cross-validation. An Annex H test suite
checks an implementation against the GUM's own worked answers — every one of
which comes from the framework being checked. Only a method that does not
share those assumptions could have surfaced this.
"""

#%% md id=next_md
@md"""
## Where next

- **[Code Generation](/n/codegen_and_deployment)** — once the model is
  trusted, compiling it into something an instrument can run.
- **[Sources & Correlation](/n/sources_and_correlation)** — a declared
  correlation is honoured on both sides of this comparison; sampling the
  inputs independently would silently reproduce the uncorrelated answer.
"""

# ╔═╡ Slate.config · per-notebook settings (Settings panel)
#   docid = 41d8e6b3-5f27-4a09-9e6c-b70f31c8d425
# ╚═╡
