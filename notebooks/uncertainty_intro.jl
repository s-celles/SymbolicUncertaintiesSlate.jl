try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% code id=setup hidecode
using Symbolics
using SymbolicUncertainties
using SymbolicUncertaintiesSlate
using DynamicQuantities
using Markdown
using Logging

# The symbols of the model. A measurement model names its inputs; the units
# come later, as an annotation of these symbols rather than a value inside
# them.
@variables V I σV σI

"Ready — symbols V, I, σV, σI; helpers tex / mathblock / unit_of / sweep loaded."

#%% md id=title title
@md"""
# Measurement Uncertainty, Symbolically

## Getting started with SymbolicUncertainties.jl

Most uncertainty software gives you a *number*. This one gives you the
**formula** — a closed-form expression for the combined standard uncertainty
of any differentiable measurement model, following the methodology of
**JCGM 100:2008**, the *Guide to the Expression of Uncertainty in
Measurement* (GUM).

A number tells you how good your measurement is. A formula tells you *why*,
and what to change.

!!! warning "Not calibration software"
    `SymbolicUncertainties.jl` implements the GUM's methodology but has not
    been independently validated for accreditation use. Nothing here is a
    calibration certificate. See the package's *Limitations* page before
    using it anywhere it matters.
"""

#%% md id=pm_md
@md"""
## 1. A measurement is an estimate and a dispersion

The infix constructor `±` pairs an estimate with its **standard
uncertainty** `u`. Either side can be a symbol, a number, or a mixture.

Note that `±` here builds a *combined standard uncertainty* `u_c`, following
the Julia convention set by `Measurements.jl`. JCGM 100:2008 §7.2.2
deliberately avoids the glyph in a **reported** result, where `±` is read as
an expanded uncertainty `y ± U = y ± k·u_c` — a different quantity by the
factor `k`. We come back to that in the reporting notebook.
"""

#%% code id=pm_demo
V_m = V ± σV
I_m = I ± σI

mathblock([
    "V &= " * tex(V_m),
    "I &= " * tex(I_m),
])

#%% md id=ohm_md
@md"""
## 2. Ohm's law — the GUM's canonical example

Divide one measurement by another and the quotient rule of JCGM 100:2008
§5.1.2 is applied for you. Nothing numeric happens: what comes back is
algebra.
"""

#%% code id=ohm_build
# Dividing by a symbol whose value cannot be proven nonzero raises a
# REQ-140 warning. That is the package doing its job — shown once here,
# silenced below — and the returned measurement is perfectly valid.
R_m = V_m / I_m

mathblock([measurement_tex(R_m; symbol = "R")])

#%% md id=ohm_check_md
@md"""
That second line is the GUM §5.1.2 equation (10) written out for `R = V/I`.
It is algebraically the familiar relative-uncertainty form

$$\frac{u_c(R)}{R} = \sqrt{\left(\frac{u(V)}{V}\right)^2 + \left(\frac{u(I)}{I}\right)^2}$$

— the package just never divides through, because it has no reason to assume
`V` and `I` are nonzero.
"""

#%% md id=units_md
@md"""
## 3. Units annotate the symbols, and the answer derives its own

A unit is not a value inside the expression tree — dragging one through every
derivative and simplification would be miserable. It is an **annotation of a
symbol**, supplied in a dictionary. `ModelingToolkit` makes the same choice.

Two things follow. `check_units` can tell you whether the model holds
together — including the check nothing else makes, that `u_c` carries the
dimension of *its own measurand* (§4.3.1), which is invisible elsewhere
because `y` and `u` live in different fields. And `evaluate` **derives** the
unit of the result rather than taking it on trust from a comment.
"""

#%% code id=units_check
check_units(R_m, Dict(V => us"V", σV => us"V", I => us"A", σI => us"A"))

#%% code id=units_evaluate
readings = Dict(
    V => 5.000us"V", σV => 0.010us"V",
    I => 0.5000us"A", σI => 0.0010us"A",
)

evaluate(R_m, readings)

#%% md id=units_note_md
@md"""
Nobody wrote `Ω` anywhere above. `A⁻¹ V` is what the model *computes*, and
that is the point: a worked example ending in a bare `10.0` and a `# ohms`
comment records what its author believed, which is a different thing.

`unit_of` is that derived unit on its own, resolved once so it can be
re-attached to the magnitudes a compiled evaluator returns:
"""

#%% code id=unit_of_demo
unit_of(R_m, readings)

#%% md id=live_md
@md"""
## 4. Live — move the instrument, watch the uncertainty

Everything below is the *same* symbolic expression, evaluated at whatever the
controls say. The formula never recompiles; only the numbers move.
"""

#%% code id=live_controls
@bind V_read  Slider(1.0, 12.0, 5.0;      step = 0.1,    label = "V reading  [V]")
@bind V_unc   Slider(0.001, 0.100, 0.010; step = 0.001,  label = "u(V)  [V]")
@bind I_read  Slider(0.05, 2.00, 0.50;    step = 0.01,   label = "I reading  [A]")
@bind I_unc   Slider(0.0001, 0.0100, 0.0010; step = 0.0001, label = "u(I)  [A]")

# The sliders hand back plain numbers; the unit is attached here, where the
# reading becomes a quantity. Nothing downstream ever sees a bare value.
live = Dict(
    V => V_read * us"V", σV => V_unc * us"V",
    I => I_read * us"A", σI => I_unc * us"A",
)

result = evaluate(R_m, live)
relative = 100 * ustrip(result.err) / ustrip(result.val)

Markdown.parse("""
| | |
|---|---|
| **R** | $(round(ustrip(result.val); digits = 4)) Ω |
| **u_c(R)** | $(round(ustrip(result.err); sigdigits = 2)) Ω |
| **relative** | $(round(relative; sigdigits = 2)) % |
""")

#%% md id=sweep_md
@md"""
### Where does the precision come from?

Hold the two instruments fixed and move the **current** through the model.
The absolute uncertainties `u(V)` and `u(I)` do not change; the resistance
being measured does — and with it, how much each instrument matters.

`sweep` compiles the model once with `build_evaluator` and evaluates it
across the range, keeping the unit on both traces.
"""

#%% code id=sweep_chart
currents = range(0.05, 2.0; length = 200) .* us"A"
band = sweep(R_m, live, I, currents)

# Magnitudes reach the plotting library; the units go in the axis labels,
# which is the only honest place for a bare number.
echart(
    series(:line, ustrip.(currents), ustrip.(band.err);
           name = "u_c(R)", smooth = true, symbol = "none");
    title = "Combined standard uncertainty of R = V/I",
    xAxis = (name = "I  [A]", type = "value"),
    yAxis = (name = "u_c(R)  [Ω]", type = "log"),
    height = 340,
)

#%% md id=sweep_note_md
@md"""
The curve falls steeply and then flattens. At low current the `1/I` factor
amplifies the voltmeter's uncertainty; past a point the ammeter's relative
uncertainty takes over and nothing more is bought by raising the current.
That crossover is a design decision, and it fell out of the algebra rather
than out of a simulation.
"""

#%% md id=identity_md
@md"""
## 5. A quantity remembers where it came from

This is the part that surprises people. A `SymbolicMeasurement` records the
**independent sources** it derives from and with what sensitivity — not a
bare uncertainty number. So an expression that reuses the same measurement
cancels *exactly*:
"""

#%% code id=identity_demo
x = 8.4 ± 0.7

slate_table([
    (expression = "x - x",   result = repr(x - x)),
    (expression = "x / x",   result = repr(x / x)),
    (expression = "x + x",   result = repr(x + x)),
    (expression = "x^2 / x", result = repr(x^2 / x)),
])

#%% md id=identity_note_md
@md"""
`x - x` is `0 ± 0`, not `0 ± 0.99`. `x + x` is `2x ± 2u`, not `u√2`. Two
numbers alone could not tell those apart — which is why the sources are
carried rather than reduced away.

The flip side is a trap worth knowing now: identity comes from the
**object**, never from the symbol name. Writing `R2 ± σR2` twice declares two
independent resistors that happen to share a tolerance symbol. Bind each
physical input to a variable once, then reuse that variable. The
*Sources & Correlation* notebook shows what it costs when you don't.
"""

#%% md id=next_md
@md"""
## Where next

- **[Sensitivity & Budget](/n/sensitivity_and_budget)** — which input is
  costing you the precision, as a table and a chart.
- **[Sources & Correlation](/n/sources_and_correlation)** — why `x - x` is
  zero, and correlation without a covariance matrix.
- **[Expanded Uncertainty & Reporting](/n/expanded_and_reporting)** — `k`,
  Welch–Satterthwaite, and the four forms §7.2.2 allows.
- **[Protocol Design](/n/protocol_design)** — run the model backwards: what
  precision do I need to buy?
- **[Beyond First Order](/n/beyond_first_order)** — where the linearisation
  stops being safe, and how to find out.
- **[Code Generation](/n/codegen_and_deployment)** — the formula as compiled
  Julia, or as C for an instrument.
"""

# ╔═╡ Slate.config · per-notebook settings (Settings panel)
#   docid = 2b1f6c04-9d3a-4f18-a7c6-51e0d9a37f11
# ╚═╡
