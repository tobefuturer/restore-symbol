
.PHONY:restore-symbol

TMP_FILE := libMachObjC.a restore-symbol.dSYM/ build/ class-dump/build/

restore-symbol: 
	rm -rf $(TMP_FILE) 
	rm -f restore-symbol
	git submodule update --init --recursive
	xcodebuild -project "restore-symbol.xcodeproj" -target "restore-symbol" -configuration "Release" CONFIGURATION_BUILD_DIR="$(shell pwd)" -jobs 4 build
	rm -rf $(TMP_FILE)
	

clean:
	rm -rf restore-symbol $(TMP_FILE)

