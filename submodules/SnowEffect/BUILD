load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")
load("@build_bazel_rules_apple//apple:ios.bzl", "ios_unit_test")
load("@build_bazel_rules_apple//apple/testing/default_runner:ios_test_runner.bzl", "ios_test_runner")

swift_library(
    name = "SnowEffect",
    module_name = "SnowEffect",
    srcs = glob(["Sources/**/*.swift"]),
    copts = ["-warnings-as-errors"],
    visibility = ["//visibility:public"],
)

swift_library(
    name = "SnowEffectTestsLib",
    testonly = True,
    srcs = glob(["Tests/**/*.swift"]),
    deps = [":SnowEffect"],
)

ios_test_runner(
    name = "SnowEffectTestRunner",
    device_type = "iPhone 17",
    os_version = "27.0",
)

ios_unit_test(
    name = "SnowEffectTests",
    minimum_os_version = "15.0",
    runner = ":SnowEffectTestRunner",
    deps = [":SnowEffectTestsLib"],
    visibility = ["//visibility:public"],
)
