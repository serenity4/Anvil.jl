module Render

using Vulkan
using VulkanShaders
using UnPack

include("init.jl")
include("memory.jl")
include("renderer.jl")

const debug_callback_c = Ref{Ptr{Cvoid}}(C_NULL)
const debug_messenger = Ref{DebugUtilsMessengerEXT}()

function __init__()
    # for debugging in Vulkan
    debug_callback_c[] = @cfunction(
        default_debug_callback,
        UInt32,
        (
            VkDebugUtilsMessageSeverityFlagBitsEXT,
            VkDebugUtilsMessageTypeFlagBitsEXT,
            Ptr{vk.VkDebugUtilsMessengerCallbackDataEXT},
            Ptr{Cvoid},
        )
    )
end

export
    Renderer,
    execute_draws

end # module
