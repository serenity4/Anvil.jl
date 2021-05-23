mutable struct FrameState
    device::Device
    swapchain::SwapchainKHR
    frame::Int
    "1-based indexing"
    img_idx::Int
    img_rendered::Vector{Semaphore}
    img_acquired::Vector{Semaphore}
    max_in_flight::Int
end

function FrameState(device::Device, swapchain::SwapchainKHR)
    max_in_flight = length(draw_cbs)
    FrameState(
        device,
        swapchain,
        0,
        1,
        map(x -> Semaphore(device), 1:max_in_flight),
        map(x -> Semaphore(device), 1:max_in_flight),
    )
end

function acquire_next_image!(fs::FrameState)
    fs.frame += 1
    idx, result = unwrap(acquire_next_image_khr(fs.device, fs.swapchain, typemax(UInt64); semaphore=fs.img_acquired[fs.img_idx]))
    @assert result in (VK_SUCCESS, VK_SUBOPTIMAL_KHR) "$result: Could not retrieve next swapchain image"
    fs.img_idx = idx + 1
end

function next_frame!(fs::FrameState, rdr::BasicRenderer)
    acquire_next_image!(fs)
    cbuffs = command_buffers(rdr, fs)

    # submit rendering commands
    img_acquired_info = SemaphoreSubmitInfoKHR(fs.img_acquired[fs.img_idx], 0, 0; stage_mask=PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR)
    img_rendered_info = SemaphoreSubmitInfoKHR(fs.img_rendered[fs.img_idx], 0, 0; stage_mask=PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR)
    render_info = SubmitInfo2KHR([img_acquired_info], cbuffs, [img_rendered_info])
    submit(rdr, [render_info])

    # submit presentation commands
    present_info = PresentInfoKHR([fs.img_rendered[fs.img_idx]], [fs.swapchain], [fs.img_idx - 1])
    present(rdr, present_info)
end
