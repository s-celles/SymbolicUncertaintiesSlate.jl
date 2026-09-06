try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% code id=setup hidecode
using Symbolics
using SymbolicUncertainties
using SymbolicUncertaintiesSlate
using DynamicQuantities
using Markdown
using Logging

@variables V I σV σI
@variables u1 u2 ν1 ν2

quiet(f) = with_logger(f, NullLogger())

# The measurand for the whole notebook: a resistance measured by Ohm's law.
R_m = quiet() do
    (V ± σV) / (I ± σI)
end

readings = Dict(
    V => 10.000us"V",   σV => 1.0e-3us"V",
    I => 0.10002us"A",  σI => 1.0e-5us"A",
)

"Ready — R = V/I, with a 10 V reading through 100.02 mA."

#%% md id=title title
@md"""
# Expanded Uncertainty & Reporting

## From `u_c` to a number a certificate can carry

A propagated measurement is not yet a reported one. JCGM 100:2008 §6 and §7
are more prescriptive than most software admits: there is a **coverage
factor** with assumptions attached, a rule for how many digits to quote,
four acceptable textual forms, and a separate statement for expanded
uncertainty that must name the factor it used.

This notebook walks that last mile.
"""

#%% md id=k_md
@md"""
## 1. The coverage factor

The expanded uncertainty is §6.2 equation (18):

$$U = k \cdot u_c(y)$$

`k = 2` is the EA-4/02 default and what the GUM's own Annex H examples use.
It is also an **assumption**: it presumes the output distribution is
approximately normal (§6.3.3) and that the effective degrees of freedom are
at least 30. Below that, `k` should come from a Student-*t* quantile
instead — Table G.2 — and the package will tell you so.
"""

#%% code id=k_demo
U2 = expanded_uncertainty(R_m)        # k = 2, the default
U3 = expanded_uncertainty(R_m, 3)

# `.k` is a `Num`, so it is unwrapped here rather than displayed raw.
as_number(k) = Float64(Symbolics.value(k))

Markdown.parse("""
`expanded_uncertainty(R_m)` → k = $(as_number(U2.k)) ·
`expanded_uncertainty(R_m, 3)` → k = $(as_number(U3.k))
""")

#%% md id=type_md
@md"""
### `U` is not a standard uncertainty, and the type says so

`expanded_uncertainty` returns an `ExpandedUncertainty`, **not** a
`SymbolicMeasurement`. That is deliberate.

`U` is the half-width of a coverage interval — a reporting quantity, not an
input to further propagation. Feed a value carrying `U` into a model that
expects `u_c` and every downstream result inflates by exactly `k`, silently.
Returning a `SymbolicMeasurement` would have made that mistake
type-correct.

The distinct type carries the estimate, `U`, the `k` that produced it, and
the degrees of freedom `k` was derived from — everything §7.2.3 requires a
certificate to state, and nothing that invites reuse in a computation.
"""

#%% code id=type_demo
propertynames(U2)

#%% md id=welch_md
@md"""
## 2. Small samples — Welch–Satterthwaite

When a Type A evaluation rests on few observations, `ν_eff` matters and §G.4
equation (G.2b) is how you get it:

$$\nu_{\text{eff}} = \frac{\left(\sum_i u_i^2\right)^2}{\sum_i u_i^4 / \nu_i}$$
"""

#%% code id=welch_demo
mathblock(["\\nu_{\\text{eff}} &= " * tex(welch_satterthwaite([u1, u2], [ν1, ν2]))])

#%% md id=welch_use_md
@md"""
Attach a concrete `ν_eff` to a measurement and the keyword form of
`expanded_uncertainty` derives `k` from Table G.2 rather than assuming
normality. A numeric `ν_eff < 30` also raises a warning, because that is the
regime where `k = 2` quietly understates the interval.
"""

#%% code id=welch_use
@variables y σy
small_sample = SymbolicMeasurement(y, σy, Symbolics.Num(4))   # ν_eff = 4

k_table = [
    (
        probability = p,
        k = as_number(quiet() do
            expanded_uncertainty(small_sample; coverage_probability = p).k
        end),
    ) for p in (0.68, 0.90, 0.95, 0.99)
]
slate_table(k_table; format = (probability = (kind = :percent, digits = 0),))

#%% md id=welch_note_md
@md"""
At `ν = 4` the 95 % factor is 2.78, not 1.96 — the interval is 42 % wider
than the normal assumption would have given. Four observations do not know
enough about their own spread for the shortcut to hold.
"""

#%% md id=report_md
@md"""
## 3. The four forms of §7.2.2

The GUM's own worked example is a 100 g mass standard calibrated to
`m_S = 100.02147 g` with `u_c = 0.35 mg`. `report` writes all four
acceptable forms; which belongs on a certificate is a house-style question,
not a metrological one.
"""

#%% code id=report_demo
report(100.02147, 0.00035; symbol = "m_S", unit = "g")

#%% md id=report_warn_md
@md"""
!!! warning "`±` is not the first choice, and a package's display is not a report"
    A `SymbolicMeasurement` prints as `val ± err` because that is the Julia
    ecosystem's convention. §7.2.2 **deliberately avoids the glyph**: `±` is
    read as an expanded uncertainty `y ± U` (§6.2), and a combined standard
    uncertainty is a different quantity by the factor `k`. The fourth form
    above uses `±` only because the surrounding text says the number is
    `u_c`.

    Do not copy a `±` display into a calibration certificate.
"""

#%% md id=digits_md
@md"""
### How many digits — §7.2.6

`u_c` is quoted to **two significant digits**, and the estimate is rounded to
that same last significant place. More digits on the estimate claims a
precision the measurement does not have; fewer discards information that was
paid for. The rule is on significant digits of the *uncertainty*, so a coarse
uncertainty coarsens the estimate with it:
"""

#%% code id=digits_demo
coarse = report(1234.5678, 12.0; symbol = "y", unit = "m")
fine   = report(100.021473829, 0.000351119; symbol = "m_S", unit = "g")

Markdown.parse("""
- `report(1234.5678, 12.0)` → **$(coarse.forms[4])**
- `report(100.021473829, 0.000351119)` → **$(fine.forms[2])**
""")

#%% md id=model_report_md
@md"""
## 4. Reporting straight from the model

With `DynamicQuantities` loaded, `report(m, values)` takes the measurement and
the unit-carrying readings, and derives the numbers **and the unit** from the
model — the same dimensional walk `evaluate` uses.

Supplying `k` produces the §7.2.4 expanded statement, which must name its
coverage factor. Without `k` there is no expanded statement to make and the
field stays `nothing`: `± U` with no stated `k` is precisely the ambiguity
§7.2.2 warns about, so the package will not write one.
"""

#%% code id=model_report
report(R_m, readings; symbol = "R", unit = "Ω", k = 2, coverage_probability = 0.95)

#%% md id=unit_note_md
@md"""
The dimensional walk composes what it is given, so this model produces
`A⁻¹ V`. `report` recognises the thirteen coherent derived SI units by their
dimension and writes `Ω` — likewise `W` for `A V`, `Hz` for `s⁻¹`. The
`unit = "Ω"` above is therefore redundant, and kept only to show the
override.

Two limits on that naming, both deliberate. A **prefixed** unit is never
renamed, because `1 kΩ` is a thousand base units and calling it `Ω` would be
wrong by that factor. And a **dimension does not determine a kind of
quantity** (VIM §1.1): torque and energy are both `m² kg s⁻²`, so the table
says `J` and a torque has to say otherwise — which is exactly what `unit`
is for.
"""

#%% md id=cert_md
@md"""
## 5. The document the result travels in

`report` renders a result; ISO/IEC 17025:2017 §7.8 is prescriptive about the
**certificate** that carries it. `certificate` builds one in that shape.

!!! danger "Every certificate this package produces is a specimen"
    Issuing a calibration certificate is an act performed by an accredited
    body under its own quality system. What follows is a drafting aid and a
    checklist — not a certificate. Documents carry a watermark saying so,
    and it cannot be switched off, only reworded.
"""

#%% code id=cert_demo
certificate(
    R_m, readings;
    symbol = "R", k = 2, coverage_probability = 0.95,
    identifier = "SPECIMEN-2026-0417",
    laboratory = "Laboratoire d'essais, 12 rue de la Mesure, Poitiers",
    location = "Permanent facility, Poitiers",
    customer = "Atelier Dupont & Fils",
    method = "Comparison against a calibrated reference (MP-04)",
    item = "Standard resistor, 100 Ω, s/n 4471-C",
    date_received = "2026-09-01",
    date_performed = "2026-09-03",
    date_issued = "2026-09-05",
    authorised_by = "S. Celles, technical manager",
    conditions = "(23.0 ± 0.5) °C, (45 ± 10) % RH",
    traceability = "Traceable to the SI through reference standard R-118, " *
                   "calibrated by LNE, certificate 2026-3391",
    model = "R = V / I",
    conformity = ConformityStatement(
        "R at 23 °C",
        "Nominal 100 Ω ± 0.1 %",
        :pass;
        decision_rule = "Simple acceptance, guard band w = 0 (ILAC-G8:2019 §4.2.1)",
    ),
)

#%% md id=findings_md
@md"""
### Missing clauses are printed on the document, not hidden in a checker

A certificate lacking its traceability statement is defective. The failure
mode of a separate `check()` function is that nobody calls it — so unmet
clauses are rendered **in place**, turning the type into a working checklist
against §7.8.
"""

#%% code id=findings_demo
draft = certificate(report(99.98, 0.014; symbol = "R", unit = "Ω", k = 2); identifier = "DRAFT-1")
slate_table([(clause = f.clause, requirement = f.requirement) for f in draft.findings])

#%% md id=findings_note_md
@md"""
Two of those clauses are worth knowing about on their own.

**§7.8.6.2 c) — a statement of conformity must name its decision rule.** The
rule is what makes a pass/fail mean anything: it fixes how the measurement
uncertainty is set against the tolerance (ILAC-G8). A pass declared without
one is not interpretable.

**§7.8.4.3 — a calibration certificate shall not recommend a calibration
interval**, unless that was agreed with the customer or is required by law.
The interval depends on how the instrument is used and on the customer's own
risk, neither of which the calibrating laboratory knows.
"""

#%% md id=live_md
@md"""
## 6. Live — what the coverage factor buys

Move the coverage probability and watch the interval. The estimate does not
move; the claim you are making about it does.
"""

#%% code id=live_controls
@bind prob Select([0.68 => "68 %", 0.90 => "90 %", 0.95 => "95 %", 0.99 => "99 %"];
                  label = "coverage probability")
@bind nu   Slider(2, 60, 30; step = 1, label = "effective degrees of freedom ν_eff")

with_dof = SymbolicMeasurement(R_m.val, R_m.err, Symbolics.Num(nu))
Uk = quiet() do
    expanded_uncertainty(with_dof; coverage_probability = prob.value)
end

point = evaluate(R_m, readings)
k = as_number(Uk.k)
half = k * ustrip(point.err)

Markdown.parse("""
| | |
|---|---|
| **estimate** | $(round(ustrip(point.val); digits = 5)) Ω |
| **u_c** | $(round(ustrip(point.err); sigdigits = 2)) Ω |
| **k** | $(k) |
| **U = k·u_c** | $(round(half; sigdigits = 2)) Ω |
| **interval** | [$(round(ustrip(point.val) - half; digits = 5)), $(round(ustrip(point.val) + half; digits = 5))] Ω |
""")

#%% code id=live_chart
nus = 2:60
factors = [
    as_number(quiet() do
        expanded_uncertainty(
            SymbolicMeasurement(R_m.val, R_m.err, Symbolics.Num(n));
            coverage_probability = prob.value,
        ).k
    end) for n in nus
]

echart(
    :line, collect(nus), factors;
    title = "Coverage factor at $(prob.label) — Student-t below ν = 30, normal above",
    xAxis = (name = "ν_eff", type = "value"),
    yAxis = (name = "k", type = "value"),
    smooth = true, symbol = "none", height = 320,
)

#%% md id=live_note_md
@md"""
The curve is flat above `ν = 30` — that is the threshold the `k = 2` shortcut
relies on — and climbs steeply below about 8. At `ν = 2` and 95 % the factor
is over 4: two observations are almost no information about a spread, and the
honest interval is more than twice as wide as the normal assumption would
suggest.
"""

#%% md id=next_md
@md"""
## Where next

- **[Protocol Design](/n/protocol_design)** — given a target `U`, what
  precision must each instrument have?
- **[Beyond First Order](/n/beyond_first_order)** — `k·u_c` assumes an
  approximately normal output. Checking that assumption is a separate job.
"""

# ╔═╡ Slate.config · per-notebook settings (Settings panel)
#   docid = 9e4b7d20-6a15-4c83-b2f7-0d3c85e19a64
# ╚═╡
