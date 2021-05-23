const Point4f = Point{4,Float32}

abstract type VertexData end

struct PosColor{P<:Point,C<:RGBA} <: VertexData
    position::P
    color::C
end

struct PosUV{P <: Point, UV<:Point{2}} <: VertexData
    position::P
    uv::UV
end

Vulkan.VertexInputAttributeDescription(::Type{T}, binding) where {T<:VertexData} =
    VertexInputAttributeDescription.(
        0:fieldcount(T)-1,
        binding,
        VkFormat.(fieldtypes(T)),
        fieldoffset.(T, 1:fieldcount(T)),
    )

Vulkan.VertexInputBindingDescription(
    ::Type{T},
    binding;
    input_rate = VK_VERTEX_INPUT_RATE_VERTEX,
) where {T<:VertexData} = VertexInputBindingDescription(binding, sizeof(T), input_rate)

function invert_y_axis(p::Point)
    coords = map(x -> x[1] == 2 ? -x[2] : x[2], enumerate(coordinates(p)))
    typeof(p)(coords)
end

function vk.VkFormat(::Type{T}) where {T}
    @match T begin
        &Point1f => VK_FORMAT_R32_SFLOAT
        &Point2f => VK_FORMAT_R32G32_SFLOAT
        &Point3f || &RGB{Float16} => VK_FORMAT_R32G32B32_SFLOAT
        &Point4f || &RGBA{Float32} => VK_FORMAT_R32G32B32A32_SFLOAT
        &RGBA{Float16} => VK_FORMAT_R16G16B16A16_SFLOAT
    end
end
