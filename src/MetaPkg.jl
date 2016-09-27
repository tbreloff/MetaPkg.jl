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

const _specs = Dict{String, MetaSpec}

function load_meta(metaname::String, filename::String)
end

end # module
