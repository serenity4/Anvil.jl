module Render

using Vulkan
using VulkanShaders
using UnPack
using ColorTypes
using Meshes
using MLStyle
using XCB

include("init.jl")
include("memory.jl")
include("vertex.jl")
include("renderer.jl")
include("frames.jl")
include("texture.jl")

const debug_callback_c = Ref{Ptr{Cvoid}}(C_NULL)
const debug_messenger = Ref{DebugUtilsMessengerEXT}()

function __init__()
    # for debugging in Vulkan
    debug_callback_c[] = @cfunction(
        default_debug_callback,
        UInt32,
        (
            DebugUtilsMessageSeverityFlagEXT,
            DebugUtilsMessageTypeFlagEXT,
            Ptr{vk.VkDebugUtilsMessengerCallbackDataEXT},
            Ptr{Cvoid},
        )
    )
end

export
    AbstractRenderer,
    BasicRenderer

end # module
