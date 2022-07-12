struct Rectangle
  area::Box{2,Float32}
  color::NTuple{4,Float32}
end

function rectangle_vert(position, index, dd)
  pos = Pointer{Vector{Vec{2,Float32}}}(dd.vertex_data)[index]
  position[] = Vec(pos.x, pos.y, 0F, 1F)
end

function rectangle_frag(out_color, dd)
  out_color[] = Pointer{Vec{4,Float32}}(dd.material_data)[]
end

function program(::Rectangle, device::Device)
  vert = @vertex device.spirv_features rectangle_vert(::Output{Position}::Vec{4,Float32}, ::Input{VertexIndex}::UInt32, ::PushConstant::DrawData)
  frag = @fragment device.spirv_features rectangle_frag(::Output::Vec{4,Float32}, ::PushConstant::DrawData)

  Program(device, vert, frag)
end

indices(::Rectangle) = [1, 2, 3, 3, 2, 4]
vertices(rect::Rectangle) = PointSet(Translated(rect.area, Translation(rect.location)), Point{2,Float32}).points
material(rect::Rectangle) = rect.color



# draw_state(::Rectangle) = (@set Lava.DrawState().program_state.cull_mode = Vk.CULL_MODE_BACK_BIT)
