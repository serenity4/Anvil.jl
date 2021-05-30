abstract type AbstractRenderer end

"""
Basic renderer that can only render 2D textures.
"""
struct BasicRenderer <: AbstractRenderer
    device::Device
    device_ci::DeviceCreateInfo
    queue::DeviceQueueInfo2
    wh::XWindowHandler
end

require_feature(r, feature) = getproperty(r.device_ci.enabled_features, feature) || error("Feature '$feature' required but not enabled.")
require_extension(r, ext) = string(ext) in r.device_ci.enabled_extension_names || error("Extension '$ext' required but not enabled.")

function BasicRenderer(device_features::PhysicalDeviceFeatures, device_extensions, wh::XWindowHandler)
    device, device_ci = init(;
        device_extensions,
        enabled_features = device_features,
        nqueues = 1
    )
    BasicRenderer(device, device_ci, DeviceQueueInfo2(first(device_ci.queue_create_infos).queue_family, 0), wh)
end

submit(r::AbstractRenderer, submits::AbstractArray{<:SubmitInfo}; fence = C_NULL) = queue_submit_2_khr(get_device_queue_2(r.device, r.queue), submits, fence)
present(r::AbstractRenderer, present_info) = queue_present_khr(get_device_queue_2(r.device, r.queue), present_info)
