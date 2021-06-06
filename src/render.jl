function Render.command_buffers(rdr::BasicRenderer, frame::FrameState, app::Application)
    command_buffer, _... = unwrap(
        allocate_command_buffers(rdr.device, CommandBufferAllocateInfo(rdr.gpu.command_pools[:primary], COMMAND_BUFFER_LEVEL_PRIMARY, 1)),
    )
    @record command_buffer begin
        cmd_bind_vertex_buffers([rdr.gpu.buffers[:vertex].resource], [0])
        cmd_bind_descriptor_sets(PIPELINE_BIND_POINT_GRAPHICS, rdr.gpu.pipelines[:perlin].info.layout, 0, [rdr.gpu.descriptor_sets[:perlin_sampler]], Int[])
        cmd_bind_pipeline(PIPELINE_BIND_POINT_GRAPHICS, rdr.gpu.pipelines[:perlin].resource)
        cmd_begin_render_pass(
            RenderPassBeginInfo(
                frame.ws.render_pass,
                frame.ws.fbs[frame.img_idx],
                Rect2D(Offset2D(0, 0), Extent2D(extent(app.wm.windows[1])...)),
                [vk.VkClearValue(vk.VkClearColorValue((0.05, 0.01, 0.1, 0.1)))]
            ),
            SUBPASS_CONTENTS_INLINE
        )
        cmd_draw(4, 1, 0, 0)
        cmd_end_render_pass()
    end
    [command_buffer]
end

function create_pipeline(rdr::BasicRenderer, rstate::RenderState, app::Application)
    @unpack device = rdr

    # build graphics pipeline
    shaders = [rdr.shaders[:vert], rdr.shaders[:frag]]
    shader_stage_cis = PipelineShaderStageCreateInfo.(shaders)
    vertex_input_state = PipelineVertexInputStateCreateInfo(
        [VertexInputBindingDescription(PosUV{Point2f,Point2f}, 0)],
        VertexInputAttributeDescription(PosUV{Point2f,Point2f}, 0),
    )
    input_assembly_state = PipelineInputAssemblyStateCreateInfo(PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, false)
    viewport_state = PipelineViewportStateCreateInfo(
        viewports = [Viewport(0, 0, extent(app.wm.windows[1])..., 0, 1)],
        scissors = [Rect2D(Offset2D(0, 0), Extent2D(extent(app.wm.windows[1])...))],
    )
    rasterizer = PipelineRasterizationStateCreateInfo(
        false,
        false,
        POLYGON_MODE_FILL,
        FRONT_FACE_CLOCKWISE,
        false,
        0.0,
        0.0,
        0.0,
        1.0,
        cull_mode = CULL_MODE_BACK_BIT,
    )
    multisample_state = PipelineMultisampleStateCreateInfo(SAMPLE_COUNT_1_BIT, false, 1.0, false, false)
    color_blend_attachment = PipelineColorBlendAttachmentState(
        true,
        BLEND_FACTOR_SRC_ALPHA,
        BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        BLEND_OP_ADD,
        BLEND_FACTOR_SRC_ALPHA,
        BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        BLEND_OP_ADD;
        color_write_mask = COLOR_COMPONENT_R_BIT | COLOR_COMPONENT_G_BIT | COLOR_COMPONENT_B_BIT,
    )
    color_blend_state = PipelineColorBlendStateCreateInfo(
        false,
        LOGIC_OP_CLEAR,
        [color_blend_attachment],
        Float32.((0.0, 0.0, 0.0, 0.0)),
    )
    pipeline_layout = PipelineLayout(device, [rdr.gpu.descriptor_set_layouts[:perlin_sampler]], [])
    info = GraphicsPipelineCreateInfo(
        shader_stage_cis,
        rasterizer,
        pipeline_layout,
        rstate.render_pass,
        0,
        0;
        vertex_input_state,
        multisample_state,
        color_blend_state,
        input_assembly_state,
        viewport_state,
    )
    (pipeline, _...), _ = unwrap(
        create_graphics_pipelines(
            device,
            [
                info,
            ],
        ),
    )
    GPUResource(pipeline, nothing, info)
end
