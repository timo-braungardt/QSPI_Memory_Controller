import os
from pathlib import Path
from cocotb_tools.runner import get_runner


def test_my_design_runner():
    sim = os.getenv("SIM", "icarus")

    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "../src/my_design.v"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="my_design",
    )

    runner.test(hdl_toplevel="my_design", test_module="test_my_design,")


if __name__ == "__main__":
    test_my_design_runner()
