"""
Abstract Vulkan object accessible via a handle.
"""
abstract type AbstractHandle{H} end

handle_type(::Type{<:AbstractHandle{H}}) where {H} = handle_type(H)
handle_type(T::Type{Handle}) = T

handle(h::Handle) = h
handle(r::AbstractHandle) = handle(r.handle)

Vulkan.device(x::AbstractHandle) = device(handle(x))
Vulkan.instance(x::AbstractHandle) = instance(handle(x))

Base.unsafe_convert(T::Type{Ptr{Cvoid}}, h::AbstractHandle) = Base.unsafe_convert(T, handle(h))
Base.convert(::Type{H}, x::AbstractHandle{H}) where {H<:Handle} = handle(x)

"""
Application-owned resource hosted in memory on the GPU.

Typical instances represent a buffer or an image `handle`
bound to `memory`.
"""
struct Allocated{H,M} <: AbstractHandle{H}
    handle::H
    memory::M
end

memory(a::Allocated) = a.memory

struct Created{H<:Handle,I} <: AbstractHandle{H}
    handle::H
    info::I
end

info(c::Created) = c.info

function require_feature(device::Created{Device,DeviceCreateInfo}, feature::Symbol)
    getproperty(info(device).enabled_features, feature) || error("Feature '$feature' required but not enabled.")
end

function require_extension(inst_or_device::Union{Created{Instance,InstanceCreateInfo},Created{Device,DeviceCreateInfo}}, extension)
    string(extension) in info(inst_or_device).enabled_extension_names || error("Extension '$extension' required but not enabled.")
end

function require_layer(instance::Created{Instance,InstanceCreateInfo}, layer)
    string(layer) in info(instance).enabled_layer_names || error("Layer '$layer' required but not enabled.")
end

const VertexBuffer = Allocated{Buffer,DeviceMemory}
const IndexBuffer = Allocated{Buffer,DeviceMemory}

abstract type ShaderResource end

struct SampledImage <: ShaderResource
    image::Allocated{Created{Image,ImageCreateInfo}}
    view::Created{ImageView,ImageViewCreateInfo}
    sampler::Sampler
end

Vulkan.DescriptorType(::Type{SampledImage}) = DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER

struct StorageBuffer <: ShaderResource
    buffer::Allocated{Buffer}
end

Vulkan.DescriptorType(::Type{StorageBuffer}) = DESCRIPTOR_TYPE_STORAGE_BUFFER
