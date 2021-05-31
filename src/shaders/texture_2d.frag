#version 450

layout(location = 0) out vec4 out_color;
layout(location = 0) in vec2 texcoords;

layout(binding = 1) uniform sampler2D texsampler;

void main() {
    out_color = texture(texsampler, texcoords);
    // out_color = vec4(texcoords, 0., 1.);
}
