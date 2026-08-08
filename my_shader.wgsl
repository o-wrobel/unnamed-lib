struct MyUniform {
    time: f32,
    speed: f32,
    center: vec2f,
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

    var x_angle: f32 = 90 - radians(20.);
    x_angle = my_uniform.time;
    var y_angle: f32 = 90 - radians(20.);
    y_angle = my_uniform.time;
    var z_angle: f32 = 90 - radians(20.);
    z_angle = my_uniform.time;

    let x_cos = cos(x_angle);
    let x_sin = sin(x_angle);

    let y_cos = cos(y_angle);
    let y_sin = sin(y_angle);

    let z_cos = cos(z_angle);
    let z_sin = sin(z_angle);

    // Rotation across Z axis
    let z_rotation = mat3x3f(
        x_cos, x_sin, 0,
        -x_sin, x_cos, 0,
        0, 0, 1,
    );

    let x_rotation = mat3x3f(
        1, 0, 0,
        0, y_cos, y_sin,
        0, -y_sin, y_cos,
    );

    let y_rotation = mat3x3f(
        z_cos, 0, z_sin,
        0, 1, 0,
        -z_sin, 0, z_cos
    );

    var pos = in.position;
    pos *= x_rotation; // X
    pos *= y_rotation; // Y
    pos *= z_rotation; // Z

    var out: VertexOutput;
    out.position = vec4f(pos.x, pos.y*ratio, 0, 1);
    out.color = in.color;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    let linear_color = pow(in.color, vec3f(2.2));
    return vec4f(linear_color, 1);
}
