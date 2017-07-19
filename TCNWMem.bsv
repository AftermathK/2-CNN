package TCNWMem;
import Vector::*;
import FIFOF::*;
import FIFO::*;
import FIFOG::*;
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
    //number of requests to BRAMs 
    Reg#(Bit#(2)) bramHold <- mkReg(0);
    Reg#(Bit#(32)) inputPointerReg <- mkReg(0); 
    Reg#(Bit#(32)) inputLengthReg <- mkReg(0); 
    Reg#(Bit#(32)) inputRowLengthReg <- mkReg(0); 
    Reg#(Bit#(32)) outputPointerReg <- mkReg(0);
    //register used to determine where to store the next row of data 
    Reg#(Bit#(2)) valueUpNext <- mkReg(0);
    Reg#(Bit#(1)) isInit <- mkReg(0);
    //reset BRAM
    Reg#(Bit#(32)) currCol<- mkReg(0);
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
    FIFOF#(Bit#(32)) valueFromMem <- mkLFIFOF();
    //state of the BRAM
    Reg#(BRAMState) state <- mkReg(tagged Resetting 0);
    //reset BRAMs
    rule resetRAMS(counterRAM < 1024);
        $display("Resetting BRAMs");
        memElemOne.request.enq(CoarseMemReq{write: True, addr: 4*counterRAM, data: 0}); 
        memElemTwo.request.enq(CoarseMemReq{write: True, addr: 4*counterRAM, data: 0}); 
        memElemThree.request.enq(CoarseMemReq{write: True, addr: 4*counterRAM, data: 0});
        counterRAM <= counterRAM+1;
        if(counterRAM==1023) begin
            isInit <= 1;
        end
    endrule
    /*
    rule resetRAMS if(state matches tagged Resetting .index);
        $display("Resetting BRAMs");
        memElemOne.request.enq(CoarseMemReq{write: True, addr: index, data: 0}); 
        memElemTwo.request.enq(CoarseMemReq{write: True, addr: index, data: 0}); 
        memElemThree.request.enq(CoarseMemReq{write: True, addr: index, data: 0});
        if(index != 0) begin
            state <= tagged Resetting (index+4);
        end else begin
            state <= tagged Ready;
        end
    endrule
    */
    
    //send requests to read from memory
    rule readMemReq(memRequests != inputSize && isInit==1);
        mem.request.enq(CoarseMemReq  {write: False, addr: inputPointerReg, data: 0});
        memRequests <= memRequests+1;
        //increment the address of the current pointer to prepare for the next read
        inputPointerReg <= inputPointerReg + 4;
    endrule
    //save value read from memory 
    rule readMemResp(mem.response.first.write == False && isInit==1);
        valueFromMem.enq(mem.response.first.data);
        mem.response.deq();
    endrule
    
    //read two values from the previously saved values in BRAMs 
    rule readMemOne(valueUpNext==0 && readRam != inputRowLengthReg && isInit==1);
        $display("Sending read requests: One"); 
        //enqueue the request to read from memory
	    memElemOne.request.enq(CoarseMemReq{write: False, addr: rowCounter, data: 0});	
	    memElemTwo.request.enq(CoarseMemReq{write: False, addr: rowCounter , data: 0});	
        readRam <= readRam+1; 
        rowCounter <= rowCounter+4;
	endrule
    rule readMemTwo(valueUpNext==1 && readRam != inputRowLengthReg && isInit==1);
        $display("Sending read requests: One"); 
        //enqueue the request to read from memory
	    memElemTwo.request.enq(CoarseMemReq{write: False, addr: rowCounter, data: 0});	
	    memElemThree.request.enq(CoarseMemReq{write: False, addr: rowCounter , data: 0});	
        readRam <= readRam+1; 
        rowCounter <= rowCounter+4;
        
	endrule
    rule readMemThree(valueUpNext==2 && readRam != inputRowLengthReg && isInit==1);
        $display("Sending read requests: One"); 
        //enqueue the request to read from memory
	    memElemOne.request.enq(CoarseMemReq{write: False, addr: rowCounter, data: 0});	
	    memElemThree.request.enq(CoarseMemReq{write: False, addr: rowCounter , data: 0});	
        readRam <= readRam+1; 
        rowCounter <= rowCounter+4;
        
	endrule
    //change rows
    rule nextRow(readRam == inputRowLengthReg && isInit==1);
        readRam <= 0;
        rowCounter <= 0;
        valueUpNext <= (valueUpNext+1)%3;
    endrule
    //send a packet to accelerator 
    rule sendToAccelOne(valueUpNext==0 && accelRequests != inputRowLengthReg && isInit==1);
        let valueOne = memElemOne.response.first.data;
        let valueTwo = memElemTwo.response.first.data;
        let valueThree = valueFromMem.first;
        valueFromMem.deq();
        memElemOne.response.deq();
        memElemTwo.response.deq();
        memElemThree.request.enq(CoarseMemReq {write: True, addr: accelCounter, data: valueThree});
        accelCounter <= accelCounter+4;
        accelRequests <= accelRequests+1;
        //feed the correct values into the accelerator
        currVec[0] <= valueOne; 
        currVec[1] <= valueTwo; 
        currVec[2] <= valueThree; 
        $display("One: Sending packet: %d %d %d to accel.",valueOne,valueTwo,valueThree);
        accelOne.request(readVReg(currVec));
    endrule
    //send a packet to accelerator 
    rule sendToAccelTwo(valueUpNext==1 && accelRequests != inputRowLengthReg && isInit==1);
        let valueOne = memElemTwo.response.first.data;
        let valueTwo = memElemThree.response.first.data;
        let valueThree = valueFromMem.first;
        valueFromMem.deq();
        memElemTwo.response.deq();
        memElemThree.response.deq();
        memElemOne.request.enq(CoarseMemReq {write: True, addr: accelCounter, data: valueThree});
        accelCounter <= accelCounter+4; 
        accelRequests <= accelRequests+1;
        //feed the correct values into the accelerator
        currVec[0] <= valueOne; 
        currVec[1] <= valueTwo; 
        currVec[2] <= valueThree; 
        $display("One: Sending packet: %d %d %d to accel.",valueOne,valueTwo,valueThree);
        accelOne.request(readVReg(currVec));
    endrule
    //send a packet to accelerator 
    rule sendToAccelThree(valueUpNext==2 && accelRequests != inputRowLengthReg && isInit==1);
        let valueOne = memElemThree.response.first.data;
        let valueTwo = memElemOne.response.first.data;
        let valueThree = valueFromMem.first;
        valueFromMem.deq();
        memElemThree.response.deq();
        memElemOne.response.deq();
        memElemTwo.request.enq(CoarseMemReq {write: True, addr: accelCounter, data: valueThree});
        accelCounter <= accelCounter+4; 
        accelRequests <= accelRequests+1;
        //feed the correct values into the accelerator
        currVec[0] <= valueOne; 
        currVec[1] <= valueTwo; 
        currVec[2] <= valueThree; 
        $display("One: Sending packet: %d %d %d to accel.",valueOne,valueTwo,valueThree);
        accelOne.request(readVReg(currVec));
    endrule
    
    //write accelerator's output to memory
    rule writeMemReq(memResponses != inputSize && isInit==1);
		let responseProduced <- accelOne.response();
        $display("");
        $display("Value written to mem: %d",responseProduced);
		//enqueue the request to write to memory, but disregard any return values--if any
        mem.request.enq(CoarseMemReq {write: True, addr: outputPointerReg, data: responseProduced});
        //increment the address of the current pointer to prepare for the next write
        outputPointerReg <= outputPointerReg+4;
	endrule
     
    //count the number of writes to memory
    rule writeMemResp(memResponses != inputSize && isInit==1);
        //decrese inputLengthReg after a successful write to memory
        inputLengthReg <= inputLengthReg-1;
        mem.response.deq();
        memResponses <= memResponses+1;
    endrule

    
    //throw away the write responses from each one memory blocks--they're not needed
    //we only care about the read responses
    rule throwOne(memElemOne.response.first.write == True );
        $display("memelemone write success"); 
        memElemOne.response.deq();
    endrule
    rule throwTwo(memElemTwo.response.first.write == True);
        $display("memElemTwo write success"); 
        memElemTwo.response.deq();
    endrule
    rule throwThree(memElemThree.response.first.write == True);
        $display("memElemThree write success"); 
        memElemThree.response.deq();
    endrule
    
    Reg#(Bit#(32)) initReg = (interface Reg;
        method Action _write(Bit#(32) x);
            if (x == 1) begin
                counterRAM <= 0; 
                //how many values are we convolving
                inputSize <= inputLengthReg;
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
                                    outputPointerReg));

    return memoryInterface;
endmodule
endpackage
