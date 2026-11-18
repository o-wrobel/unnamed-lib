struct MyUniform {
    model_transform: mat4x4f,
    view_tranform: mat4x4f,
    projection_transform: mat4x4f,
    time: f32,
}

struct LightingUniform {
    directions: array<vec4f, 2>,
    colors: array<vec4f, 2>,
}

@group(0) @binding(0) var<uniform> my_uniform: MyUniform;
@group(0) @binding(1) var gradient_texture: texture_2d<f32>;
@group(0) @binding(2) var texture_sampler: sampler;
@group(0) @binding(3) var<uniform> lighting: LightingUniform;

struct VertexInput {
    @location(0) position: vec3f,
    @location(1) normal: vec3f,
    @location(2) color: vec3f,
    @location(3) uv: vec2f,
}

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) color: vec3f,
    @location(1) normal: vec3f,
    @location(2) uv: vec2f,
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
    out.normal = (my_uniform.model_transform * vec4f(in.normal, 0)).xyz;
    out.uv = in.uv;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    let normal = normalize(in.normal);

    let light_color1 = lighting.colors[0].rgb;
    let light_direction1 = normalize(lighting.directions[0].xyz);
    let shading1 = max(0, dot(light_direction1, normal));

    let light_color2 = lighting.colors[1].rgb;
    let light_direction2 = normalize(lighting.directions[1].xyz);
    let shading2 = max(0, dot(light_direction2, normal));

    let shading_color = shading1 * light_color1 + shading2 * light_color2;

    let base_color = textureSample(gradient_texture, texture_sampler, in.uv).rgb;
    let color = shading_color * base_color;
    let linear_color = pow(color, vec3f(2.2));
    return vec4f(linear_color, 1);
}
