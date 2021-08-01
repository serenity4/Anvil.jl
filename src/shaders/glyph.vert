#version 450

// location and character information
layout(location = 0) in VertexData {
    vec4 position;
    // starting index in the curve buffer (i.e. character)
    flat uint start;
    // number of curves to process
    flat uint curve_count;
} in_vdata;

layout(location = 0) out {
    vec4 position;
    // starting index in the curve buffer (i.e. character)
    flat uint start;
    // number of curves to process
    flat uint curve_count;
} out_vdata;

void main() {
    out_vdata = in_vdata;
}
