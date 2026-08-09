struct MyUniform {
    time: f32,
    pitch: f32,
    yaw: f32,
    roll: f32,
    roll_mat: mat4x4f,
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
    let t = my_uniform.time;

    let pitch = radians(my_uniform.pitch);
    let yaw = radians(my_uniform.yaw);
    let roll = radians(my_uniform.roll);

    let pitch_cos = cos(pitch);
    let pitch_sin = sin(pitch);

    let yaw_cos = cos(yaw);
    let yaw_sin = sin(yaw);

    let roll_cos = cos(roll);
    let roll_sin = sin(roll);

    let pitch_rotation = transpose(mat4x4f(
        1, 0, 0, 0,
        0, pitch_cos, pitch_sin, 0,
        0, -pitch_sin, pitch_cos, 0,
        0, 0, 0, 1
    ));

    let yaw_rotation = transpose(mat4x4f(
        yaw_cos, 0, -yaw_sin, 0,
        0, 1, 0, 0,
        yaw_sin, 0, yaw_cos, 0,
        0, 0, 0, 1
    ));

    // Rotation across Z axis
    let roll_rotation = my_uniform.roll_mat;

    var pos = in.position;

    let zoom = 0.3;
    let scaling = transpose(mat4x4f(
        zoom, 0, 0, 0,
        0, zoom, 0, 0,
        0, 0, zoom, 0,
        0, 0, 0, 1
    ));

    let translation = transpose(mat4x4f(
        1, 0, 0, 0.5,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
    ));

    let model_transform = pitch_rotation * yaw_rotation * roll_rotation * translation * scaling;

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
