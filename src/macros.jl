
macro meta(ex::Expr)
    @show ex.head ex.args
    ret = Expr(:block)
    if ex.head == :import
        name = string(ex.args[1])
        spec = get_spec(name)
        @show spec
        for name in spec.tagged
            push!(ret.args, :(import $name))
        end
        for pkg in spec.branch
            push!(ret.args, :(import $(pkg.name)))
        end
    end
    esc(ret)
end
