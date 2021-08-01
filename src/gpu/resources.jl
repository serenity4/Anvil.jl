"""
Abstract Vulkan object accessible via a handle.
"""
abstract type AbstractHandle{H} end

handle_type(::Type{<:AbstractHandle{H}}) where {H} = handle_type(H)
handle_type(T::Type{Handle}) = T

handle(h::Handle) = h
handle(r::AbstractHandle) = r.handle

"""
Application-owned resource hosted in memory on the GPU.

Typical instances represent a buffer or an image `handle`
bound to `memory`.
"""
struct Allocated{H,M} <: AbstractHandle{H}
    handle::H
    memory::M
end

struct Created{H<:Handle,I} <: AbstractHandle{H}
    handle::H
    info::I
end

Base.@kwdef struct ResourceStorage
    images::Dictionary{Symbol,Allocated{Image}} = Dictionary()
    buffers::Dictionary{Symbol,Allocated{Buffer}} = Dictionary()
    semaphores::Dictionary{Symbol,Semaphore} = Dictionary()
    fences::Dictionary{Symbol,Fence} = Dictionary()
    command_pools::Dictionary{Symbol,CommandPool} = Dictionary()
    descriptor_pools::Dictionary{Symbol,Created{DescriptorPool}} = Dictionary()
    descriptor_sets::Dictionary{Symbol,DescriptorSet} = Dictionary()
    descriptor_set_layouts::Dictionary{Symbol,DescriptorSetLayout} = Dictionary()
    image_views::Dictionary{Symbol,ImageView} = Dictionary()
    samplers::Dictionary{Symbol,Sampler} = Dictionary()
    pipelines::Dictionary{Symbol,GPUResource{Pipeline}} = Dictionary()
end

const VertexBuffer = Allocated{Buffer,DeviceMemory}
const IndexBuffer = Allocated{Buffer,DeviceMemory}
const DescriptorSetVector = Created{Vector{DescriptorSet},DescriptorSetAllocateInfo}

abstract type ShaderResource end

struct SampledImage <: ShaderResource
    image::GPUResource{Image}
    view::GPUResource{ImageView}
    sampler::Sampler
end

Vulkan.DescriptorType(::Type{SampledImage}) = DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER

struct StorageBuffer <: ShaderResource
    buffer::AllocatedResource{Buffer}
end

Vulkan.DescriptorType(::Type{StorageBuffer}) = DESCRIPTOR_TYPE_STORAGE_BUFFER

function Base.show(io::IO, gpu::GPUState)
    print(io, "GPUState with")
    fields = fieldnames(GPUState)
    props = getproperty.(Ref(gpu), fieldnames(GPUState))
    idxs = findall(!isempty, props)
    props = props[idxs]
    fields = fields[idxs]
    if !isempty(props)
        lastfield = last(fields)
        for (field, prop) in zip(fields, props)
            print(io, ' ', length(prop), ' ', replace(string(field), "_" => " "))
            field ≠ lastfield && print(io, ',')
        end
    else
        print(io, " no resources")
    end
end

function Base.show(io::IO, ::MIME"text/plain", gpu::GPUState)
    print(io, "GPUState")
    fields = fieldnames(GPUState)
    props = getproperty.(Ref(gpu), fieldnames(GPUState))
    idxs = findall(!isempty, props)
    props = props[idxs]
    fields = fields[idxs]
    if !isempty(props)
        println(io)
        lastfield = last(fields)
        for (field, prop) in zip(fields, props)
            println(io, "└─ ", length(prop), ' ', replace(string(field), "_" => " "))
        end
    else
        print(io, " no resources")
    end
end
