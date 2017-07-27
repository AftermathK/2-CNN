package TwoCNA;
import Vector::*;
import SpecialFIFOs::*;
import FIFOF::*;
typedef 0 WAIT_TIME;
//streamSize must always be the product of the kernel's dimensions
interface TwoCNA#(type operandType, numeric type kernelSize, numeric type streamSize);
    method Action cleanAccel(); 
    method Action initHorizontal(Vector#(kernelSize, Vector#(kernelSize, operandType)) inputKernel); 
	method  operandType isReady();	
	method  operandType hasInit();	
	method Action request(Vector#(kernelSize, operandType) req);
    method ActionValue#(operandType) response;

endinterface
module mkTwoCNA(TwoCNA#(operandType, kernelSize,streamSize)) provisos (Bits#(operandType, a__), Arith#(operandType), Literal#(operandType));
	//if initializing
	Reg#(Bool) isInit <- mkReg(False);
        
	//how long have we waited
	Reg#(Bit#(32)) currWait <- mkReg(0);
	//horizontal queue vector
    Vector#(streamSize, FIFOF#(operandType)) horizontalStream <- replicateM(mkLFIFOF);
		
    //depth of the adder tree
    //log3(kernelSize^2)+1
    Integer depthSize = log2(valueOf(kernelSize)*valueOf(kernelSize)) / log2(3) + 1;
    
    //product of kernel's dimensions
    Integer kernelPD = valueOf(kernelSize)*valueOf(kernelSize);

	Vector#(kernelSize, Reg#(Vector#( kernelSize, operandType))) kernel <- replicateM(mkReg(replicate(0))); 
	
	//tree queue vector of vectors-may seem as a waste of space but compiler will handle 
    //vector of size::: log3(kernelSize^2)+1 * kernelSize^2
    Vector#(TAdd#(TDiv#(TLog#(TMul#(kernelSize,kernelSize)),TLog#(3)),1), Vector#(TMul#(kernelSize, kernelSize), FIFOF#(operandType))) adderTree;
    for(Integer m=0; m<depthSize; m=m+1) begin
		adderTree[m] <-replicateM(mkLFIFOF);
	end
	    


	//construct the adder trees rules 
    Integer currentPower = valueOf(kernelSize)*valueOf(kernelSize);
	Integer addRange = currentPower-3; //how far will we have to do allow a level to add all the numbers
    for(Integer i=0; i<depthSize; i=i+1) begin
        for(Integer j=0; j <= addRange; j=j+3) begin
		    rule adderTreeRules;
                //$display("Pushing in %d at level: %d in FIFO: %d", adderTree[i][j].first() + adderTree[i][j+1].first(), i+1,j/2);
                adderTree[i+1][j/3].enq(adderTree[i][j].first() + adderTree[i][j+1].first() + adderTree[i][j+2].first());
                adderTree[i][j].deq();
                adderTree[i][j+1].deq();
                adderTree[i][j+2].deq();
            endrule
        end
	    currentPower = currentPower/3;
	    addRange = currentPower-3;
    end 
     
    //create all of the rules needed for the top horizontal stream
    Integer currLeaf = 0;
    //i-->number of rows in kernel
    //j-->number of columns in kernel
    for(Integer i=0; i<=valueOf(kernelSize)-1; i=i+1) begin
        for(Integer j=0; j<=valueOf(kernelSize)-1; j=j+1) begin 
            rule streamRules;
                if(currLeaf%valueOf(kernelSize) == 0) begin
			        //$display("Dequeuing from FIFO: %d", i);
                    //perform multiplications needed here
                    adderTree[0][currLeaf].enq(horizontalStream[currLeaf].first()*kernel[i][j]); 
		    	    //$display("Pushing %d into adder tree [0, %d]", horizontalStream[i].first()*kernel[i], i);
                    horizontalStream[currLeaf].deq();
                end
                else begin
                    //$display("Pushing %d into FIFO: %d", horizontalStream[i].first(),i+1);
			        //$display("Dequeuing from FIFO: %d", i);
                    horizontalStream[currLeaf-1].enq(horizontalStream[currLeaf].first());
                    //perform multiplications needed here
		    	    //$display("Pushing %d into adder tree [0, %d]", horizontalStream[i].first()*kernel[i], i);
                    adderTree[0][currLeaf].enq(horizontalStream[currLeaf].first()*kernel[i][j]); 
                    horizontalStream[currLeaf].deq();
                end
            endrule
            currLeaf = currLeaf+1;
        end
    end 

    //clear() each FIFO
    method Action cleanAccel();
        /* 
	    if(currWait == fromInteger(valueOf(WAIT_TIME))) begin
			currWait <= 0;
		end
        */
        //clear the horizontal stream's FIFOs
        for(Integer i=0; i<valueOf(streamSize);i=i+1) begin
            horizontalStream[i].clear();
        end
                
        Integer currPower = valueOf(kernelSize)*valueOf(kernelSize);
	    Integer addR = currPower-3; //how far will we have to do allow a level to add all the numbers
        //clear the tree of FIFOs 
        
        for(Integer i=0; i<depthSize; i=i+1) begin
            for(Integer j=0; j <= addR; j=j+3) begin
                adderTree[i][j].clear(); 
                adderTree[i][j+1].clear(); 
                adderTree[i][j+2].clear(); 
            end
	        currPower = currPower/3;
	        addR = currPower-3;
        end 
    endmethod
	//method for initiating variables
	method Action initHorizontal(Vector#(kernelSize, Vector#(kernelSize, operandType)) kernelInput);
		writeVReg(kernel,kernelInput);
	    currWait <= 0;	
        isInit <= True;	
		for(Integer i=0; i<valueOf(kernelSize)*valueOf(kernelSize); i=i+1) begin
			horizontalStream[i].enq(0);
		end		
         
	endmethod            
        //methods for interaction with accelerator
	method operandType isReady();
		if(currWait < fromInteger(valueOf(WAIT_TIME))) begin
			return 0;
		end							
		else begin
			return 1;
		end	
	endmethod	
	method operandType hasInit();
		if(isInit)begin
			return 1;
		end							
		else begin
			return 0;
		end	
	endmethod	
	method Action request(Vector#(kernelSize, operandType) req);
        for(Integer i=0; i<valueOf(kernelSize); i=i+1) begin
            horizontalStream[(i+1)*valueOf(kernelSize)-1].enq(req[i]);  
        end
    endmethod

    method ActionValue#(operandType) response();
	    if(currWait != fromInteger(valueOf(WAIT_TIME))) begin
			currWait <= currWait + 1;
		end		                
        adderTree[depthSize-1][0].deq();
        return adderTree[depthSize-1][0].first();
    endmethod           
endmodule
endpackage
