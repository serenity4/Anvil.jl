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
  instance::Instance
  device::Device
  frame_cycle::FrameCycle{Window}
  color::LogicalAttachment
  pending::Vector{ExecutionState}
  programs::Dict{Symbol,Program} # application-managed, not used internally
  frame_diagnostics::FrameDiagnostics
  task::Task
  function Renderer(window::Window; release = get(ENV, "GIVRE_RELEASE", "false") == "true")
    instance, device = Lava.init(; debug = !release, with_validation = !release, instance_extensions = ["VK_KHR_xcb_surface"])
    programs = compile_programs(device)
    color = LogicalAttachment(RGBA{Float16}, collect(Int, extent(window)))
    new(instance, device, FrameCycle(device, surface(instance, window)), color, ExecutionState[], programs, FrameDiagnostics())
  end
end

function Lava.render(givre, rdr::Renderer)
  next = acquire_next_image(rdr.frame_cycle)
  if next === Vk.ERROR_OUT_OF_DATE_KHR
    recreate!(rdr.frame_cycle)
    render(givre, rdr)
  else
    isa(next, Int) || error("Could not acquire an image from the swapchain (returned $next)")
    color = Resource(rdr.color)
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

function surface(instance, win::XCBWindow)
  handle = unwrap(Vk.create_xcb_surface_khr(instance, Vk.XcbSurfaceCreateInfoKHR(win.conn.h, win.id)))
  Surface(handle, win)
end
