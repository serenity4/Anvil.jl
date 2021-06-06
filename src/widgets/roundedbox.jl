# struct RoundedBox{T} <: SDFWidget{T}
#     f::Function
#     box::Box{2,T}
#     roundedness::T
#     function RoundedBox(box::Box{2,T}, roundedness) where {T}
#         new{T}(round(roundedness, sdf(box)), box, convert(T, roundedness))
#     end
# end

# Meshes.boundingbox(w::RoundedBox) = w.box
