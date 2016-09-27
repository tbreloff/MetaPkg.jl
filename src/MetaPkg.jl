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

# maps spec_name --> MetaSpec
const _specs = Dict{String, MetaSpec}

function load_meta(metaname::String, filename::String)
    f = open(filename)
    spec = nothing
    for l in eachline(f)
        tokens = split(strip(l))
        isempty(tokens) && continue

        # process the "julia 0.5-" line... setting the spec
        if first(tokens) == "julia"
            version = VersionNumber(tokens[2])
            spec = if VERSION >= version
                get!(_specs, metaname, MetaSpec(metaname))
            else
                nothing
            end

        # for other lines, we only care to process if this version applies
        elseif spec != nothing
        end
    end
end

end # module
