List=(
        testbench_spi_read_write
    )

rm tests_output.txt
touch tests_output.txt

for test in ${List[*]} 
    do
        make TESTBENCH_NAME=$test | tee -a tests_output.txt
    done

echo
echo Total number of tests: ${#List[@]}
echo Failing tests: $( grep -o 'Fatal' tests_output.txt | wc -l )
echo Succeding test: $( grep -o 'OK' tests_output.txt | wc -l )
echo See output in ./tests_output.txt
