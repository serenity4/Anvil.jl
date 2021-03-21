module Givre

using Vulkan
using VulkanShaders
using XCB
using MLStyle
using UnPack

include("init.jl")

function __init__()
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

include("memory.jl")
include("app.jl")
include("window.jl")

export
    Application


end
