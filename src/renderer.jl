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
    instance, device = Lava.init(; debug = !release, with_validation = !release, instance_extensions = ["VK_KHR_xcb_surface"])
    color = color_attachment(device, window)
    new(instance, device, FrameCycle(device, Surface(instance, window); n = 2), color, ExecutionState[], ProgramCache(device), FrameDiagnostics())
  end
end

color_attachment(device::Device, window::Window) = attachment_resource(device, zeros(RGBA{Float16}, extent(window)); usage_flags = Vk.IMAGE_USAGE_TRANSFER_SRC_BIT | Vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT)
