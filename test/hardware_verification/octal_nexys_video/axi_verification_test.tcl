proc write_data {address length data} {
    create_hw_axi_txn write_txn [get_hw_axis hw_axi_1] -type write -address $address -len $length -data $data -force
    run_hw_axi [get_hw_axi_txns write_txn]
}

proc read_data {address length} {
    create_hw_axi_txn read_txn [get_hw_axis hw_axi_1] -type read -address $address -len $length -force
    run_hw_axi read_txn
    return [get_property DATA [get_hw_axi_txns read_txn]]
}

## assert function from https://wiki.tcl-lang.org/page/Assertions
proc assert condition {
    if {![uplevel 1 expr $condition]} {
        return -code error "assertion failed: $condition"
    }
}

proc setup_all_zero {} {
    write_data 0 256 0x00000000
}

### ==================
###   Test Functions
### ==================
proc test_write {} {
    setup_all_zero
    set data [read_data  0 4]
    assert {$data == {00000000}}

    write_data 0 3 0x55aa55aa
    set data [read_data  0 4]
    assert {{$data} == "{0000000055aa55aa55aa55aa55aa55aa}"}

    write_data 2 1 0x11111111
    set data [read_data  0 4]
    assert {{$data} == "{0000000055aa55aa55aa1111111155aa}"}
}


### ===================
###   Helper Function
### ===================
# get all test functions and run them
set all_functions [info procs]
foreach name $all_functions {
        if { [string first "test_" $name] != -1 } {
            puts "Running $name"
            $name
        }
    }
