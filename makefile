
.PHONY:restore-symbol

TMP_FILE := libMachObjC.a restore-symbol.dSYM/ build/

restore-symbol: 
	rm -f restore-symbol
	xcodebuild -project "restore-symbol.xcodeproj" -target "restore-symbol" -configuration "Release" CONFIGURATION_BUILD_DIR="$(shell pwd)" -jobs 4 build
	rm -rf $(TMP_FILE)
	

clean:
	rm -rf restore-symbol $(TMP_FILE)

