from unittest import SkipTest
from pathlib import Path
import yaml
from shutil import which
import subprocess
import pytest
from unittest import SkipTest

"""
lint_vivado_test.py

This script allows pytest to run the vivado lint on the project groups
defined in the lint_groups_config.yml

When run with pytest the output will be in the console,
when run with python, the vivado editor will be opened.
"""


FILE_YAML = Path("../../lint_groups_config.yml")
YAML_TOPS = ""
PATH_TO_SRC_FOLDER = "../../"


def parse_yaml(yaml_path):
    with open(yaml_path, "r") as f:
        file_content = yaml.safe_load(f)

    groups = file_content.get("groups")
    for group in groups:
        for i in range(len(group["files"])):
            group["files"][i] = PATH_TO_SRC_FOLDER + group["files"][i]
    return groups


def get_tops(groups):
    arr = []
    for group in groups:
        arr.append(group["top"])
    print(arr)
    return arr


def get_files(groups, top):
    for group in groups:
        if group["top"] == top:
            return group["files"]


# This code generates the testcases for pytest
if not FILE_YAML.exists():
    raise SkipTest(f"Group yaml file not found!")
YAML_TOPS = get_tops(parse_yaml(FILE_YAML))


@pytest.mark.parametrize("group", YAML_TOPS)
def test_vivado_linting(group, gui=False):
    # check if vivado is in path
    vivado_path = which("vivado")
    if vivado_path is None:
        raise SkipTest(f"Vivado not found!")

    # check if tcl script is there
    file_tcl_script = Path("./lint_vivado_script.tcl")
    if not file_tcl_script.exists():
        raise Exception(f"tcl script not found!")

    parsedYaml = parse_yaml(FILE_YAML)

    cmd = []
    if not gui:
        cmd = [
            vivado_path,
            "-mode",
            "batch",
            "-source",
            str(file_tcl_script),
            "-nolog",
            "-nojournal",
            "-tclargs",
            group,
        ] + get_files(parsedYaml, group)
    else:
        cmd = [
            vivado_path,
            "-source",
            str(file_tcl_script),
            "-nolog",
            "-nojournal",
            "-tclargs",
            group,
        ] + get_files(parsedYaml, group)

    result = subprocess.run(cmd)
    assert result.returncode == 0


if __name__ == "__main__":
    for top in YAML_TOPS:
        test_vivado_linting(top, True)
