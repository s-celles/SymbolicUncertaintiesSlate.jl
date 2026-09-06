try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% code id=setup hidecode
using Symbolics
using SymbolicUncertainties
using SymbolicUncertaintiesSlate
using DynamicQuantities
using Markdown
using Logging

@variables V I σV σI
@variables V1 σV1 V2 σV2 V3 σV3

quiet(f) = with_logger(f, NullLogger())

R_m = quiet() do
    (V ± σV) / (I ± σI)
end

# A 5 V source through a 500 mA load: R ≈ 10 Ω.
bench = Dict(
    V => 5.000us"V",  σV => 0.010us"V",
    I => 0.5000us"A", σI => 0.0010us"A",
)

"Ready — R = V/I on a 5 V / 500 mA bench, and a three-term voltage chain."

#%% md id=title title
@md"""
# Protocol Design

## Running the measurement model backwards

Everything so far went forwards: given instruments, what is the uncertainty?
The question a laboratory actually asks is the **inverse** — *given a target,
what instruments do I need to buy?*

Because the propagation is symbolic, that question has a closed-form answer
rather than a search. This is the payoff for never reducing the model to a
number: an expression can be solved, a number cannot.
"""

#%% md id=target_md
@md"""
## 1. The target, stated in the measurand's own unit

A target `u_c` is a quantity, so it is written with its unit. The inference
functions take a bare magnitude **in the unit the model computes**, which
`unit_of` derives — so the conversion happens here, once, in the open.
"""

#%% code id=target_setup
R_unit = unit_of(R_m, bench)
target = 50.0us"mΩ"                     # what the calibration procedure demands
target_mag = ustrip(uconvert(R_unit, target))

present = evaluate(R_m, bench)

Markdown.parse("""
| | |
|---|---|
| **measurand unit, derived** | $(R_unit) |
| **target u_c** | $(target) = $(round(target_mag; sigdigits = 3)) $(R_unit) |
| **present u_c** | $(round(ustrip(present.err); sigdigits = 3)) $(R_unit) |
""")

#%% md id=infer_md
@md"""
## 2. `infer_precision` — solve `u_c(y) = target` for one input

The combined uncertainty is quadratic in each `σᵢ`, so the solve is an
algebraic split rather than a numerical root-find:

$$u_c^2 = c_i^2 \\sigma_i^2 + \\sum_{j \\neq i} (c_j \\sigma_j)^2
\\quad \\Longrightarrow \\quad
\\sigma_i^\\star = \\sqrt{\\frac{u_c^{\,2} - \\sum_{j \\neq i} (c_j \\sigma_j)^2}{c_i^2}}$$

No solver dependency, no `Nemo.jl`, and it works for every GUM-standard
measurement model.
"""

#%% code id=infer_demo
σV_needed = quiet() do
    infer_precision(R_m, σV, target_mag)
end

mathblock(["\\sigma_V^{\\star} &= " * tex(σV_needed)])

#%% md id=infer_num_md
@md"""
Substitute the bench — the current and its uncertainty are what they are —
and the expression becomes the voltmeter specification you go shopping with:
"""

#%% code id=infer_num
# Evaluated at the bench itself: a one-point sweep through the value the
# dictionary already holds, so the unit survives the round trip.
σV_star = sweep(σV_needed, bench, I, [bench[I]]; unit = us"V")[1]

Markdown.parse("""
To reach **u_c(R) = $(target)** on this bench, the voltmeter must achieve

**u(V) ≤ $(round(ustrip(σV_star) * 1000; sigdigits = 3)) mV**

against the $(round(ustrip(bench[σV]) * 1000; sigdigits = 3)) mV it has today.
""")

#%% md id=all_md
@md"""
## 3. `infer_all_precisions` — the worst-case table

The same question asked of every input at once. Each entry is the precision
that input would need **alone** to drive `u_c` to the target, using the
shortcut `σᵢ⋆ = target / |cᵢ|`.

Read it as an upper bound, not a specification: it is what that input could
get away with if every other input were perfect. Nothing is perfect, so the
real requirement is always tighter — which is what §4 is for.
"""

#%% code id=all_demo
alone = quiet() do
    infer_all_precisions(R_m, [V, I], [σV, σI], target_mag)
end

markdown_table([
    (input = "V", sigma = "σV", alone = "\$" * tex(alone[σV]) * "\$"),
    (input = "I", sigma = "σI", alone = "\$" * tex(alone[σI]) * "\$"),
])

#%% md id=required_md
@md"""
`required_precision` is the same closed form under the framing metrology
actually uses — a **condition** rather than an equation. Read the returned
expression as the boundary: values of `σV` strictly below it satisfy
`u_c < target`, values equal saturate it, values above violate it.
"""

#%% code id=required_demo
isequal(
    Symbolics.simplify(quiet() do
        required_precision(R_m, σV, target_mag)
    end),
    Symbolics.simplify(σV_needed),
)

#%% md id=alloc_md
@md"""
## 4. `budget_allocation` — spending a fixed budget optimally

The other design question. You have a total uncertainty budget the
measurement can afford, spread across `N` inputs. How should it be divided?

Lagrange gives the answer in closed form. Minimising `u_c` subject to
`Σᵢ σᵢ = B` yields the **inverse-sensitivity-squared** weighting

$$\\sigma_i^\\star = B \\cdot \\frac{1/c_i^2}{\\sum_j 1/c_j^2}$$

whose stationarity condition is `cᵢ²σᵢ = cⱼ²σⱼ`: at the optimum, an extra
euro spent on any input buys the same reduction in `u_c`.
"""

#%% md id=alloc_sym_md
@md"""
### The symmetric case

Three voltage drops in series, `V = V₁ + V₂ + V₃`. Every sensitivity
coefficient is 1, so the optimum is the obvious one — split it three ways.
"""

#%% code id=alloc_sym
chain = quiet() do
    propagate((a, b, c) -> a + b + c, [V1 ± σV1, V2 ± σV2, V3 ± σV3])
end

# A budget spread over three voltages is itself a voltage. `budget_allocation`
# takes a bare magnitude, so the conversion into the model's own unit happens
# here rather than being assumed.
B_total = 3.0us"mV"
B = ustrip(uconvert(us"V", B_total))
sym = budget_allocation(chain, [V1, V2, V3], [σV1, σV2, σV3], B)

markdown_table([
    (input = string(k), allocation_mV = round(1000 * Float64(Symbolics.value(v)); digits = 3))
    for (k, v) in sort(collect(sym); by = p -> string(first(p)))
])

#%% md id=alloc_asym_md
@md"""
### The asymmetric case

Now the same three drops, but the second is measured through a gain of 3 and
the third through a gain of 6 — `V = V₁ + 3V₂ + 6V₃`. The sensitivities are
1, 3 and 6, so the inverse-square weights are `1 : 1/9 : 1/36`.

The channel the measurand is *most* sensitive to gets the *smallest*
allowance. That is the whole content of the result, and it is the opposite of
what the intuition "spend where it matters" suggests — you spend where the
precision is cheap, because the sensitive channel amplifies whatever error
you leave there.
"""

#%% code id=alloc_asym
geared = quiet() do
    propagate((a, b, c) -> a + 3b + 6c, [V1 ± σV1, V2 ± σV2, V3 ± σV3])
end

asym = budget_allocation(geared, [V1, V2, V3], [σV1, σV2, σV3], B)
asym_rows = [
    (
        input = string(k),
        allocation_mV = round(1000 * Float64(Symbolics.value(v)); digits = 4),
    ) for (k, v) in sort(collect(asym); by = p -> string(first(p)))
]

echart(
    :bar,
    [r.input for r in asym_rows], [r.allocation_mV for r in asym_rows];
    title = "Optimal allocation of a $(B_total) budget across V₁ + 3V₂ + 6V₃",
    yAxis = (name = "σᵢ⋆  [mV]", type = "value"),
    height = 300,
)

#%% md id=live_md
@md"""
## 5. Live — what the target costs

Move the target and the bench, and read off the voltmeter you need. The
region below the curve is the specification that meets the target; above it,
the target is out of reach at that current no matter which voltmeter you buy.
"""

#%% code id=live_controls
@bind target_mΩ Slider(10.0, 200.0, 50.0; step = 5.0,  label = "target u_c(R)  [mΩ]")
@bind i_unc_µA  Slider(100.0, 5000.0, 1000.0; step = 100.0, label = "u(I)  [µA]")

live = Dict(
    V => 5.000us"V",  σV => 0.010us"V",
    I => 0.5000us"A", σI => i_unc_µA * 1e-6us"A",
)
live_target = ustrip(uconvert(unit_of(R_m, live), target_mΩ * us"mΩ"))

needed = quiet() do
    infer_precision(R_m, σV, live_target)
end

currents = range(0.05, 2.0; length = 160) .* us"A"
σV_curve = sweep(needed, live, I, currents; unit = us"V")

# Where the ammeter alone already exceeds the target, no voltmeter helps and
# the closed form returns a non-finite or negative value. Those points are
# dropped rather than plotted as zeros — an unreachable target is not a
# requirement of 0 V.
ok = [isfinite(ustrip(q)) && ustrip(q) > 0 for q in σV_curve]

echart(
    series(:line, ustrip.(currents)[ok], (1000 .* ustrip.(σV_curve))[ok];
           name = "required u(V)", smooth = true, symbol = "none");
    title = "Voltmeter needed for u_c(R) = $(target_mΩ) mΩ",
    xAxis = (name = "I  [A]", type = "value"),
    yAxis = (name = "required u(V)  [mV]", type = "value"),
    height = 340,
)

#%% md id=live_note_md
@md"""
Two readings of that curve.

**It has a left edge.** Below some current the ammeter's own contribution
already exceeds the target on its own, and the curve simply stops — there is
no voltmeter, however good, that rescues it. Buying a better voltmeter is the
wrong purchase order in that region.

**Past the edge it rises, and settles into a straight line.** The closed form
is `σ_V^⋆ = sqrt(I²·target² − V²·u(I)²/I²)`, so once the ammeter term has
faded the requirement is simply `I · target` — relaxing in direct proportion
to the test current. Raising the current is usually cheaper than buying a
decade of voltmeter, and the algebra is what tells you the exchange rate.

Push `u(I)` up with the second slider and watch the left edge march right:
degrade the ammeter and whole ranges of operating point stop being usable.
"""

#%% md id=errors_md
@md"""
## 6. When the inference refuses

Three cases raise rather than returning something unusable, all under
REQ-091:

- a **negative target** — a standard uncertainty is non-negative (§4.3.1);
- an input the measurand **does not depend on** — there is nothing to solve
  for;
- an `u_c` that is **not quadratic** in that `σᵢ` — a transcendental term
  such as `sin(σᵢ)` breaks the algebraic split, and the message points at
  `Nemo.jl` or numerical root-finding rather than guessing.

And `budget_allocation` raises when every sensitivity coefficient is zero:
there is no allocation of a budget across inputs that do not affect the
answer.
"""

#%% md id=next_md
@md"""
## Where next

- **[Beyond First Order](/n/beyond_first_order)** — every answer here rests
  on the linearisation. Checking when that is safe is the next question.
- **[Code Generation](/n/codegen_and_deployment)** — the finished model,
  compiled into the instrument that will use it.
"""

# ╔═╡ Slate.config · per-notebook settings (Settings panel)
#   docid = c3f60a58-7e21-4b96-8d04-1af7b25e9c30
# ╚═╡
