module Givre

using Vulkan
using VulkanShaders
using XCB
using MLStyle
using UnPack
using AbstractGUI
using SignedDistanceFunctions
using ColorTypes
using ProceduralNoise
using GeometryExperiments
using Setfield

import AbstractGUI: callbacks, vertex_data

const Point2f = Point{2,Float32}
const Optional{T} = Union{T,Nothing}

include("gpu/GPU.jl")
using .GPU

include("render/Render.jl")
using .Render

include("utils.jl")
include("widgets.jl")
include("app.jl")
include("noise.jl")
include("render.jl")

export
    Application,
    ApplicationState


end
