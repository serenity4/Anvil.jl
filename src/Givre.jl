"""
Threading model:
- One *application thread* manages the state of the whole application.
- One *rendering thread* processes and submits rendering commands to the GPU, and is synchronized with the swapchain.

The application thread starts the rendering thread, then monitors it while performing its own work in reaction to window inputs.
For every new frame, the renderer will ask the application to give it a list of `RenderNode`s to execute for this frame.
This list is assumed to be owned by the renderer when returned by the application.

## Environment variables

- `GIVRE_LOG_FRAMECOUNT = "true"`: When set to `true`, log the current frame and related timings in the REPL while executing `main`.
- `GIVRE_RELEASE = "false"`: When set to `true`, the renderer will not use validation layers and will not use debugging utilities.
"""
module Givre

const APPLICATION_THREADID = 2
const RENDERER_THREADID = 3

using CompileTraces
using Lava
using ConcurrencyGraph
using Lava: Command
using ShaderLibrary
using ShaderLibrary: Instance, aspect_ratio
using Accessors: @set, setproperties
using GeometryExperiments
using Accessors
using XCB
using Entities
using Entities: new!
using MLStyle
using AbstractGUI
using AbstractGUI: Input

const Window = XCBWindow
const WindowManager = XWindowManager

import ConcurrencyGraph: shutdown

const Optional{T} = Union{T,Nothing}

include("renderer.jl")
include("components.jl")
include("systems.jl")
include("main.jl")

@compile_traces "precompilation_traces.jl"

export main, reset_mpi_state


end
