module Givre

using Vulkan
using XCB
using MLStyle
using UnPack
using AbstractGUI
using Meshes
using SignedDistanceFunctions
using ColorTypes
using ProceduralNoise

import AbstractGUI: callbacks, vertex_data

const Optional{T} = Union{T,Nothing}

include("gpu/GPU.jl")
using .GPU

include("render/Render.jl")
using .Render

include("utils.jl")
include("widgets.jl")
include("app.jl")

export
    Application,
    ApplicationState


end
