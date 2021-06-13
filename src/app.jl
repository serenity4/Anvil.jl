mutable struct ApplicationState
    resolution::NTuple{2,Int}
    scale::NTuple{2,Int}
    position::Point{2,Int}
    noise::Matrix{Float64}
    gpu::GPUState # mostly for compute shaders
    haschanged::Bool
end

ApplicationState(resolution, scale, position) = ApplicationState(resolution, scale, position, zeros(resolution...), GPUState(), false)

haschanged(app::ApplicationState) = app.haschanged

function ApplicationState(position=(1920/2,1080/2))
    app = ApplicationState((512, 512), (4, 4), position)
    update!(app)
    app
end

struct Application{WM<:AbstractWindowManager,R<:AbstractRenderer}
    state::ApplicationState
    wm::WM
    gui::GUIManager{WM}
    rdr::R
    gr::GUIRenderer
end

main_window(wm::WindowManager) = first(values(wm.impl.windows))

"""
Should I put widgets in some global state? What would it be then, a vector, dict?
Also, it won't be very efficient, since all widgets will basically have a different type...
"""
function add_perlin_image!(app::Application)
    wname = :perlin
    img = ImageWidget(
        app.state.position,
        (512, 512),
        (1., 1.),
    )
    app.gui.widgets[wname] = img

    rdr = app.rdr

    app.gui.callbacks[img] = WidgetCallbacks(
        on_drag = (src_w::ImageWidget, src_ed::EventDetails, _, ed::EventDetails) -> begin
            Δloc = Point(ed.location) - Point(src_ed.location)
            new_img = @set src_w.center = src_w.center + Δloc
            update_vertex_buffer!(rdr.device, rdr.gpu, wname, new_img)
        end,
        on_drop = (src_w::ImageWidget, src_ed::EventDetails, _, dst_ed::EventDetails) -> begin
            Δloc = Point(dst_ed.location) - Point(src_ed.location)
            app.state.position = src_w.center + Δloc
            add_perlin_image!(app)
        end
    )

    update_vertex_buffer!(rdr.device, rdr.gpu, wname, img)
end

render_infos(app::Application) = (RenderInfo(app.gr, wname, w) for (wname, w) in app.gui.widgets)

function Base.run(app::Application, mode::ExecutionMode = Synchronous(); render=true)
    if render
        rdr = app.rdr
        gr = app.gr
        device = rdr.device
        rstate = render_state(rdr)
        add_perlin_image!(app)
        image_info = ImageCreateInfo(
            IMAGE_TYPE_2D,
            FORMAT_R16G16B16A16_SFLOAT,
            Extent3D(app.state.resolution..., 1),
            1,
            1,
            SAMPLE_COUNT_1_BIT,
            IMAGE_TILING_OPTIMAL,
            IMAGE_USAGE_TRANSFER_DST_BIT | IMAGE_USAGE_SAMPLED_BIT,
            SHARING_MODE_EXCLUSIVE,
            [0],
            IMAGE_LAYOUT_UNDEFINED,
        )
        image = unwrap(create_image(device, image_info))
        memory = DeviceMemory(image, MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
        view_info = ImageViewCreateInfo(
            image,
            IMAGE_VIEW_TYPE_2D,
            image_info.format,
            ComponentMapping(fill(COMPONENT_SWIZZLE_IDENTITY, 4)...),
            ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
        )
        view = unwrap(create_image_view(device, view_info))
        add_widget!(
            gr,
            :perlin,
            app.gui.widgets[:perlin],
            ShaderInfo(
                Shader(device, ShaderFile(joinpath(@__DIR__, "shaders", "texture_2d.vert"), FormatGLSL()), DescriptorBinding[]),
                Shader(
                    device,
                    ShaderFile(joinpath(@__DIR__, "shaders", "texture_2d.frag"), FormatGLSL()),
                    [DescriptorBinding(DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 0, 1)],
                ),
            ),
            (
                (resource) -> begin
                    Extent3D(app.state.resolution..., 1) ≠ resource.image.info.extent
                end,
                (resource) -> begin
                    image_info = resource.image.info
                    image_info = @set image_info.extent = Extent3D(app.state.resolution..., 1)
                    image = unwrap(create_image(device, image_info))
                    memory = DeviceMemory(image, MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
                    view_info = resource.view.info
                    view_info = @set view_info.image = image
                    view = unwrap(create_image_view(device, view_info))
                    (SampledImage(
                        GPUResource(image, memory, image_info),
                        GPUResource(view, nothing, view_info),
                        resource.sampler,
                    ),)
                end
            ),
            SampledImage(
                GPUResource(image, memory, image_info),
                GPUResource(view, nothing, view_info),
                Sampler(
                    device,
                    FILTER_LINEAR,
                    FILTER_LINEAR,
                    SAMPLER_MIPMAP_MODE_LINEAR,
                    SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
                    SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
                    SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
                    0,
                    true,
                    get_physical_device_properties(device.physical_device).limits.max_sampler_anisotropy,
                    false,
                    COMPARE_OP_ALWAYS,
                    0,
                    0,
                    BORDER_COLOR_FLOAT_OPAQUE_BLACK,
                    false,
                ),
            )
        )
        transfer_texture!(gr, app.state)
        recreate_pipelines!(gr, app.gui, rstate)
        run(app.gui,
            mode;
            on_iter_last = () -> begin
                frame = rstate.frame
                if needs_resource_update(gr)
                    @timeit to "Update resources" begin
                        wait_hasrendered(frame)
                        update_resources(gr)
                    end
                end
                if haschanged(app.state)
                    @timeit to "Transfer texture" transfer_texture!(gr, app.state)
                    app.state.haschanged = false
                end
                @timeit to "Draw next frame" next_frame!(frame, rdr, app)
            end)
        gpu = app.state.gpu
        GC.@preserve gpu rdr rstate device_wait_idle(rdr.device)
    else
        run(app.gui, mode)
    end
end

function on_button_pressed(details::EventDetails)
    x, y = details.location
    click = details.data.button
    state = details.data.state
    buttons_pressed = pressed_buttons(state)
    printed_state = isempty(buttons_pressed) ? "" : "with $(join(string.(buttons_pressed), ", ")) button$(length(buttons_pressed) > 1 ? "s" : "") held"
    @info "$click at $x, $y $printed_state"
end

function Application()
    app_state = ApplicationState()
    connection = Connection()
    win = XCBWindow(connection; x=20, y=20, width=1920, height=1080, border_width=50, window_title="Givre", icon_title="Givre", attributes=[XCB.XCB_CW_BACK_PIXEL], values=[0])
    wm = XWindowManager(connection, [win])
    wwm = WindowManager(wm)
    gm = GUIManager(wwm)
    rdr = BasicRenderer(["VK_KHR_surface", "VK_KHR_xcb_surface"], PhysicalDeviceFeatures(:sampler_anisotropy), ["VK_KHR_swapchain", "VK_KHR_synchronization2"], main_window(wwm))
    app = Application(app_state, wwm, gm, rdr, GUIRenderer(rdr))

    _update! = app_state -> begin
        update!(app_state)
        app_state.haschanged = true
    end

    key_mappings = Dict{KeyCombination,Any}(
        key"ctrl+q" => (ev, _) -> throw(CloseWindow(ev.win, "Received closing request from user input")),
        key"s" => (_, _) -> begin
            app_state.scale = app_state.scale .+ 2
            _update!(app_state)
        end,
        key"j" => (_, _) -> begin
            app_state.resolution = app_state.resolution .+ 50
            _update!(app_state)
        end,
        key"k" => (_, _) -> begin
            app_state.resolution = app_state.resolution .- 50
            _update!(app_state)
        end,
    )

    function on_key_pressed(details::EventDetails)
        @unpack win, data = details
        @info keystroke_info(wm.keymap, details)
        @unpack key, modifiers = data
        kc = KeyCombination(key, modifiers)
        if haskey(key_mappings, kc)
            key_mappings[kc](details, app_state)
        end
    end

    set_callbacks!(wm, win, WindowCallbacks(;
        on_key_pressed,
        on_key_released = identity,
        on_pointer_move = identity,
        on_mouse_button_pressed = identity,
        on_mouse_button_released = identity,
    ))

    app
end
