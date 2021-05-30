mutable struct WindowState
    swapchain::SwapchainKHR
    swapchain_ci::SwapchainCreateInfoKHR
    render_pass::RenderPass
    fb_imgs::Vector{Image}
    fb_views::Vector{ImageView}
    fbs::Vector{Framebuffer}
end

function Vulkan.SurfaceCapabilities2KHR(ws::WindowState)
    unwrap(get_physical_device_surface_capabilities_2_khr(ws.render_pass.device.physical_device, PhysicalDeviceSurfaceInfo2KHR(ws.swapchain.surface)))
end

function update!(ws::WindowState)
    @unpack swapchain, render_pass = ws
    device = render_pass.device

    new_extent = SurfaceCapabilities2KHR(ws).current_extent

    if new_extent ≠ ws.swapchain_ci.image_extent # regenerate swapchain
        ws.swapchain_ci = setproperties(ws.swapchain_ci, old_swapchain=swapchain, image_extent=new_extent)
        swapchain = SwapchainKHR(device, ws.swapchain_ci)
    end

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

    fbs = map(fb_views) do view
        Framebuffer(device, ws.render_pass, [fb_image_view], extent.width, extent.height, 1)
    end

    @pack! ws = swapchain, fb_imgs, fb_views, fbs
end

function WindowState(swapchain::SwapchainKHR, swapchain_ci::SwapchainCreateInfoKHR, render_pass::RenderPass)
    ws = WindowState(swapchain, swapchain_ci, render_pass, [], [], [])
    update!(ws)
end

"""
State necessary to execute draw and presentation commands at every frame.
"""
mutable struct FrameState
    device::Device
    ws::WindowState
    frame::Int
    "1-based indexing"
    img_idx::Int
    img_rendered::Vector{Semaphore}
    img_acquired::Vector{Semaphore}
    max_in_flight::Int
end

function FrameState(device::Device, ws::WindowState)
    max_in_flight = length(draw_cbs)
    FrameState(
        device,
        ws,
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
    swapchain = fs.ws.swapchain
    acquire_next_image!(fs)
    cbuffs = command_buffers(rdr, fs)

    # submit rendering commands
    img_acquired_info = SemaphoreSubmitInfoKHR(fs.img_acquired[fs.img_idx], 0, 0; stage_mask=PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR)
    img_rendered_info = SemaphoreSubmitInfoKHR(fs.img_rendered[fs.img_idx], 0, 0; stage_mask=PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT_KHR)
    render_info = SubmitInfo2KHR([img_acquired_info], cbuffs, [img_rendered_info])
    submit(rdr, [render_info])

    # submit presentation commands
    present_info = PresentInfoKHR([fs.img_rendered[fs.img_idx]], [swapchain], [fs.img_idx - 1])
    if swapchain == fs.ws.swapchain # no window state changes, present the image
        present(rdr, present_info)
    else # start over
        next_frame!(fs, rdr)
    end
end
