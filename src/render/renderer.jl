struct Renderer
    device::Device
    queue::DeviceQueueInfo2
    pipelines::Dict{Symbol,Pipeline}
end

submit(r::Renderer, submits::AbstractArray{<:SubmitInfo}, fence::Fence) = queue_submit(get_device_queue_2(r.device, r.queue), submits, fence)

function Renderer()
    device, queue_family = init(; queue_flags = QUEUE_COMPUTE_BIT | QUEUE_GRAPHICS_BIT | QUEUE_TRANSFER_BIT, nqueues = 1)
    Renderer(device, DeviceQueueInfo2(queue_family, 0))
end

function execute_draws(r::Renderer)

end
