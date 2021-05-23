abstract type SDFWidget{T} end

in(p::Point, w::SDFWidget) = w.f(p) <= 0

function vertex_data(w::SDFWidget{T}) where {T}
    box = boundingbox(w)
    mincoords = coordinates(box.min)
    maxcoords = coordinates(box.max)
    Quadrangle(
        b.min,
        b.min + Vec(first(maxcoords) - first(mincoords), zero(T)),
        b.max,
        b.min + Vec(zero(T), last(maxcoords) - last(mincoords)),
    )
end

include("widgets/roundedbox.jl")
