set part_name    "xc7a200tsbg484-1"  
set design_name  [lindex $argv 0]
set src_files    [lrange $argv 1 end]

foreach f $src_files {
    read_verilog $f
}

synth_design -top ${design_name} -part ${part_name} -mode out_of_context -lint
