struct Rectangle
  location::Point2f
  area::Box{2,Float32}
  color::RGBA{Float32}
end

struct RectangleData
  positions::DeviceAddress
  color::Vec4
end

function rectangle_vert(position, index, data_address)
  data = @load data_address::RectangleData
  pos = @load data.positions[index]::Vec2
  position[] = Vec(pos.x, pos.y, 0F, 1F)
end

function rectangle_frag(out_color, data_address)
  data = @load data_address::RectangleData
  out_color[] = data.color
end

function program(device::Device, ::Type{Rectangle})
  vert = @vertex device rectangle_vert(::Vec4::Output{Position}, ::UInt32::Input{VertexIndex}, ::DeviceAddressBlock::PushConstant)
  frag = @fragment device rectangle_frag(::Vec4::Output, ::DeviceAddressBlock::PushConstant)
  Program(vert, frag)
end

vertices(rect::Rectangle) = [Vec2(p...) for p in PointSet(Translated(rect.area, Translation(rect.location)), Point{2,Float32})]

function Rectangle(bottom_left::Point{2}, top_right::Point{2}, color::RGBA)
  location = centroid(bottom_left, top_right)
  area = Box(Scaling(top_right .- bottom_left ./ 2))
  Rectangle(location, area, color)
end

function draw(rdr::Renderer, rect::Rectangle, color)
  prog = rdr.programs[:rectangle]
  (; r, g, b, alpha) = rect.color
  data = @invocation_data prog begin
    b1 = @block vertices(rect)
    @block RectangleData(@address(b1), Vec4(r, g, b, alpha))
  end
  graphics_command(
    DrawIndexed(1:4),
    prog,
    data,
    RenderTargets(color),
    RenderState(),
    setproperties(ProgramInvocationState(), (;
      primitive_topology = Vk.PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP,
      triangle_orientation = Vk.FRONT_FACE_COUNTER_CLOCKWISE,
    )),
    @resource_dependencies begin
      @write
      (color => (0.08, 0.05, 0.1, 1.0))::Color
    end
  )
end
