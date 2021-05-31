using ColorTypes
using FileIO
using Meshes

function render_texture(r::BasicRenderer, points, texture; width = 1000, height = 1000, uv_coords = nothing)
    device = r.device
    queue = r.queue

    props = get_physical_device_properties(device.physical_device)

    uv_coords = something(uv_coords, [Point2f((1 .+ coordinates(p)) / 2) for p ∈ points])
    VertexType = PosUV{eltype(points),eltype(uv_coords)}
    format = FORMAT_R16G16B16A16_SFLOAT

    # prepare vertex and index data
    p = PolyArea(Meshes.CircularVector(points))
    mesh = discretize(p, FIST())
    vdata = VertexType.(points, uv_coords)

    # prepare shaders
    vert_shader = Shader(device, ShaderFile(joinpath(@__DIR__, "texture_2d.vert"), FormatGLSL()), DescriptorBinding[])
    frag_shader = Shader(
        device,
        ShaderFile(joinpath(@__DIR__, "texture_2d.frag"), FormatGLSL()),
        [DescriptorBinding(DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 0, 1)],
    )
    shaders = [vert_shader, frag_shader]
    dset_layouts = create_descriptor_set_layouts(shaders)

    # build graphics pipeline
    shader_stage_cis = PipelineShaderStageCreateInfo.(shaders)
    vertex_input_state = PipelineVertexInputStateCreateInfo(
        [VertexInputBindingDescription(eltype(vdata), 0)],
        VertexInputAttributeDescription(eltype(vdata), 0),
    )
    input_assembly_state = PipelineInputAssemblyStateCreateInfo(PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, false)
    viewport_state = PipelineViewportStateCreateInfo(
        viewports = [Viewport(0, 0, width, height, 0, 1)],
        scissors = [Rect2D(Offset2D(0, 0), Extent2D(width, height))],
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

    command_buffer, _... = unwrap(
        allocate_command_buffers(device, CommandBufferAllocateInfo(command_pool, COMMAND_BUFFER_LEVEL_PRIMARY, 1)),
    )

    begin_command_buffer(command_buffer, CommandBufferBeginInfo())
    cmd_bind_vertex_buffers(command_buffer, [vbuffer], [0])
    cmd_bind_descriptor_sets(command_buffer, PIPELINE_BIND_POINT_GRAPHICS, pipeline_layout, 0, dsets, [])
    cmd_bind_pipeline(command_buffer, PIPELINE_BIND_POINT_GRAPHICS, pipeline)
    cmd_begin_render_pass(
        command_buffer,
        RenderPassBeginInfo(
            render_pass,
            framebuffer,
            Rect2D(Offset2D(0, 0), Extent2D(width, height)),
            [vk.VkClearValue(vk.VkClearColorValue((0.1f0, 0.1f0, 0.15f0, 1.0f0)))],
        ),
        SUBPASS_CONTENTS_INLINE,
    )
    cmd_draw(command_buffer, 4, 1, 0, 0)
    cmd_end_render_pass(command_buffer)
    end_command_buffer(command_buffer)

    GC.@preserve tbuffer tmemory timage timage_memory cbuffer unwrap(wait_for_fences(device, [tuploaded], true, 0))
    unwrap(queue_submit(queue, [SubmitInfo([], [], [command_buffer], [])]))
    GC.@preserve vbuffer vmemory timage timage_view timage_memory descriptor_pool command_pool command_buffer dsets unwrap(
        queue_wait_idle(queue),
    )

    # map image into a Julia array
    image = download_data(Vector{RGBA{Float16}}, local_image_memory, (width, height))

    save(output_png, image)

    image
end

# main(
#     joinpath(@__DIR__, "render.png"),
#     Point2f[(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)],
#     joinpath(@__DIR__, "texture_2d.png"),
#     width = 2048,
#     height = 2048,
# )
