module MetaPkg

export
    meta_add,
    meta_rm,
    meta_free,
    meta_checkout,
    @meta

type Package
    name::String
    url::String
    isregistered::Bool
    branchmap::Dict{String,String}
end

"Gets the proper branch to check out for this package given meta branch"
function package_branch(pkg::Package, branch = "master")
    if haskey(pkg.branchmap, "_")
        pkg.branchmap["_"]
    else
        get(pkg.branchmap, branch, branch)
    end
end

type MetaSpec
    name::String
    tagged::Vector{String}  # these are added to the REQUIRE file
    branch::Vector{Package}
    meta::Vector{MetaSpec}
end
MetaSpec(name::AbstractString) = MetaSpec(name, String[], Package[], MetaSpec[])

# maps spec_name --> MetaSpec
const _specs = Dict{String, MetaSpec}()
const _default_dir = joinpath(dirname(@__FILE__), "..", "requires")
const _protocol = Ref("git")
const _do_pkg_calls = Ref(true)

dry_run(dry::Bool = true) = (_do_pkg_calls[] = !dry; return)


"git or https"
setprotocol!(proto::AbstractString) = (@assert proto in ("git", "https"); _protocol[] = proto)

# XXX.jl --> XXX
function strip_extension(name::AbstractString)
    split(name,".")[1]
end

# git@github.com:tbreloff/Plots.jl --> Plots
function name_from_url(url::AbstractString)
    strip_extension(split(url, "/")[end])
end

function stringify(expr::Expr)
    expr.head == :(=>) || error("Unexpected expr in stringify: $expr")
    for i=1:length(expr.args)
        arg = expr.args[i]
        if isa(arg,Symbol)
            expr.args[i] = string(arg)
        end
    end
    expr
end


function parse_branchmap(bmap::AbstractString)
    if isempty(bmap)
        Dict{String,String}()
    else
        expr = parse(bmap)
        # dump(expr)
        if isa(expr, Symbol)
            Dict{String,String}("_" => string(expr))
        else
            de = :(Dict{String,String}())
            if expr.head == :tuple
                args = map(stringify, expr.args)
                append!(de.args, expr.args)
            else
                push!(de.args, stringify(expr))
            end
            eval(de)
        end
    end
end

"Load a MetaSpec from a file."
function load_meta(metaname::AbstractString, dir::AbstractString = _default_dir)
    f = open(joinpath(dir, metaname))
    info("Loading MetaSpec from $(joinpath(dir, metaname))")
    spec = nothing
    isbranch = true
    ismeta = false

    for l in eachline(f)
        tokens = split(strip(l))
        isempty(tokens) && continue

        # process the "julia 0.5-" line... setting the spec
        firsttoken = first(tokens)
        if firsttoken == "julia"
            version = length(tokens) > 1 ? VersionNumber(tokens[2]) : VERSION
            spec = if VERSION >= version
                # create a new MetaSpec for this version
                _specs[metaname] = MetaSpec(metaname)
            else
                nothing
            end
            isbranch = true
            ismeta = false

        # for other lines, we only care to process if this version applies
        elseif spec != nothing
            if firsttoken == "tagged:"
                isbranch = false
                continue
            elseif firsttoken == "branch:"
                isbranch = true
                continue
            elseif firsttoken == "meta:"
                ismeta = true
                continue
            end

            if ismeta
                # for meta, add the spec, checking for leading directory
                byslash = split(firsttoken, "/")
                push!(spec.meta, if length(byslash) == 1
                    load_meta(strip_extension(firsttoken))
                else
                    load_meta(strip_extension(byslash[end]), dir = join(byslash[1:end-1], "/"))
                end)

            elseif isbranch
                # for branch section, look for <name>, <org>/<name>, or full url and add Package object
                repo = firsttoken
                byslash = split(repo, "/")
                if length(byslash) == 1
                    name = strip_extension(byslash[1])
                    try
                        # TODO: verify this is in METADATA and load url
                        url = Pkg.Read.url(name)
                        name = name_from_url(url)
                    catch err
                        warn("MetaPkg requirement is not a registered package: \"$l\"")
                        continue
                    end
                elseif length(byslash) == 2
                    org, name = byslash
                    name = strip_extension(name)
                    url = if _protocol[] == "git"
                        "git@github.com:$org/$name.jl"
                    else
                        "https://github.com/$org/$name.jl"
                    end
                else
                    url = repo
                    name = name_from_url(url)
                end

                isregistered = try
                    Pkg.Read.url(name)
                    true
                catch
                    false
                end
                # @show name, url, isregistered

                push!(spec.branch, Package(
                    name,
                    url,
                    isregistered,
                    parse_branchmap(join(tokens[2:end]))
                ))
            else

                # otherwise just add as a "tagged", meaning we don't check it out
                push!(spec.tagged, strip(l))
            end

        else
            error("Meta file not properly formed.  spec == nothing. line: $l")
        end
    end
    spec
end

function get_spec(metaname::AbstractString, dir::AbstractString = _default_dir)
    if haskey(_specs, metaname)
        _specs[metaname]
    else
        spec = load_meta(metaname, dir)
        if spec == nothing
            error("MetaSpec $metaname not loaded properly from $dir")
        end
        spec
    end
end

function is_installed(name::AbstractString)
    try
        Pkg.installed(name) === nothing ? false: true
    catch
        false
    end
end

# -----------------------------------------------------------------------

function meta_add(metaname::AbstractString; dir::AbstractString = _default_dir)
    meta_add(get_spec(metaname, dir))
end

function meta_add(spec::MetaSpec)
    info("Adding meta package: $(spec.name)")
    for name in spec.tagged
        is_installed(name) && continue
        info("Going to run: Pkg.add(\"$name\")")
        _do_pkg_calls[] && Pkg.add(name)
    end
    for pkg in spec.branch
        if pkg.isregistered
            is_installed(pkg.name) && continue
            info("Going to run: Pkg.add(\"$(pkg.name)\")")
            _do_pkg_calls[] && Pkg.add(pkg.name)
        else
            is_installed(pkg.name) && continue
            info("Going to run: Pkg.clone(\"$(pkg.url)\")")
            _do_pkg_calls[] && Pkg.clone(pkg.url)
        end
    end
    for subspec in spec.meta
        meta_add(subspec)
    end
end

# -----------------------------------------------------------------------

function meta_rm(metaname::AbstractString; dir::AbstractString = _default_dir)
    meta_rm(get_spec(metaname, dir))
end

function meta_rm(spec::MetaSpec)
    info("Removing meta package: $(spec.name)")
    for name in spec.tagged
        is_installed(name) || continue
        info("Going to run: Pkg.rm(\"$name\")")
        _do_pkg_calls[] && Pkg.rm(name)
    end
    for pkg in spec.branch
        is_installed(pkg.name) || continue
        info("Going to run: Pkg.rm(\"$(pkg.name)\")")
        _do_pkg_calls[] && Pkg.rm(pkg.name)
    end
    for subspec in spec.meta
        rm(subspec)
    end
end

# -----------------------------------------------------------------------

function meta_free(metaname::AbstractString; dir::AbstractString = _default_dir)
    meta_free(get_spec(metaname, dir))
end

function meta_free(spec::MetaSpec)
    info("Freeing meta package: $(spec.name)")
    for name in spec.tagged
        info("Going to run: Pkg.free(\"$name\")")
        _do_pkg_calls[] && Pkg.free(name)
    end
    for pkg in spec.branch
        if pkg.isregistered
            info("Going to run: Pkg.free(\"$(pkg.name)\")")
            _do_pkg_calls[] && Pkg.free(pkg.name)
        else
            pkgbranch = package_branch(pkg, "master")
            info("Going to run: Pkg.checkout(\"$(pkg.name)\", \"$pkgbranch\")")
            _do_pkg_calls[] && Pkg.checkout(pkg.name, pkgbranch)
        end
    end
    for subspec in spec.meta
        free(subspec)
    end
end

# -----------------------------------------------------------------------

function do_checkout(name, branchname)
    repo = LibGit2.GitRepo(Pkg.dir(name))
    LibGit2.fetch(repo)
    Pkg.checkout(name, branchname)
end

function meta_checkout(metaname::AbstractString, branch::AbstractString = "master"; dir::AbstractString = _default_dir)
    meta_checkout(get_spec(metaname, dir), branch)
end

function meta_checkout(spec::MetaSpec, branch::AbstractString = "master")
    info("Checking out branch $branch for meta package: $(spec.name)")
    for pkg in spec.branch
        pkgbranch = package_branch(pkg, branch)
        info("Going to run: Pkg.checkout(\"$(pkg.name)\", \"$pkgbranch\")")
        _do_pkg_calls[] && do_checkout(pkg.name, pkgbranch)
    end
    for subspec in spec.meta
        checkout(subspec, branch)
    end
end

# -----------------------------------------------------------------------
# utilities to extend Pkg

function confirm_action(prompt::AbstractString="")
    print(prompt, " Do you wish to continue? (y/n): ")
    lowercase(chomp(readline())) in ("y", "yes")
end

function confirm_rm(path::AbstractString)
    ispath(path) || return
    prompt = "About to remove path $path."
    if confirm_action(prompt)
        Base.rm(path, force=true, recursive=true)
    end
end

"Completely remove a package, including from cache, lib, and trash."
function purge(repo::AbstractString)
    info("Going to purge $repo... This means using Pkg.rm and then deleting traces in the .julia folder.")
    gotspec = false
    try
        # first try to purge a meta spec
        spec = get_spec(repo)
        gotspec = true
        for name in spec.tagged
            purge(name)
        end
        for pkg in spec.branch
            purge(pkg.name)
        end
        for subspec in spec.meta
            purge(subspec.name)
        end
        return
    catch
        gotspec && rethrow()
    end

    if !gotspec
        # normal remove
        Pkg.rm(repo)

        pkgdir = Pkg.dir()

        # purge from trash
        confirm_rm(joinpath(pkgdir, ".trash", repo))

        # purge from lib
        confirm_rm(joinpath(pkgdir, "..", "lib", "v$(VERSION.major).$(VERSION.minor)", repo) * ".ji")

        # purge from cache
        confirm_rm(joinpath(pkgdir, ".cache", repo))
    end
    return
end

# -----------------------------------------------------------------------

include("macros.jl")

end # module
