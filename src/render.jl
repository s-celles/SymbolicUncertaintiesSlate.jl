# Typesetting.
#
# A measurand and its combined standard uncertainty are algebra, and algebra
# reads far better set than printed. Slate renders LaTeX in both markdown and
# code-cell output, so a notebook can show `u_c` the way the GUM writes it
# rather than as a line of Julia.

"""
    tex(x) -> String

Render `x` as an **inline** LaTeX fragment, with no delimiters and no
environment.

The caller decides where it goes — inside `\$…\$` in a markdown cell, or as a
row of [`mathblock`](@ref). `Latexify.latexify(x)` alone wraps its output in
`\\begin{equation}`, which cannot be nested and cannot sit inline; this strips
that back to the fragment.

A `SymbolicMeasurement` renders as `estimate \\pm u_c`, matching the
package's own display. Note that JCGM 100:2008 §7.2.2 deliberately avoids the
`±` glyph in a *reported* result, where it is read as an expanded uncertainty
`y ± U`; see [`SymbolicUncertainties.report`](https://s-celles.github.io/SymbolicUncertainties.jl/dev/reporting/)
for the four forms a certificate uses. This is notebook display, not a report.

```julia
tex(V / I)          # "\\frac{V}{I}"
```
"""
tex(x) = _strip_env(String(Latexify.latexify(x; env = :raw)))
# `Symbolics.Num <: Real`, so the plain-number method has to be the *narrower*
# one or it swallows every symbolic expression and prints `V / I` where
# `\frac{V}{I}` was wanted.
tex(x::Symbolics.Num) = _strip_env(String(Latexify.latexify(x; env = :raw)))
tex(x::Real) = string(x)
tex(m::SymbolicMeasurement) = tex(m.val) * " \\pm " * tex(m.err)

# `env = :raw` already drops the equation environment on current Latexify, but
# the guard costs nothing and the failure it prevents — a nested environment
# that silently renders as literal text — is invisible until someone reads the
# page.
function _strip_env(s::AbstractString)
    s = replace(s, r"\\begin\{equation\}\s*" => "", r"\s*\\end\{equation\}" => "")
    s = replace(s, r"^\s*\$+" => "", r"\$+\s*$" => "")
    return String(strip(s))
end

"""
    mathblock(rows) -> Markdown.MD

Stack `rows` — each an `lhs &= rhs` fragment — into one aligned display block.

The `&` in every row is the alignment point, so a column of definitions lines
up on its equals signs the way a derivation should.

```julia
mathblock([
    "R &= " * tex(R.val),
    "u_c(R) &= " * tex(R.err),
])
```

Return it from a code cell and Slate typesets it; the same value interpolates
into a markdown cell with `{{ }}`.
"""
function mathblock(rows)
    Markdown.parse(
        "\$\$\\begin{aligned}" * join(rows, " \\\\[6pt] ") * "\\end{aligned}\$\$",
    )
end

"""
    measurement_tex(m::SymbolicMeasurement; symbol = "y") -> String

The two aligned rows a measurement deserves: its estimate, and its combined
standard uncertainty on a line of its own.

`u_c` is usually the larger expression by an order of magnitude, so setting it
beside the estimate makes both unreadable. Returned as a string of
`mathblock` rows so it composes with other rows in one block.

```julia
mathblock([measurement_tex(R; symbol = "R")])
```
"""
function measurement_tex(m::SymbolicMeasurement; symbol::AbstractString = "y")
    return join(
        [
            "$(symbol) &= " * tex(m.val),
            "u_c($(symbol)) &= " * tex(m.err)
        ],
        " \\\\[6pt] "
    )
end
