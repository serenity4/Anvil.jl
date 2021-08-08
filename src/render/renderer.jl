abstract type AbstractRenderer end

"""
Basic renderer that can only render 2D textures.
"""
struct BasicRenderer <: AbstractRenderer
    device::Created{Device,DeviceCreateInfo}
    surface::Created{SurfaceKHR}
    queue::DeviceQueueInfo2
end

Vulkan.device(rdr::AbstractRenderer) = rdr.device

function BasicRenderer(instance_extensions, device_features::PhysicalDeviceFeatures, device_extensions, window::AbstractWindow)
    device = init(; instance_extensions, device_extensions, enabled_features = device_features, nqueues = 1)
    surface_ci = SurfaceCreateInfoKHR(window)
    surface = Created(unwrap(create_xcb_surface_khr(device.physical_device.instance, surface_ci)), surface_ci)

    r = BasicRenderer(device, surface, DeviceQueueInfo2(first(device.info.queue_create_infos).queue_family_index, 0))
    can_present(r) || error("Presentation not supported for physical device $physical_device")
    r
end

SurfaceCreateInfoKHR(win::XCBWindow; kwargs...) = XcbSurfaceCreateInfoKHR(win.conn.h, win.id; kwargs...)

submit(r::AbstractRenderer, submits::AbstractArray{<:SubmitInfo2KHR}; fence = C_NULL) =
    queue_submit_2_khr(get_device_queue_2(r.device, r.queue), submits, function_pointer(r.device.handle, "vkQueueSubmit2KHR"); fence)
present(r::AbstractRenderer, present_info) = queue_present_khr(get_device_queue_2(r.device, r.queue), present_info)

function can_present(r::BasicRenderer)
    unwrap(get_physical_device_surface_support_khr(r.device.handle.physical_device, r.queue.queue_index, r.surface))
end
