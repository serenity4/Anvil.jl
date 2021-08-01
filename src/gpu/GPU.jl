module GPU

using Vulkan
using Dictionaries
using MLStyle

const debug_callback_c = Ref{Ptr{Cvoid}}(C_NULL)
const debug_messenger = Ref{DebugUtilsMessengerEXT}()

function __init__()
    # for debugging in Vulkan
    debug_callback_c[] =
        @cfunction(default_debug_callback, UInt32, (DebugUtilsMessageSeverityFlagEXT, DebugUtilsMessageTypeFlagEXT, Ptr{vk.VkDebugUtilsMessengerCallbackDataEXT}, Ptr{Cvoid}))
end

include("init.jl")
include("resources.jl")
include("memory.jl")
include("command.jl")

export
    # init
    debug_messenger,
    init,

    # resources
    GPUResource,
    GPUState,
    VertexBuffer,
    IndexBuffer,
    DescriptorSetVector,
    ShaderResource,
    SampledImage,
    StorageBuffer,

    # memory
    buffer_size,
    upload_data,
    download_data,

    # command
    @record

end # module
