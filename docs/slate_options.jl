# Build options shared by `render.jl` and `make.jl`.
#
# This file exists because the two scripts MUST agree. DocumenterSlate's cache
# fingerprint is computed from the notebook bytes, the resolved environment, the
# Julia / KaimonSlate / DocumenterSlate versions, and a hash of the
# render-affecting options — which includes `fail_on_error` and
# `worker_environment`. If `make.jl` passed even one of them differently from
# `render.jl`, the fingerprint would differ, the cache lookup would miss, and
# `execution = :never` would abort the deploy job with a "cache miss" error that
# says nothing about the actual cause. Defining them once removes the
# opportunity to drift.
#
# `execution` is the one legitimate difference, so it is the argument: `:auto`
# for the render job (execute on a cache miss), `:never` for the deploy job (a
# cache miss is an error). It is not part of the fingerprint.

const REPO = dirname(@__DIR__)

function slate_options(execution::Symbol)
    return SlateBuildOptions(;
        # The notebooks live at the repository root, not under docs/: they are
        # the very files you open with `slate notebooks/uncertainty_intro.jl`.
        # The docs build reads them; it does not keep a copy that would drift.
        source = joinpath(REPO, "notebooks"),
        output = joinpath(@__DIR__, "src", "notebooks"),
        cache_dir = joinpath(@__DIR__, "slate_cache"),
        slate_toml = joinpath(@__DIR__, "slate.toml"),
        execution = execution,
        # Strict: the first cell that throws fails the build. Restated here
        # rather than defaulted because it feeds the cache fingerprint, and a
        # silent divergence from `render.jl` would surface as an opaque cache
        # miss rather than as the disagreement it is.
        fail_on_error = true,
        # The parent process environment is not inherited; this is the explicit
        # allowlist. The notebooks print σ, Ω, ν and ± throughout — without a
        # UTF-8 locale the captured output would come back mangled.
        worker_environment = Dict(
            "LANG" => "C.UTF-8",
            "LC_ALL" => "C.UTF-8",
        ),
    )
end
