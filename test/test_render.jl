@testitem "tex renders an expression as inline LaTeX" begin
    using Symbolics, SymbolicUncertainties

    @variables V I
    s = tex(V / I)

    @test s isa String
    @test occursin("frac", s)
    # Inline, not a display environment: the caller decides the delimiters.
    @test !occursin("\\begin{equation}", s)
    @test !occursin("\$", s)
    @test !endswith(s, "\n")
end

@testitem "tex renders a measurement as estimate ± uncertainty" begin
    using Symbolics, SymbolicUncertainties, Logging

    @variables V I σV σI
    R = with_logger(NullLogger()) do
        (V ± σV) / (I ± σI)
    end
    s = tex(R)

    @test occursin("\\pm", s)
    @test occursin("sqrt", s) || occursin("\\sqrt", s)
end

@testitem "tex renders plain numbers" begin
    @test tex(2.5) == "2.5"
    @test tex(3) == "3"
end

@testitem "mathblock stacks aligned rows into one display block" begin
    using Markdown

    md = mathblock(["a &= 1", "b &= 2"])

    @test md isa Markdown.MD
    s = repr(MIME"text/plain"(), md)
    @test occursin("begin{aligned}", s)
    @test occursin("a &= 1", s)
    # Rows are separated, not concatenated.
    @test occursin("\\\\", s)
end

@testitem "mathblock accepts a single row and an empty list" begin
    using Markdown

    @test mathblock(["x &= 1"]) isa Markdown.MD
    @test mathblock(String[]) isa Markdown.MD
end

@testitem "measurement_tex labels the measurand and splits the two lines" begin
    using Symbolics, SymbolicUncertainties, Logging

    @variables V I σV σI
    R = with_logger(NullLogger()) do
        (V ± σV) / (I ± σI)
    end
    s = measurement_tex(R; symbol = "R")

    @test occursin("R &=", s)
    @test occursin("u_c(R) &=", s)
    # Two aligned rows, so it drops straight into `mathblock`.
    @test occursin("\\\\", s)
end
