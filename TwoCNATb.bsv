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
	TwoCNA#(OperandType, KERNEL_SIZE, KERNEL_DIM) nna <- mkTwoCNA;
	
    //test cleanAccel()
    Reg#(Bit#(32)) clean <- mkReg(0);
    Reg#(Bit#(32)) count<- mkReg(0);
	//count the number of cycles
	rule cycle_count;
		cycles <= cycles + 1;
	endrule
	
	rule first(isInit);
		isInit <= False;	
		nna.initHorizontal(kernel);	
	endrule	
	rule request(!isInit && clean==0);
        if(requests>= 0 && requests <=8) begin
            currVec[0] <= operations[0][requests];		
            currVec[1] <= operations[1][requests];		
            currVec[2] <= operations[2][requests];
            nna.request(readVReg(currVec));	
		    requests <= requests+1;
            count <= count + 1;
        end
        else begin
            nna.cleanAccel();
            clean <= 1;
            requests <= 0;
            isInit <= True;
        end
	endrule	
	
	rule respond(!isInit);
		Bit#(32) outputValue <- nna.response();	
		$display("Response Produced: %d and CC: ", outputValue, requests);

	endrule	
	
	rule refresh(clean == 1);
		$display("Total number of cycles needed: %d",cycles);
		$display("Resetting...Starting over...");
        currVec[0] <= 0;		
        currVec[1] <= 0;		
        currVec[2] <= 0;
        clean <= 0;
	endrule
   
    rule finish(count==20);
        $finish(0); 
    endrule
    
endmodule
