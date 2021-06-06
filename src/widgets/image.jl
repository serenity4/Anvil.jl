struct ImageWidget <: Widget
    center::Point{2,Float64}
    dims::Point{2,Float64}
    uv_scale::Point{2,Float64}
end

function GeometryExperiments.PointSet(img::ImageWidget)
    base_points = PointSet(HyperCube, GeometryExperiments.Point{2,Float32})
    loc = (Translation(-1., -1.) ∘ inv(Scaling(1920/2, 1080/2)))(img.center)
    PointSet(map(Translation(loc) ∘ inv(Scaling(1920, 1080)) ∘ Scaling(img.dims), base_points.points))
end

function AbstractGUI.vertex_data(img::ImageWidget)
    pos = PointSet(img).points
    uv = map(Scaling(img.uv_scale) ∘ Scaling(0.5, 0.5) ∘ Translation(1., 1.), PointSet(HyperCube, GeometryExperiments.Point{2,Float32}).points)
    [PosUV{Point2f,Point2f}.(pos, uv)...]
end

function index_data(w::Widget)
    p = PolyArea(Meshes.CircularVector(vertex_data(w)))
    mesh = discretize(p, FIST())
end

function vertex_buffer(w::Widget, rdr::BasicRenderer)
    vdata = vertex_data(w)
    vbuffer = Buffer(rdr.device, buffer_size(vdata), BUFFER_USAGE_VERTEX_BUFFER_BIT, SHARING_MODE_EXCLUSIVE, [0])
    vmemory = DeviceMemory(vbuffer, vdata)
    GPUResource(vbuffer, vmemory)
end
