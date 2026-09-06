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

@testitem "markdown_table renders named tuples as a GFM table" begin
    using Markdown

    md = markdown_table([
        (quantity = "V", u = "0.01 V", percent = 50.0),
        (quantity = "I", u = "0.001 A", percent = 50.0)
    ])

    @test md isa Markdown.MD
    s = repr(MIME"text/plain"(), md)
    # Header from the keys, one row per entry.
    @test occursin("quantity", s)
    @test occursin("percent", s)
    @test occursin("0.01 V", s)
    @test occursin("50.0", s)
end

@testitem "markdown_table escapes a pipe in a cell" begin
    using Markdown

    # A `|` inside a cell would otherwise start a new column and shift every
    # value in the row one place left, silently.
    md = markdown_table([(expr = "a | b", value = "1")])
    s = repr(MIME"text/plain"(), md)

    @test occursin("a", s)
    @test !occursin("| a | b |", s)
end

@testitem "markdown_table handles an empty row set" begin
    using Markdown

    md = markdown_table(NamedTuple{(:a,), Tuple{Int}}[])
    @test md isa Markdown.MD
    @test occursin("no rows", lowercase(repr(MIME"text/plain"(), md)))
end

@testitem "markdown_table rounds float cells for display" begin
    using Markdown

    s = repr(MIME"text/plain"(), markdown_table([(share = 30.703624733475472,)]))

    # Seventeen digits of a variance share is a claim nobody is making.
    @test occursin("30.7", s)
    @test !occursin("30.703624733475472", s)
    # A caller who wants every digit passes a string, which is left alone.
    s2 = repr(MIME"text/plain"(), markdown_table([(share = "30.703624733475472",)]))
    @test occursin("30.703624733475472", s2)
end
