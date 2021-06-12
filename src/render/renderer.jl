abstract type AbstractRenderer end

"""
Basic renderer that can only render 2D textures.
"""
struct BasicRenderer <: AbstractRenderer
    device::Device
    device_ci::DeviceCreateInfo
    surface::SurfaceKHR
    queue::DeviceQueueInfo2
    gpu::GPUState
    shaders::Dict{Symbol,Shader}
end

require_feature(r, feature) = getproperty(r.device_ci.enabled_features, feature) || error("Feature '$feature' required but not enabled.")
require_extension(r, ext) = string(ext) in r.device_ci.enabled_extension_names || error("Extension '$ext' required but not enabled.")

function BasicRenderer(
        instance_extensions,
        device_features::PhysicalDeviceFeatures,
        device_extensions,
        window::AbstractWindow
    )

    device, device_ci = init(;
        instance_extensions,
        device_extensions,
        enabled_features = device_features,
        nqueues = 1
    )
    surface = unwrap(create_xcb_surface_khr(device.physical_device.instance, SurfaceCreateInfoKHR(window)))

    gpu = GPUState(command_pools = Dict(:primary => CommandPool(device, 0)))
    r = BasicRenderer(device, device_ci, surface, DeviceQueueInfo2(first(device_ci.queue_create_infos).queue_family_index, 0), gpu, Dict())
    can_present(r) || error("Presentation not supported for physical device $physical_device")
    r
end

SurfaceCreateInfoKHR(win::XCBWindow; kwargs...) = XcbSurfaceCreateInfoKHR(win.conn.h, win.id; kwargs...)

submit(r::AbstractRenderer, submits::AbstractArray{<:SubmitInfo2KHR}; fence = C_NULL) = queue_submit_2_khr(get_device_queue_2(r.device, r.queue), submits, function_pointer(r.device, "vkQueueSubmit2KHR"); fence)
present(r::AbstractRenderer, present_info) = queue_present_khr(get_device_queue_2(r.device, r.queue), present_info)

function can_present(r::BasicRenderer)
    unwrap(get_physical_device_surface_support_khr(r.device.physical_device, r.queue.queue_index, r.surface))
end
