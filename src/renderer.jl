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

print_framecount(fd::FrameDiagnostics) = print("Frame: ", rpad(fd.count, 5), " (", rpad(fd.elapsed_ms, 4), " ms)            \r")

mutable struct Renderer
  instance::Lava.Instance
  # In case we'd like to provide access to the device outside of the renderer,
  # Vulkan devices are freely usable from multiple threads.
  # Only specific functions require external synchronization, hopefully we don't need those outside of the renderer.
  device::Device
  frame_cycle::FrameCycle{Window}
  color::Resource
  pending::Vector{ExecutionState}
  program_cache::ProgramCache
  frame_diagnostics::FrameDiagnostics
  task::Task
  function Renderer(window::Window; release = is_release())
    instance, device = Lava.init(; debug = !release, with_validation = !release, instance_extensions = ["VK_KHR_xcb_surface"], device_specific_features = [:sample_rate_shading])
    color = color_attachment(device, window)
    new(instance, device, FrameCycle(device, Surface(instance, window); n = 2), color, ExecutionState[], ProgramCache(device), FrameDiagnostics())
  end
end

color_attachment(device::Device, window::Window) = attachment_resource(device, nothing; format = RGBA{Float16}, dims = collect(Int64, extent(window)), usage_flags = Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT, samples = 8, name = :color)

function start(renderer::Renderer)
  options = SpawnOptions(start_threadid = RENDERER_THREADID, allow_task_migration = false, execution_mode = LoopExecution(0.005))
  renderer.task = spawn(() -> render(app, renderer), options)
end

function Lava.render(app, rdr::Renderer)
  state = cycle!(rdr.frame_cycle) do image
    if collect(Int, extent(app.window)) ≠ dimensions(rdr.color.attachment)
      rdr.color = color_attachment(rdr.device, app.window)
    end
    (; color) = rdr
    ret = tryfetch(execute(() -> frame_nodes(color), task_owner()))
    iserror(ret) && shutdown_scheduled() && return draw_and_prepare_for_presentation(rdr.device, RenderNode[], color, image)
    nodes = unwrap(ret)::Vector{RenderNode}
    draw_and_prepare_for_presentation(rdr.device, nodes, color, image)
  end
  !isnothing(state) && push!(rdr.pending, state)
  filter!(exec -> !wait(exec, 0), rdr.pending)
  next!(rdr.frame_diagnostics)
  get(ENV, "ANVIL_LOG_FRAMECOUNT", "true") == "true" && print_framecount(rdr.frame_diagnostics)
  nothing
end
