mutable struct FrameDiagnostics
  t0::Float64
  tref::Float64
  elapsed_ms::Int
  count::Int
end
FrameDiagnostics() = FrameDiagnostics(time(), time(), 0, 0)

function next!(fd::FrameDiagnostics)
  fd.count += 1
  tref = time()
  elapsed_ms = round(Int, (tref - fd.tref) * 1000)
  fd.elapsed_ms = elapsed_ms
  fd.tref = tref
  fd
end

mutable struct Renderer
  instance::Lava.Instance
  device::Device
  frame_cycle::FrameCycle{Window}
  color::Resource
  pending::Vector{ExecutionState}
  program_cache::ProgramCache
  frame_diagnostics::FrameDiagnostics
  task::Task
  function Renderer(window::Window; release = get(ENV, "GIVRE_RELEASE", "false") == "true")
    instance, device = Lava.init(; debug = !release, with_validation = !release, instance_extensions = ["VK_KHR_xcb_surface"])
    color = attachment_resource(device, zeros(RGBA{Float16}, extent(window)); usage_flags = Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT)
    new(instance, device, FrameCycle(device, Surface(instance, window)), color, ExecutionState[], ProgramCache(device), FrameDiagnostics())
  end
end

function Lava.render(givre, rdr::Renderer)
  next = acquire_next_image(rdr.frame_cycle)
  if next === Vk.ERROR_OUT_OF_DATE_KHR
    recreate!(rdr.frame_cycle)
    render(givre, rdr)
  else
    isa(next, Int) || error("Could not acquire an image from the swapchain (returned $next)")
    (; color) = rdr
    fetched = tryfetch(execute(() -> frame_nodes(givre, color), task_owner()))
    iserror(fetched) && shutdown_scheduled() && return
    nodes = unwrap(fetched)::Vector{RenderNode}
    state = cycle!(image -> draw_and_prepare_for_presentation(rdr.device, nodes, color, image), rdr.frame_cycle, next)
    next!(rdr.frame_diagnostics)
    get(ENV, "GIVRE_LOG_FRAMECOUNT", "true") == "true" && print_framecount(rdr.frame_diagnostics)
    filter!(exec -> !wait(exec, 0), rdr.pending)
    push!(rdr.pending, state)
  end
end

print_framecount(fd::FrameDiagnostics) = print("Frame: ", rpad(fd.count, 5), " (", rpad(fd.elapsed_ms, 4), " ms)            \r")
