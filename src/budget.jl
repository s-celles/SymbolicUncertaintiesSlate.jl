# The EA-4/02 §7.3 budget, rendered.
#
# `uncertainty_budget` returns the metrology; this turns it into something a
# table widget and a bar chart can consume, without either of them having to
# know what a sensitivity coefficient is.
#
# Every cell keeps its unit. A budget is the one table where the columns are
# deliberately heterogeneous in unit — u(xᵢ) is in the unit of xᵢ, cᵢ is in
# measurand-per-xᵢ, and the contribution is in the unit of the measurand — so
# dropping the units is exactly what makes a budget unreadable.

# The label a row carries: the input variable where there is one, otherwise
# the source's own name.
_row_label(r::BudgetRow) = r.variable === nothing ? string(r.name) : string(r.variable)

"""
    budget_table(b::UncertaintyBudget) -> Vector{NamedTuple}

The budget as display rows, with every column left in closed form.

Columns are `quantity`, `u`, `c`, `contribution` and `relative`, matching
EA-4/02 §7.3. Each is rendered to a `String`, so a table widget has something
printable in every cell — a symbolic sensitivity coefficient is not a number
and should not be dressed as one.

Rows keep the budget's own order. Pass values to
[`budget_table(b, values)`](@ref budget_table) for the numeric, unit-carrying
form.
"""
function budget_table(b::UncertaintyBudget)
    return [(
                quantity = _row_label(r),
                u = string(r.sigma),
                c = string(r.sensitivity),
                contribution = string(r.contribution),
                relative = string(r.relative)
            ) for r in b]
end

"""
    budget_table(b::UncertaintyBudget, values) -> Vector{NamedTuple}

The budget evaluated at `values`, with every quantity carrying its unit.

Columns are `quantity`, `u`, `c`, `contribution` — each a string that includes
its unit — and `percent`, the share of the variance as a bare number so a
table's in-cell bar viz has something to scale.

The three units are derived, not asserted:

- `u` is in the unit `values` annotates that source's `σ` with;
- `contribution` is in the unit of the measurand, because that is what a
  budget row *is* — `|cᵢ|·u(xᵢ)` expressed in the measurand's own unit;
- `c` is their quotient, measurand per input.

```julia
budget_table(uncertainty_budget(R), ohm)
```

For uncorrelated sources the `percent` column is a variance decomposition and
sums to 100. Under a declared correlation it does not: the JCGM 100:2008
§5.2.2 equation (13) cross terms belong to no single row, so the shares can
overshoot and a negative cross term can push one row past 100 % on its own.
`b.correlated` is what says which regime you are in.
"""
function budget_table(b::UncertaintyBudget, values::AbstractDict)
    isempty(b) && return NamedTuple{
        (:quantity, :u, :c, :contribution, :percent),
        Tuple{String, String, String, String, Float64}
    }[]

    y_unit = unit_of(b, values)
    uc = _magnitude(SymbolicUncertainties.evaluate(
        SymbolicMeasurement(b.measurand, b.uc),
        values
    ).err)

    rows = NamedTuple{
        (:quantity, :u, :c, :contribution, :percent),
        Tuple{String, String, String, String, Float64}
    }[]
    for r in b
        σ_value = get(values, r.sigma, nothing)
        σ_unit = σ_value === nothing ? oneunit(y_unit) : oneunit(σ_value)
        σ = _eval_at(r.sigma, values) * σ_unit
        contribution = _eval_at(r.contribution, values) * y_unit
        c = _eval_at(r.sensitivity, values) * (y_unit / σ_unit)
        push!(
            rows,
            (
                quantity = _row_label(r),
                u = string(σ),
                c = string(c),
                contribution = string(contribution),
                percent = 100 * (_magnitude(contribution) / uc)^2
            )
        )
    end
    return rows
end

"""
    contribution_series(b::UncertaintyBudget, values) -> @NamedTuple{labels, contributions, percent, unit}

The budget as chart series, sorted largest contribution first.

- `labels` — one per source, in the plotted order;
- `contributions` — bare magnitudes, `Vector{Float64}`;
- `percent` — each source's share of the variance;
- `unit` — the unit those magnitudes are in, which is the measurand's.

A plotting library takes numbers, so the magnitudes are stripped here and the
unit returned alongside for the axis label. That is the only place a bare
number is the right answer, and naming the unit next to it is the price.

```julia
s = contribution_series(uncertainty_budget(Vout), divider)
echart(:bar, s.labels, s.contributions; title = "u_i(Vout)  [\$(s.unit)]")
```

A source that cancelled — the `x` in `x - x` — produces no budget row, so it
is absent here rather than plotted as a zero bar. An empty budget gives empty
series and no division by a zero total.
"""
function contribution_series(b::UncertaintyBudget, values::AbstractDict)
    if isempty(b)
        return (
            labels = String[],
            contributions = Float64[],
            percent = Float64[],
            unit = oneunit(1.0)
        )
    end

    y_unit = unit_of(b, values)
    labels = String[_row_label(r) for r in b]
    contributions = Float64[_eval_at(r.contribution, values) for r in b]

    order = sortperm(contributions; rev = true)
    labels = labels[order]
    contributions = contributions[order]

    total = sum(abs2, contributions)
    percent = total == 0 ? zeros(length(contributions)) :
              [100 * c^2 / total for c in contributions]

    return (
        labels = labels,
        contributions = contributions,
        percent = percent,
        unit = y_unit
    )
end

# Substitute the magnitudes and compile the result to a number.
#
# The unit is handled by the caller, from the model rather than from this
# expression: a budget row's dimension is fixed by which column it is in.
function _eval_at(expr, values::AbstractDict)
    numeric = Dict(k => _magnitude(v) for (k, v) in values)
    substituted = Symbolics.substitute(Symbolics.Num(expr), numeric)
    v = Symbolics.value(substituted)
    v isa Number && !(v isa Symbolics.Num) && return float(v)
    return float(Symbolics.build_function(substituted; expression = Val{false})())
end
