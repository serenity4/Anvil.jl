"""
Threading model:
- One *application thread* manages the state of the whole application.
- One *rendering thread* processes and submits rendering commands to the GPU, and is synchronized with the swapchain.

Preferences:
- `RELEASE`: set to `"true"` to remove debug logging and validation layers for the renderer.

The application thread starts the rendering thread, then monitors it while performing its own work in reaction to window inputs.
For every new frame, the renderer will ask the application to give it a list of `RenderNode`s to execute for this frame.
This list is assumed to be owned by the renderer when returned by the application.
"""
module Givre

using Lava
using Accessors: @set, setproperties
using ConcurrencyGraph
using GeometryExperiments
using Accessors
using XCB

const Window = XCBWindow
const WindowManager = XWindowManager

reset_mpi_state() = reset_all()

const Optional{T} = Union{T,Nothing}

include("preferences.jl")

include("inputs.jl")
include("renderer.jl")
include("main.jl")
include("render.jl")
include("rectangle.jl")

export main, reset_mpi_state


end
