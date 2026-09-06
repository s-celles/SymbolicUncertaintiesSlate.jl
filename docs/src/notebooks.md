# The notebooks

Seven notebooks, in reading order. Each is a live Kaimon Slate document —
what you see here is that document executed at build time; what you get by
running it is the same document with its controls working.

The arc is deliberate. Notebooks 1–3 build the model and explain what a
symbolic measurement actually *is*. Notebooks 4–5 turn it into decisions: a
reported result, and a purchasing specification. Notebooks 6–7 question the
framework itself and then leave the notebook entirely.

## 1. [Measurement Uncertainty, Symbolically](notebooks/uncertainty_intro.md)

`±`, the arithmetic operators, and Ohm's law. Why the answer is a formula
rather than a number, how units annotate the symbols and the result derives
its own, and the first surprise: `x - x` is exactly `0 ± 0`.

*Start here.*

## 2. [Sensitivity & the Uncertainty Budget](notebooks/sensitivity_and_budget.md)

Sensitivity coefficients `∂f/∂xᵢ`, and the EA-4/02 §7.3 budget built on them
— the table that says where the next euro of calibration effort should go.
Move the circuit and watch which source dominates change: a budget describes
a **model at an operating point**, not a property of the hardware.

## 3. [Sources & Correlation](notebooks/sources_and_correlation.md)

What a `SymbolicMeasurement` really carries. Why cancellation is exact, the
trap that identity is the *object* and never the symbol name — worth a factor
of 2.5 in `u_c` when you get it wrong — and correlation without anyone
supplying a covariance matrix.

## 4. [Expanded Uncertainty & Reporting](notebooks/expanded_and_reporting.md)

Coverage factors and their assumptions, Welch–Satterthwaite for small
samples, the four textual forms §7.2.2 allows, and a specimen calibration
certificate in the shape ISO/IEC 17025 §7.8 requires — with its unmet clauses
printed on the document rather than hidden in a checker nobody calls.

## 5. [Protocol Design](notebooks/protocol_design.md)

The model run backwards. Given a target `u_c`, what precision must each
instrument have? And given a fixed budget, how should it be divided? Both
have closed-form answers, which is the payoff for never reducing the model to
a number.

## 6. [Beyond First Order](notebooks/beyond_first_order.md)

Everything above rests on a first-order Taylor expansion. Four tools for
deciding whether that is safe here — a curvature indicator, a rigorous bound,
the Amd.1:2026 correction to the estimate, and the JCGM 101:2008 §8.2 Monte
Carlo cross-check. None of them changes a result; they report.

Includes the case where the GUM's own Annex H.1 example fails the test, and
why that is instructive rather than alarming.

## 7. [Code Generation & Deployment](notebooks/codegen_and_deployment.md)

Out of the notebook: a compiled Julia evaluator for a hot loop, C source for
an instrument, LaTeX for a certificate, a `DataFrame` for a pipeline. The
same expression in six shapes, none of them transcribed by hand.
