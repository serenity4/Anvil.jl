struct ImageWidget <: Widget
    center::Point{2,Float64}
    dims::Point{2,Float64}
    uv_scale::Point{2,Float64}
end

Base.show(io::IO, w::ImageWidget) = print(io, "Image(width=", w.dims[1], ", height=", w.dims[2], ")")

vertex_data_type(::Type{ImageWidget}) = PosUV{Point2f,Point2f}
mesh_encoding_type(T::Type{ImageWidget}) = MeshVertexEncoding{TriangleStrip, vertex_data_type(T)}

function GeometryExperiments.PointSet(img::ImageWidget)
    set = PointSet(HyperCube, Point2f)
    (Translation(img.center) ∘ Scaling(img.dims) ∘ Scaling(1 / 2, 1 / 2))(set)
end

function GeometryExperiments.MeshVertexEncoding(img::ImageWidget)
    pos = (Translation(-1.0, -1.0) ∘ inv(Scaling(1920 / 2, 1080 / 2)))(PointSet(img))
    uv = (Scaling(img.uv_scale) ∘ Scaling(0.5, 0.5) ∘ Translation(1.0, 1.0))(PointSet(HyperCube, Point2f))
    MeshVertexEncoding(collect(vertex_data_type(img).(pos.points, uv.points)), Triangle)
end

nvertices(::Type{ImageWidget}) = 4
resource_types(::Type{ImageWidget}) = (SampledImage,)
