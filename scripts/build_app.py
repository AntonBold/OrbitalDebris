# =============================================================================
# build_app.py  --  clean and build debris_app without opening the Vitis IDE
#
#   source <Vitis install>/settings64.sh      (puts vitis on PATH)
#   vitis -s scripts/build_app.py             (from the repo root)
#
# Rebuilds the debris_app component in the generated workspace vitis/
# (sources from src/sw, see src/sw/vitis/UserConfig.cmake). Create the
# workspace first with scripts/create_vitis.py, and re-create it after a new
# build/pl_ps.xsa or a change to src/sw/vitis/.
# Output: vitis/debris_app/build/debris_app.elf, which scripts/run_board.tcl
# loads onto the board.
# =============================================================================

import os
import sys

import vitis

repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
workspace = os.path.join(repo_root, "vitis")
elf = os.path.join(workspace, "debris_app", "build", "debris_app.elf")

# An ELF left over from an earlier build mustn't count as success
before = os.path.getmtime(elf) if os.path.exists(elf) else None

client = vitis.create_client()
try:
    try:
        client.set_workspace(path=workspace)
    except Exception as e:
        if "already in use" in str(e):
            sys.exit("workspace %s is open in another Vitis (the IDE, or a leftover server).\n"
                     "Close it, or check: pgrep -af 'vitis|rigel'" % workspace)
        raise
    app = client.get_component(name="debris_app")
    app.clean()
    app.build()
finally:
    vitis.dispose()

if not os.path.exists(elf) or (before is not None and os.path.getmtime(elf) <= before):
    sys.exit("build FAILED: %s was not (re)written -- check the build output above" % elf)
print("built %s" % elf)
