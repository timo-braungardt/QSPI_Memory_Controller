# Commands to use the JTAG-AXI transaction generator

Create the transaction types with:  
```
create_hw_axi_txn write_txn [get_hw_axis hw_axi_1] -type write \
-address 00000000 -len 1 -data {11111111}

create_hw_axi_txn read_txn [get_hw_axis hw_axi_1] -type read \
-address 00000000 -len 4
```

Run an transaciton with:  
```
run_hw_axi [get_hw_axi_txns write_txn_4]

run_hw_axi [get_hw_axi_txns write_txn_x]

run_hw_axi [get_hw_axi_txns read_txn]
```
