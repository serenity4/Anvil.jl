struct RenderComponent
  command::DrawCommand
  program::Program
  state::DrawState
end

program(device::Device, x) = program(device, typeof(x))
instances(renderable) = 1:1
render_state(::DataType) = RenderState()
render_state(x) = render_state(typeof(x))
invocation_state(::DataType) = ProgramInvocationState()
invocation_state(x) = invocation_state(typeof(x))


function RenderComponent(rg::RenderGraph, renderable)
  prog = program(rg.device, renderable)
  data_address = DeviceAddress(allocate_data(rg, prog, program_data(rg, renderable, prog)))
  command = DrawIndexed(0, indices(renderable), instances(renderable))
  state = DrawState(render_state(renderable), invocation_state(renderable), data_address)
  RenderComponent(command, prog, state)
end

function Lava.draw(node::RenderNode, rc::RenderComponent, color_attachment::PhysicalAttachment)
  targets = RenderTargets(color_attachment)
  draw(node, rc.command, rc.program, targets, rc.state)
end

function Diatone.render(node::RenderNode, render_components::Dictionary{UUID,RenderComponent}, color_attachment::PhysicalAttachment)
  for rc in render_components
    render(rec, rc, color_attachment)
  end
end

"""
Render a component and fetch the array of pixels.
"""
function render_to_array(device::Device, x; dims = (32, 32))
  color = attachment(device; format = Vk.FORMAT_R16G16B16A16_SFLOAT, usage = Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_TRANSFER_DST_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT, dims)
  pcolor = PhysicalAttachment(color)
  rg = RenderGraph(device)
  graphics = RenderNode(render_area = RenderArea(dims...))
  @add_resource_dependencies rg begin
      (pcolor => (0.0, 0.1, 0.1, 1.0))::Color = graphics()
  end
  rc = RenderComponent(rg, x)
  draw(graphics, rc, pcolor)
  render(rg)
  collect(RGBA{Float16}, image(view(color)), device)
end

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
