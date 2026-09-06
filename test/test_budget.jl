@testitem "budget_table renders the symbolic budget row by row" begin
    using Symbolics, SymbolicUncertainties, Logging

    @variables V I σV σI
    R = with_logger(NullLogger()) do
        (V ± σV) / (I ± σI)
    end
    rows = budget_table(uncertainty_budget(R))

    @test length(rows) == 2
    @test keys(rows[1]) == (:quantity, :u, :c, :contribution, :relative)
    # Closed forms, rendered for display: every cell is printable.
    @test all(r -> all(v -> v isa String, values(r)), rows)
    @test rows[1].quantity == "V"
    @test rows[2].quantity == "I"
    @test occursin("σV", rows[1].u)
end

@testitem "budget_table with values gives every cell its unit" begin
    using Symbolics, SymbolicUncertainties, DynamicQuantities, Logging

    @variables V I σV σI
    R = with_logger(NullLogger()) do
        (V ± σV) / (I ± σI)
    end
    ohm = Dict(V => 5.0us"V", σV => 0.01us"V", I => 0.5us"A", σI => 0.001us"A")

    rows = budget_table(uncertainty_budget(R), ohm)

    @test keys(rows[1]) == (:quantity, :u, :c, :contribution, :percent)
    # The uncertainty of a voltage is a voltage; the sensitivity to it is
    # ohms per volt; the contribution is in ohms, like the measurand.
    @test occursin("V", rows[1].u)
    @test occursin("0.01", rows[1].u)
    @test occursin("Ω", rows[1].contribution) || occursin("A⁻¹ V", rows[1].contribution)
    # For uncorrelated sources the variance shares are a decomposition
    # and sum to 100 % (EA-4/02 §7.3).
    @test sum(r -> r.percent, rows) ≈ 100.0 rtol = 1e-10
    @test rows[1].percent ≈ 50.0 rtol = 1e-9
end

@testitem "contribution_series ranks the sources and names their unit" begin
    using Symbolics, SymbolicUncertainties, DynamicQuantities, Logging

    @variables Vin σVin R1 σR1 R2 σR2
    Vout = with_logger(NullLogger()) do
        propagate((v, r1, r2) -> v * r2 / (r1 + r2), [Vin ± σVin, R1 ± σR1, R2 ± σR2])
    end
    divider = Dict(
        Vin => 5.0us"V", σVin => 0.01us"V",
        R1 => 1000.0us"Ω", σR1 => 10.0us"Ω",
        R2 => 3000.0us"Ω", σR2 => 20.0us"Ω"
    )

    s = contribution_series(uncertainty_budget(Vout), divider)

    @test keys(s) == (:labels, :contributions, :percent, :unit)
    @test length(s.labels) == 3
    @test s.labels isa Vector{String}
    # Magnitudes for the chart, with the unit alongside for its axis —
    # a bare number reaches a plotting library, never a reader.
    @test s.contributions isa Vector{Float64}
    @test dimension(uexpand(s.unit)) == dimension(uexpand(1.0u"V"))
    # Sorted largest first, so a bar chart reads top-down.
    @test issorted(s.contributions; rev = true)
    @test sum(s.percent) ≈ 100.0 rtol = 1e-10
    # Quadrature: the contributions recombine into u_c.
    uc = ustrip(uconvert(s.unit, evaluate(Vout, divider).err))
    @test sqrt(sum(abs2, s.contributions)) ≈ uc rtol = 1e-10
end

@testitem "contribution_series keeps a cancelled source out of the chart" begin
    using SymbolicUncertainties, Symbolics, DynamicQuantities

    # `x - x` is exactly zero: the source cancels and leaves no row at
    # all, so there is nothing to plot and no division by a zero total.
    @variables L σL
    x = L ± σL
    metre = Dict(L => 2.0us"m", σL => 0.001us"m")

    s = contribution_series(uncertainty_budget(x - x), metre)

    @test isempty(s.labels)
    @test isempty(s.contributions)
    @test isempty(s.percent)
end

@testitem "budget_table reports a correlated budget as not a decomposition" begin
    using Symbolics, SymbolicUncertainties, DynamicQuantities, Logging

    @variables Va σVa Vb σVb
    a, b = with_logger(NullLogger()) do
        declare_correlated(Va ± σVa, Vb ± σVb, 0.9)
    end
    d = a - b
    vals = Dict(Va => 10.0us"V", σVa => 0.5us"V", Vb => 4.0us"V", σVb => 0.5us"V")

    rows = budget_table(uncertainty_budget(d), vals)

    # Under a declared correlation the §5.2.2 eq. (13) cross term belongs
    # to no row, so the shares no longer add to 100 %. The table says so
    # rather than leaving the reader to notice.
    @test sum(r -> r.percent, rows) > 100.0
end
