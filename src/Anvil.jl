"""
Threading model:
- One *application thread* manages the state of the whole application.
- One *rendering thread* processes and submits rendering commands to the GPU, and is synchronized with the swapchain.

The application thread starts the rendering thread, then monitors it while performing its own work in reaction to window inputs.
For every new frame, the renderer will ask the application to give it a list of `RenderNode`s to execute for this frame.
This list is assumed to be owned by the renderer when returned by the application.

## Environment variables

- `ANVIL_LOG_FRAMECOUNT = "true"`: When set to `true`, log the current frame and related timings in the REPL while executing `main`.
- `ANVIL_LOG_KEY_PRESS = "false"`: When set to `true`, log all key presses to stdout.
- `ANVIL_RELEASE = "false"`: When set to `true`, the renderer will not use validation layers and will not use debugging utilities.
"""
module Anvil

const APPLICATION_THREADID = 2
const RENDERER_THREADID = 3

using CompileTraces
using ColorTypes
using Lava
using Lava: Command
using CooperativeTasks: CooperativeTasks, nthreads, execute, fetch, tryfetch, spawn, SpawnOptions, LoopExecution, reset_mpi_state, monitor_children, shutdown_scheduled, schedule_shutdown, shutdown_children, task_owner
using ShaderLibrary
using ShaderLibrary: Instance, aspect_ratio
using OpenType
using OpenType: Tag4
using Accessors: @set, setproperties
using GeometryExperiments
using XCB
using Entities
using MLStyle
using AbstractGUI
using AbstractGUI: Input, consume!, propagate!
using Dictionaries
using StaticArrays: @SVector, SVector
using ForwardMethods: @forward_methods

using Base: Callable, annotate!, annotations
using StyledStrings
using StyledStrings: eachregion, Face, addface!
using InteractiveUtils: subtypes

const Window = XCBWindow
const WindowManager = XWindowManager

import GeometryExperiments: boundingelement
import Entities: new!

const Optional{T} = Union{T,Nothing}
const Box2 = Box{2,Float64}
const P2 = Point2
const P2f = Point2f

include("renderer.jl")
include("components.jl")
include("layout.jl")
include("bindings.jl")
include("widgets.jl")
include("systems.jl")
include("application.jl")
include("theme.jl")
include("main.jl")

const app = Application()
const WINDOW_ENTITY_COUNTER = Entities.Counter()

@compile_traces "precompilation_traces.jl"

function __init__()
  addface!(:application_shortcut_show => Face(underline = true))
  addface!(:application_shortcut_hide => Face(underline = false))
end

export main, app,
       RenderComponent,
       InputComponent


end
