# QSPI Memory Controller
A memory controller with an AXI-Interface for SPI, and PSRAM Devices.

## OWAS Files
For the OWAS chip we want 4 Octal SPI controller in parallel.
For that implementation use these files:
```
./src/OctalMemoryController_quad.v",
./src/AXIInterface.v",
./src/OSPIController_quad.v",
./src/OctalSPI_quad.v",
```
With `OctalMemoryController_quad` as the top of the module.

Leave the parameters in their default:
```
ADDR_WIDTH = 32,
DATA_WIDTH = 32,
STRB_WIDTH = (DATA_WIDTH / 8),
ID_WIDTH = 8,
```
Set the CHIP_TYPE parameter to 1 for simulation or **2 for the hardware verification and tapeout**.
```
CHIP_TYPE = -1    // 1 is Infineon, 2 is APMemory
```

### Code Formating
For Verilog the [Verible formater](https://open-vsx.org/extension/bmpenuelas/systemverilog-formatter-vscode) was used with the settings:
```
"systemverilogFormatter.veribleBuild": "none",
"systemverilogFormatter.commandLineArguments": "--indentation_spaces 4"
```

For python the [Black formater](https://marketplace.visualstudio.com/items?itemName=ms-python.black-formatter) was used with the settings:
```
"black-formatter.args": ["--line-length", "100"]
```