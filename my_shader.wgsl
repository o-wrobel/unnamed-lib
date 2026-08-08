struct MyUniform {
    time: f32,
    pitch: f32,
    yaw: f32,
    roll: f32,
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
    let pitch = radians(my_uniform.pitch);
    let yaw = radians(my_uniform.yaw);
    let roll = radians(my_uniform.roll);

    let pitch_cos = cos(pitch);
    let pitch_sin = sin(pitch);

    let yaw_cos = cos(yaw);
    let yaw_sin = sin(yaw);

    let roll_cos = cos(roll);
    let roll_sin = sin(roll);

    let pitch_rotation = transpose(mat3x3f(
        1, 0, 0,
        0, pitch_cos, pitch_sin,
        0, -pitch_sin, pitch_cos,
    ));

    let yaw_rotation = transpose(mat3x3f(
        yaw_cos, 0, -yaw_sin,
        0, 1, 0,
        yaw_sin, 0, yaw_cos
    ));

    // Rotation across Z axis
    let roll_rotation = transpose(mat3x3f(
        roll_cos, roll_sin, 0,
        -roll_sin, roll_cos, 0,
        0, 0, 1,
    ));

    var pos = in.position;
    pos *= pitch_rotation; // pitch (X)
    pos *= yaw_rotation; // yaw   (Y)
    pos *= roll_rotation; // roll  (Z)

    var out: VertexOutput;
    out.position = vec4f(pos.x, pos.y*ratio, pos.z * 0.5 + 0.5, 1);
    out.color = in.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    let linear_color = pow(in.color, vec3f(2.2));
    return vec4f(linear_color, 1);
}
