const std = @import("std");
const Allocator = std.mem.Allocator;
const wgpu = @import("wgpu");

pub const ShaderVisibility = struct {
    vertex: bool = false,
    fragment: bool = false,
    compute: bool = false,

    pub fn toApi(self: ShaderVisibility) wgpu.RenderPipeline.ShaderStage {
        return .{
            .vertex = self.vertex,
            .fragment = self.fragment,
            .compute = self.compute,
        };
    }
};

pub const BindGroupLayout = struct {
    entries: []const Entry,
    label: []const u8 = "",

    pub const Entry = struct {
        binding: ?u32 = null,
        visibility: ShaderVisibility = .{},
        resource: Resource,
    };

    pub const Resource = union(enum) {
        buffer: wgpu.BindGroupLayout.BufferBindingLayout,
        texture: wgpu.BindGroupLayout.TextureBindingLayout,
        sampler: wgpu.BindGroupLayout.SamplerBindingLayout,
    };

    pub fn toApi(layout: BindGroupLayout, device: wgpu.Device, allocator: Allocator) !wgpu.BindGroupLayout {
        const buffer = try allocator.alloc(wgpu.BindGroupLayout.Entry, layout.entries.len);
        defer allocator.free(buffer);
        for (layout.entries, 0..) |e, i| {
            const binding: u32 = @intCast(e.binding orelse i);
            const wgpu_entry: wgpu.BindGroupLayout.Entry = switch (e.resource) {
                .buffer => |b| .{
                    .binding = binding,
                    .visibility = e.visibility.toApi(),
                    .buffer = b,
                },
                .texture => |t| .{
                    .binding = binding,
                    .visibility = e.visibility.toApi(),
                    .texture = t,
                },
                .sampler => |s| .{
                    .binding = binding,
                    .visibility = e.visibility.toApi(),
                    .sampler = s,
                },
            };
            buffer[i] = wgpu_entry;
        }
        return try device.createBindGroupLayout(.{ .entries = buffer, .label = layout.label });
    }
};

pub fn bufferLayout(comptime T: type) wgpu.RenderPipeline.VertexBufferLayout {
    const ti = @typeInfo(T);
    const s = ti.@"struct";
    const field_types = s.field_types;
    const attributes: [field_types.len]wgpu.RenderPipeline.VertexAttribute = blk: {
        var result: [field_types.len]wgpu.RenderPipeline.VertexAttribute = undefined;
        var offset: u32 = 0;
        var location: u32 = 0;
        for (field_types) |K| {
            const format = formatFromType(K);
            const size = @sizeOf(K);
            result[location] = .{
                .format = format,
                .offset = offset,
                .shader_location = location,
            };
            offset += size;
            location += 1;
        }
        break :blk result;
    };
    return .{
        .attributes = &attributes,
        .array_stride = @sizeOf(T),
    };
}

pub fn formatFromType(comptime T: type) wgpu.RenderPipeline.VertexFormat {
    var type_name: []const u8 = undefined;
    var type_size_bits: u32 = undefined;
    return switch (@typeInfo(T)) {
        .vector => |V| blk: {
            switch (@typeInfo(V.child)) {
                .float => |F| {
                    type_name = "float";
                    type_size_bits = F.bits;
                },
                else => @compileError("Unimplemented for non-float vectors"),
            }
            const format_name = std.fmt.comptimePrint("{s}{d}x{d}", .{ type_name, type_size_bits, V.len });
            break :blk @field(wgpu.RenderPipeline.VertexFormat, format_name);
        },
        else => @compileError("Unimplemented for non-float vectors"),
    };
}
