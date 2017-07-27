package TCNWMem;
import Vector::*;
import FIFOF::*;
import FIFO::*;
import FIFOG::*;
import FIFOLevel::*;
import TwoCNA::*;
import BuildVector::*;
import MemUtil::*;
import Port::*;
import PolymorphicMem::*;
typedef Bit#(32) OperandType;
typedef union tagged {
    void Ready;
    Bit#(32) Resetting;
} BRAMState deriving (Bits, Eq, FShow);
module mkTCNWMem#(CoarseMemServerPort#(32,2) mem)(CoarseMemServerPort#(32,2));
	//instantiate the CA
	//accelOne will always contain its top row with zeros
    TwoCNA#(Bit#(32),3,9) accelOne <- mkTwoCNA;
    
    Reg#(Bit#(32)) inputSize <- mkReg(0);
    Reg#(Bit#(32)) dataSize <- mkReg(0);
    //index corresponding to the location of the accelerator for read values 
    Reg#(Bit#(32)) rowCounter <- mkReg(0);
    //index corresponding to the location of the accelerator for values sent to accel 
    Reg#(Bit#(32)) accelCounter <- mkReg(0);
    //number of requests made to memory
    Reg#(Bit#(32)) memRequests <- mkReg(0);
    //number of responses from memory
    Reg#(Bit#(32)) memResponses <- mkReg(0);
    //number of requests made to RAMs 
    Reg#(Bit#(32)) readRam <- mkReg(0);
    //number of requests sent to accel
    Reg#(Bit#(32)) accelRequests <- mkReg(0);
    Reg#(Bit#(32)) fifoRowCounter <- mkReg(0);
    Reg#(Bit#(32)) fifoColCounter <- mkReg(0);
    
    //Keep track of the read requests sent to memory
    Reg#(Bit#(32)) memReadRequests <- mkReg(0);
    
    //number of requests to BRAMs 
    Reg#(Bit#(32)) inputPointerReg <- mkReg(0); 
    Reg#(Bit#(32)) inputLengthReg <- mkReg(0); 
    Reg#(Bit#(32)) inputRowLengthReg <- mkReg(0); 
    Reg#(Bit#(32)) inputColLengthReg <- mkReg(0); 
    //length of the row with zeros padded (inputRowLengthReg+2) 
    Reg#(Bit#(32)) actualRowLength <- mkReg(0); 
    //number columns in the data 
    Reg#(Bit#(32)) actualColLength <- mkReg(0); 
    Reg#(Bit#(32)) outputPointerReg <- mkReg(0);
    //register used to determine where to store the next row of data 
    Reg#(Bit#(2)) readValueUpNext <- mkReg(0);
    //register used to determine which values from BRAMs to send to accel 
    Reg#(Bit#(2)) accelValueUpNext <- mkReg(0);
    Reg#(Bit#(1)) isInit <- mkReg(0);
    //reset BRAM
    Reg#(Bit#(32)) counterRAM <- mkReg(-1);
    Vector#(3,Reg#(OperandType)) currVec <- replicateM(mkReg(0));
    //load req
    //mem.request.enq(CoarseMemReq { write: False, addr: , data: 0})
    //store req 
    //mem.request.enq(CoarseMemReq { write: True, addr: , data: })
    //receive response 
    //mem.response.first -> returns CoarseMemResp (struct with write: and data:)
	//mem.response.deq()
    Vector#(3, Vector#(3, Reg#(OperandType))) kernel;
    for(Integer m=0; m<3; m=m+1) begin
        kernel[m] <- replicateM(mkReg(0));
    end
    //Vector#(3, Reg#(Vector#(3,OperandType))) kernel <- replicateM(mkReg(replicate(0)));
    //throw away junk values until values are ready
    /*	
    
    rule removeJunk(accelOne.isReady() == 0);
		let temp <- accelOne.response();
	endrule
    */
    //block one
    //memElemOne (memory element 1) 
    CoarseMemServerPort#(32,2) memElemOne <- mkPolymorphicBRAM(1024);
    //memElemTwo (memory element 2) 
    CoarseMemServerPort#(32,2) memElemTwo <- mkPolymorphicBRAM(1024);
    //memElemThree (memory element 3)
    CoarseMemServerPort#(32,2) memElemThree <- mkPolymorphicBRAM(1024);
    //value read from mem 
    FIFOLevelIfc#(Bit#(32), 8) valueFromMem <- mkFIFOLevel();
    //state of the BRAM
    Reg#(BRAMState) state <- mkReg(tagged Resetting 0);
    
    //(* descending_urgency = "writeMemResp, readMemReq" *) 
    //reset BRAMs
    rule resetRAMS(counterRAM <= inputRowLengthReg+2);
        //$display("Resetting BRAMs");
        memElemOne.request.enq(CoarseMemReq{write: True, addr: 4*counterRAM, data: 0}); 
        memElemTwo.request.enq(CoarseMemReq{write: True, addr: 4*counterRAM, data: 0}); 
        memElemThree.request.enq(CoarseMemReq{write: True, addr: 4*counterRAM, data: 0});
        counterRAM <= counterRAM+1;
        if(counterRAM==inputRowLengthReg+2) begin
            isInit <= 1;
        end
    endrule
    
    //send requests to read from memory
    rule readMemReq(memRequests != dataSize && isInit==1 && valueFromMem.isLessThan(4));
        //$display("Sending a memory request");
        mem.request.enq(CoarseMemReq  {write: False, addr: inputPointerReg, data: 0});
        memRequests <= memRequests+1;
        //increment the address of the current pointer to prepare for the next read
        inputPointerReg <= inputPointerReg + 4;
        //memReadRequests <= memReadRequests+1;
    endrule
    //feed value read from memory or feed zeros 
    rule readMemResp((mem.response.first.write == False && isInit==1)||(fifoColCounter >= actualColLength && fifoColCounter < actualColLength+2));
        if(fifoColCounter >= actualColLength) begin
            //$display("Enqueuing zeros");
            valueFromMem.enq(0);
        end
        else if(fifoRowCounter >= inputRowLengthReg) begin
            //feed zeros
            //$display("Enqueuing zeros");
            valueFromMem.enq(0);
            if(fifoRowCounter == inputRowLengthReg+1) begin
                fifoRowCounter <= 0; 
            end
            else begin
                fifoRowCounter <= fifoRowCounter+1;
            end
        end
        else begin
            //feed values read from memory 
            //$display("Enqueuing value read from mem");
            valueFromMem.enq(mem.response.first.data);
            mem.response.deq();
            fifoRowCounter <= fifoRowCounter+1; 
        end
    endrule
    
    //read two values from the previously saved values in BRAMs 
    rule readRAMS(readRam != actualRowLength && isInit==1);
        
        if(readValueUpNext == 0) begin
            //enqueue the request to read from memory
            //$display("Reading memElemOne and memElemTwo"); 
            memElemOne.request.enq(CoarseMemReq{write: False, addr: rowCounter, data: 0});	
            memElemTwo.request.enq(CoarseMemReq{write: False, addr: rowCounter , data: 0});	
        end
        else if(readValueUpNext == 1) begin
            //enqueue the request to read from memory
            //$display("Reading memElemTwo and memElemThree"); 
            memElemTwo.request.enq(CoarseMemReq{write: False, addr: rowCounter, data: 0});	
            memElemThree.request.enq(CoarseMemReq{write: False, addr: rowCounter , data: 0});	
        end
        else begin
            //enqueue the request to read from memory
            //$display("Reading memElemOne and memElemThree"); 
            memElemOne.request.enq(CoarseMemReq{write: False, addr: rowCounter, data: 0});	
            memElemThree.request.enq(CoarseMemReq{write: False, addr: rowCounter , data: 0});	
        end
        
        readRam <= readRam+1; 
        rowCounter <= rowCounter+4;
	endrule
    //change rows
    rule nextRowReq(readRam == actualRowLength && isInit==1);
        //$display("Switching from one read state to another"); 
        //$display("Current number of values left: %d %d", memResponses, inputLengthReg); 
        //$display("fifoColCounter: %d and actualColLength: %d", fifoColCounter, actualColLength); 
        //$display("accelRequests: %d and actualRowLength: %d", accelRequests, actualRowLength); 
        readRam <= 0;
        rowCounter <= 0;
        fifoColCounter <= fifoColCounter+1;  
        readValueUpNext <= (readValueUpNext+1)%3;
    endrule
    rule nextRowAccel(accelRequests == actualRowLength && isInit==1);
        //$display("Switching from one accelerator state to another"); 
        accelCounter <= 0;
        accelRequests <= 0;
        accelValueUpNext <= (accelValueUpNext+1)%3;
    endrule
    
    //send a packet to accelerator 
    rule sendToAccel(accelRequests != actualRowLength && isInit==1);
        if(accelValueUpNext == 0) begin
            let valueOne = memElemOne.response.first.data;
            let valueTwo = memElemTwo.response.first.data;
            let valueThree = valueFromMem.first;
            //$display("One: Sending to accel %d %d %d", valueOne,valueTwo,valueThree);
            valueFromMem.deq();
            memElemOne.response.deq();
            memElemTwo.response.deq();
            memElemThree.request.enq(CoarseMemReq {write: True, addr: accelCounter, data: valueThree});
            //feed the correct values into the accelerator
            currVec[0] <= valueOne; 
            currVec[1] <= valueTwo; 
            currVec[2] <= valueThree; 
            

        end
        else if(accelValueUpNext == 1) begin
            let valueOne = memElemTwo.response.first.data;
            let valueTwo = memElemThree.response.first.data;
            let valueThree = valueFromMem.first;
            //$display("Two: Sending to accel %d %d %d", valueOne,valueTwo,valueThree);
            valueFromMem.deq();
            memElemTwo.response.deq();
            memElemThree.response.deq();
            memElemOne.request.enq(CoarseMemReq {write: True, addr: accelCounter, data: valueThree});
            //feed the correct values into the accelerator
            currVec[0] <= valueOne; 
            currVec[1] <= valueTwo; 
            currVec[2] <= valueThree; 
            

        end
        else begin
            let valueOne = memElemThree.response.first.data;
            let valueTwo = memElemOne.response.first.data;
            let valueThree = valueFromMem.first;
            //$display("Three: Sending to accel %d %d %d", valueOne,valueTwo,valueThree);
            valueFromMem.deq();
            memElemThree.response.deq();
            memElemOne.response.deq();
            memElemTwo.request.enq(CoarseMemReq {write: True, addr: accelCounter, data: valueThree});
            //feed the correct values into the accelerator
            currVec[0] <= valueOne; 
            currVec[1] <= valueTwo; 
            currVec[2] <= valueThree; 
        end
        memReadRequests <= memReadRequests-1;
        accelCounter <= accelCounter+4; 
        accelRequests <= accelRequests+1;
        accelOne.request(readVReg(currVec));
    endrule
    
    //write accelerator's output to memory
    rule writeMemReq(memResponses != inputSize && isInit==1);
		let responseProduced <- accelOne.response();
        //$display("");
        //$display("Value written to mem: %d",responseProduced);
        //$display("Values left: %d", inputLengthReg);
		//enqueue the request to write to memory, but disregard any return values--if any
        mem.request.enq(CoarseMemReq {write: True, addr: outputPointerReg, data: responseProduced});
        //increment the address of the current pointer to prepare for the next write
        outputPointerReg <= outputPointerReg+4;
	endrule
     
    //count the number of writes to memory
    rule writeMemResp(mem.response.first.write == True && memResponses != inputSize && isInit==1);
        //decrese inputLengthReg after a successful write to memory
        //$display("Memory acknowledges write");
        inputLengthReg <= inputLengthReg-1;
        mem.response.deq();
        memResponses <= memResponses+1;
    endrule

    
    //throw away the write responses from each one memory blocks--they're not needed
    //we only care about the read responses
    rule throwOne(memElemOne.response.first.write == True );
        //$display("memelemone write success"); 
        memElemOne.response.deq();
    endrule
    rule throwTwo(memElemTwo.response.first.write == True);
        //$display("memElemTwo write success"); 
        memElemTwo.response.deq();
    endrule
    rule throwThree(memElemThree.response.first.write == True);
        //$display("memElemThree write success"); 
        memElemThree.response.deq();
    endrule
    
    Reg#(Bit#(32)) initReg = (interface Reg;
        method Action _write(Bit#(32) x);
            if (x == 1) begin
                counterRAM <= 0; 
                //how many values are we convolving
                dataSize <= inputRowLengthReg*(inputColLengthReg); 
                inputSize <= (inputRowLengthReg+2)*(inputColLengthReg + 2);
                inputLengthReg <= (inputRowLengthReg+2)*(inputColLengthReg + 2);
                actualRowLength <= inputRowLengthReg+2;
                actualColLength <= inputColLengthReg;
                Vector#(3, Vector#(3, OperandType)) tempKernel;
                tempKernel[0] = readVReg(kernel[0]);
                tempKernel[1] = readVReg(kernel[1]);
                tempKernel[2] = readVReg(kernel[2]);
                accelOne.initHorizontal(tempKernel);
            end
        endmethod
        method Bit#(32) _read();
            return accelOne.hasInit();
        endmethod
    endinterface);
	

    CoarseMemServerPort#(32,2) memoryInterface <- mkPolymorphicMemFromRegs( 
                                    vec( 
                                    asReg(kernel[0][0]), 
                                    kernel[0][1], 
                                    kernel[0][2], 
                                    kernel[1][0], 
                                    kernel[1][1], 
                                    kernel[1][2], 
                                    kernel[2][0], 
                                    kernel[2][1], 
                                    kernel[2][2], 
                                    initReg, 
                                    inputPointerReg,
                                    inputRowLengthReg,
                                    inputLengthReg, 
                                    outputPointerReg,
                                    inputColLengthReg));

    return memoryInterface;
endmodule
endpackage
