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
using Graphs
using Entities
using MLStyle
using Dictionaries
using ForwardMethods: @forward_methods
using FileIO

using Reexport
@reexport using ColorTypes
@reexport using FixedPointNumbers: N0f8
@reexport using CooperativeTasks: CooperativeTasks, nthreads, fetch, tryfetch, spawn, SpawnOptions, LoopExecution, monitor_owned_tasks, shutdown_owned_tasks, schedule_shutdown, shutdown_scheduled, task_owner
@reexport using OpenType: Tag4, @tag_str, @tag4_str
@reexport using Accessors: @set, setproperties, @reset
using XCB
@reexport using AbstractGUI
using AbstractGUI: events, actions
import AbstractGUI: overlay!, unoverlay!
@reexport using StaticArrays: @SVector, SVector

using Base: Callable, annotate!, annotations
using .Meta: isexpr
@reexport using StyledStrings
using StyledStrings: AnnotatedString, annotatedstring, eachregion, Face, addface!
using StyledStrings.StyledMarkup: annotatedstring_optimize!
using InteractiveUtils: subtypes
using TOML

const Window = XCBWindow
const WindowManager = XWindowManager

import GeometryExperiments: boundingelement
import Entities: new!

const Optional{T} = Union{T,Nothing}
const Box2 = Box{2,Float64}
const P2 = Point2
const P2f = Point2f
const WidgetID = EntityID

include("renderer.jl")
include("geometry.jl")
include("components.jl")
include("modules/Layout.jl")
@reexport using .Layout
using .Layout: Direction
import .Layout: positional_feature
const Group = Layout.Group{EntityID}
include("layout.jl")
include("bindings.jl")
include("interaction_set.jl")
include("widgets.jl")
include("systems.jl")
include("assets.jl")
include("observables.jl")
include("application.jl")
include("theme.jl")

const app = Application()
const WINDOW_ENTITY_COUNTER = Entities.Counter()

global APPLICATION_DIRECTORY::String
global ASSET_DIRECTORY::String

@compile_traces "precompilation_traces.jl"

function __init__()
  addface!(:application_shortcut_show => Face(underline = true))
  addface!(:application_shortcut_hide => Face(underline = false))
  global APPLICATION_DIRECTORY = dirname(@__DIR__)
  global ASSET_DIRECTORY = joinpath(dirname(@__DIR__), "assets")
end

@reexport using XCB

export
       app, Application,
       APPLICATION_DIRECTORY,
       ASSET_DIRECTORY,
       save_events, replay_events,
       execute, @execute,

       # Components.
       RenderComponent, LocationComponent,
       GeometryComponent, GeometryType, GEOMETRY_TYPE_RECTANGLE, GEOMETRY_TYPE_FILLED_CIRCLE, FilledCircle,
       ZCoordinateComponent,
       ENTITY_COMPONENT_ID, RENDER_COMPONENT_ID, LOCATION_COMPONENT_ID, GEOMETRY_COMPONENT_ID, ZCOORDINATE_COMPONENT_ID, WIDGET_COMPONENT_ID, WINDOW_COMPONENT_ID,

       RenderObjectType, RENDER_OBJECT_RECTANGLE, RENDER_OBJECT_IMAGE, RENDER_OBJECT_TEXT,
       ImageModeStretched, ImageModeTiled, ImageModeCropped, ImageParameters,

       window_geometry,

       # Widgets.
       Widget, disable!, enable!,
       Rectangle, ImageVisual, RectangleVisual,
       Text, Button, Checkbox,
       MenuItem, Menu, collapse!, expand!, close!, constituents, add_menu_item!, add_menu_items!,
       line_center,

       # Interaction sets.
       InteractionSet, wipe!, use_interaction_set, current_interaction_set,

       # Application state.
       get_entity, get_location, get_geometry, get_z, get_render, get_widget, set_widget, unset_widget, get_window,
       set_location, set_geometry, set_z, has_z, set_render, has_render, unset_render, set_widget, set_window,
       overlay, unoverlay,
       add_callback, remove_callback,

       bind, unbind, KeyBindingsToken,

       font_file, get_font,
       texture_file, get_texture,

       is_left_click,

       place, place_after, align, distribute, pin, at, width, height, remove_layout_operations, put_behind, put_in_front, synchronize,

       is_release, @set_name, EntityID, new_entity, @get_widget,
       observe!, unobserve!, @observable, @bind,
       P2, P2f, Box

end
