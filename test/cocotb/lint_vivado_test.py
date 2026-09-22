from unittest import SkipTest
from pathlib import Path
import yaml
from shutil import which
import subprocess
import pytest


VIVADO_PATH = ""
FILE_TCL_SCRIPT = ""
FILE_YAML_GROUP = ""
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



# check if yaml file is there
FILE_YAML_GROUP = Path("../../lint_groups_config.yml")
if not FILE_YAML_GROUP.exists():
    raise Exception(f"Group yaml not found!")
YAML_GROUP = parse_yaml(FILE_YAML_GROUP)
YAML_TOP = get_tops(YAML_GROUP)


@pytest.mark.parametrize("group", YAML_TOP )
def test_vivado_linting(group):
    print(group)
    # check if vivado is in path
    VIVADO_PATH = which("vivado")
    if VIVADO_PATH is None:
        raise SkipTest(f"Vivado not found!")

    # check if tcl script is there
    FILE_TCL_SCRIPT = Path("./lint_vivado_script.tcl")
    if not FILE_TCL_SCRIPT.exists():
        raise Exception(f"tcl script not found!")
    
    cmd = [
        VIVADO_PATH,
        "-mode", "batch",
        "-source", str(FILE_TCL_SCRIPT),
        "-nolog",
        "-nojournal",
        "-tclargs", group,
    ] + get_files(YAML_GROUP, group)
    
    result = subprocess.run(cmd)
    assert result.returncode == 0


if __name__ == "__main__":
    test_vivado_linting(get_tops(YAML_GROUP))
