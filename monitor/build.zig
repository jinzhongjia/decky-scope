const std = @import("std");

pub fn build(b: *std.Build) void {
    // 目标：x86_64-linux，无 libc（不指定 abi、不 linkLibC → 默认直接 syscall）
    const target = b.standardTargetOptions(.{
        .default_target = .{ .cpu_arch = .x86_64, .os_tag = .linux },
    });
    // 体积优化：默认 ReleaseSmall（配合 main.zig 里的自定义 panic/logFn/u8 main，
    // 实测 78KB；ReleaseSafe 约 100KB，如需更多运行时安全检查可切换）
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Build optimization mode") orelse .ReleaseSmall;

    const exe = b.addExecutable(.{
        .name = "deckscope-monitor",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            // monitor 是 timerfd+epoll 单线程事件循环，声明 single_threaded
            // 可裁掉 std 的线程同步机架（实测省 ~18KB）
            .single_threaded = true,
            .strip = optimize == .ReleaseSmall,
            // 无 unwind 表：monitor 不做堆栈回溯（panic 已改纯 syscall 直出），
            // 去掉 .eh_frame/.eh_frame_hdr 约 3KB
            .unwind_tables = if (optimize != .Debug) .none else null,
        }),
    });
    // 注意：全项目禁止 linkLibC() 与 @cImport
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the monitor").dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = .Debug,
        }),
    });
    b.step("test", "Run unit tests").dependOn(&b.addRunArtifact(tests).step);
}
