struct Rectangle
  location::Point2f
  area::Box{2,Float32}
  color::RGBA{Float32}
end

struct RectangleData
  positions::UInt64
  color::Vec4
end

function rectangle_vert(position, index, data_address)
  data = @load data_address::RectangleData
  pos = @load index data.positions::Vec2
  position[] = Vec(pos.x, pos.y, 0F, 1F)
end

function rectangle_frag(out_color, data_address)
  data = @load data_address::RectangleData
  out_color[] = data.color
end

function program(device::Device, ::Type{Rectangle})
  vert = @vertex device.spirv_features rectangle_vert(::Output{Position}::Vec4, ::Input{VertexIndex}::UInt32, ::PushConstant::DeviceAddress)
  frag = @fragment device.spirv_features rectangle_frag(::Output::Vec4, ::PushConstant::DeviceAddress)

  Program(device, vert, frag)
end

indices(::Rectangle) = [1, 2, 3, 3, 2, 4]
vertices(rect::Rectangle) = [Vec2(p[1], p[2]) for p in PointSet(Translated(rect.area, Translation(rect.location)), Point{2,Float32})]
function program_data(rg::RenderGraph, rect::Rectangle, prog::Program)
  (; r, g, b, alpha) = rect.color
  RectangleData(allocate_data(rg, prog, vertices(rect)), Vec4(r, g, b, alpha))
end

function Rectangle(bottom_left::Point{2}, top_right::Point{2}, color::RGBA)
  location = centroid(bottom_left, top_right)
  area = Box(Scaling(top_right .- bottom_left ./ 2))
  Rectangle(location, area, color)
end

invocation_state(::Type{Rectangle}) = @set ProgramInvocationState().triangle_orientation = Vk.FRONT_FACE_COUNTER_CLOCKWISE
