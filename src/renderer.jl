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
  function Renderer(window::Window; release = @is_release)
    instance, device = Lava.init(; debug = !release, with_validation = !release, instance_extensions = ["VK_KHR_xcb_surface"])
    programs = compile_programs(device)
    color = LogicalAttachment(RGBA{Float16}, collect(Int, extent(window)))
    new(instance, device, FrameCycle(device, surface(instance, window)), color, ExecutionState[], programs, FrameDiagnostics())
  end
end

function Lava.render(givre, rdr::Renderer)
  ret = acquire_next_image(rdr.frame_cycle)
  if ret === Vk.ERROR_OUT_OF_DATE_KHR
    recreate!(rdr.frame_cycle)
    render(givre, rdr)
  else
    isa(ret, Int) || error("Could not acquire an image from the swapchain (returned $ret)")
    state = cycle!(rdr.frame_cycle, ret) do image
      color = Resource(rdr.color)
      nodes = fetch(execute(() -> frame_nodes(givre, color), task_owner()))::Vector{RenderNode}
      submission = draw_and_prepare_for_presentation(rdr.device, nodes, color, image)
    end
    next!(rdr.frame_diagnostics)
    print("Frame: ", rpad(rdr.frame_diagnostics.count, 5), " (", rpad(rdr.frame_diagnostics.elapsed_ms, 4), " ms)            \r")
    filter!(exec -> !wait(exec, 0), rdr.pending)
    push!(rdr.pending, state)
  end
end

function surface(instance, win::XCBWindow)
  handle = unwrap(Vk.create_xcb_surface_khr(instance, Vk.XcbSurfaceCreateInfoKHR(win.conn.h, win.id)))
  Surface(handle, win)
end
