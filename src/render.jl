struct RenderComponent
  vertex_data::Vector{UInt8}
  vertex_indices::Vector{UInt32}
  material::Optional{UInt64}
  draw_state::DrawState
  program::Program
end

function Diatone.render(rec::CompactRecord, rc::RenderComponent, color_attachment::PhysicalAttachment)
  !isnothing(rc.material) && set_material(rec, rc.material)
  set_draw_state(rec, rc.draw_state)
  set_program(rec, rc.program)
  draw(rec, rc.vertex_data, rc.indices, color_attachment)
end

function Diatone.render(rec::CompactRecord, render_components::Dictionary{UUID,RenderComponent}, color_attachment::PhysicalAttachment)
  for rc in render_components
    render(rec, rc, color_attachment)
  end
end

"""
Render a component and fetch the array of pixels.
"""
function render_to_array(device::Device, rc::RenderComponent; dims = (32, 32))
  color = attachment(device; format = Vk.FORMAT_R16G16B16A16_SFLOAT, usage = Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_TRANSFER_DST_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT, dims)
  pcolor = PhysicalAttachment(color)
  rg = RenderGraph(device)
  graphics = RenderNode(render_area = RenderArea(dims...)) do rec
    render_on_color_attachment(rec, rg.device, [object], pcolor)
  end
  @add_resource_dependencies rg begin
      (pcolor => (0.0, 0.1, 0.1, 1.0))::Color = graphics()
  end
  render(rg)
  collect(RGBA{Float16}, image(view(color)), device)
end
