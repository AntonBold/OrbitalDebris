# =============================================================================
# create_vitis.py  --  regenerate the Vitis workspace from build/pl_ps.xsa
#
#   source <Vitis install>/settings64.sh      (puts vitis on PATH)
#   vitis -s scripts/create_vitis.py          (from the repo root)
#
# The Vitis counterpart of scripts/create_project.tcl: everything in vitis/
# is generated (and gitignored); delete it and re-run. Re-run after every
# new .xsa (scripts/generate_bitstream.tcl). Builds:
#   vitis/debris_platform   platform from build/pl_ps.xsa, standalone domain
#                           standalone_psu_cortexa53_0 on A53 #0
#   vitis/debris_app        empty_application on that domain, with
#                           src/sw/vitis/UserConfig.cmake (sources in src/sw)
#                           and src/sw/vitis/lscript.ld (2 MB stack)
# and builds the app once: vitis/debris_app/build/debris_app.elf, which
# scripts/run_board.tcl loads. For later source-only changes,
# scripts/build_app.py rebuilds just the app.
#
# Deletes vitis/ first. Close any Vitis IDE that has vitis/ open.
# =============================================================================

import os
import shutil
import sys

import vitis

repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
workspace = os.path.join(repo_root, "vitis")
xsa = os.path.join(repo_root, "build", "pl_ps.xsa")
app_cfg = os.path.join(repo_root, "src", "sw", "vitis")

platform_name = "debris_platform"
app_name = "debris_app"
cpu = "psu_cortexa53_0"
domain = "standalone_psu_cortexa53_0"

xpfm = os.path.join(workspace, platform_name, "export", platform_name, platform_name + ".xpfm")
elf = os.path.join(workspace, app_name, "build", app_name + ".elf")

if not os.path.exists(xsa):
    sys.exit("missing %s -- run scripts/generate_bitstream.tcl first" % xsa)

if os.path.exists(workspace):
    print("removing old workspace %s" % workspace)
    shutil.rmtree(workspace)

client = vitis.create_client()
try:
    client.set_workspace(path=workspace)

    print("creating %s from %s" % (platform_name, xsa))
    platform = client.create_platform_component(
        name=platform_name, hw_design=xsa, os="standalone", cpu=cpu, domain_name=domain)
    platform.build()
    if not os.path.exists(xpfm):
        sys.exit("platform build FAILED: %s not written -- check the output above" % xpfm)

    print("creating %s on %s" % (app_name, domain))
    app = client.create_app_component(
        name=app_name, platform=xpfm, domain=domain, template="empty_application")
    for f in ("UserConfig.cmake", "lscript.ld"):
        shutil.copy(os.path.join(app_cfg, f), os.path.join(workspace, app_name, "src", f))
    app.build()
finally:
    vitis.dispose()

if not os.path.exists(elf):
    sys.exit("app build FAILED: %s not written -- check the output above" % elf)
print("built %s" % elf)
