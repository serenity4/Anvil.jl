const Point4f = Point{4,Float32}

abstract type VertexData end

struct PosColor{P<:Point,C<:RGBA} <: VertexData
    position::P
    color::C
end

struct PosUV{P<:Point,UV<:Point{2}} <: VertexData
    position::P
    uv::UV
end

Vulkan.VertexInputAttributeDescription(::Type{T}, binding) where {T<:VertexData} =
    VertexInputAttributeDescription.(
        0:fieldcount(T)-1,
        binding,
        Format.(fieldtypes(T)),
        fieldoffset.(T, 1:fieldcount(T)),
    )

Vulkan.VertexInputBindingDescription(::Type{T}, binding; input_rate = VERTEX_INPUT_RATE_VERTEX) where {T<:VertexData} =
    VertexInputBindingDescription(binding, sizeof(T), input_rate)

function Vulkan.Format(::Type{T}) where {T}
    @match T begin
        &Point{1,Float32} => FORMAT_R32_SFLOAT
        &Point{2,Float32} => FORMAT_R32G32_SFLOAT
        &Point{3,Float32} || &RGB{Float32} => FORMAT_R32G32B32_SFLOAT
        &Point{4,Float32} || &RGBA{Float32} => FORMAT_R32G32B32A32_SFLOAT
        &RGBA{Float16} => FORMAT_R16G16B16A16_SFLOAT
    end
end
