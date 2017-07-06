import Vector::*;
import TwoCNA::*;
typedef 7 OFFSET;
typedef 3 KERNEL_SIZE;
typedef 9 KERNEL_DIM;
typedef Bit#(32) OperandType;
module mkTbTwoCNA();
	Reg#(Bit#(64)) cycles <- mkReg(0);
	Reg#(Bit#(64)) requests <- mkReg(0);
	Reg#(Bool) isInit <- mkReg(True);	
        //kernel
    Vector#(KERNEL_SIZE, Vector#(KERNEL_SIZE, OperandType)) kernel = newVector; //adjust later 
	//kernel pattern	
	kernel[0][0] = 4;
	kernel[0][1] = 5;
	kernel[0][2] = 6;
	kernel[1][0] = 0;
	kernel[1][1] = 0;
	kernel[1][2] = 0;
	kernel[2][0] = 3;
	kernel[2][1] = 2;
	kernel[2][2] = 1;
	
    
    //current values fed
    Vector#(3,Reg#(OperandType)) currVec <- replicateM(mkReg(0));
    //vector with 1000 elements
	Vector#(3,Vector#(6, OperandType)) operations = newVector;	

	//vector of correct outputs	
	Vector#(3,Vector#(4, OperandType)) correctOutputs = newVector;	
    /*
    operations[0][0] = 0;
    operations[0][1] = 0;
    operations[0][2] = 0;
    operations[0][3] = 0;
    operations[0][4] = 0;
    operations[0][5] = 0;
    
    operations[1][0] = 1;
    operations[1][1] = 5;
    operations[1][2] = 2;
    operations[1][3] = 3;
    operations[1][4] = 0;
    operations[1][5] = 0;
    */

    operations[0][0] = 8;
    operations[0][1] = 7;
    operations[0][2] = 3;
    operations[0][3] = 6;
    operations[0][4] = 0;
    operations[0][5] = 0;

    operations[1][0] = 3;
    operations[1][1] = 3;
    operations[1][2] = 9;
    operations[1][3] = 1;
    operations[1][4] = 0;
    operations[1][5] = 0;
    
    operations[2][0] = 0;
    operations[2][1] = 0;
    operations[2][2] = 0;
    operations[2][3] = 0;
    operations[2][4] = 0;
    operations[2][5] = 0;
    /* 
    operations[2][0] = 3;
    operations[2][1] = 3;
    operations[2][2] = 9;
    operations[2][3] = 1;
    operations[2][4] = 0;
    operations[2][5] = 0;
    */ 
    /*	
	for(Integer i=0;i<3;i=i+1) begin
	    for(Integer j=0; j<3; j=j+1) begin	
            operations[i][j] = fromInteger(i*j);
        end	
    end
    */	
	TwoCNA#(OperandType, KERNEL_SIZE, KERNEL_DIM) nna <- mkTwoCNA;
	
	//test cases
	//initialize the vector to 0
	/*
    for(Integer j=0;j<1012;j=j+1) begin
			correctOutputs[j] = 0; 	
	end
	*/
    //compute the reference values
    /* 	
    for(Integer j=0;j<100;j=j+1) begin
		for(Integer k=0; k<valueOf(KERNEL_SIZE); k=k+1) begin
			correctOutputs[j+valueOf(OFFSET)] = correctOutputs[j+valueOf(OFFSET)]+(kernel[valueOf(KERNEL_SIZE)-1-k]*operations[j+k]); 	
		end
	end
    */

	//count the number of cycles
	rule cycle_count;
		cycles <= cycles + 1;
	endrule
	
	rule first(isInit);
		isInit <= False;	
		nna.initHorizontal(kernel);	
	endrule	
	rule request(!isInit);
        currVec[0] <= operations[0][requests];		
        currVec[1] <= operations[1][requests];		
        currVec[2] <= operations[2][requests];		
        nna.request(readVReg(currVec));	
		requests <= requests+1;
		//$display("Enqueuing into FIFO: %d", 0);
	endrule	
	
	rule respond(!isInit);
		Bit#(32) outputValue <- nna.response();	
	    //	$display("Response Produced: %d",outputValue);
		/*	
		if(correctOutputs[requests] == outputValue) begin
			$display("PASS");
		end
        */		
        //$display("Was value ready? : %d", nna.isReady());	
		$display("Response Produced: %d and CC: ", outputValue, requests);
		//Bit#(32) temp = correctOutputs[requests];
		//$display("Actual: %d", temp);

	endrule	
	
	rule finish(requests==10);
		$display("Total number of cycles needed: %d",cycles);
		$finish(0);
	endrule

endmodule
