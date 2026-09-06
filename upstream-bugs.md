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
| `uncertainty_budget(m)` | `slate_table(budget_table(uncertainty_budget(m)))` |
| `(a, b)` of `Num`s | `slate_table([(name = "a", value = tex(a)), …])` |
| a `Dict{Num,Num}` | a `slate_table` of `tex`-rendered rows |
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
