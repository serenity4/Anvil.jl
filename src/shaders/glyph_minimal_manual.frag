/*

Inputs:
- position
- curves
- text color
- pixel per em

Output: color

*/

#version 450

// location and character information
layout(location = 0) in VertexData {
    vec4 position;
    // starting index in the curve buffer (i.e. character)
    flat uint start;
    // number of curves to process
    flat uint curve_count;
} vdata;

layout(location = 0) out vec4 color;

layout(push_constant) uniform RenderInfo {
    vec4 text_color;
    float pixel_per_em;
} render_info;

struct CurveData {
    float p1[2];
    float p2[2];
    float p3[2];
};

layout(set = 0, binding = 0) readonly buffer CurveBuffer {
    CurveData curves[];
} curve_buffer;

const float atol = 0.0001;

void main() {
    float intensity = 0.0;

    for (uint curve_idx = vdata.start; curve_idx < vdata.start + vdata.curve_count; curve_idx++) {

        CurveData curve_points = curve_buffer.curves[curve_idx];

        curve_points.p1[0] = curve_points.p1[0] - vdata.position.x;
        curve_points.p1[1] = curve_points.p1[1] - vdata.position.y;
        curve_points.p2[0] = curve_points.p2[0] - vdata.position.x;
        curve_points.p2[1] = curve_points.p2[1] - vdata.position.y;
        curve_points.p3[0] = curve_points.p3[0] - vdata.position.x;
        curve_points.p3[1] = curve_points.p3[1] - vdata.position.y;

        for (uint coord = 0; coord < 2; coord++) {

            float xbar_1 = curve_points.p1[1 - coord];
            float xbar_2 = curve_points.p2[1 - coord];
            float xbar_3 = curve_points.p3[1 - coord];

            if (max(max(curve_points.p1[coord], curve_points.p2[coord]), curve_points.p2[coord]) * render_info.pixel_per_em <= -0.5) continue;

            uint rshift = (xbar_1 > 0 ? 2 : 0) + (xbar_2 > 0 ? 4 : 0) + (xbar_3 > 0 ? 8 : 0);
            uint code = 0x2E74U >> rshift & 3U;
            if (code != 0U) {
                float a = xbar_1 - 2 * xbar_2 + xbar_3;
                float b = xbar_1 - xbar_2;
                float c = xbar_1;

                float t1;
                float t2;

                if (abs(a) < atol) {
                    t1 = c / (2 * b);
                    t2 = t1;
                } else {
                    float Delta = b * b - a * c;
                    if (Delta < 0) continue;
                    float delta = sqrt(Delta);
                    t1 = (b - delta) / a;
                    t2 = (b + delta) / a;
                }

                float x1 = (a * t1 - 2.0 * b) * t1 + c;
                float x2 = (a * t2 - 2.0 * b) * t2 + c;
                float val;

                if ((code & 1U) == 1U) {
                    val = clamp(render_info.pixel_per_em * x1 + 0.5, 0.0, 1.0);
                }
                if (code > 1U) {
                    val = clamp(render_info.pixel_per_em * x2 + 0.5, 0.0, 1.0);
                }
                intensity += val * (coord == 0U ? 1 : -1);
            }
        }
    }

    intensity = sqrt(abs(intensity));
    float alpha = render_info.text_color.a * intensity;
    color = vec4(render_info.text_color.rgb, alpha);
}
