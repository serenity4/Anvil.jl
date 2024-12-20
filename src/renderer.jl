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

print_framecount(fd::FrameDiagnostics) = print(string("Frame: ", rpad(fd.count, 5), " (", rpad(fd.elapsed_ms, 4), " ms)            \r"))

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
    filter_validation_message("VUID-VkImageViewCreateInfo-usage-02275")
    instance, device = Lava.init(; debug = !release, with_validation = !release, instance_extensions = ["VK_KHR_xcb_surface"], device_specific_features = [:sample_rate_shading])
    color = new_color_attachment(device, window)
    new(instance, device, FrameCycle(device, Surface(instance, window); n = 2), color, ExecutionState[], ProgramCache(device), FrameDiagnostics())
  end
end

function filter_validation_message(name)
  ignores = get(ENV, "VK_LAYER_MESSAGE_ID_FILTER", "")
  contains(ignores, name) && return
  value = isempty(ignores) ? name : "$name,$ignores"
  ENV["VK_LAYER_MESSAGE_ID_FILTER"] = value
end

new_color_attachment(device::Device, window::Window) = attachment_resource(device, nothing; format = RGBA{Float16}, dims = collect(Int64, extent(window)), usage_flags = Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT, samples = 8, name = :color)

function start(renderer::Renderer; period = 0.000)
  options = SpawnOptions(start_threadid = RENDERER_THREADID, disallow_task_migration = true, execution_mode = LoopExecution(period))
  renderer.task = spawn(() -> render(app, renderer), options)
end

function Lava.render(app, rdr::Renderer)
  state = cycle!(rdr.frame_cycle) do frame
    if collect(Int, extent(app.window)) ≠ dimensions(rdr.color.attachment)
      rdr.color = new_color_attachment(rdr.device, app.window)
    end
    ret = tryfetch(CooperativeTasks.execute(() -> frame_nodes(rdr.color), task_owner()))
    iserror(ret) && shutdown_scheduled() && return nothing
    nodes = unwrap(ret)::Vector{RenderNode}
    draw_and_prepare_for_presentation(rdr.device, nodes, rdr.color, frame)
  end
  !isnothing(state) && push!(rdr.pending, state)
  filter!(exec -> !wait(exec, 0), rdr.pending)
  next!(rdr.frame_diagnostics)
  get(ENV, "ANVIL_LOG_FRAMECOUNT", "true") == "true" && print_framecount(rdr.frame_diagnostics)
  nothing
end
