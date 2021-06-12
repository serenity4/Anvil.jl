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
    widgets::Vector{<:Widget}
    state::ApplicationState
end

"""
Should I put widgets in some global state? What would it be then, a vector, dict?
Also, it won't be very efficient, since all widgets will basically have a different type...
"""
function recreate_widgets!(rdr::BasicRenderer, app::Application)
    empty!(app.widgets)
    img = ImageWidget(app.state.position, (512, 512), (1., 1.), WidgetCallbacks(on_pointer_move = (ed::EventDetails) -> begin
        if ed.data.state.left
            app.state.position = Point(ed.location)
        end
    end))
    if !haskey(rdr.gpu.buffers, :vertex)
        rdr.gpu.buffers[:vertex] = vertex_buffer(img, rdr)
    else
        upload_data(rdr.gpu.buffers[:vertex].memory, vertex_data(img))
    end
    push!(app.widgets, img)
end

function Base.run(app::Application, mode::ExecutionMode = Synchronous(); render=true)
    if render
        rdr = BasicRenderer(["VK_KHR_surface", "VK_KHR_xcb_surface"], PhysicalDeviceFeatures(:sampler_anisotropy), ["VK_KHR_swapchain", "VK_KHR_synchronization2"], app.wm)
        rstate = render_state(rdr)
        initialize!(rdr, app)
        rdr.gpu.pipelines[:perlin] = create_pipeline(rdr, rstate, app)
        run(app.wm, mode;
        on_iter_last = () -> begin
                recreate_widgets!(rdr, app)
                if haschanged(app.state)
                    wait_hasrendered(rstate.frame)
                    update_texture_resources!(rdr, app.state)
                    app.state.haschanged = false
                end
                next_frame!(rstate.frame, rdr, app)
            end)
        gpu = app.state.gpu
        GC.@preserve gpu rdr rstate device_wait_idle(rdr.device)
    else
        run(app.wm, mode)
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

    app_state = ApplicationState()
    app = Application(wm, Widget[], app_state)

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
        on_pointer_move = (ed::EventDetails) -> begin
            widget = find_target(app.widgets, ed)
            if !isnothing(widget)
                execute_callback(widget, ed)
            end
        end
    ))

    app
end
