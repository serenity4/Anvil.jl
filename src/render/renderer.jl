abstract type AbstractRenderer end

"""
Basic renderer that can only render 2D textures.
"""
struct BasicRenderer <: AbstractRenderer
    device::Device
    queue::DeviceQueueInfo2
    features::PhysicalDeviceFeatures
    extensions::Vector{String}
    wh::XWindowHandler
end

require_feature(r, feature) = getproperty(r.features.vks, feature) || error("Feature '$feature' required but not enabled.")
require_extension(r, ext) = ext in r.extensions || error("Extension '$ext' required but not enabled.")

function BasicRenderer(device_features::PhysicalDeviceFeatures, device_extensions, wh::XWindowHandler)
    device, queue = init(;
        enabled_features = device_features,
        device_extensions,
    )
    BasicRenderer(device, DeviceQueueInfo2(queue_family, 0), device_features, device_extensions, wh)
end

submit(r::AbstractRenderer, submits::AbstractArray{<:SubmitInfo}; fence = C_NULL) = queue_submit_2_khr(get_device_queue_2(r.device, r.queue), submits, fence)
present(r::AbstractRenderer, present_info) = queue_present_khr(get_device_queue_2(r.device, r.queue), present_info)
