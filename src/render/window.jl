function on_resize()

    @unpack device, surface, render_state = app
    @unpack arr_sem_image_available, arr_sem_render_finished, arr_fen_image_drawn, arr_fen_acquire_image, max_simultaneously_drawn_frames = render_state

    device_wait_idle(device)

    recreate_swapchain!(app)
    finalize.(app.framebuffers)
    finalize(app.render_pass)
    free_command_buffers(device, app.command_pools[:a], render_state.arr_command_buffers)
    finalize(render_state)
    prepare_rendering_to_target!(app, Target{SwapchainKHR}())
    recreate_pipeline!(app.pipelines[:main], app)
    command_buffers_info = CommandBufferAllocateInfo(app.command_pools[:a], COMMAND_BUFFER_LEVEL_PRIMARY, length(app.framebuffers))
    command_buffers = CommandBuffer(app.device, command_buffers_info, length(app.framebuffers))
    record_render_pass(app, data, command_buffers)
    initialize_render_state!(app, command_buffers; frame=render_state.frame, max_simultaneously_drawn_frames=render_state.max_simultaneously_drawn_frames)
end
