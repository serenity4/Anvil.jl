"""
State necessary to execute draw and presentation commands at every frame.
"""
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
    @assert result in (SUCCESS, SUBOPTIMAL_KHR) "$result: Could not retrieve next swapchain image"
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

mutable struct WindowState
    device::Device
    swapchain::SwapchainKHR
    swapchain_ci::SwapchainCreateInfoKHR
    render_pass::RenderPass
    fb_imgs::Vector{Image}
    fb_views::Vector{ImageView}
    fbs::Vector{Framebuffer}
end

function update!(ws::WindowState)
    @unpack device, swapchain = ws
    @unpack surface = ws.swapchain_ci
    @unpack minImageCount, imageFormat, imageColorSpace, imageArrayLayers, imageUsage, imageSharingMode, queueFamilyIndices, preTransform, compositeAlpha, presentMode, clipped, pNext, flags = swapchain.vks

    new_swapchain_ci = SwapchainCreateInfoKHR(surface, minImageCount, imageFormat, imageColorSpace, imageArrayLayers, imageUsage, imageSharingMode)

    fb_imgs = unwrap(get_swapchain_images_khr(device, swapchain))

    fb_views = map(fb_imgs) do img
        ImageView(
            device,
            img,
            IMAGE_VIEW_TYPE_2D,
            ws.format,
            ComponentMapping(fill(COMPONENT_SWIZZLE_IDENTITY, 4)...),
            ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
        )
    end

    InstanceCreateInfo()

    extent = unwrap(get_physical_device_surface_capabilities_2_khr(device.physical_device, PhysicalDeviceSurfaceInfo2KHR(swapchain.surface))).current_extent
    fbs = map(fb_views) do view
        Framebuffer(device, ws.render_pass, [fb_image_view], extent.vks.width, extent.vks.height, 1)
    end

    @pack! ws = fb_imgs, fb_imgs, fbs
end

function WindowState(device::Device, swapchain::SwapchainKHR, render_pass::RenderPass)
    ws = WindowState(device, swapchain, render_pass, [], [], [])
    update!(ws)
end
