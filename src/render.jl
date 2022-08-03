const COLOR_ATTACHMENT_UUID = UUID("00000000-0000-0000-0000-000000000000")
const COLOR_ATTACHMENT = Lava.LogicalAttachment(COLOR_ATTACHMENT_UUID, Vk.FORMAT_R16G16B16A16_SFLOAT)

program(device::Device, x) = program(device, typeof(x))
instances(x) = 1:1
indexed_draw(x) = DrawIndexed(indices(x), instances(x))
render_state(::DataType) = RenderState()
render_state(x) = render_state(typeof(x))
invocation_state(::DataType) = ProgramInvocationState()
invocation_state(x) = invocation_state(typeof(x))
render_targets(x) = RenderTargets(COLOR_ATTACHMENT)
program_invocation(device, x) = ProgramInvocation(program(device, x), indexed_draw(x), render_targets(x), invocation_data(x), render_state(x), invocation_state(x))

function substitute_color_attachment(node::RenderNode, color::Union{LogicalAttachment,PhysicalAttachment})
  for (i, invocation) in enumerate(node.program_invocations)
    for (j, color_target) in enumerate(invocation.targets.color)
      if Lava.uuid(color_target) === COLOR_ATTACHMENT_UUID
        @reset node.program_invocations[i].targets.color[j] = color
      end
    end
  end
  node
end

"""
Render a component and fetch the array of pixels.
"""
function render_to_array(device::Device, node::RenderNode, dims = nothing)
  if isnothing(dims)
    (; extent) = (node.render_area::RenderArea).rect
    dims = (extent.width, extent.height)
  end
  color = attachment(device; COLOR_ATTACHMENT.format, usage = Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_TRANSFER_DST_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT, dims)
  pcolor = PhysicalAttachment(COLOR_ATTACHMENT_UUID, color)
  graphics = substitute_color_attachment(node, pcolor)
  rg = RenderGraph(device)
  @add_resource_dependencies rg begin
      (pcolor => (0.0, 0.1, 0.1, 1.0))::Color = graphics()
  end
  render(rg)
  collect(RGBA{Float16}, image(view(color)), device)
end

render_to_array(device::Device, invocation::ProgramInvocation; dims = (32, 32)) = render_to_array(device, RenderNode(program_invocations = [invocation], render_area = RenderArea(dims...)))

function load_expr(data, index = nothing)
  Meta.isexpr(data, :(::)) || error("Type annotation required for the loaded element in expression $data")
  address, type = esc.(data.args)
  !isnothing(index) && (type = :(Vector{$type}))
  ex = :(Pointer{$type}($address)[])
  !isnothing(index) && push!(ex.args, esc(index))
  ex
end

macro load(index, data) load_expr(data, index) end
macro load(data) load_expr(data) end
