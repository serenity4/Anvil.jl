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

struct Application{WM<:AbstractWindowManager}
    """
    Window manager. Only XCB is supported for now.
    """
    wm::WM
    gui::GUIManager
    state::ApplicationState
end

main_window(wm::WindowManager) = first(values(wm.impl.windows))

"""
Should I put widgets in some global state? What would it be then, a vector, dict?
Also, it won't be very efficient, since all widgets will basically have a different type...
"""
function recreate_widgets!(rdr::BasicRenderer, app::Application)
    img = ImageWidget(
        app.state.position,
        (512, 512),
        (1., 1.),
    )
    if !haskey(rdr.gpu.buffers, :vertex)
        rdr.gpu.buffers[:vertex] = vertex_buffer(img, rdr)
    else
        upload_data(rdr.gpu.buffers[:vertex].memory, vertex_data(img))
    end
    app.gui.widgets[:perlin_texture] = img
    app.gui.callbacks[img] = WidgetCallbacks(
        on_drag = (src_w::ImageWidget, src_ed::EventDetails, _, ed::EventDetails) -> begin
            Δloc = Point(ed.location) - Point(src_ed.location)
            new_img = @set src_w.center = src_w.center + Δloc
            upload_data(rdr.gpu.buffers[:vertex].memory, vertex_data(new_img))
        end,
        on_drop = (src_w::ImageWidget, src_ed::EventDetails, _, dst_ed::EventDetails) -> begin
            Δloc = Point(dst_ed.location) - Point(src_ed.location)
            app.state.position = src_w.center + Δloc
            recreate_widgets!(rdr, app)
        end
    )
end

function Base.run(app::Application, mode::ExecutionMode = Synchronous(); render=true)
    if render
        rdr = BasicRenderer(["VK_KHR_surface", "VK_KHR_xcb_surface"], PhysicalDeviceFeatures(:sampler_anisotropy), ["VK_KHR_swapchain", "VK_KHR_synchronization2"], main_window(app.wm))
        rstate = render_state(rdr)
        initialize!(rdr, app)
        rdr.gpu.pipelines[:perlin] = create_pipeline(rdr, rstate, app)
        recreate_widgets!(rdr, app)
        run(app.gui,
            mode;
            on_iter_last = () -> begin
            @timeit to "Update application" if haschanged(app.state)
                    @timeit to "Recreate widgets" recreate_widgets!(rdr, app)
                    @timeit to "Wait render ends" wait_hasrendered(rstate.frame)
                    @timeit to "Update texture resources" update_texture_resources!(rdr, app.state)
                    app.state.haschanged = false
                end
                @timeit to "Draw next frame" next_frame!(rstate.frame, rdr, app)
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
    connection = Connection()
    win = XCBWindow(connection; x=20, y=20, width=1920, height=1080, border_width=50, window_title="Givre", icon_title="Givre", attributes=[XCB.XCB_CW_BACK_PIXEL], values=[0])
    wm = XWindowManager(connection, [win])
    wwm = WindowManager(wm)
    gm = GUIManager(wwm)

    app_state = ApplicationState()
    app = Application(wwm, gm, app_state)

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
