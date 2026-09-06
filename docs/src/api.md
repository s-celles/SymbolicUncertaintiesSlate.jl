```@meta
CurrentModule = SymbolicUncertaintiesSlate
```

# API reference

Presentation helpers for driving `SymbolicUncertainties.jl` from a Kaimon
Slate notebook. There is no metrology here: every number these produce comes
from the upstream package, through its public API — `evaluate` for the
dimensional walk, `build_evaluator` for the magnitudes, `uncertainty_budget`
for the decomposition.

## Units

```@docs
unit_of
```

## Evaluation across a range

```@docs
sweep
```

## The budget, rendered

```@docs
budget_table
contribution_series
```

## Typesetting

```@docs
tex
mathblock
measurement_tex
```
