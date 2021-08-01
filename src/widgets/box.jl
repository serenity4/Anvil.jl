struct Box <: Widget
    center::Point{2,Float64}
    dims::Point{2,Float64}
    color::RGB
end

GeometryExperiments.PointSet(b::Box) = (Translation(b.center) ∘ Scaling(b.dims ./ 2))(PointSet(HyperCube, Point2f))

vertex_data_type(::Type{Box}) = PosColor{Point2f,RGB{Float16}}
mesh_encoding_type(T::Type{Box}) = MeshVertexEncoding{TriangleStrip, vertex_data_type(T)}

function GeometryExperiments.MeshVertexEncoding(b::Box)
    pos = (Translation(-1.0, -1.0) ∘ inv(Scaling(1920 / 2, 1080 / 2)))(PointSet(b))
    MeshVertexEncoding(collect(vertex_data_type(b).(pos.points, Ref(b.color))), Triangle)
end

nvertices(::Type{Box}) = 4
resource_types(::Type{Box}) = ()
