function Rhyolite.command_buffers(fstate::FrameState, app::Application, render_set::RenderSet)
    command_buffer, _... = unwrap(allocate_command_buffers(device(fstate), _CommandBufferAllocateInfo(CommandPool(app.gr.command_pools), COMMAND_BUFFER_LEVEL_PRIMARY, 1)))

    @record command_buffer begin
        cmd_begin_render_pass(
            RenderPassBeginInfo(
                fstate.render_pass,
                fstate.current_frame[].framebuffer,
                Rect2D(Offset2D(0, 0), Extent2D(extent(main_window(app.wm))...)),
                [ClearValue(ClearColorValue((0.05f0, 0.01f0, 0.1f0, 0.1f0)))],
            ),
            SUBPASS_CONTENTS_INLINE,
        )

        render_set = app.gr.render_set
        prepare!(render_set)
        bind_state = BindState(nothing, nothing, [], nothing, nothing)
        for render_info in render_set.render_infos
            bind_state = bind(command_buffer, BindRequirements(render_info), bind_state)
            draw_args = render_info.draw_args
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

# type piracy.
@nospecialize
Vulkan.PrimitiveTopology(::Type{<:IndexList{Line}}) = PRIMITIVE_TOPOLOGY_LINE_LIST
Vulkan.PrimitiveTopology(::Type{<:Strip{Line}}) = PRIMITIVE_TOPOLOGY_LINE_STRIP
Vulkan.PrimitiveTopology(::Type{<:IndexList{Triangle}}) = PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
Vulkan.PrimitiveTopology(::Type{<:Strip{Triangle}}) = PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP
Vulkan.PrimitiveTopology(::Type{<:Fan{Triangle}}) = PRIMITIVE_TOPOLOGY_TRIANGLE_FAN
@specialize

function Vulkan.GraphicsPipelineCreateInfo(
        device::Created{Device,DeviceCreateInfo},
        render_pass::RenderPass,
        extent,
        shaders::Vector{Shader},
        mesh::Type{MeshVertexEncoding{I,T}},
        pipeline_layout::PipelineLayout,
    ) where {I,T}

    require_feature(device, :sampler_anisotropy)

    shader_stages = PipelineShaderStageCreateInfo.([shaders.vertex, shaders.fragment], shaders.specialization_constants)
    vertex_input_state = PipelineVertexInputStateCreateInfo([VertexInputBindingDescription(T, 0)], vertex_input_attribute_descriptions(T, 0))
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

function setup_swapchain(device::Device, surface::SurfaceKHR)
    surface_formats = unwrap(get_physical_device_surface_formats_khr(device.physical_device, surface))
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
    capabilities = unwrap(get_physical_device_surface_capabilities_khr(device.physical_device, surface))
    swapchain_ci = SwapchainCreateInfoKHR(
        surface,
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
    swapchain = Created(unwrap(create_swapchain_khr(device, swapchain_ci)), swapchain_ci)

    render_pass = RenderPass(
        device,
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
                SUBPASS_EXTERNAL,
                0;
                src_stage_mask = PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                dst_stage_mask = PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                dst_access_mask = ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            ),
        ],
    )

    swapchain, render_pass
end

function Vulkan.GraphicsPipelineCreateInfo(app::Application, widget)
    spec = gr
    layout_info = PipelineLayoutCreateInfo()
    GraphicsPipelineCreateInfo(
        gr.device,
        get(gr.pipeline_layout_cache),
    )
end
