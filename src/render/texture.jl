using ColorTypes
using FileIO
using Meshes

function render_texture(r::BasicRenderer, points, texture; width = 1000, height = 1000, uv_coords = nothing)
    device = r.device
    queue = r.queue

    require_feature(r, :samplerAnisotropy)
    require_extension(r, "VK_KHR_swapchain")

    props = get_physical_device_properties(device.physical_device)

    uv_coords = something(uv_coords, [Point2f((1 .+ coordinates(p)) / 2) for p ∈ points])
    VertexType = PosUV{eltype(points),eltype(uv_coords)}
    format = VK_FORMAT_R16G16B16A16_SFLOAT

    # define render pass
    target_attachment = AttachmentDescription(
        format,
        SAMPLE_COUNT_1_BIT,
        VK_ATTACHMENT_LOAD_OP_CLEAR,
        VK_ATTACHMENT_STORE_OP_STORE,
        VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        VK_ATTACHMENT_STORE_OP_DONT_CARE,
        VK_IMAGE_LAYOUT_UNDEFINED,
        VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    )
    render_pass = RenderPass(
        device,
        [target_attachment],
        [
            SubpassDescription(
                VK_PIPELINE_BIND_POINT_GRAPHICS,
                [],
                [AttachmentReference(0, VK_IMAGE_LAYOUT_ATTACHMENT_OPTIMAL_KHR)],
                [],
            ),
        ],
        [
            SubpassDependency(
                VK_SUBPASS_EXTERNAL,
                0;
                src_stage_mask = PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                dst_stage_mask = PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                dst_access_mask = ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            ),
        ],
    )

    # create surface for the only window we have
    surface = unwrap(create_xcb_surface_khr(device.physical_device.instance, XcbSurfaceCreateInfoKHR(r.wh.conn, r.wh.windows[1].id)))

    if !unwrap(get_physical_device_surface_support_khr(device.physical_device, queue.vks.queueIndex, surface))
        error("Surface not supported on queue index $(device.queues.present.queue_index) for physical device $physical_device")
    end

    capabilities = unwrap(get_physical_device_surface_capabilities_2_khr(device.physical_device, PhysicalDeviceSurfaceInfo2KHR(surface)))

    swapchain = unwrap(create_swapchain_khr(
        device,
        surface,
        3,
        format,
        VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
        capabilities.current_extent,
        1,
        IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        VK_SHARING_MODE_EXCLUSIVE,
        [],
        capabilities.current_transform,
        COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        VK_PRESENT_MODE_IMMEDIATE_KHR,
        false,
    ))

    fb_images = unwrap(get_swapchain_images_khr(device, swapchain))

    fb_image_views = map(fb_images) do image
        ImageView(
            fb_image.device,
            fb_image,
            VK_IMAGE_VIEW_TYPE_2D,
            format,
            ComponentMapping(fill(VK_COMPONENT_SWIZZLE_IDENTITY, 4)...),
            ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
        )
    end

    #TODO: create render pass and framebuffer only when the swapchain image is acquired
    # https://www.reddit.com/r/vulkan/comments/jtuhmu/synchronizing_frames_in_flight/gcfedfy/
    # WARNING: work in progress, everything below is to be reworked
    framebuffer = Framebuffer(render_pass.device, render_pass, [fb_image_view], width, height, 1)

    # prepare vertex and index data
    p = PolyArea(Meshes.CircularVector(points))
    mesh = discretize(p, FIST())
    vdata = VertexType.(points, uv_coords)

    # prepare vertex buffer
    vbuffer = Buffer(device, buffer_size(vdata), BUFFER_USAGE_VERTEX_BUFFER_BIT, VK_SHARING_MODE_EXCLUSIVE, [0])
    vmemory = DeviceMemory(vbuffer, vdata)

    # prepare shaders
    vert_shader = Shader(device, ShaderFile(joinpath(@__DIR__, "texture_2d.vert"), FormatGLSL()), DescriptorBinding[])
    frag_shader = Shader(
        device,
        ShaderFile(joinpath(@__DIR__, "texture_2d.frag"), FormatGLSL()),
        [DescriptorBinding(VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 0, 1)],
    )
    shaders = [vert_shader, frag_shader]
    dset_layouts = create_descriptor_set_layouts(shaders)

    # build graphics pipeline
    shader_stage_cis = PipelineShaderStageCreateInfo.(shaders)
    vertex_input_state = PipelineVertexInputStateCreateInfo(
        [VertexInputBindingDescription(eltype(vdata), 0)],
        VertexInputAttributeDescription(eltype(vdata), 0),
    )
    input_assembly_state = PipelineInputAssemblyStateCreateInfo(VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, false)
    viewport_state = PipelineViewportStateCreateInfo(
        viewports = [Viewport(0, 0, width, height, 0, 1)],
        scissors = [Rect2D(Offset2D(0, 0), Extent2D(width, height))],
    )
    rasterizer = PipelineRasterizationStateCreateInfo(
        false,
        false,
        VK_POLYGON_MODE_FILL,
        VK_FRONT_FACE_CLOCKWISE,
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
        VK_BLEND_FACTOR_SRC_ALPHA,
        VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        VK_BLEND_OP_ADD,
        VK_BLEND_FACTOR_SRC_ALPHA,
        VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA,
        VK_BLEND_OP_ADD;
        color_write_mask = COLOR_COMPONENT_R_BIT | COLOR_COMPONENT_G_BIT | COLOR_COMPONENT_B_BIT,
    )
    color_blend_state = PipelineColorBlendStateCreateInfo(
        false,
        VK_LOGIC_OP_CLEAR,
        [color_blend_attachment],
        Float32.((0.0, 0.0, 0.0, 0.0)),
    )
    pipeline_layout = PipelineLayout(device, dset_layouts, [])
    (pipeline, _...), _ = unwrap(
        create_graphics_pipelines(
            device,
            [
                GraphicsPipelineCreateInfo(
                    shader_stage_cis,
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
                ),
            ],
        ),
    )

    # load texture into buffer
    tdata = RGBA{Float16}.(load(texture))
    tbuffer = Buffer(
        device,
        buffer_size(tdata),
        BUFFER_USAGE_TRANSFER_DST_BIT | BUFFER_USAGE_TRANSFER_SRC_BIT,
        VK_SHARING_MODE_EXCLUSIVE,
        [0],
    )
    tmemory = DeviceMemory(tbuffer, tdata)

    # create texture image
    timage = Image(
        device,
        VK_IMAGE_TYPE_2D,
        format,
        Extent3D(size(tdata)..., 1),
        1,
        1,
        SAMPLE_COUNT_1_BIT,
        VK_IMAGE_TILING_OPTIMAL,
        IMAGE_USAGE_TRANSFER_DST_BIT | IMAGE_USAGE_SAMPLED_BIT,
        VK_SHARING_MODE_EXCLUSIVE,
        [0],
        VK_IMAGE_LAYOUT_UNDEFINED,
    )
    timage_memory = DeviceMemory(timage, MEMORY_PROPERTY_DEVICE_LOCAL_BIT)

    command_pool = CommandPool(device, 0)

    # upload texture to image
    cbuffer, _... = unwrap(
        allocate_command_buffers(device, CommandBufferAllocateInfo(command_pool, VK_COMMAND_BUFFER_LEVEL_PRIMARY, 1)),
    )
    begin_command_buffer(cbuffer, CommandBufferBeginInfo())
    cmd_pipeline_barrier(
        cbuffer,
        PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        PIPELINE_STAGE_TRANSFER_BIT,
        [],
        [],
        [
            ImageMemoryBarrier(
                AccessFlag(0),
                ACCESS_TRANSFER_WRITE_BIT,
                VK_IMAGE_LAYOUT_UNDEFINED,
                VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                VK_QUEUE_FAMILY_IGNORED,
                VK_QUEUE_FAMILY_IGNORED,
                timage,
                ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
            ),
        ],
    )
    cmd_copy_buffer_to_image(
        cbuffer,
        tbuffer,
        timage,
        VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        [
            BufferImageCopy(
                0,
                size(tdata)...,
                ImageSubresourceLayers(IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
                Offset3D(0, 0, 0),
                Extent3D(size(tdata)..., 1),
            ),
        ],
    )
    cmd_pipeline_barrier(
        cbuffer,
        PIPELINE_STAGE_TRANSFER_BIT,
        PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
        [],
        [],
        [
            ImageMemoryBarrier(
                ACCESS_TRANSFER_WRITE_BIT,
                AccessFlag(0),
                VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                VK_QUEUE_FAMILY_IGNORED,
                VK_QUEUE_FAMILY_IGNORED,
                timage,
                ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
            ),
        ],
    )
    end_command_buffer(cbuffer)

    tuploaded = Fence(device)
    unwrap(queue_submit(queue, [SubmitInfo([], [], [cbuffer], [])]; fence = tuploaded))

    timage_view = ImageView(
        timage.device,
        timage,
        VK_IMAGE_VIEW_TYPE_2D,
        format,
        ComponentMapping(fill(VK_COMPONENT_SWIZZLE_IDENTITY, 4)...),
        ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
    )

    tsampler = Sampler(
        device,
        VK_FILTER_LINEAR,
        VK_FILTER_LINEAR,
        VK_SAMPLER_MIPMAP_MODE_LINEAR,
        VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
        VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
        VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
        0,
        true,
        props.limits.max_sampler_anisotropy,
        false,
        VK_COMPARE_OP_ALWAYS,
        0,
        0,
        VK_BORDER_COLOR_FLOAT_OPAQUE_BLACK,
        false,
    )

    # create local image for transfer
    local_image = Image(
        device,
        VK_IMAGE_TYPE_2D,
        format,
        Extent3D(width, height, 1),
        1,
        1,
        SAMPLE_COUNT_1_BIT,
        VK_IMAGE_TILING_LINEAR,
        IMAGE_USAGE_TRANSFER_DST_BIT,
        VK_SHARING_MODE_EXCLUSIVE,
        [0],
        VK_IMAGE_LAYOUT_UNDEFINED,
    )

    local_image_memory = DeviceMemory(local_image, MEMORY_PROPERTY_HOST_COHERENT_BIT | MEMORY_PROPERTY_HOST_VISIBLE_BIT)

    command_buffer, _... = unwrap(
        allocate_command_buffers(device, CommandBufferAllocateInfo(command_pool, VK_COMMAND_BUFFER_LEVEL_PRIMARY, 1)),
    )

    descriptor_pool = DescriptorPool(device, 1, [DescriptorPoolSize(VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1)])
    dsets = unwrap(allocate_descriptor_sets(device, DescriptorSetAllocateInfo(descriptor_pool, dset_layouts)))
    update_descriptor_sets(
        device,
        [
            WriteDescriptorSet(
                first(dsets),
                1,
                0,
                VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
                [DescriptorImageInfo(tsampler, timage_view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL)],
                [],
                [],
            ),
        ],
        [],
    )

    begin_command_buffer(command_buffer, CommandBufferBeginInfo())
    cmd_bind_vertex_buffers(command_buffer, [vbuffer], [0])
    cmd_bind_descriptor_sets(command_buffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline_layout, 0, dsets, [])
    cmd_bind_pipeline(command_buffer, VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline)
    cmd_pipeline_barrier(
        command_buffer,
        PIPELINE_STAGE_TOP_OF_PIPE_BIT,
        PIPELINE_STAGE_TRANSFER_BIT,
        [],
        [],
        [
            ImageMemoryBarrier(
                AccessFlag(0),
                ACCESS_MEMORY_READ_BIT,
                VK_IMAGE_LAYOUT_UNDEFINED,
                VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                VK_QUEUE_FAMILY_IGNORED,
                VK_QUEUE_FAMILY_IGNORED,
                local_image,
                ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
            ),
        ],
    )
    cmd_begin_render_pass(
        command_buffer,
        RenderPassBeginInfo(
            render_pass,
            framebuffer,
            Rect2D(Offset2D(0, 0), Extent2D(width, height)),
            [vk.VkClearValue(vk.VkClearColorValue((0.1f0, 0.1f0, 0.15f0, 1.0f0)))],
        ),
        VK_SUBPASS_CONTENTS_INLINE,
    )
    cmd_draw(command_buffer, 4, 1, 0, 0)
    cmd_end_render_pass(command_buffer)
    cmd_pipeline_barrier(
        command_buffer,
        PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        PIPELINE_STAGE_TRANSFER_BIT,
        [],
        [],
        [
            ImageMemoryBarrier(
                ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
                ACCESS_MEMORY_READ_BIT,
                VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                VK_QUEUE_FAMILY_IGNORED,
                VK_QUEUE_FAMILY_IGNORED,
                fb_image,
                ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
            ),
        ],
    )
    cmd_copy_image(
        command_buffer,
        fb_image,
        VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        local_image,
        VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        [
            ImageCopy(
                ImageSubresourceLayers(IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
                Offset3D(0, 0, 0),
                ImageSubresourceLayers(IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
                Offset3D(0, 0, 0),
                Extent3D(width, height, 1),
            ),
        ],
    )
    end_command_buffer(command_buffer)

    GC.@preserve tbuffer tmemory timage timage_memory cbuffer unwrap(wait_for_fences(device, [tuploaded], true, 0))
    unwrap(queue_submit(queue, [SubmitInfo([], [], [command_buffer], [])]))
    GC.@preserve vbuffer vmemory timage timage_view timage_memory fb_image fb_image_view fb_image_memory local_image descriptor_pool command_pool command_buffer dsets unwrap(
        queue_wait_idle(queue),
    )

    # map image into a Julia array
    image = download_data(Vector{RGBA{Float16}}, local_image_memory, (width, height))

    save(output_png, image)

    image
end

main(
    joinpath(@__DIR__, "render.png"),
    Point2f[(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)],
    joinpath(@__DIR__, "texture_2d.png"),
    width = 2048,
    height = 2048,
)
