function create_buffer_resource(allocate_buffer, device::Device, vdata)
    resource = allocate_buffer(device, buffer_size(vdata))
    upload_data(resource.memory, vdata)
    resource
end

function allocate_buffer(device::Device, size, usage, memory_properties; sharing_mode = SHARING_MODE_EXCLUSIVE, queue_indices = [0])
    vbuffer = Buffer(device, size, usage, sharing_mode, queue_indices)
    vmemory = DeviceMemory(vbuffer, memory_properties)
    GPUResource(vbuffer, vmemory)
end

allocate_vertex_buffer(device::Device, size) = allocate_buffer(device, size, BUFFER_USAGE_VERTEX_BUFFER_BIT, MEMORY_PROPERTY_HOST_VISIBLE_BIT | MEMORY_PROPERTY_HOST_COHERENT_BIT)
allocate_index_buffer(device::Device, size) = allocate_buffer(device, size, BUFFER_USAGE_INDEX_BUFFER_BIT, MEMORY_PROPERTY_HOST_VISIBLE_BIT | MEMORY_PROPERTY_HOST_COHERENT_BIT)

function update_buffer!(gpu::GPUState, allocate_buffer, device::Device, key::Symbol, data)
    if !haskey(gpu.buffers, key)
        gpu.buffers[key] = create_buffer_resource(allocate_buffer, device, data)
    else
        upload_data(gpu.buffers[key].memory, data)
    end
end

function update_buffers!(gpu::GPUState, device::Device, wname::Symbol, w::Widget)
    vkey = vertex_buffer_symbol(wname)
    ikey = index_buffer_symbol(wname)
    mesh = MeshVertexEncoding(w)

    encoding = mesh.encoding
    indices = if encoding isa IndexList
        class = GeometryExperiments.topology_class(typeof(encoding))
        n = GeometryExperiments.parametric_dimension(class)
        convert(Vector{Point{n,UInt32}}, encoding.indices)
    else
        convert(Vector{UInt32}, collect(encoding.indices))
    end

    update_buffer!(gpu, allocate_vertex_buffer, device, vkey, mesh.vertex_data)
    update_buffer!(gpu, allocate_index_buffer, device, ikey, indices)
end

index_buffer_symbol(wname::Symbol) = Symbol(wname, :_index)
vertex_buffer_symbol(wname::Symbol) = Symbol(wname, :_vertex)
vertex_data_type(w::Widget) = vertex_data_type(typeof(w))
mesh_encoding_type(w::Widget) = mesh_encoding_type(typeof(w))
nvertices(T::Type{<:Widget}) = not_implemented_for(T)
nvertices(w::Widget) = nvertices(typeof(w))
resource_types(w::Widget) = resource_types(typeof(w))

include("widgets/image.jl")
include("widgets/box.jl")
include("widgets/text.jl")
