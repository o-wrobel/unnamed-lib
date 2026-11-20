struct MyUniform {
    model_transform: mat4x4f,
    view_tranform: mat4x4f,
    projection_transform: mat4x4f,
    camera_world_position: vec3f,
    time: f32,
}

struct LightingUniform {
    directions: array<vec3f, 2>,
    colors: array<vec3f, 2>,
    hardness: f32,
    diffuse_strength: f32,
    specular_strength: f32,
}

@group(0) @binding(0) var<uniform> my_uniform: MyUniform;
@group(0) @binding(1) var diffuse_texture: texture_2d<f32>;
@group(0) @binding(2) var normal_texture: texture_2d<f32>;
@group(0) @binding(3) var texture_sampler: sampler;
@group(0) @binding(4) var<uniform> lighting: LightingUniform;

struct VertexInput {
    @location(0) position: vec3f,
    @location(1) tangent: vec3f,
    @location(2) bitangent: vec3f,
    @location(3) normal: vec3f,
    @location(4) color: vec3f,
    @location(5) uv: vec2f,
}

struct VertexOutput {
    @builtin(position) position: vec4f,
    @location(0) color: vec3f,
    @location(1) tangent: vec3f,
    @location(2) bitangent: vec3f,
    @location(3) normal: vec3f,
    @location(4) uv: vec2f,
    @location(5) view_direction: vec3f,
}

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    let ratio = 640 / 480.0;

    var pos = in.position;

    let model = my_uniform.model_transform;
    let view = my_uniform.view_tranform;
    let projection = my_uniform.projection_transform;

    var out: VertexOutput;
    let world_position = model * vec4f(in.position, 1);
    out.position = (projection * view * world_position);
    out.color = in.color;
    out.tangent = (model * vec4f(in.tangent, 0)).xyz;
    out.bitangent = (model * vec4f(in.bitangent, 0)).xyz;
    out.normal = (my_uniform.model_transform * vec4f(in.normal, 0)).xyz;
    out.uv = in.uv;
    out.view_direction = my_uniform.camera_world_position - world_position.xyz;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4f {
    let V = normalize(in.view_direction);

    let normal_strength = 1.;
    let encoded_normal = textureSample(normal_texture, texture_sampler, in.uv).rgb;
    let local_normal = encoded_normal * 2 - 1;

    let local_to_world = mat3x3f(
        normalize(in.tangent),
        normalize(in.bitangent),
        normalize(in.normal),
    );
    let world_normal = local_to_world * local_normal;

    let normal = normalize(mix(in.normal, world_normal, normal_strength));

    let base_color = textureSample(diffuse_texture, texture_sampler, in.uv).rgb;
    var shading_color: vec3f = vec3f(0);
    for (var i: u32 = 0; i < 2; i++) {
        let light_direction = normalize(lighting.directions[i].xyz);
        let R = reflect(-light_direction, normal);
        let RoV = max(0.0, dot(R, V));
        let specular = pow(RoV, lighting.hardness);
        let light_color = lighting.colors[i].rgb;
        let diffuse = max(0, dot(light_direction, normal));
        shading_color += lighting.diffuse_strength * diffuse * light_color
            + lighting.specular_strength * specular;
    }

    let color = shading_color * base_color;
    let linear_color = pow(color, vec3f(2.2));
    return vec4f(linear_color, 1);
}
