@group(0) @binding(0) var<uniform> time: f32;

struct VertexInput {
    @location(0) position: vec2f,
    @location(1) color: vec3f
}

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) color: vec3f
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    let ratio = 640 / 480.0;
    let ratio_vec = vec2f(1, ratio);
    let speed = 2.0;
    let radius = 0.2;
    let offset = radius * vec2f(cos(time*speed), sin(time*speed));

    var pos = in.position;
    pos += offset;
    pos *= ratio_vec;

    var out: VertexOutput;
    out.position = vec4f(pos, 0, 1);
    out.color = in.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    let linear_color = pow(in.color, vec3f(2.2));
    return vec4f(linear_color, 1);
}
