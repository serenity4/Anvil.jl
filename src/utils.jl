"""
Remap a value from `(low1, high1)` to `(low2, high2)`.
"""
function remap(value, low1, high1, low2, high2)
    low2 + (value - low1) * (high2 - low2) / (high1 - low1)
end

remap(value, from, to) = remap(value, from..., to...)
remap(values::AbstractArray, to; from = extrema(values)) = remap.(values, Ref(from), Ref(to))

remap(low1, high1, low2, high2) = x -> remap(x, low1, high1, low2, high2)

not_implemented_for(T) = error("Not implemented for ", T)

"""
    @forward MyType.prop method1, method2, ...

Extend the provided methods by forwarding the property `prop` of `MyType` instances.
This will give, for a given `method`:
```julia
method(x::MyType, args...; kwargs...) = method(x.prop, args...; kwargs...)
```

"""
macro forward(ex, fs)
    T, prop = @match ex begin
        :($T.$prop) => (T, prop)
        _ => error("Invalid expression $ex, expected <Type>.<prop>")
    end

    fs = @match fs begin
        :(($(fs...),)) => fs
        :($mod.$method) => [fs]
        ::Symbol => [fs]
        _ => error("Expected a method or a tuple of methods, got $fs")
    end

    defs = map(fs) do f
        esc(:($f(x::$T, args...; kwargs...) = $f(x.$prop, args...; kwargs...)))
    end

    Expr(:block, defs...)
end
