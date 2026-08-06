@vertex
fn vs_main(@builtin(vertex_index) in_vertex_index: u32) -> @builtin(position) vec4f {
    var p = vec2f(0, 0);
    if (in_vertex_index == 0) {
        p = vec2f(-0.5, -0.5);
    } else if (in_vertex_index == 1) {
        p = vec2f(0.5, -0.5);
    } else {
        p = vec2f(0, 0.5);
    }
    return vec4f(p, 0, 1);
}

@fragment
fn fs_main() -> @location(0) vec4f {
    return vec4f(0, 0.4, 1, 1);
}
