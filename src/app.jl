mutable struct ApplicationState
    resolution::NTuple{2,Int}
    scale::NTuple{2,Int}
    noise::Matrix{Float64}
    gpu::GPUState
end

ApplicationState(resolution, scale) = ApplicationState(resolution, scale, zeros(resolution...), GPUState())

function ApplicationState()
    app = ApplicationState((512, 512), (4, 4))
    update!(app)
    app
end

update!(app::ApplicationState) = app.noise = perlin(app.resolution, app.scale)

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
        allocate_command_buffers(rdr.device, CommandBufferAllocateInfo(rdr.command_pool, COMMAND_BUFFER_LEVEL_PRIMARY, 1)),
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

function initialize!(rdr::BasicRenderer, app::ApplicationState)
    info = ImageCreateInfo(
        IMAGE_TYPE_2D,
        FORMAT_R16G16B16A16_SFLOAT,
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
    upload!(rdr, app)
end

struct Application{WH<:AbstractWindowHandler}
    """
    Window manager. Only XCB is supported for now.
    """
    wm::WH
    widgets::Vector{<:Widget}
    state::ApplicationState
    rdr::Optional{BasicRenderer}
end

function Base.run(app::Application, mode::ExecutionMode = Synchronous())#, r::Renderer)
    run(app.wm, mode)#; on_iter_last = () -> execute_draws(r))
    gpu = app.state.gpu
    GC.@preserve gpu device_wait_idle(app.rdr.device)
end

function on_button_pressed(details::EventDetails)
    x, y = details.location
    click = details.data.button
    state = details.data.state
    buttons_pressed = pressed_buttons(state)
    printed_state = isempty(buttons_pressed) ? "" : "with $(join(string.(buttons_pressed), ", ")) button$(length(buttons_pressed) > 1 ? "s" : "") held"
    @info "$click at $x, $y $printed_state"
end

const key_mappings = Dict{KeyCombination,Any}(
    key"ctrl+q" => (ev, _) -> throw(CloseWindow(ev.win, "Received closing request from user input")),
)

function Application(; render=true)
    connection = Connection()
    setup = Setup(connection)
    iter = XCB.xcb_setup_roots_iterator(setup)
    screen = unsafe_load(iter.data)

    win = XCBWindow(connection, screen; x=20, y=20, width=1920, height=1080, border_width=50, window_title="Givre", icon_title="Givre", attributes=[XCB.XCB_CW_BACK_PIXEL], values=[screen.black_pixel])

    wh = XWindowHandler(connection, [win])

    rdr = render ? BasicRenderer(["VK_KHR_surface", "VK_KHR_xcb_surface"], PhysicalDeviceFeatures(:sampler_anisotropy), ["VK_KHR_swapchain", "VK_KHR_synchronization2"], wh) : nothing
    app_state = ApplicationState()

    render && initialize!(rdr, app_state)

    function on_key_pressed(details::EventDetails)
        @unpack win, data = details
        @info keystroke_info(wh.keymap, details)
        @unpack key, modifiers = data
        kc = KeyCombination(key, modifiers)
        if haskey(key_mappings, kc)
            key_mappings[kc](details, app_state)
        end
    end

    set_callbacks!(wh, win, WindowCallbacks(;
        on_key_pressed,
    ))

    Application(wh, Widget[], app_state, rdr)
end
