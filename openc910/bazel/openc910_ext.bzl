"""Module extension that fetches stock XUANTIE-RV/openc910 from GitHub as the
`@openc910` repo, applies our RVFI patch on top of the upstream RTL, overlays
the new RVFI generation sources (`rvfi/rtl/*.v`), and installs our BUILD file
(`//bazel:openc910.BUILD`). Upstream openc910 ships no Bazel and has no git
submodules, so a lightweight custom repository rule is enough.

Nothing is vendored into this repo: the core is fetched by Bazel and the only
in-repo artifacts are the BUILD overlay, the RVFI `.patch`, and the RVFI
overlay sources — all applied to the fetched tree at fetch time.
"""

_OPENC910_REMOTE = "https://github.com/XUANTIE-RV/openc910.git"
_OPENC910_COMMIT = "b91c90914c19f114d35c8f6b73408eb241ed847c"

def _git(ctx, args, cwd = "", what = ""):
    res = ctx.execute(["git"] + args, working_directory = cwd, timeout = 1200)
    if res.return_code != 0:
        fail("openc910 fetch: git {} failed ({}):\n{}\n{}".format(what or str(args), res.return_code, res.stdout, res.stderr))
    return res

def _openc910_repo_impl(ctx):
    _git(ctx, ["init", "-q"], what = "init")
    _git(ctx, ["remote", "add", "origin", ctx.attr.remote], what = "remote add")
    _git(ctx, ["fetch", "-q", "--depth", "1", "origin", ctx.attr.commit], what = "fetch")
    _git(ctx, ["-c", "advice.detachedHead=false", "checkout", "-q", "FETCH_HEAD"], what = "checkout")

    # Overlay the RVFI generation sources into the fetched tree so the BUILD
    # can reference them under a stable path inside @openc910.
    for f in ctx.attr.rvfi_srcs:
        ctx.symlink(f, "rvfi/rtl/" + f.name)

    # C910's cpu_cfig.h / sysmap.h are `define-only config headers that no RTL
    # file `includes; upstream compiles them FIRST in the filelist and relies on
    # the `define's persisting across the (single) compilation unit. Make `.v`
    # copies so rules_hdl/Verilator treat them as compilable sources (the BUILD
    # lists them first in openc910_core srcs).
    for h in ["C910_RTL_FACTORY/gen_rtl/cpu/rtl/cpu_cfig", "C910_RTL_FACTORY/gen_rtl/mmu/rtl/sysmap"]:
        ctx.execute(["cp", h + ".h", h + ".v"], timeout = 60)

    # Apply the RVFI RTL patch (exports rd/mem/trap taps + top-level RVFI ports
    # under `ifdef RVFI). Use Bazel's native patch implementation (ctx.patch)
    # rather than the `patch` binary, which the cvm image does not ship.
    ctx.patch(ctx.attr.rvfi_patch, strip = 1)

    ctx.symlink(ctx.attr.build_file, "BUILD.bazel")

_openc910_repo = repository_rule(
    implementation = _openc910_repo_impl,
    attrs = {
        "remote": attr.string(mandatory = True),
        "commit": attr.string(mandatory = True),
        "build_file": attr.label(mandatory = True, allow_single_file = True),
        "rvfi_patch": attr.label(mandatory = True, allow_single_file = True),
        "rvfi_srcs": attr.label_list(allow_files = True),
    },
)

def _ext_impl(_ctx):
    _openc910_repo(
        name = "openc910",
        remote = _OPENC910_REMOTE,
        commit = _OPENC910_COMMIT,
        build_file = "//bazel:openc910.BUILD",
        rvfi_patch = "//bazel:openc910_rvfi.patch",
        rvfi_srcs = ["//rvfi/rtl:ct_rvfi_gen.v"],
    )

openc910_ext = module_extension(implementation = _ext_impl)
