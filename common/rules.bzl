load("@bazel_tools//tools/build_defs/pkg:pkg.bzl", "pkg_tar", "pkg_deb")

LOCAL_JDK_PREFIX = "external/local_jdk/"

def _java_deps_impl(ctx):
    names = {}
    files = []
    filenames = []

    for file in ctx.attr.target.data_runfiles.files.to_list():
        if file.basename in filenames:
            continue # do not pack JARs with same name
        if file.extension == 'jar' and not file.path.startswith(LOCAL_JDK_PREFIX):
            names[file.path] = ctx.attr.java_deps_root + file.basename
            files.append(file)
            filenames.append(file.basename)

    jars_mapping = ctx.actions.declare_file("jars.mapping")

    ctx.actions.write(
        output = jars_mapping,
        content = str(names)
    )

    ctx.actions.run(
        outputs = [ctx.outputs.distribution],
        inputs = files + [jars_mapping],
        arguments = [jars_mapping.path, ctx.outputs.distribution.path],
        executable = ctx.executable._java_deps_builder,
        progress_message = "Generating tarball with Java deps: {}".format(
            ctx.outputs.distribution.short_path)
    )


java_deps = rule(
    attrs = {
        "target": attr.label(mandatory=True),
        "java_deps_root": attr.string(
            doc = "Folder inside archive to put JARs into"
        ),
        "_java_deps_builder": attr.label(
            default = "//common:java_deps",
            executable = True,
            cfg = "host"
        )
    },
    implementation = _java_deps_impl,
    outputs = {
        "distribution": "%{name}.tgz"
    },
)


def _tgz2zip_impl(ctx):
    ctx.actions.run(
        inputs = [ctx.file.tgz],
        outputs = [ctx.outputs.zip],
        executable = ctx.executable._tgz2zip_py,
        arguments = [ctx.file.tgz.path, ctx.outputs.zip.path, ctx.attr.prefix],
        progress_message = "Converting {} to {}".format(ctx.file.tgz.short_path, ctx.outputs.zip.short_path)
    )

    return DefaultInfo(data_runfiles = ctx.runfiles(files=[ctx.outputs.zip]))


tgz2zip = rule(
    attrs = {
        "tgz": attr.label(
            allow_single_file=[".tar.gz"],
            mandatory = True
        ),
        "output_filename": attr.string(
            mandatory = True,
        ),
        "prefix": attr.string(
            default="."
        ),
        "_tgz2zip_py": attr.label(
            default = "//common:tgz2zip",
            executable = True,
            cfg = "host"
        )
    },
    implementation = _tgz2zip_impl,
    outputs = {
        "zip": "%{output_filename}.zip"
    },
    output_to_genfiles = True
)


def assemble_targz(name,
                   output_filename = None,
                   targets = [],
                   additional_files = {},
                   empty_directories = [],
                   permissions = {},
                   visibility = ["//visibility:private"]):
    pkg_tar(
        name = "{}__do_not_reference__targz".format(name),
        deps = targets,
        extension = "tar.gz",
        files = additional_files,
        empty_dirs = empty_directories,
        modes = permissions,
    )

    pkg_tar(
        name = name,
        deps = [":{}__do_not_reference__targz".format(name)],
        package_dir = output_filename,
        extension = "tar.gz",
        visibility = visibility
    )


def assemble_zip(name,
                 output_filename,
                 targets,
                 additional_files = {},
                 empty_directories = [],
                 permissions = {},
                 visibility = ["//visibility:private"]):
    pkg_tar(
        name="{}__do_not_reference__targz".format(name),
        deps = targets,
        extension = "tar.gz",
        files = additional_files,
        empty_dirs = empty_directories,
        modes = permissions,
    )

    tgz2zip(
        name = name,
        tgz = ":{}__do_not_reference__targz".format(name),
        output_filename = output_filename,
        prefix = "./" + output_filename,
        visibility = visibility
    )