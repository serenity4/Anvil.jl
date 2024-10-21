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
using Lava: Command, Memory, @task
using Lava
using ShaderLibrary
using ShaderLibrary: Instance, aspect_ratio
using OpenType
using GeometryExperiments
using Entities
using MLStyle
using Dictionaries
using ForwardMethods: @forward_methods
using FileIO

using Reexport
@reexport using ColorTypes
@reexport using CooperativeTasks: CooperativeTasks, nthreads, execute, fetch, tryfetch, spawn, SpawnOptions, LoopExecution, reset_mpi_state, monitor_children, shutdown_scheduled, schedule_shutdown, shutdown_children, task_owner
@reexport using OpenType: Tag4, @tag_str, @tag4_str
@reexport using Accessors: @set, setproperties
using XCB
@reexport using AbstractGUI
@reexport using AbstractGUI: Input, consume!, propagate!
@reexport using StaticArrays: @SVector, SVector

using Base: Callable, annotate!, annotations
@reexport using StyledStrings
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
include("assets.jl")
include("application.jl")
include("theme.jl")

const app = Application()
const WINDOW_ENTITY_COUNTER = Entities.Counter()

@compile_traces "precompilation_traces.jl"

const ASSET_DIRECTORY = Ref{String}()

function __init__()
  addface!(:application_shortcut_show => Face(underline = true))
  addface!(:application_shortcut_hide => Face(underline = false))
  ASSET_DIRECTORY[] = joinpath(dirname(@__DIR__), "assets")
end

@reexport using XCB

export
       app, Application,
       ASSET_DIRECTORY,

       # Components.
       RenderComponent, InputComponent, LocationComponent, GeometryComponent, ZCoordinateComponent,
       ENTITY_COMPONENT_ID, RENDER_COMPONENT_ID, INPUT_COMPONENT_ID, LOCATION_COMPONENT_ID, GEOMETRY_COMPONENT_ID, ZCOORDINATE_COMPONENT_ID, WIDGET_COMPONENT_ID, WINDOW_COMPONENT_ID,

       RenderObjectType, RENDER_OBJECT_RECTANGLE, RENDER_OBJECT_IMAGE, RENDER_OBJECT_TEXT,

       # Widgets.
       Rectangle, Image, Text, Button, Checkbox, MenuItem, Menu, collapse!, expand!,
       line_center,

       # Application state.
       get_entity, get_location, get_geometry, get_z, get_render, get_input_handler, get_widget, get_window,
       set_location, set_geometry, set_z, has_z, set_render, has_render, unset_render, set_input_handler, unset_input_handler, set_widget, set_window,

       bind, unbind,

       font_file, get_font,
       texture_file, get_texture,

       is_left_click,

       add_constraint, remove_constraints, put_behind, synchronize,

       is_release, @set_name, EntityID, new_entity,
       P2, P2f, Box

end
