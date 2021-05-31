update!(app::ApplicationState) = app.noise = perlin(app.resolution, app.scale)

function initialize!(rdr::BasicRenderer, app::ApplicationState, attachment::AttachmentDescription)
    # quick checks
    require_feature(rdr, :sampler_anisotropy)
    require_extension(rdr, "VK_KHR_swapchain")

    info = ImageCreateInfo(
        IMAGE_TYPE_2D,
        attachment.format,
        Extent3D(app.resolution..., 1),
        1,
        1,
        SAMPLE_COUNT_1_BIT,
        IMAGE_TILING_OPTIMAL,
        IMAGE_USAGE_TRANSFER_DST_BIT | IMAGE_USAGE_SAMPLED_BIT,
        SHARING_MODE_EXCLUSIVE,
        [0],
        IMAGE_LAYOUT_UNDEFINED,
    )
    image = unwrap(create_image(rdr.device, info))
    memory = DeviceMemory(image, MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
    perlin = GPUResource(image, memory, info)
    rdr.gpu.images[:perlin] = perlin
    rdr.gpu.descriptor_pools[:sampler] = DescriptorPool(rdr.device, 1, [DescriptorPoolSize(DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1)])
    rdr.gpu.image_views[:perlin] = ImageView(
        rdr.device,
        image,
        IMAGE_VIEW_TYPE_2D,
        info.format,
        ComponentMapping(fill(COMPONENT_SWIZZLE_IDENTITY, 4)...),
        ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
    )
    props = get_physical_device_properties(rdr.device.physical_device)
    rdr.gpu.samplers[:perlin] = Sampler(
        rdr.device,
        FILTER_LINEAR,
        FILTER_LINEAR,
        SAMPLER_MIPMAP_MODE_LINEAR,
        SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
        SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
        SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
        0,
        true,
        props.limits.max_sampler_anisotropy,
        false,
        COMPARE_OP_ALWAYS,
        0,
        0,
        BORDER_COLOR_FLOAT_OPAQUE_BLACK,
        false,
    )
    initialize_descriptor_sets!(rdr, app)
    upload!(rdr, app)
end

function render_state(rdr::BasicRenderer, attachment::AttachmentDescription)
    SurfaceFormatKHR
    surface_formats = unwrap(get_physical_device_surface_formats_khr(rdr.device.physical_device, rdr.surface))
    format = first(surface_formats)
    capabilities = unwrap(get_physical_device_surface_capabilities_khr(rdr.device.physical_device, rdr.surface))
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
        rdr.device,
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

function initialize_descriptor_sets!(rdr::BasicRenderer, app::ApplicationState)
end

function upload!(rdr::BasicRenderer, app::ApplicationState)
    # create local buffer
    local_buffer = Buffer(
        rdr.device,
        buffer_size(app.noise),
        BUFFER_USAGE_TRANSFER_DST_BIT | BUFFER_USAGE_TRANSFER_SRC_BIT,
        SHARING_MODE_EXCLUSIVE,
        [0],
    )
    noise_data = remap(app.noise, (0., 1.))
    local_data = RGBA{Float16}.(noise_data, noise_data, noise_data, 1.)
    local_memory = DeviceMemory(local_buffer, local_data)
    local_resource = GPUResource(local_buffer, local_memory, nothing)
    app.gpu.buffers[:staging] = local_resource

    # upload
    app.gpu.semaphores[:is_uploaded] = Semaphore(rdr.device)
    image = rdr.gpu.images[:perlin].resource
    cbuffer, _... = unwrap(
        allocate_command_buffers(rdr.device, CommandBufferAllocateInfo(rdr.gpu.command_pools[:primary], COMMAND_BUFFER_LEVEL_PRIMARY, 1)),
    )
    @record cbuffer begin
        # transition layout to transfer destination
        cmd_pipeline_barrier(
            PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            PIPELINE_STAGE_TRANSFER_BIT,
            [],
            [],
            [
                ImageMemoryBarrier(
                    AccessFlag(0),
                    ACCESS_TRANSFER_WRITE_BIT,
                    IMAGE_LAYOUT_UNDEFINED,
                    IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                    vk.VK_QUEUE_FAMILY_IGNORED,
                    vk.VK_QUEUE_FAMILY_IGNORED,
                    image,
                    ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
                ),
            ],
        )
        cmd_copy_buffer_to_image(
            local_buffer,
            image,
            IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            [
                BufferImageCopy(
                    0,
                    app.resolution...,
                    ImageSubresourceLayers(IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
                    Offset3D(0, 0, 0),
                    Extent3D(app.resolution..., 1),
                ),
            ],
        )
        # transition to final layout
        cmd_pipeline_barrier(
            PIPELINE_STAGE_TRANSFER_BIT,
            PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
            [],
            [],
            [
                ImageMemoryBarrier(
                    ACCESS_TRANSFER_WRITE_BIT,
                    AccessFlag(0),
                    IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                    IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                    vk.VK_QUEUE_FAMILY_IGNORED,
                    vk.VK_QUEUE_FAMILY_IGNORED,
                    image,
                    ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
                ),
            ],
        )
    end

    transfer = CommandBufferSubmitInfoKHR(cbuffer, 0)
    upload_signal = SemaphoreSubmitInfoKHR(app.gpu.semaphores[:is_uploaded], 0, 0; stage_mask = PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT_KHR)
    submit(rdr, [SubmitInfo2KHR([], [transfer], [upload_signal])])
    @debug "Noise texture transfer submitted"
end
