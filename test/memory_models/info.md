# Memory Model
The memory modles are not distributed with this repository, because they require a login to download.
Here are the download links to the models so you can download them yourself.

[Infineon S25HL512T QSPI](https://www.infineon.com/gated/infineon-s25hl512t-qspi-verilog-model-simulationmodels-en_353680e5-c0c2-4bed-88f8-6f3a0c8b926a)  
[Infineon S26HL512T HyperBus](https://www.infineon.com/gated/infineon-s26hl512t-hyperbus-verilog-model-simulationmodels-en_b4bcb92d-4d16-4c0c-ac36-721c32f343a8)

The infineon models cannot be run by open source simulators, because it uses the `specify` blocks in verilog.
For the Infineon model `s25hl512t` you have to set the parameter `tdevice_CSRBL`, because it is not provided in the files.
```
specparam   tdevice_CSRBL = 1ns;
```
