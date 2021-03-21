module Givre

using Vulkan
using VulkanShaders
using XCB
using MLStyle
using UnPack
using AbstractGUI

include("vulkan/init.jl")
include("vulkan/memory.jl")
include("app.jl")
include("window.jl")

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
    Application


end
