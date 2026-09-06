# Security Policy

## Supported versions

This project is pre-1.0. Only the latest released version receives security
fixes.

| Version | Supported |
|---------|-----------|
| 0.1.x   | ✅        |
| < 0.1   | ❌        |

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Report it privately through GitHub's coordinated disclosure flow:

1. Go to the [Security Advisories page](https://github.com/s-celles/SymbolicUncertaintiesSlate.jl/security/advisories/new).
2. Open a draft advisory (GHSA) describing the issue.

Include, as far as you can:

- the affected version and Julia version;
- a minimal reproduction;
- the impact you believe it has.

You can expect an acknowledgement within **7 days** and an assessment within
**30 days**. If the report is accepted, a fix and a published advisory follow;
if it is declined, you get the reasoning.

## Scope

This package renders and evaluates notebooks. Two things are worth stating
plainly about that.

**Notebook code is arbitrary Julia.** Opening a `.jl` notebook from an
untrusted source and running it executes whatever it contains, exactly as
running a script would. The documentation build is deliberately split so that
the job which executes notebook code never has the deployment key in scope;
apply the same reasoning when running notebooks you did not write.

**This is not calibration software.** A wrong uncertainty is a correctness
bug, not a security vulnerability, and belongs in the issue tracker — but
see the non-warranty clause in [`LICENSE.md`](LICENSE.md) and the
regulated-use disclaimer in the documentation before relying on any output
here.
