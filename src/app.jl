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
    app_state = ApplicationState()

    if render
        rdr = BasicRenderer(["VK_KHR_surface", "VK_KHR_xcb_surface"], PhysicalDeviceFeatures(:sampler_anisotropy), ["VK_KHR_swapchain", "VK_KHR_synchronization2"], wh)
        attachment = AttachmentDescription(
            FORMAT_R16G16B16A16_SFLOAT,
            SAMPLE_COUNT_1_BIT,
            ATTACHMENT_LOAD_OP_CLEAR,
            ATTACHMENT_STORE_OP_STORE,
            ATTACHMENT_LOAD_OP_DONT_CARE,
            ATTACHMENT_STORE_OP_DONT_CARE,
            IMAGE_LAYOUT_UNDEFINED,
            IMAGE_LAYOUT_PRESENT_SRC_KHR,
        )
        state = render_state(rdr, attachment)
        initialize!(rdr, app_state, attachment)
    else
        rdr = nothing
    end

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
