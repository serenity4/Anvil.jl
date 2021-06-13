function init_debug(instance::Instance)
    messenger = DebugUtilsMessengerEXT(
        instance,
        |(
            DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT,
            DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,
            DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT,
            DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
        ),
        |(DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT, DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT, DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT),
        debug_callback_c[],
        function_pointer(instance, "vkCreateDebugUtilsMessengerEXT"),
        function_pointer(instance, "vkDestroyDebugUtilsMessengerEXT"),
    )
    debug_messenger[] = messenger
    nothing
end

function init(;
    instance_layers = [],
    instance_extensions = [],
    device_extensions = [],
    enabled_features = PhysicalDeviceFeatures(),
    nqueues = 1,
    queue_flags = QUEUE_COMPUTE_BIT | QUEUE_GRAPHICS_BIT,
    with_validation = true,
    debug = true,
)

    if with_validation && "VK_LAYER_KHRONOS_validation" ∉ instance_layers
        push!(instance_layers, "VK_LAYER_KHRONOS_validation")
    end
    if debug && "VK_EXT_debug_utils" ∉ instance_extensions
        push!(instance_extensions, "VK_EXT_debug_utils")
    end

    available_layers = unwrap(enumerate_instance_layer_properties())
    unsupported_layers = filter(!in(getproperty.(available_layers, :layer_name)), instance_layers)
    if !isempty(unsupported_layers)
        error("Requesting unsupported instance layers: $unsupported_layers")
    end

    available_extensions = unwrap(enumerate_instance_extension_properties())
    unsupported_extensions = filter(!in(getproperty.(available_extensions, :extension_name)), instance_extensions)
    if !isempty(unsupported_extensions)
        error("Requesting unsupported instance extensions: $unsupported_extensions")
    end

    instance = Instance(instance_layers, instance_extensions; application_info = ApplicationInfo(v"1", v"1", v"1.2"))

    physical_device = first(unwrap(enumerate_physical_devices(instance)))

    # TODO: check for supported device features
    available_extensions = unwrap(enumerate_device_extension_properties(physical_device))
    unsupported_extensions = filter(!in(getproperty.(available_extensions, :extension_name)), device_extensions)
    if !isempty(unsupported_extensions)
        error("Requesting unsupported device extensions: $unsupported_extensions")
    end

    if debug
        init_debug(instance)
    end

    queue_family = find_queue_family(physical_device, queue_flags)
    device_ci = DeviceCreateInfo(
        [DeviceQueueCreateInfo(queue_family, ones(Float32, nqueues))],
        [],
        device_extensions;
        enabled_features,
    )
    device = unwrap(create_device(physical_device, device_ci))
    device, device_ci
end
