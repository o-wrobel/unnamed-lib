struct MyUniform {
    model_transform: mat4x4f,
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

    let model_transform = my_uniform.model_transform;

    pos = (model_transform * vec4f(pos, 1)).xyz;

    let focal_point = vec3f(0., 0., -2.0);
    let focal_length = 2.0;
    pos = pos - focal_point;

    let near = 0.001;
    let far = 100.0;

    let divides = 1. / (focal_length * (far - near));
    let perspective = transpose(mat4x4f(
        1, 0, 0, 0,
        0, ratio, 0, 0,
        0, 0, far * divides, -far * near * divides,
        0, 0, 1. / focal_length, 0
    ));

    let scale = 2.0;
    let ortho = transpose(mat4x4f(
        1/scale, 0, 0, 0,
        0, ratio/scale, 0, 0,
        0, 0, 1.0/(far - near), -near / (far - near),
        0, 0, 0, 1
    ));

    var out: VertexOutput;
    out.position = perspective * vec4f(pos, 1);
    // out.position.w = pos.z / focal_length;
    out.color = in.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    let linear_color = pow(in.color, vec3f(2.2));
    return vec4f(linear_color, 1);
}
