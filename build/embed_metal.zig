const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);

    if (args.len != 5) {
        std.debug.print("usage: embed-metal <metal-source> <common-h> <impl-h> <output.s>\n", .{});
        std.process.exit(1);
    }

    const cwd = std.Io.Dir.cwd();

    const metal_src = try cwd.readFileAlloc(io, args[1], arena, .unlimited);
    const common_h = try cwd.readFileAlloc(io, args[2], arena, .unlimited);
    const impl_h = try cwd.readFileAlloc(io, args[3], arena, .unlimited);

    var merged: std.ArrayList(u8) = .empty;

    var line_iter = std.mem.splitScalar(u8, metal_src, '\n');
    while (line_iter.next()) |line| {
        if (std.mem.indexOf(u8, line, "__embed_ggml-common.h__") != null) {
            try merged.appendSlice(arena, common_h);
            try merged.appendSlice(arena, "\n");
        } else if (std.mem.indexOf(u8, line, "#include \"ggml-metal-impl.h\"") != null) {
            try merged.appendSlice(arena, impl_h);
            try merged.appendSlice(arena, "\n");
        } else {
            try merged.appendSlice(arena, line);
            try merged.appendSlice(arena, "\n");
        }
    }

    const data = merged.items;

    var output: std.ArrayList(u8) = .empty;

    try output.appendSlice(arena, ".section __DATA,__ggml_metallib\n");
    try output.appendSlice(arena, ".globl _ggml_metallib_start\n");
    try output.appendSlice(arena, "_ggml_metallib_start:\n");

    var i: usize = 0;
    while (i < data.len) {
        const end = @min(i + 16, data.len);
        try output.appendSlice(arena, ".byte ");
        for (i..end) |j| {
            if (j > i) try output.append(arena, ',');
            try output.appendSlice(arena, try std.fmt.allocPrint(arena, "{d}", .{data[j]}));
        }
        try output.append(arena, '\n');
        i = end;
    }

    try output.appendSlice(arena, ".globl _ggml_metallib_end\n");
    try output.appendSlice(arena, "_ggml_metallib_end:\n");

    var out_file = try cwd.createFile(io, args[4], .{});
    defer out_file.close(io);

    try out_file.writeStreamingAll(io, output.items);
}
