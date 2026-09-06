# Upstream bugs

Defects in dependencies that this repository has to work around. Each entry
records what breaks, the minimal reproduction, the workaround in force here,
and what the upstream fix would be.

---

## UB-001 — DocumenterSlate renders cell output at a stale world age

**Package:** [DocumenterSlate.jl](https://github.com/s-celles/DocumenterSlate.jl)
(observed at the `main` revision resolved on 2026-09-06,
`~/.julia/packages/DocumenterSlate/LsaoG`)

**Status:** open, worked around here

### What breaks

Any notebook cell whose **value is a `Symbolics` object** aborts the whole
notebook build. The failure is reported at the worker level rather than
against a cell, so the message names neither the notebook cell nor the real
cause:

```
ERROR: isolated notebook worker failed: MethodError: no method matching size(::SymbolicUtils.ShapeVecT)

Closest candidates are:
  size(::SymbolicUtils.SmallVec) (method too new to be called from this world context.)
   @ SymbolicUtils …/SymbolicUtils/src/small_array.jl:275
```

`method too new to be called from this world context` is the tell: the method
exists, and dispatch refuses it because of world age.

### Minimal reproduction

A two-cell notebook, no part of this repository involved:

```julia
#%% code id=setup
using Symbolics
@variables x y
"ready"

#%% code id=expr
x / y
```

Rendered through `build_slates`, this fails. Replace the second cell with
`string(x / y)` and the same notebook renders (`status = :executed`).

### Cause

`DocumenterSlate._isolated_worker` (src/isolated.jl) is a single function
invocation that does three things in order:

1. `Pkg.activate(request.project_dir)`;
2. `_execute_cells(...)` — which runs the notebook's `using Symbolics`,
   **loading new methods into a newer world**;
3. `cell_to_markdown(cell; …)` — which `show`s each cell's value.

Step 3 runs at the world age fixed when `_isolated_worker` was *entered*, in
step 0. The `show` path for a `Symbolics.Num` dispatches into
`SymbolicUtils`, whose `size(::SmallVec)` method was defined during step 2 —
too new for the caller's world, so dispatch fails.

The cells themselves are fine: KaimonSlate evaluates each one dynamically, so
cell code sees the current world. Only DocumenterSlate's own rendering of the
resulting values is stranded in the old one.

Nothing about this is specific to `Symbolics`. Any package a notebook loads
whose display path reaches a method defined by that same load is affected;
`Symbolics` reaches it on the very first expression, which is why it shows up
immediately here.

### Workaround in force

The notebooks never return a bare `Symbolics` value from a cell. Every
symbolic result is converted **inside the cell** — where the world age is
current — before it becomes the cell's value:

| instead of | write |
|---|---|
| `R_m` | `mathblock([measurement_tex(R_m; symbol = "R")])` |
| `m.err` | `mathblock(["u_c &= " * tex(m.err)])` |
| `uncertainty_budget(m)` | `markdown_table(budget_table(uncertainty_budget(m)))` |
| `(a, b)` of `Num`s | `markdown_table([(name = "a", value = tex(a)), …])` |
| a `Dict{Num,Num}` | a `markdown_table` of `tex`-rendered rows |
| `U.k` | `Float64(Symbolics.value(U.k))` |

`tex`, `mathblock`, `measurement_tex` and `budget_table` all run as ordinary
cell code, so the conversion happens in the current world and only a `String`,
a `Markdown.MD` or a table reaches the renderer.

This costs nothing when a notebook is opened in Slate directly — raw display
works there — and the rendered pages are better for it: typeset math beats a
dump of `sqrt(((1 / I)^2)*(σV^2) + …)`.

### Upstream fix

Call the renderer through `Base.invokelatest`, so it runs in the world the
notebook's own `using` statements produced. In `_isolated_worker`:

```julia
rendered = String[
    let …
        Base.invokelatest(cell_to_markdown, cell; show_code = request.show_code,
                          anchor_prefix = request.slug, asset_path = asset_path)
    end for cell in executed.cells
]
```

`extract_assets!` sits on the same side of the world boundary and needs the
same treatment if a cell's value carries a rich display.

Reporting the failure against the cell whose value could not be rendered
would help independently of the fix: the current message gives no way to find
the offending cell short of bisecting the notebook.

---

## UB-002 — DocumenterSlate renders charts and tables as a struct dump

**Package:** [DocumenterSlate.jl](https://github.com/s-celles/DocumenterSlate.jl)
(observed at the `main` revision resolved on 2026-09-06)

**Status:** open, partially worked around here

### What breaks

A cell returning a KaimonSlate rich display object — `echart(...)` or
`slate_table(...)` — renders on the published page as the `text/plain` dump of
its internal struct:

```
KaimonSlate.ReportEngine.EChart(Dict{String, Any}("xAxis" => Dict{String, Any}(…
    "series" => Dict{String, Any}[Dict("data" => [[0.05, 2.0099751242241775], …
```

For a 200-point sweep that is roughly 15 kB of unreadable JSON in the middle
of the page. `slate_table` is worse in kind if not in size: the reader gets
`ColumnDef("quantity", :string, :left, nothing, true, true, :none, nothing)`
where a table belongs.

Nothing is lost — the notebook itself renders correctly in Slate, and the
values are right — but the published documentation is where most readers meet
these notebooks.

### Cause

`DocumenterSlate.extract_assets!` (src/assets.jl) recognises exactly two MIME
types, `image/png` and `image/svg+xml`. A value showable as neither falls
through to `text/plain`. `EChart` and `SlateTable` are showable as neither:
they are rendered by Slate's front end from a JSON payload, and there is no
server-side rasteriser behind them.

This is not specific to this repository — the same dumps appear in
[GiacSlate.jl](https://github.com/JuliaGiac/GiacSlate.jl)'s published notebook
pages, which is the reference this project is modelled on.

### Workaround in force

**Tables** are returned as `Markdown` tables via
[`markdown_table`](@ref) instead of `slate_table`. A Markdown table renders
as a real table in Slate *and* in Documenter, and every table in these
notebooks is small enough (2–11 rows) that sorting and filtering buy nothing.
`slate_table` remains the right call for a large or explorable result, and
`markdown_table`'s docstring says so.

**Charts** are left as `echart`. There is no static substitute that keeps the
reactive behaviour a slider drives, and rendering ECharts server-side is not
something this package can do. The dumps stay.

### Upstream fix

Two candidates, not exclusive:

1. **Render the payload as a live chart.** `SlateOutputOptions` already carries
   `interactivity = :client`, which nothing currently consumes. Emitting a
   `<div>` plus the ECharts option JSON, with the library loaded from the
   documentation's assets, would make published charts interactive rather than
   dumped — the option payload is already exactly what ECharts takes.
2. **Emit a static fallback.** Failing that, `show(io, MIME"text/html", ::EChart)`
   and `::SlateTable` renderers in KaimonSlate, plus `text/html` in
   `_ASSET_MIME_EXTENSIONS`, would at least put a table where a table belongs.

A `CairoMakie` figure is showable as PNG and so already extracts correctly.
Authors who need publication-quality static plots can use Makie today; that is
a trade of interactivity for a figure, not a fix.
