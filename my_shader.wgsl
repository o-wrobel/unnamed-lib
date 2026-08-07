struct MyUniform {
    time: f32,
    speed: f32,
    center: vec2f,
}

@group(0) @binding(0) var<uniform> my_uniform: MyUniform;

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
    let speed = my_uniform.speed;
    let t = my_uniform.time * speed;
    let ratio = 640 / 480.0;
    let ratio_vec = vec2f(1, ratio);

    let i_hat = vec2f(cos(t), sin(t));
    let j_hat = vec2f(-sin(t), cos(t));
    let rotation_matrix = mat2x2<f32>(i_hat, j_hat);

    var pos = in.position;
    pos = pos * rotation_matrix;
    pos += my_uniform.center;
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
