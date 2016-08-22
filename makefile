
.PHONY:restore-symbol
restore-symbol: 
	rm restore-symbol
	xcodebuild -project "restore-symbol.xcodeproj" -target "restore-symbol" -configuration "Release" CONFIGURATION_BUILD_DIR="$(shell pwd)" -jobs 4 build
	rm -rf libMachObjC.a restore-symbol.dSYM/
	

clean:
	rm -rf restore-symbol libMachObjC.a restore-symbol.dSYM/

