function update!(app::ApplicationState)
    app.noise = @timeit to "Generate noise" perlin(app.resolution, app.scale)
    app.haschanged = true
end

function texture_data(app::ApplicationState)
    noise_data = remap(app.noise, (0.0, 1.0))
    RGBA{Float16}.(noise_data, noise_data, noise_data, 1.0)
end

function create_staging_buffer!(app::ApplicationState, device::Device)
    # initialize local buffer
    info = BufferCreateInfo(buffer_size(app.noise), BUFFER_USAGE_TRANSFER_DST_BIT | BUFFER_USAGE_TRANSFER_SRC_BIT, SHARING_MODE_EXCLUSIVE, [0])
    local_buffer = unwrap(create_buffer(device, info))
    local_memory = DeviceMemory(local_buffer, texture_data(app))
    local_resource = GPUResource(local_buffer, local_memory, info)
    app.gpu.buffers[:staging] = local_resource
end

function transfer_texture!(gr::GUIRenderer, app::ApplicationState)
    rdr = gr.rdr
    # (re)create staging buffer if necessary
    if !haskey(app.gpu.buffers, :staging) || buffer_size(app.noise) ≠ app.gpu.buffers[:staging].info.size
        create_staging_buffer!(app, device(rdr))
    else
        upload_data(memory(app.gpu.buffers[:staging]), texture_data(app))
    end

    # transfer host-visible memory to device-local image
    image = gr.resources[:perlin][1].image.resource
    cbuffer, _... = unwrap(allocate_command_buffers(device(rdr), CommandBufferAllocateInfo(rdr.gpu.command_pools[:primary], COMMAND_BUFFER_LEVEL_PRIMARY, 1)))
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
                    QUEUE_FAMILY_IGNORED,
                    QUEUE_FAMILY_IGNORED,
                    image,
                    ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
                ),
            ],
        )
        cmd_copy_buffer_to_image(
            app.gpu.buffers[:staging].resource,
            image,
            IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            [BufferImageCopy(0, app.resolution..., ImageSubresourceLayers(IMAGE_ASPECT_COLOR_BIT, 0, 0, 1), Offset3D(0, 0, 0), Extent3D(app.resolution..., 1))],
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
                    QUEUE_FAMILY_IGNORED,
                    QUEUE_FAMILY_IGNORED,
                    image,
                    ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
                ),
            ],
        )
    end

    transfer = CommandBufferSubmitInfoKHR(cbuffer, 0)
    submit(rdr, [SubmitInfo2KHR([], [transfer], [])])
end
