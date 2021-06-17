function vertex_buffer(w::Widget, device::Device)
    vdata = vertex_data(w)
    resource = allocate_vertex_buffer(device, buffer_size(vdata))
    upload_data(resource.memory, vdata)
    resource
end

function allocate_vertex_buffer(device::Device, size)
    vbuffer = Buffer(device, size, BUFFER_USAGE_VERTEX_BUFFER_BIT, SHARING_MODE_EXCLUSIVE, [0])
    vmemory = DeviceMemory(vbuffer, MEMORY_PROPERTY_HOST_VISIBLE_BIT | MEMORY_PROPERTY_HOST_COHERENT_BIT)
    GPUResource(vbuffer, vmemory)
end

function update_vertex_buffer!(device::Device, gpu::GPUState, wname::Symbol, w::Widget)
    bname = vertex_buffer_symbol(wname)
    if !haskey(gpu.buffers, bname)
        gpu.buffers[bname] = vertex_buffer(w, device)
    else
        upload_data(gpu.buffers[bname].memory, vertex_data(w))
    end
end

vertex_buffer_symbol(wname::Symbol) = Symbol(wname, :_vertex)
vertex_data_type(w::Widget) = vertex_data_type(typeof(w))
nvertices(T::Type{<:Widget}) = not_implemented_for(T)
nvertices(w::Widget) = nvertices(typeof(w))
resource_types(w::Widget) = resource_types(typeof(w))

include("widgets/image.jl")
include("widgets/box.jl")
