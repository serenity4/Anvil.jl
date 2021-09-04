const Point4f = Point{4,Float32}

struct PosColor{P<:Point,C<:Colorant}
    position::P
    color::C
end

struct PosUV{P<:Point,UV<:Point{2}}
    position::P
    uv::UV
end

# type piracy
@nospecialize
Vulkan.Format(::Type{Point{1,Float32}}) = FORMAT_R32_SFLOAT
Vulkan.Format(::Type{Point{2,Float32}}) = FORMAT_R32G32_SFLOAT
Vulkan.Format(::Union{Type{Point{3,Float32}},RGB{Float32}}) = FORMAT_R32G32B32_SFLOAT
Vulkan.Format(::Union{Type{Point{4,Float32}},RGBA{Float32}}) = FORMAT_R32G32B32A32_SFLOAT
Vulkan.Format(::Type{RGB{Float16}}) = FORMAT_R16G16B16_SFLOAT
Vulkan.Format(::Type{RGBA{Float16}}) = FORMAT_R16G16B16A16_SFLOAT
@specialize
