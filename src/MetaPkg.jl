module MetaPkg

type Package
    name::String
    url::String
    isregistered::Bool
    branchmap::Dict{String,String}
end

type MetaSpec
    name::String
    tagged::Vector{String}  # these are added to the REQUIRE file
    branch::Vector{Package}
end
MetaSpec(name::String) = MetaSpec(name, String[], Package[])

# maps spec_name --> MetaSpec
const _specs = Dict{String, MetaSpec}()

const _protocol = Ref("git")
setprotocol!(proto::AbstractString) = (_protocol[] = s)

function strip_extension(name::AbstractString)
    split(name,".")[1]
end

function name_from_url(url::AbstractString)
    strip_extension(split(url, "/")[end])
end

# TODO: something useful
function parse_branchmap(bmap::AbstractString)
    if isempty(bmap)
        Dict{String,String}()
    else
        eval(parse(bmap))
    end
end

function load_meta(metaname::AbstractString, dir::AbstractString = joinpath(dirname(@__FILE__), "..", "requires"))
    f = open(joinpath(dir, metaname))
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
                    url = if _protocol[] == :git
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
                @show name, url, isregistered

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

end # module
