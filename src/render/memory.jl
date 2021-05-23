function find_memory_type(physical_device::PhysicalDevice, type_flag, properties::MemoryPropertyFlag)
    mem_props = get_physical_device_memory_properties(physical_device)
    indices =
        findall(
            x -> properties in x.property_flags,
            mem_props.memory_types[1:mem_props.memory_type_count],
        ) .- 1
    if isempty(indices)
        error("Could not find memory with properties $properties")
    else
        ind = findfirst(i -> type_flag & 1 << i ≠ 0, indices)
        if isnothing(ind)
            error("Could not find memory with type $type_flag")
        else
            indices[ind]
        end
    end
end

function Vulkan.DeviceMemory(device::Device, memory_requirements::MemoryRequirements, properties)
    DeviceMemory(
        device,
        memory_requirements.size,
        find_memory_type(device.physical_device, memory_requirements.memory_type_bits, properties),
    )
end

buffer_size(data::AbstractVector{T}) where {T} = sizeof(T) * length(data)
buffer_size(data) = sizeof(data)

"""
Upload data to the specified memory.

!!! warning
    The `memory` must be host coherent and host visible, otherwise the operation will fail.
"""
function upload_data(memory::DeviceMemory, data::DenseArray{T}) where {T}
    memptr = unwrap(map_memory(memory.device, memory, 0, buffer_size(data)))
    GC.@preserve data unsafe_copyto!(Ptr{T}(memptr), pointer(data), length(data))
    unwrap(unmap_memory(memory.device, memory))
end

"""
Download data from the specified memory to an `Array`.

If `copy` if set to true, then all the data mapped from `memory` will be copied. If not, care should be taken to preserve the `memory` mapped and valid as long as the returned data is in use.
"""
function download_data(::Type{<:DenseArray{T}}, memory::DeviceMemory, dims; offset=0, copy=true, unmap=true) where {T}
    size = sizeof(T) * prod(dims)
    memptr = unwrap(map_memory(memory.device, memory, offset, size))
    data = unsafe_wrap(Array, convert(Ptr{T}, memptr), dims; own=false)
    if unmap
        unwrap(unmap_memory(memory.device, memory))
    end
    if copy
        deepcopy(data)
    else
        data
    end
end

"""
Allocate a `DeviceMemory` object with the specified properties and bind it to the `buffer` using memory requirements from `get_buffer_memory_requirements`.
"""
function Vulkan.DeviceMemory(buffer::Buffer, properties::MemoryPropertyFlag) where {T}
    device = buffer.device
    memreqs = get_buffer_memory_requirements(device, buffer)
    memory = DeviceMemory(device, memreqs, properties)
    unwrap(bind_buffer_memory(device, buffer, memory, 0))
    memory
end

"""
Allocate a host visible and coherent `DeviceMemory` object, bind it to the `buffer` using memory requirements from `get_buffer_memory_requirements` and upload `data` to it.
"""
function Vulkan.DeviceMemory(buffer::Buffer, data::DenseArray{T}) where {T}
    memory = DeviceMemory(buffer, MEMORY_PROPERTY_HOST_VISIBLE_BIT | MEMORY_PROPERTY_HOST_COHERENT_BIT)
    upload_data(memory, data)
    memory
end

"""
Allocate a `DeviceMemory` object and bind it to the `image` using memory requirements from `get_image_memory_requirements`.
"""
function Vulkan.DeviceMemory(image::Image, properties::MemoryPropertyFlag)
    memreqs = get_image_memory_requirements(image.device, image)
    memory = DeviceMemory(image.device, memreqs, properties)
    unwrap(bind_image_memory(image.device, image, memory, 0))
    memory
end
