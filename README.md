
```sh
zig fetch --save <url-to-this-repo>
```

In the build.zig:

```zig
const ggml = b.dependency("ggml-build", .{ .optimize = .ReleaseFast });
exe.root_module.linkLibrary(ggml.artifact("ggml"));
```
