# Deploy job: consumes the cache `docs/render.jl` populated, and executes no
# notebook cell (`execution = :never`). This is the only script that ever runs
# with `DOCUMENTER_KEY` in scope — hence execution being *forbidden* here rather
# than merely absent: a cache miss raises, there is no fallback to executing.

import Pkg
Pkg.instantiate()

using Documenter
using DocumenterSlate
using SymbolicUncertaintiesSlate

# ── The notebooks ────────────────────────────────────────────────────────────
# The options are shared with `render.jl` rather than restated, because most of
# them feed the cache fingerprint and any divergence would show up here as an
# opaque cache miss. `:never` is the only difference: a miss raises instead of
# executing.
include("slate_options.jl")

result = build_slates(slate_options(:never))

# Slate's in-app notebook links (`/n/<slug>`) mean nothing once the notebook is
# a Documenter page: they resolve inside the running Slate hub, not on the
# published site, and Documenter rightly flags them as broken local links.
# Rewrite each one that names a notebook this build produced into the sibling
# page it corresponds to. A `/n/` link to something *not* built is left alone,
# so it still surfaces as an error rather than being quietly swallowed.
let slugs = Set(first(splitext(basename(relpath))) for (_, relpath) in result.pages)
    for (_, relpath) in result.pages
        page = joinpath(@__DIR__, "src", "notebooks", relpath)
        text = read(page, String)
        rewritten = replace(text, r"\]\(/n/([A-Za-z0-9_-]+)\)" =>
            m -> (slug = match(r"/n/([A-Za-z0-9_-]+)", m).captures[1];
                  slug in slugs ? "]($slug.md)" : m))
        rewritten == text || write(page, rewritten)
    end
end

# `result.pages` carries paths relative to `opts.output` (docs/src/notebooks/)
# by design: only the caller knows its own layout. Documenter's `pages=` wants
# them relative to docs/src/ instead — hence the prefix, added here.
notebook_pages = [title => joinpath("notebooks", relpath) for (title, relpath) in result.pages]

const PAGES = [
    "Home" => "index.md",
    "Getting started" => "getting-started.md",
    # `notebooks.md` leads the section so the group has a real page of its own
    # at `/notebooks/`. Without it that URL 404s: `notebooks/` would be only a
    # directory holding the generated pages, and a Documenter sidebar group is a
    # collapsible header, not a page.
    "The notebooks" => Any["Overview" => "notebooks.md"; notebook_pages],
    "API reference" => "api.md",
]

# ── llms.txt / llms-full.txt ─────────────────────────────────────────────────
# The https://llmstxt.org convention: a short index of the documentation, and a
# single-file concatenation of it. Documenter has no native support, so both are
# written into docs/src/ *before* `makedocs` runs, which then copies them into
# docs/build/ as ordinary static files. Both are generated from `PAGES`, so they
# cannot drift.

"Flatten the (nested) `PAGES` into (title, path) pairs."
function flatten_pages(entries, prefix = "")
    flat = Pair{String,String}[]
    for (name, value) in entries
        label = isempty(prefix) ? name : prefix * " > " * name
        if value isa AbstractString
            push!(flat, label => value)
        else
            append!(flat, flatten_pages(value, label))
        end
    end
    return flat
end

const FLAT_PAGES = flatten_pages(PAGES)
const SRC = joinpath(@__DIR__, "src")

open(joinpath(SRC, "llms.txt"), "w") do io
    println(io, "# SymbolicUncertaintiesSlate.jl")
    println(io, "> Interactive Kaimon Slate notebooks for SymbolicUncertainties.jl — ",
                "purely symbolic propagation of measurement uncertainty under ",
                "JCGM 100:2008 (GUM), from a first `±` to compiled C, with every ",
                "quantity carrying its unit.")
    println(io)
    println(io, "## Documentation")
    println(io)
    for (name, path) in FLAT_PAGES
        # `index.md` is the site root, not `/index/`.
        url = path == "index.md" ? "" : replace(path, ".md" => "/")
        println(io, "- [", name, "](", url, ")")
    end
    println(io)
    println(io, "## Optional")
    println(io)
    println(io, "- [Repository](https://github.com/s-celles/SymbolicUncertaintiesSlate.jl): the notebooks themselves, in `notebooks/`.")
    println(io, "- [SymbolicUncertainties.jl](https://s-celles.github.io/SymbolicUncertainties.jl/): the package these notebooks drive.")
    println(io, "- [Full text](llms-full.txt): every documentation page concatenated.")
end

open(joinpath(SRC, "llms-full.txt"), "w") do io
    println(io, "# SymbolicUncertaintiesSlate.jl — full documentation")
    println(io, "> The complete documentation source, ", length(FLAT_PAGES), " pages.")
    println(io)
    for (name, path) in FLAT_PAGES
        source_path = joinpath(SRC, path)
        isfile(source_path) || continue
        println(io, "## Section: ", name)
        println(io, "<!-- Source: ", path, " -->")
        println(io)
        println(io, read(source_path, String))
        println(io, "\n---\n")
    end
end

# ── The site ─────────────────────────────────────────────────────────────────
DocMeta.setdocmeta!(
    SymbolicUncertaintiesSlate,
    :DocTestSetup,
    :(using SymbolicUncertaintiesSlate);
    recursive = true,
)

makedocs(;
    sitename = "SymbolicUncertaintiesSlate.jl",
    modules = [SymbolicUncertaintiesSlate],
    authors = "Sébastien Celles",
    repo = Documenter.Remotes.GitHub("s-celles", "SymbolicUncertaintiesSlate.jl"),
    format = Documenter.HTML(;
        canonical = "https://s-celles.github.io/SymbolicUncertaintiesSlate.jl",
        edit_link = "main",
        # Notebook pages carry full cell output, so they exceed Documenter's
        # default page-size threshold as a matter of course.
        size_threshold_ignore = [path for (_, path) in notebook_pages],
    ),
    # The `julia` blocks on the authored pages are illustrative: running them
    # needs a live Slate kernel, so they are not doctests.
    doctest = false,
    checkdocs = :exports,
    plugins = [SlatePlugin(result)],
    pages = PAGES,
)

# Documenter warns when `deploydocs` is called outside a recognized CI
# environment. Keep local `just docs` builds warning-free while retaining
# deployment in GitHub Actions.
if get(ENV, "CI", "") == "true"
    deploydocs(;
        repo = "github.com/s-celles/SymbolicUncertaintiesSlate.jl.git",
        devbranch = "main",
        push_preview = true,
    )
end
