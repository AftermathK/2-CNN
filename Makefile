
twoCNA:
	mkdir -p build
	bsc -u -sim -simdir build -bdir build -info-dir build -keep-fires -g  mkTbTwoCNA  TwoCNATb.bsv 
	bsc -e mkTbTwoCNA -sim -o ./simTwoCNA -simdir build -bdir build -keep-fires

clean:
	rm -rf build sim* out verilog dump.vcd 
