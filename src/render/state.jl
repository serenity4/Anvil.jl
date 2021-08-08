struct RenderState{R<:AbstractRenderer}
    render_pass::RenderPass
    window::WindowState
    frame::FrameState
    renderer::R
end

function RenderState(rdr::AbstractRenderer, render_pass::RenderPass, swapchain_ci::SwapchainCreateInfoKHR)
    require_extension(device(rdr), "VK_KHR_swapchain")

    swapchain = unwrap(create_swapchain_khr(render_pass.device, swapchain_ci))
    window = WindowState(swapchain, swapchain_ci, render_pass)
    frame = FrameState(render_pass.device, window)
    RenderState(render_pass, window, frame, rdr)
end
