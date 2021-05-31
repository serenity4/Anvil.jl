function schedule_draw!(rdr::BasicRenderer, app::ApplicationState)

end

function add_noise_sampler!(rdr::BasicRenderer)
    view = ImageView(
        timage.device,
        timage,
        IMAGE_VIEW_TYPE_2D,
        format,
        ComponentMapping(fill(COMPONENT_SWIZZLE_IDENTITY, 4)...),
        ImageSubresourceRange(IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1),
    )

    sampler = Sampler(
        device,
        FILTER_LINEAR,
        FILTER_LINEAR,
        SAMPLER_MIPMAP_MODE_LINEAR,
        SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
        SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
        SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER,
        0,
        true,
        props.limits.max_sampler_anisotropy,
        false,
        COMPARE_OP_ALWAYS,
        0,
        0,
        BORDER_COLOR_FLOAT_OPAQUE_BLACK,
        false,
    )
end
