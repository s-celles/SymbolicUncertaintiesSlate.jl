@testitem "unit_of derives the measurand's unit from the model" begin
    using Symbolics, SymbolicUncertainties, DynamicQuantities, Logging

    @variables V I σV σI
    R = with_logger(NullLogger()) do
        (V ± σV) / (I ± σI)
    end
    ohm = Dict(V => 5.0us"V", σV => 0.01us"V", I => 0.5us"A", σI => 0.001us"A")

    u = unit_of(R, ohm)

    # Nobody wrote "ohm" anywhere: the unit is what the model computes.
    @test u == oneunit(evaluate(R, ohm).val)
    @test dimension(uexpand(u)) == dimension(uexpand(1.0u"Ω"))
    # A unit, not a value — the magnitude is 1 by construction.
    @test ustrip(u) == 1.0
end

@testitem "unit_of accepts a budget's own measurand" begin
    using Symbolics, SymbolicUncertainties, DynamicQuantities, Logging

    @variables V I σV σI
    R = with_logger(NullLogger()) do
        (V ± σV) / (I ± σI)
    end
    ohm = Dict(V => 5.0us"V", σV => 0.01us"V", I => 0.5us"A", σI => 0.001us"A")

    # A budget carries the measurand and the u_c it decomposes, which is
    # the measurement — so a budget alone is enough to name the unit.
    @test unit_of(uncertainty_budget(R), ohm) == unit_of(R, ohm)
end

@testitem "sweep moves one input and keeps the units on the answer" begin
    using Symbolics, SymbolicUncertainties, DynamicQuantities, Logging

    @variables V I σV σI
    R = with_logger(NullLogger()) do
        (V ± σV) / (I ± σI)
    end
    ohm = Dict(V => 5.0us"V", σV => 0.01us"V", I => 0.5us"A", σI => 0.001us"A")

    got = sweep(R, ohm, I, [0.4, 0.5, 0.6] .* us"A")

    @test keys(got) == (:val, :err)
    @test length(got.val) == 3
    @test all(q -> q isa DynamicQuantities.AbstractQuantity, got.val)
    @test all(q -> dimension(uexpand(q)) == dimension(uexpand(1.0u"Ω")), got.val)
    @test ustrip(got.val[2]) ≈ 10.0
    # More current at the same absolute uncertainties is a better
    # measurement of R: u_c falls across the sweep.
    @test issorted(ustrip.(got.err); rev = true)
    # The mid-point of the sweep is the base point.
    @test ustrip(got.err[2]) ≈ ustrip(evaluate(R, ohm).err)
end

@testitem "sweep converts a swept value stated in another unit" begin
    using Symbolics, SymbolicUncertainties, DynamicQuantities, Logging

    @variables Vin σVin R1 σR1 R2 σR2
    Vout = with_logger(NullLogger()) do
        propagate((v, r1, r2) -> v * r2 / (r1 + r2), [Vin ± σVin, R1 ± σR1, R2 ± σR2])
    end
    divider = Dict(
        Vin => 5.0us"V", σVin => 0.01us"V",
        R1 => 1.0us"kΩ", σR1 => 0.01us"kΩ",
        R2 => 3.0us"kΩ", σR2 => 0.02us"kΩ"
    )

    # R1 is stated in kΩ in the model but swept in Ω. A magnitude taken
    # without converting would be a thousand times wrong and perfectly
    # plausible, so the conversion happens rather than the strip.
    got = sweep(Vout, divider, R1, [500.0, 1000.0, 2000.0] .* us"Ω")

    @test ustrip(got.val[2]) ≈ 3.75
    @test ustrip(got.val[1]) ≈ 5.0 * 3000 / 3500
end

@testitem "sweep refuses a value of the wrong dimension" begin
    using Symbolics, SymbolicUncertainties, DynamicQuantities, Logging

    @variables V I σV σI
    R = with_logger(NullLogger()) do
        (V ± σV) / (I ± σI)
    end
    ohm = Dict(V => 5.0us"V", σV => 0.01us"V", I => 0.5us"A", σI => 0.001us"A")

    @test_throws ArgumentError sweep(R, ohm, I, [0.4, 0.5] .* us"V")
end

@testitem "sweep on a bare expression takes its unit from the caller" begin
    using Symbolics, SymbolicUncertainties, DynamicQuantities, Logging

    @variables V I σV σI
    R = with_logger(NullLogger()) do
        (V ± σV) / (I ± σI)
    end
    ohm = Dict(V => 5.0us"V", σV => 0.01us"V", I => 0.5us"A", σI => 0.001us"A")

    # `infer_precision` solves for a σ, so the answer is a voltage — a
    # fact about the question asked, which the caller states.
    σV_needed = with_logger(NullLogger()) do
        infer_precision(R, σV, 0.05)
    end
    got = sweep(σV_needed, ohm, I, [0.4, 0.5, 0.6] .* us"A"; unit = us"V")

    @test length(got) == 3
    @test all(q -> dimension(uexpand(q)) == dimension(uexpand(1.0u"V")), got)
    # A target u_c of 50 mΩ is easier to hit at higher current, so the
    # voltmeter is allowed to be worse.
    @test issorted(ustrip.(got))
end

@testitem "sweep requires a unit for a bare expression" begin
    using Symbolics, SymbolicUncertainties, DynamicQuantities, Logging

    @variables V I σV σI
    R = with_logger(NullLogger()) do
        (V ± σV) / (I ± σI)
    end
    ohm = Dict(V => 5.0us"V", σV => 0.01us"V", I => 0.5us"A", σI => 0.001us"A")

    # An arbitrary expression has no measurand to derive a unit from, so
    # the unit is not guessed.
    @test_throws UndefKeywordError sweep(R.err, ohm, I, [0.4, 0.5] .* us"A")
end
