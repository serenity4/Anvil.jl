mutable struct ApplicationState

end

struct Application{WH<:AbstractWindowHandler}
    """
    Window manager. Only XCB is supported for now.
    """
    wm::WH
    widgets::Vector{<:Widget}
    state::ApplicationState
end

Application(wm::AbstractWindowHandler) = Application(wm, Widget[])

function Base.run(app::Application, mode::ExecutionMode = Synchronous())#, r::Renderer)
    run(app.wm, mode)#; on_iter_last = () -> execute_draws(r))
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

function Application()
    connection = Connection()
    setup = Setup(connection)
    iter = XCB.xcb_setup_roots_iterator(setup)
    screen = unsafe_load(iter.data)

    win = XCBWindow(connection, screen; x=0, y=1000, border_width=50, window_title="Givre", icon_title="Givre", attributes=[XCB.XCB_CW_BACK_PIXEL], values=[screen.black_pixel])

    wh = XWindowHandler(connection, [win])

    app_state = ApplicationState()

    function on_key_pressed(wh::XWindowHandler, details::EventDetails)
        @unpack win, data = details
        @info keystroke_info(wh.keymap, details)
        @unpack key, modifiers = data
        kc = KeyCombination(key, modifiers)
        if haskey(key_mappings, kc)
            key_mappings[kc](details, app_state)
        end
    end

    set_callbacks!(wh, win, WindowCallbacks(;
        on_key_pressed = x -> on_key_pressed(wh, x),
    ))

    Application(wh, Widget[], app_state)
end
