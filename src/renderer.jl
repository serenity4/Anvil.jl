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

struct FrameCycleInfo
  render_graph::RenderGraph
  target::Resource
  frame::Frame
  index::Int
end

mutable struct Renderer
  instance::Lava.Instance
  # In case we'd like to provide access to the device outside of the renderer,
  # Vulkan devices are freely usable from multiple threads.
  # Only specific functions require external synchronization, hopefully we don't need those outside of the renderer.
  device::Device
  frame_cycle::FrameCycle{Window}
  cycles::Vector{FrameCycleInfo}
  program_cache::ProgramCache
  frame_diagnostics::FrameDiagnostics
  lock::ReentrantLock
  task::Task
  function Renderer(window::Window; release = is_release())
    instance, device = Lava.init(; debug = !release, with_validation = !release, instance_extensions = ["VK_KHR_xcb_surface"], device_specific_features = [:sample_rate_shading])
    n = 3
    cycles = Vector{FrameCycleInfo}(undef, n)
    new(instance, device, FrameCycle(device, Surface(instance, window); n), cycles, ProgramCache(device), FrameDiagnostics(), ReentrantLock())
  end
end

@forward_methods Renderer field=:lock Base.lock Base.unlock

remove_validation_message_filters() = ENV["VK_LAYER_MESSAGE_ID_FILTER"] = ""

function filter_validation_message(name)
  ignores = get(ENV, "VK_LAYER_MESSAGE_ID_FILTER", "")
  contains(ignores, name) && return
  value = isempty(ignores) ? name : "$name,$ignores"
  ENV["VK_LAYER_MESSAGE_ID_FILTER"] = value
end

new_color_attachment(device::Device, window::Window) = attachment_resource(device, nothing; format = RGBA{Float16}, dims = collect(Int64, window.extent), usage_flags = Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT | Vk.IMAGE_USAGE_TRANSFER_DST_BIT, samples = RENDER_SAMPLE_COUNT, name = :color)

function start(renderer::Renderer; period = 0.000)
  options = SpawnOptions(start_threadid = RENDERER_THREADID, disallow_task_migration = true, execution_mode = LoopExecution(period))
  renderer.task = spawn(() -> render(renderer), options)
end

function Lava.render(renderer::Renderer)
  (; frame_cycle) = renderer
  cycle!(frame_cycle) do status::FrameCycleStatus
    shutdown_scheduled() && return nothing
    status === FRAME_CYCLE_FIRST_FRAME && return initialize_cycles!(renderer)
    status === FRAME_CYCLE_SWAPCHAIN_RECREATED && return reinitialize_cycles!(renderer)
    @assert status === FRAME_CYCLE_RENDERING_FRAME
    cycle = renderer.cycles[frame_cycle.frame_index]
    Lava.finish!(cycle.render_graph)
    result = tryfetch(CooperativeTasks.execute(() -> synchronize_commands_for_cycle!(cycle), task_owner()))
    iserror(result) && propagate_error_and_shutdown(unwrap_error(result))
    shutdown_scheduled() && return nothing
    render!(cycle.render_graph, cycle.frame)
  end
  next!(renderer.frame_diagnostics)
  get(ENV, "ANVIL_LOG_FRAMECOUNT", "true") == "true" && print_framecount(renderer.frame_diagnostics)
  nothing
end

initialize_cycles!(renderer::Renderer) = reinitialize_cycles!(renderer)

function reinitialize_cycles!(renderer::Renderer)
  (; cycles, frame_cycle, device) = renderer
  (; frames) = frame_cycle
  @assert length(cycles) === length(frames)
  n = length(cycles)
  for i in 1:n
    if isassigned(cycles, i)
      previous = cycles[i]
      Lava.finish!(previous.render_graph)
    end
    frame = frames[i]
    rg = RenderGraph(device)
    target = new_color_attachment(device, app.window)
    initialize_for_presentation!(rg, target, frame)
    info = FrameCycleInfo(rg, target, frame, i)
    cycles[i] = info
  end
  wait_initialize_frames_and_commands!()
end

function wait_initialize_frames_and_commands!()
  result = tryfetch(CooperativeTasks.execute(initialize_frames_and_commands!, task_owner()))
  iserror(result) && propagate_error_and_shutdown(unwrap_error(result))
end

is_task_shutdown(@nospecialize exc::Exception) = isa(exc, TaskException) && exc.code === SHUTDOWN_RECEIVED

function propagate_error_and_shutdown(exc)
  !is_task_shutdown(exc) && propagate_error(exc)
  schedule_shutdown()
end
