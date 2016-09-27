module MetaPkg

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
end
MetaSpec(name::String) = MetaSpec(name, String[], Package[])

# maps spec_name --> MetaSpec
const _specs = Dict{String, MetaSpec}()
const _default_dir = joinpath(dirname(@__FILE__), "..", "requires")
const _protocol = Ref("git")
const _do_pkg_calls = Ref(true)

dry_run(dry::Bool = true) = (_do_pkg_calls[] = !dry)


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

        # for other lines, we only care to process if this version applies
        elseif spec != nothing
            if firsttoken == "tagged:"
                isbranch = false
                continue
            elseif firsttoken == "branch:"
                isbranch = true
                continue
            end

            if isbranch
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

# -----------------------------------------------------------------------

function add(metaname::AbstractString, dir::AbstractString = _default_dir)
    add(get_spec(metaname, dir))
end

function add(spec::MetaSpec)
    info("Adding meta package: $(spec.name)")
    for name in spec.tagged
        info("Going to run: Pkg.add(\"$name\")")
        _do_pkg_calls[] && Pkg.add(name)
    end
    for pkg in spec.branch
        if pkg.isregistered
            info("Going to run: Pkg.add(\"$(pkg.name)\")")
            _do_pkg_calls[] && Pkg.add(pkg.name)
        else
            info("Going to run: Pkg.clone(\"$(pkg.url)\")")
            _do_pkg_calls[] && Pkg.clone(pkg.url)
        end
    end
end

# -----------------------------------------------------------------------

function rm(metaname::AbstractString, dir::AbstractString = _default_dir)
    rm(get_spec(metaname, dir))
end

function rm(spec::MetaSpec)
    info("Removing meta package: $(spec.name)")
    for name in spec.tagged
        info("Going to run: Pkg.rm(\"$name\")")
        _do_pkg_calls[] && Pkg.rm(name)
    end
    for pkg in spec.branch
        info("Going to run: Pkg.rm(\"$(pkg.name)\")")
        _do_pkg_calls[] && Pkg.rm(pkg.name)
    end
end

# -----------------------------------------------------------------------

function free(metaname::AbstractString, dir::AbstractString = _default_dir)
    free(get_spec(metaname, dir))
end

function free(spec::MetaSpec)
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
end

# -----------------------------------------------------------------------

function checkout(metaname::AbstractString, branch::AbstractString = "master")
    haskey(_specs, metaname) || error("MetaSpec not loaded for $metaname.  Call MetaPkg.add or MetaPkg.load_meta")
    checkout(_specs[metaname], branch)
end

function checkout(spec::MetaSpec, branch::AbstractString = "master")
    info("Checking out branch $branch for meta package: $(spec.name)")
    for pkg in spec.branch
        pkgbranch = package_branch(pkg, branch)
        info("Going to run: Pkg.checkout(\"$(pkg.name)\", \"$pkgbranch\")")
        _do_pkg_calls[] && Pkg.checkout(pkg.name, pkgbranch)
    end
end

# -----------------------------------------------------------------------
# -----------------------------------------------------------------------
# -----------------------------------------------------------------------
# -----------------------------------------------------------------------

end # module
