struct Box <: Widget
    center::Point{2,Float64}
    dims::Point{2,Float64}
    color::Point{3,RGB}
end

GeometryExperiments.PointSet(b::Box) = (Translation(b.center) ∘ Scaling(b.dims ./ 2))(PointSet(HyperCube, Point2f))

vertex_data_type(::Type{Box}) = PosColor{Point2f,Point{3,RGB}}

function AbstractGUI.vertex_data(b::Box)
    pos = (Translation(-1., -1.) ∘ inv(Scaling(1920/2, 1080/2)))(PointSet(b))
    collect(vertex_data_type(b).(pos.points, Ref(b.color)))
end

nvertices(::Type{Box}) = 4
