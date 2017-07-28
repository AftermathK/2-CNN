#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
// riscv specific includes
#include "uart.h"
#include "spi.h"
#include "sd.h"
#include "rtc.h"
#include "stats.h"
#include "encoding.h"
#include "printk.h"

#define REPLICATE_4(x) x x x x
#define REPLICATE_16(x) REPLICATE_4(x) REPLICATE_4(x) REPLICATE_4(x) REPLICATE_4(x)
#define REPLICATE_64(x) REPLICATE_16(x) REPLICATE_16(x) REPLICATE_16(x) REPLICATE_16(x)
#define REPLICATE_256(x) REPLICATE_64(x) REPLICATE_64(x) REPLICATE_64(x) REPLICATE_64(x)

// This location will get overwritten, but that's okay
long mem_loc = 0;

void perf_16x16_nop_loop() {
    _start_stats("16x16 nop loop");
    for (int i = 0 ; i < 16 ; i++) {
        REPLICATE_16( asm volatile("nop"); )
    }
    _stop_stats("16x16 nop loop");
}

void perf_256x1_nop_loop() {
    _start_stats("256x1 nop loop");
    for (int i = 0 ; i < 256 ; i++) {
        asm volatile("nop");
    }
    _stop_stats("256x1 nop loop");
}

void perf_16x16_load_loop() {
    unsigned long lw_result;
    _start_stats("16x16 load loop");
    for (int i = 0 ; i < 16 ; i++) {
        REPLICATE_16( asm volatile("lw %0, 0(%1)" : "=r" (lw_result) : "r" (&mem_loc)); );
    }
    _stop_stats("16x16 load loop");
}

void perf_16x16_store_loop() {
    unsigned long lw_result;
    _start_stats("16x16 store loop");
    for (int i = 0 ; i < 16 ; i++) {
        REPLICATE_16( asm volatile("sw %0, 0(%1)" : : "r" (i), "r" (&mem_loc)); );
    }
    _stop_stats("16x16 store loop");
}

void perf_256x1_mret_loop() {
    long i = 256;
    long new_mepc = 0;
    long mstatus_mpp = MSTATUS_MPP;
    _start_stats("256x1 mret loop");
    asm volatile(
            "csrr %1, mstatus;"
            "csrw mscratch, %1;"
            "auipc %1, 0;"
            "addi %1, %1, 20;"
            "csrw mepc, %1;"
            "1: csrs mstatus, %2;"
            "mret;" // mret to pc + 4
            "addi %0, %0, -1;"
            "bgtz %0, 1b;"
            "csrr %1, mscratch;"
            "csrw mstatus, %1;"
        : "+r" (i) : "r" (new_mepc), "r" (mstatus_mpp) );
    _stop_stats("256x1 mret loop");
}

void perf_256x1_ecall_loop() {
    int i = 256;
    int new_mepc = 0;
    long prev_mstatus = 0;
    _start_stats("256x1 ecall loop");
    asm volatile("csrr %0, mstatus" : "+r" (prev_mstatus));
    asm volatile(
            "csrr %1, mtvec;"
            "csrw mscratch, %1;" // save trap handler
            "auipc %1, 0;"
            "addi %1, %1, 16;"
            "csrw mtvec, %1;"
            "1: ecall;" // ecall to pc + 4
            "addi %0, %0, -1;"
            "bgtz %0, 1b;"
            "csrr %1, mscratch;"
            "csrw mtvec, %1;" // restore trap handler
        : "+r" (i) : "r" (new_mepc));
    asm volatile("csrw mstatus, %0" : : "r" (prev_mstatus));
    _stop_stats("256x1 ecall loop");
}

void perf_16x16_uart_out_loop() {
    long i = 16;
    long uart_loc = 0x40000020;
    long print_char = (long) '.';
    long newline_char = (long) '\n';
    _start_stats("16x16 uart out loop");
    asm volatile(
            "1: "
            REPLICATE_16( "sw %0, 0(%2);" )
            "sw %1, 0(%2);"
            "addi %3, %3, -1;"
            "bgtz %3, 1b;"
            : "+r" (print_char), "+r" (newline_char), "+r" (uart_loc), "+r" (i));
    _stop_stats("16x16 uart out loop");
}

void perf_16x16_timer_read_loop() {
    long i = 16;
    long timer_loc = 0x20000008;
    long timer_val = 0;
    _start_stats("16x16 timer read loop");
    asm volatile(
            "1: "
            REPLICATE_16( "lw %0, 0(%2);" )
            "addi %1, %1, -1;"
            "bgtz %1, 1b;"
        : "+r" (timer_val), "+r" (i) : "r" (timer_loc) );
    _stop_stats("16x16 timer read loop");
}

void perf_16x16_timer_write_loop() {
    long i = 16;
    long timer_loc = 0x20000008;
    long timer_val = 0;
    _start_stats("16x16 timer write loop");
    asm volatile(
            "1: "
            REPLICATE_16( "sw %0, 0(%2);" )
            "addi %1, %1, -1;"
            "bgtz %1, 1b;"
        : "+r" (timer_val), "+r" (i) : "r" (timer_loc) );
    _stop_stats("16x16 timer write loop");
}

void perf_sleep_256() {
    _start_stats("sleep(256)");
    sleep(256);
    _stop_stats("sleep(256)");
}

void test_sd_card_read_block_0() {
    _uart_print_string("Initializing SD card\n");
    // targeting 100 kHz clock for initialization
    // 31.25 MHz -> 100 kHz
    int ret = sd_init(156);

    if (ret != 0) {
        _uart_print_string("ERROR: sd_init() failed\n");
        return;
    }

    // full-speed
    _spi_setSclkDiv(1);

    unsigned char data[512];
    ret = sd_readBlock(0, (void*) data);

    if (ret != 0) {
        _uart_print_string("ERROR: sd_readBlock() failed\n");
        return;
    }

    for (int i = 0 ; i < 512 ; i++) {
        if (((i % 16) == 0) && (i != 0)) {
            _uart_print_char('\n');
        } else if (((i % 2) == 0) && (i != 0)) {
            _uart_print_char(' ');
        }
        _uart_print_hex_char(data[i]);
    }
    _uart_print_char('\n');
}

void perf_sd_card_read_bw() {
    _start_stats("32 MB Read from SD Card");
    const int blocks = 32 * 2048;
    unsigned char data[512];
    for (int i = 0 ; i < blocks ; i++) {
        sd_readBlock(i, (void*) data);
    }
    _stop_stats("32 MB Read from SD Card");
}

int main(int argc, char* argv[]) {
    _uart_flush();
    uint32_t val = _divGet();
    printf("The current value for div: %d\n",val);
    uint32_t newDiv = 17;
     _divSet(newDiv);
    _uart_print_string("Performing a two-dimensional convolution\n");
    //initiating a kernel of size 4
    //dimensions of input stream 
    
    /*
     *
     *
     *  rows and columns define a rowsxcolumns input matrix
     *
     *
     */
    uint32_t rows = 30;
    uint32_t columns = 30;
    uint32_t kernel[3][3];
    uint32_t referenceInput[rows+4][columns+4]; 
    uint32_t referenceOutput[rows+2][columns+2];
    for(int i=0; i<rows+4;i++){
        for(int j=0; j<columns+4; j++){
            referenceInput[i][j] = 0;
        }
    }
    /*
     *
     *
     *
     *
     *  3x3 Kernel: The following 2D array will be used to compute a reference solution
     *  and feed into accelerator
     *
     *
     *
     *
     *
     * */
    /*
    kernel[0][0] = 4;
    kernel[0][1] = 5;
    kernel[0][2] = 6;
    kernel[1][0] = 0;
    kernel[1][1] = 0;
    kernel[1][2] = 0;
    kernel[2][0] = 3;
    kernel[2][1] = 2;
    kernel[2][2] = 1;
    */
    /*
    kernel[0][0] = 4999;
    kernel[0][1] = 3451;
    kernel[0][2] = 6357;
    kernel[1][0] = 5437;
    kernel[1][1] = 8341;
    kernel[1][2] = 4581;
    kernel[2][0] = 4513;
    kernel[2][1] = 2191;
    kernel[2][2] = 9999;
    */ 
    kernel[0][0] = 94754999;
    kernel[0][1] = 48733451;
    kernel[0][2] = 19836357;
    kernel[1][0] = 40345437;
    kernel[1][1] = 75108341;
    kernel[1][2] = 47034581;
    kernel[2][0] = 64574513;
    kernel[2][1] = 14802191;
    kernel[2][2] = 74269999;
   
    //define some values for the input stram
    volatile uint32_t stream[rows*columns];
    volatile uint32_t outputStream[(rows+2)*(columns+2)+10];
    //uint32_t reference[104];
    /* 
    referenceInput[2][2] = 1;
    referenceInput[2][3] = 5;
    referenceInput[2][4] = 2;
    referenceInput[2][5] = 3;
    
    referenceInput[3][2] = 8;
    referenceInput[3][3] = 7;
    referenceInput[3][4] = 3;
    referenceInput[3][5] = 6;
    
    referenceInput[4][2] = 3;
    referenceInput[4][3] = 3;
    referenceInput[4][4] = 9;
    referenceInput[4][5] = 1;
    */
    
    //initialize to zero
    for(int i=2; i<rows+2;i++){
        for(int j=2; j<columns+2; j++){ 
            referenceInput[i][j] = i+j-2;
            //printf("%d\t",referenceInput[i][j]);
        }
        //printf("\n");
    }
    int streamCount = 0;
    for(int i=2; i<rows+2;i++){
        for(int j=2; j<columns+2; j++){ 
            stream[streamCount] = i+j-2;
            streamCount++;
        }
    
    }
    /* 
    stream[0] = 1; 
    stream[1] = 5; 
    stream[2] = 2; 
    stream[3] = 3; 
    
    stream[4] = 8; 
    stream[5] = 7; 
    stream[6] = 3; 
    stream[7] = 6; 
    
    stream[8] = 3; 
    stream[9] = 3;
    stream[10] = 9;
    stream[11] = 1;
    */ 
    //_uart_flush();
    printf("\n");
    printf("Output Matrix Produced Sequentially\n");
    long clockBegin = _get_cycles();
    for(int i=1; i<=rows+2; i++){
        for(int j=1; j<=columns+2; j++){
            referenceOutput[i-1][j-1] = kernel[0][0]*referenceInput[i-1][j-1]+
                                        kernel[0][1]*referenceInput[i-1][j]+
                                        kernel[0][2]*referenceInput[i-1][j+1]+
                                        kernel[1][0]*referenceInput[i][j-1] + 
                                        kernel[1][1]*referenceInput[i][j]+
                                        kernel[1][2]*referenceInput[i][j+1]+
                                        kernel[2][0]*referenceInput[i+1][j-1] + 
                                        kernel[2][1]*referenceInput[i+1][j]+
                                        kernel[2][2]*referenceInput[i+1][j+1];

            //_uart_flush();
        }
    }
    long clockEnd =_get_cycles();
    for(int i=1; i<=rows+2; i++){
        for(int j=1; j<=columns+2; j++){
            //printf("%d\t",referenceOutput[i-1][j-1]);
            //_uart_flush();
        }
        //printf("\n");
    }
    long clockNum = clockEnd-clockBegin;
    printf("Number of CCs from sequential 2D convolution: %d\n",clockNum); 
    
    //_uart_flush();
    int currValue = 0;
    //calculating the convolution for 100 values coming through the input stream
    
    //printf("Number of CCs for sequential convolution: %d\n",clockNum); 
    //---------------------------initiate the Convolution Accelerator------------------------
    //---------------------------initiate the Convolution Accelerator------------------------
    //---------------------------initiate the Convolution Accelerator------------------------
    //---------------------------initiate the Convolution Accelerator------------------------
    //---------------------------initiate the Convolution Accelerator------------------------
    //---------------------------initiate the Convolution Accelerator------------------------
    //MAPPINGS:
    //KERNEL[0][0] = 0x00
    //KERNEL[0][1] = 0x04
    //KERNEL[0][2] = 0x08
    //KERNEL[1][0] = 0x0C
    //KERNEL[1][1] = 0x10
    //KERNEL[1][2] = 0x14
    //KERNEL[2][0] = 0x18
    //KERNEL[2][1] = 0x1C
    //KERNEL[2][2] = 0x20
    //initReg   = 0x24
    //inputPointerReg = 0x28
    //inputRowLengthReg = 0x2C
    //inputLengthReg = 0x30
    //outputPointerReg = 0x34

    //set a pointer to the correct base memory location
    volatile uint32_t *acc = (uint32_t *)0x30020000;
    //TODO:set correct output addresses
    acc[0] = kernel[0][0]; 
    acc[1] = kernel[0][1]; 
    acc[2] = kernel[0][2]; 
    acc[3] = kernel[1][0]; 
    acc[4] = kernel[1][1]; 
    acc[5] = kernel[1][2]; 
    acc[6] = kernel[2][0]; 
    acc[7] = kernel[2][1]; 
    acc[8] = kernel[2][2]; 
    //inputPointerReg
    acc[10] = (uint32_t)stream;; 
    //inputRowLenghReg
    acc[11] = (uint32_t)columns; 
    //inputLenghReg
    acc[12] = (uint32_t)columns*rows; 
    //outputPointerReg
    acc[13] = (uint32_t)outputStream;
    acc[14] = (uint32_t)rows;
    //initiate the accelerator
    /* 
    printf("acc[0]: %d\n",*(acc)); 
    printf("acc[1]: %d\n",*(acc+1)); 
    printf("acc[2]: %d\n",*(acc+2)); 
    printf("acc[3]: %d\n",*(acc+3)); 
    printf("acc[4]: %d\n",*(acc+4)); 
    printf("acc[5]: %d\n",*(acc+5)); 
    printf("acc[6]: %d\n",*(acc+6)); 
    printf("acc[7]: %d\n",*(acc+7)); 
    printf("acc[8]: %d\n",*(acc+8)); 
    printf("acc[9]: %d\n",*(acc+9)); 
    printf("acc[10]: %d\n",*(acc+10)); 
    printf("acc[11]: %d\n",*(acc+11)); 
    printf("acc[12]: %d\n",*(acc+12)); 
    printf("acc[13]: %d\n",*(acc+13)); 
    printf("\n");*/ 
    acc[9] = 1;
    //curr outputStream index
    //int currOutputIndex = 0; 
    //send data to the accelerator

    //-----------ACCELERATOR BEGIN
    clockBegin =_get_cycles();
    while(acc[12] != 0){
        //wait for accelerator to finish        
    }
    //printf("%d\n",acc[12]);
    clockEnd =_get_cycles();
    long clockNum2 = clockEnd-clockBegin;
    //--------------ACCELERATOR END 
    //iterate over the values produced by the accelerator and print them
    int pointerAddress = 2; 
    /* 
    for(int p=2; p<33; p++){
        printf("Value found at outputStream[%d] = %d\n", p,outputStream[p]);
    }*/
    //_uart_flush();
    printf("\n");
    printf("Output Matrix Produced by Accelerator\n");
    for(int i=0; i<rows+2; i++){
        for(int j=0; j<columns+2; j++){
            //printf("%d\t",outputStream[pointerAddress]);
            //_uart_flush();
            pointerAddress++;
        }
        //printf("\n");
    } 
    //_uart_flush();
    printf("Number of CCs for accelerator convolution: %d\n",clockNum2); 
    printf("\n");
    pointerAddress = 2; 
    //_uart_flush();
    int notPassed = 0; 
    for(int i=0; i<rows+2; i++){
        for(int j=0; j<columns+2; j++){
            if(outputStream[pointerAddress] == referenceOutput[i][j]){ 
                //printf("PASSED\t");
                //_uart_flush();
            }
            else{
                notPassed++;
            }
            pointerAddress++;
        }
        printf("\n");
        //printf("The current value for div: %d\n",newDiv);
       //printf("Current value produced sequentially: %d \n", reference[i]);
       /*
       if(reference[i] == outputStream[i]){
          printf("PASSED\n");
       }
       */
    } 
    printf("\n");
    printf("Failed Entries: %d\n",notPassed);
    printf("Accelerator to Sequential Executions ClockCycle Ratio: %d\n",clockNum/clockNum2); 
    //_uart_flush();
    return 0;
}
