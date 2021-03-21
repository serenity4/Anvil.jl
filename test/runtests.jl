using Givre
using XCB
using Test

function main()
    app = Application()

    send = XCB.send(app.wm, first(app.wm.windows))

    if ENV["DISPLAY"] == ":99" # running on xvfb
        task = run(app.wm, Asynchronous(); warn_unknown=true)
        send(key_event_from_name(app.wm.keymap, :AC04, KeyModifierState(), KeyPressed()))
        @info "- Waiting for window to close"
        wait(task)
    else
        run(app.wm, Synchronous(); warn_unknown=true, poll=false)
    end
end

@testset "Givre.jl" begin
    main()
end
