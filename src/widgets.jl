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

vertex_data_type(w::Widget) = vertex_data_type(typeof(w))
mesh_encoding_type(w::Widget) = mesh_encoding_type(typeof(w))
nvertices(T::Type{<:Widget}) = not_implemented_for(T)
nvertices(w::Widget) = nvertices(typeof(w))
resource_types(w::Widget) = resource_types(typeof(w))
push_data(w::Widget) = nothing

indices(encoding::IndexEncoding) = convert(Vector{UInt32}, collect(encoding.indices))

function indices(encoding::IndexList)
    class = GeometryExperiments.topology_class(typeof(encoding))
    n = GeometryExperiments.parametric_dimension(class)
    convert(Vector{Point{n,UInt32}}, encoding.indices)
end

function Rhyolite.ShaderDependencies(w::Widget)
    mesh = MeshVertexEncoding(w)
    ShaderDependencies(mesh.vertex_data, indices(mesh.encoding), [])
end

include("widgets/image.jl")
include("widgets/box.jl")
include("widgets/text.jl")
