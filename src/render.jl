function Render.command_buffers(rdr::BasicRenderer, frame::FrameState, app::Application)
    command_buffer, _... = unwrap(allocate_command_buffers(device(rdr), CommandBufferAllocateInfo(rdr.gpu.command_pools[:primary], COMMAND_BUFFER_LEVEL_PRIMARY, 1)))

    @record command_buffer begin
        cmd_begin_render_pass(
            RenderPassBeginInfo(
                frame.ws.render_pass,
                frame.ws.fbs[frame.img_idx],
                Rect2D(Offset2D(0, 0), Extent2D(extent(main_window(app.wm))...)),
                [ClearValue(ClearColorValue((0.05f0, 0.01f0, 0.1f0, 0.1f0)))],
            ),
            SUBPASS_CONTENTS_INLINE,
        )

        bind_state = BindState(nothing, nothing, [], nothing, [])
        for info in render_infos(app)
            bind_state = bind(command_buffer, info.bind_requirements, bind_state)
            @unpack bind_state, draw_args = info
            if !isnothing(bind_state.index_buffer)
                cmd_draw_indexed(draw_args[1:3]..., 0, draw_args[4])
            else
                cmd_draw(draw_args...)
            end
        end

        cmd_end_render_pass()
    end

    [command_buffer]
end

# warning: this is type piracy.
Vulkan.PrimitiveTopology(::Type{<:IndexList{Line}}) = PRIMITIVE_TOPOLOGY_LINE_LIST
Vulkan.PrimitiveTopology(::Type{<:Strip{Line}}) = PRIMITIVE_TOPOLOGY_LINE_STRIP
Vulkan.PrimitiveTopology(::Type{<:IndexList{Triangle}}) = PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
Vulkan.PrimitiveTopology(::Type{<:Strip{Triangle}}) = PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP
Vulkan.PrimitiveTopology(::Type{<:Fan{Triangle}}) = PRIMITIVE_TOPOLOGY_TRIANGLE_FAN

function Vulkan.GraphicsPipelineCreateInfo(device::Device, shaders::ShaderInfo, mesh::Type{MeshVertexEncoding{I,T}}, render_pass::RenderPass, extent, dependencies::ShaderDependencies) where {I,T}
    require_feature(device, :sampler_anisotropy)

    # build graphics pipeline
    shader_stages = PipelineShaderStageCreateInfo.([shaders.vertex, shaders.fragment], shaders.specialization_constants)
    vertex_input_state = PipelineVertexInputStateCreateInfo([VertexInputBindingDescription(T, 0)], VertexInputAttributeDescription(T, 0))
    input_assembly_state = PipelineInputAssemblyStateCreateInfo(PrimitiveTopology(I), false)
    viewport_state = PipelineViewportStateCreateInfo(viewports = [Viewport(0, 0, extent..., 0, 1)], scissors = [Rect2D(Offset2D(0, 0), Extent2D(extent...))])
    rasterizer = PipelineRasterizationStateCreateInfo(false, false, POLYGON_MODE_FILL, FRONT_FACE_CLOCKWISE, false, 0.0, 0.0, 0.0, 1.0, cull_mode = CULL_MODE_BACK_BIT)
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
    color_blend_state = PipelineColorBlendStateCreateInfo(false, LOGIC_OP_CLEAR, [color_blend_attachment], Float32.((0.0, 0.0, 0.0, 0.0)))
    pipeline_layout = PipelineLayout(device(rdr), !isempty(descriptors) ? first(dependencies.descriptor_sets).info.set_layouts : [], shaders.push_ranges)
    GraphicsPipelineCreateInfo(
        shader_stages,
        rasterizer,
        pipeline_layout,
        render_pass,
        0,
        0;
        vertex_input_state,
        multisample_state,
        color_blend_state,
        input_assembly_state,
        viewport_state,
    )
end

function render_state(rdr::BasicRenderer)
    surface_formats = unwrap(get_physical_device_surface_formats_khr(device(rdr).physical_device, rdr.surface))
    format = first(surface_formats)
    attachment = AttachmentDescription(
        format.format,
        SAMPLE_COUNT_1_BIT,
        ATTACHMENT_LOAD_OP_CLEAR,
        ATTACHMENT_STORE_OP_STORE,
        ATTACHMENT_LOAD_OP_DONT_CARE,
        ATTACHMENT_STORE_OP_DONT_CARE,
        IMAGE_LAYOUT_UNDEFINED,
        IMAGE_LAYOUT_PRESENT_SRC_KHR,
    )
    capabilities = unwrap(get_physical_device_surface_capabilities_khr(device(rdr).physical_device, rdr.surface))
    swapchain_ci = SwapchainCreateInfoKHR(
        rdr.surface,
        3,
        format.format,
        format.color_space,
        Extent2D(capabilities.current_extent.vks.width, capabilities.current_extent.vks.height),
        1,
        IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        SHARING_MODE_EXCLUSIVE,
        [],
        capabilities.current_transform,
        COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        PRESENT_MODE_IMMEDIATE_KHR,
        false,
    )

    render_pass = RenderPass(
        device(rdr),
        [attachment],
        [
            SubpassDescription(
                PIPELINE_BIND_POINT_GRAPHICS,
                [],
                [AttachmentReference(0, IMAGE_LAYOUT_ATTACHMENT_OPTIMAL_KHR)],
                [],
            ),
        ],
        [
            SubpassDependency(
                vk.VK_SUBPASS_EXTERNAL,
                0;
                src_stage_mask = PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                dst_stage_mask = PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                dst_access_mask = ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            ),
        ],
    )

    RenderState(rdr, render_pass, swapchain_ci)
end
