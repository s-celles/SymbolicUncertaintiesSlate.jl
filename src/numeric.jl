# Evaluation, with the units kept on.
#
# Two upstream facts shape everything here.
#
# `Symbolics.substitute` replaces symbols and leaves the arithmetic standing —
# `sqrt(0.05)` stays `sqrt(0.05)` — which SymbolicUncertainties records as
# UB-001 in its `upstream-bugs.md`. Compiling the expression is what actually
# produces a number, and `build_evaluator` is the public way to do it.
#
# A unit is an annotation of a *symbol*, supplied in the values dictionary,
# never a value inside the expression tree. So the magnitude and the unit are
# computed by two different walks, and both come from the upstream package:
# `build_evaluator` for the number, `evaluate` for the unit. Neither is
# reimplemented here.

"""
    unit_of(m::SymbolicMeasurement, values) -> Quantity
    unit_of(b::UncertaintyBudget, values) -> Quantity

The unit the measurement model computes for its measurand, as a quantity of
magnitude 1.

Nobody writes this unit down: it is derived from the model and the units
annotating its inputs, by the same dimensional walk
[`SymbolicUncertainties.evaluate`](https://s-celles.github.io/SymbolicUncertainties.jl/dev/dimensional-analysis/)
uses. A worked example that ends in a bare `10.0` and a `# ohms` comment
records what its author *believed* the model produces.

```julia
ohm = Dict(V => 5.0us"V", σV => 0.01us"V", I => 0.5us"A", σI => 0.001us"A")
unit_of((V ± σV) / (I ± σI), ohm)     # 1.0 A⁻¹ V
```

Held once, outside a loop, it is what re-attaches the unit to the magnitudes
a compiled evaluator returns.

Requires `DynamicQuantities` to be loaded, as `evaluate` does.
"""
function unit_of(m::SymbolicMeasurement, values::AbstractDict)
    oneunit(SymbolicUncertainties.evaluate(m, values).val)
end

# A budget carries the measurand and the u_c it decomposes — which is
# precisely the measurement — so a budget alone is enough to name the unit.
function unit_of(b::UncertaintyBudget, values::AbstractDict)
    unit_of(SymbolicMeasurement(b.measurand, b.uc), values)
end

# The magnitude of a value in the unit the model was written in.
#
# Upstream `evaluate` pairs `ustrip(q)` with a `oneunit(q)` annotation, so a
# model written in kΩ propagates the magnitude 1.0 alongside the unit kΩ. This
# follows that convention rather than expanding to SI base units, because the
# two have to agree: a sweep that silently switched to ohms would be wrong by
# exactly a thousand and look entirely plausible.
_magnitude(q) = float(DQ.ustrip(q))
_magnitude(x::Real) = float(x)

# Restate `x` in the unit `reference` is written in, then take its magnitude.
# Same dimension is required; the same *unit* is not, so a resistance stated
# in Ω can be swept through a model written in kΩ.
function _magnitude_as(x, reference, what::AbstractString)
    if x isa DQ.AbstractQuantity && reference isa DQ.AbstractQuantity
        if DQ.dimension(DQ.uexpand(x)) != DQ.dimension(DQ.uexpand(reference))
            throw(
                ArgumentError(
                "sweep: $(what) is $(DQ.dimension(DQ.uexpand(x))) but the " *
                "model annotates it as $(DQ.dimension(DQ.uexpand(reference))). " *
                "A value of a different dimension is not the same quantity.",
            ),
            )
        end
        return _magnitude(DQ.uconvert(oneunit(reference), x))
    elseif x isa DQ.AbstractQuantity || reference isa DQ.AbstractQuantity
        throw(
            ArgumentError(
            "sweep: $(what) and the model's own value must agree on " *
            "whether the quantity carries a unit. A dimensionless input " *
            "takes plain reals; every other input takes quantities.",
        ),
        )
    end
    return _magnitude(x)
end

# Compile the (val, err) evaluator once, and return it with the argument order
# it expects. `build_evaluator` is upstream's public code-generation entry
# point; a sweep is exactly the hot loop it exists for.
function _compiled(m::SymbolicMeasurement, values::AbstractDict)
    vars = Symbolics.Num[Symbolics.Num(k) for k in keys(values)]
    return SymbolicUncertainties.build_evaluator(m, vars), vars
end

"""
    sweep(m::SymbolicMeasurement, values, variable, xs) -> @NamedTuple{val, err}

Evaluate the measurement once per element of `xs`, with `variable` taking that
element and every other input taking its value from `values`.

This is the shape an interactive chart wants: hold the measurement model
fixed, move one input, and watch the estimate and its combined standard
uncertainty respond. Both returned vectors carry units — the estimate's from
the model via [`unit_of`](@ref), each element of `xs` interpreted in the unit
`values` annotates `variable` with.

```julia
band = sweep(R, ohm, I, range(0.1, 1.0; length = 200) .* us"A")
# band.val, band.err :: Vector{Quantity}, both in Ω
```

`xs` may be stated in any unit of the right dimension — `us"Ω"` against a
model written in `us"kΩ"` is converted, not stripped. A value of the wrong
dimension raises `ArgumentError` rather than being coerced.

The model is compiled once with
[`SymbolicUncertainties.build_evaluator`](https://s-celles.github.io/SymbolicUncertainties.jl/dev/code-generation/)
and the unit resolved once, so the cost per point is a function call.
"""
function sweep(m::SymbolicMeasurement, values::AbstractDict, variable, xs)
    key = Symbolics.Num(variable)
    haskey(values, key) || throw(
        ArgumentError(
        "sweep: `$(key)` is not one of the model's inputs " *
        "($(join(sort!(string.(keys(values))), ", "))).",
    ),
    )

    g, vars = _compiled(m, values)
    unit = unit_of(m, values)
    base = [_magnitude(values[v]) for v in vars]
    slot = findfirst(isequal(key), vars)

    val = Vector{typeof(unit)}(undef, length(xs))
    err = Vector{typeof(unit)}(undef, length(xs))
    for (i, x) in enumerate(xs)
        args = copy(base)
        args[slot] = _magnitude_as(x, values[key], "the swept value of `$(key)`")
        v, e = g(args...)
        val[i] = v * unit
        err[i] = e * unit
    end
    return (val = val, err = err)
end

"""
    sweep(expr, values, variable, xs; unit) -> Vector{Quantity}

Sweep a bare symbolic expression — a sensitivity coefficient, an inferred
precision, a contribution — rather than a whole measurement.

An expression is not a measurand, so there is no model to derive its unit
from and `unit` is a **required** keyword. `infer_precision(R, σV, target)`
solves for a voltmeter's precision, so its answer is in volts; that is a fact
about the question asked, and the caller is the one who knows it.

```julia
sweep(σV_needed, ohm, I, currents; unit = us"V")
```
"""
function sweep(expr, values::AbstractDict, variable, xs; unit)
    key = Symbolics.Num(variable)
    haskey(values, key) || throw(
        ArgumentError(
        "sweep: `$(key)` is not one of the model's inputs " *
        "($(join(sort!(string.(keys(values))), ", "))).",
    ),
    )

    vars = Symbolics.Num[Symbolics.Num(k) for k in keys(values)]
    g = Symbolics.build_function(Symbolics.Num(expr), vars...; expression = Val{false})
    base = [_magnitude(values[v]) for v in vars]
    slot = findfirst(isequal(key), vars)

    out = Vector{typeof(oneunit(unit))}(undef, length(xs))
    for (i, x) in enumerate(xs)
        args = copy(base)
        args[slot] = _magnitude_as(x, values[key], "the swept value of `$(key)`")
        out[i] = g(args...) * oneunit(unit)
    end
    return out
end
