# Memory Model
The memory modles are not distributed with this repository, because they require a login to download.
Here are the download links to the models so you can download them yourself.

[Infineon S25HL512T QSPI](https://www.infineon.com/gated/infineon-s25hl512t-qspi-verilog-model-simulationmodels-en_353680e5-c0c2-4bed-88f8-6f3a0c8b926a)  
[Infineon S26HL512T HyperBus](https://www.infineon.com/gated/infineon-s26hl512t-hyperbus-verilog-model-simulationmodels-en_b4bcb92d-4d16-4c0c-ac36-721c32f343a8)  
[Infineon Octal SPI Model](https://www.infineon.com/gated/infineon-verilog-model-for-octal-spi-interface-simulationmodels-en_d3e0fd9b-b4c1-4165-9fcc-9e936dba99d0)  
[Infineon S27KL0641 Hyperbus (you have to unzip the .exe as well)](https://www.infineon.com/content/dam/infineon/row/public/documents/10/50/infineon-s27kl0641-simulationmodels-en.zip)  
[Microchip 23LC1024 QSPI](https://www.microchip.com/en-us/product/23LC1024#Design%20Resources)  
[Winbond](https://www.winbond.com/hq/support/documentation/?__locale=en&line=/product/customized-memory-solution/index.html&family=/product/customized-memory-solution/psram/index.html&category=/.categories/resources/verilog-model/)  

The infineon models cannot be run by open source simulators, because it uses the `specify` blocks in verilog.
For the Infineon model `s25hl512t` you have to set the parameter `tdevice_CSRBL`, because it is not provided in the files.
```
specparam   tdevice_CSRBL = 1ns;
```
The winbond model is an encrypted `.vp` file, wich can maybe only be run by a cadence simulator?
