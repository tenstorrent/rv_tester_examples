"""Module extension that fetches stock openhwgroup/cva6 from GitHub as the
`@cva6` repo, initialising only the submodules the core RTL needs
(`core/cvfpu` and its nested `fpu_div_sqrt_mvp`), and overlaying our
BUILD file (`//bazel:cva6.BUILD`). Upstream CVA6 ships no Bazel, and
`git_repository` cannot init a *subset* of submodules, hence the custom rule.
"""

_CVA6_REMOTE = "https://github.com/openhwgroup/cva6.git"
_CVA6_COMMIT = "31b45637935e944a0e9b4e2cb14e9bb49c9bdd23"

# "<parent-dir>|<submodule-path>", initialised in order so a nested submodule
# is fetched after its parent is checked out. Empty parent == repo root.
_SUBMODULES = [
    "|core/cvfpu",
    "core/cvfpu|src/fpu_div_sqrt_mvp",
]

def _git(ctx, args, cwd = "", what = ""):
    res = ctx.execute(["git"] + args, working_directory = cwd, timeout = 1200)
    if res.return_code != 0:
        fail("cva6 fetch: git {} failed ({}):\n{}\n{}".format(what or str(args), res.return_code, res.stdout, res.stderr))
    return res

def _run(ctx, args, what):
    res = ctx.execute(args, timeout = 600)
    if res.return_code != 0:
        fail("cva6 fetch: {} failed ({}):\n{}\n{}".format(what, res.return_code, res.stdout, res.stderr))
    return res

def _cva6_repo_impl(ctx):
    _git(ctx, ["init", "-q"], what = "init")
    _git(ctx, ["remote", "add", "origin", ctx.attr.remote], what = "remote add")
    _git(ctx, ["fetch", "-q", "--depth", "1", "origin", ctx.attr.commit], what = "fetch")
    _git(ctx, ["-c", "advice.detachedHead=false", "checkout", "-q", "FETCH_HEAD"], what = "checkout")
    for pair in ctx.attr.submodules:
        parent, _, path = pair.partition("|")
        _git(ctx, ["submodule", "update", "--init", "--depth", "1", path], cwd = parent, what = "submodule " + path)

    # Stage clean-path copies of the include dirs whose namespace repeats in
    # the real path (.../common_cells/include/common_cells, .../axi/include/axi).
    # rules_hdl_compat derives the +incdir by truncating at the FIRST namespace
    # match, so it needs a path where the namespace appears once. Copying into
    # bazel_include/<ns>/ (namespace appears once) yields the correct incdir
    # `<repo>/bazel_include`. Kept in the fetched @cva6 so nothing is vendored
    # into the consuming repo and there is no version skew.
    _run(ctx, ["mkdir", "-p", "bazel_include"], "mkdir bazel_include")
    _run(ctx, ["cp", "-rL", "vendor/pulp-platform/common_cells/include/common_cells", "bazel_include/common_cells"], "stage common_cells include")
    _run(ctx, ["cp", "-rL", "vendor/pulp-platform/axi/include/axi", "bazel_include/axi"], "stage axi include")

    ctx.symlink(ctx.attr.build_file, "BUILD.bazel")

_cva6_repo = repository_rule(
    implementation = _cva6_repo_impl,
    attrs = {
        "remote": attr.string(mandatory = True),
        "commit": attr.string(mandatory = True),
        "submodules": attr.string_list(),
        "build_file": attr.label(mandatory = True, allow_single_file = True),
    },
)

def _ext_impl(_ctx):
    _cva6_repo(
        name = "cva6",
        remote = _CVA6_REMOTE,
        commit = _CVA6_COMMIT,
        submodules = _SUBMODULES,
        build_file = "//bazel:cva6.BUILD",
    )

cva6_ext = module_extension(implementation = _ext_impl)
