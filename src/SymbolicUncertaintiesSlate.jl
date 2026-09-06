"""
    SymbolicUncertaintiesSlate

Presentation helpers for driving
[`SymbolicUncertainties.jl`](https://github.com/s-celles/SymbolicUncertainties.jl)
from a [Kaimon Slate](https://github.com/kahliburke/KaimonSlate.jl) notebook.

The package holds nothing metrological. Every number it produces comes
from `SymbolicUncertainties`; what lives here is the last mile a notebook
needs and a library has no business carrying — turning a symbolic
expression into a `Float64`, a budget into a table a widget can render, a
source breakdown into chart series, and any of it into typeset LaTeX.

See the notebooks in `notebooks/`, rendered as documentation pages.
"""
module SymbolicUncertaintiesSlate

import DynamicQuantities as DQ
import Latexify
import Markdown
import Symbolics
import SymbolicUncertainties
using SymbolicUncertainties: SymbolicMeasurement, UncertaintyBudget, BudgetRow

export unit_of, sweep, budget_table, contribution_series, tex, mathblock,
       measurement_tex

include("numeric.jl")
include("budget.jl")
include("render.jl")

end # module SymbolicUncertaintiesSlate
