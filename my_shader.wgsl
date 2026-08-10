struct MyUniform {
    model_transform: mat4x4f,
    view_tranform: mat4x4f,
    projection_transform: mat4x4f,
    time: f32,
}

@group(0) @binding(0) var<uniform> my_uniform: MyUniform;

struct VertexInput {
    @location(0) position: vec3f,
    @location(1) color: vec3f
}

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) color: vec3f
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    let ratio = 640 / 480.0;

    var pos = in.position;

    let model = my_uniform.model_transform;
    let view = my_uniform.view_tranform;
    let projection = my_uniform.projection_transform;

    var out: VertexOutput;
    out.position = (projection * view * model * vec4f(pos, 1));
    out.color = in.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    let linear_color = pow(in.color, vec3f(2.2));
    return vec4f(linear_color, 1);
}
