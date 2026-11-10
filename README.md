# QSPI Memory Controller
A memory controller with an AXI-Interface for SPI devices.  
Currently OSPI PSRAM is supported by the `OctalMemoryController` module and SPI/QSPI by the `QuadMemoryController` in the `./src/` folder. 

## Timing Constraints
> [!IMPORTANT]
> For the OSPI data transfer to work, you need to propperly set up your timing constraints.

The Octal SPI interface runns on dual data without any DDR macro.  
You can find some examples in the `/test/hardware_verification/` folder.
In simulation, the octal data out has to be delayed relative to the bus clock.

At the moment the OSPI memory controller has a valid bitstream with an 50MHz system clock.
This gives a transfer speed of 47MiB/sec.

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