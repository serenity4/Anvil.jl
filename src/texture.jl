abstract type ShaderResource end

struct Texture2D <: ShaderResource end

Meshes.vertices(::Texture2D) = Point2f[(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)]

function AbstractGUI.vertex_data(tex::Texture2D)
    points = vertices(tex)
    uv_coords = [Point2f((1 .+ coordinates(p)) / 2) for p ∈ points]
    PosUV.(points, uv_coords)
end

function index_data(tex::ShaderResource)
    p = PolyArea(Meshes.CircularVector(vertex_data(tex)))
    mesh = discretize(p, FIST())
end

function vertex_buffer(resource::ShaderResource, rdr::BasicRenderer)
    vdata = vertex_data(resource)
    vbuffer = Buffer(rdr.device, buffer_size(vdata), BUFFER_USAGE_VERTEX_BUFFER_BIT, SHARING_MODE_EXCLUSIVE, [0])
    vmemory = DeviceMemory(vbuffer, vdata)
    GPUResource(vbuffer, vmemory)
end
