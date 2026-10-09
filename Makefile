CC = gcc
ARCH ?= ppc
DEPLOYMENT_TARGET ?= 10.3
OBJCFLAGS ?= -O2 -Wall -std=gnu99
CFLAGS ?= -O2 -Wall -std=gnu99
OBJC_EXCEPTION_FLAGS = -fobjc-exceptions
ifeq ($(ARCH),ppc)
TARGETFLAGS = -mcpu=750 -mno-altivec
endif
XML_LIBS ?= -lxml2
ifeq ($(ARCH),ppc)
XML_CFLAGS ?= -I/usr/include/libxml2
else
XML_CFLAGS ?= -I$(shell xcrun --show-sdk-path)/usr/include/libxml2
endif
APP = build/$(ARCH)/HomeBankPanther.app
VERSION = 0.4.0
HTTPS_PREFIX ?= $(HOME)/homebank-https-sources/out/$(ARCH)
DRIVE_CFLAGS = -I$(HTTPS_PREFIX)/include -Ivendor/cjson -DCJSON_NESTING_LIMIT=64
DRIVE_LIBS = $(HTTPS_PREFIX)/lib/libwolfssl.a -framework Security
DRIVE_SOURCES = src/HBDrive.m src/HBJournal.m
C_SOURCES = src/HBXML.c vendor/cjson/cJSON.c
XML_OBJECT = build/$(ARCH)/HBXML.o
CJSON_OBJECT = build/$(ARCH)/cJSON.o
WALLET_SOURCES = src/HBWallet.m src/HBWalletStore.m src/HBWalletEditing.m src/HBWalletCalendar.m
SOURCES = src/main.m src/HBApplication.m src/HBOperationEditor.m src/HBCalendarWindow.m src/HBDrivePanel.m $(WALLET_SOURCES) $(DRIVE_SOURCES)
HEADERS = $(wildcard src/*.h)

.PHONY: all test benchmark package source-package clean drive-check drive-tools-prepare drive-resources original-compat-test mixed-xml-test
all: $(APP)/Contents/MacOS/HomeBankPanther drive-resources

$(XML_OBJECT): src/HBXML.c src/HBXML.h
	mkdir -p build/$(ARCH)
	MACOSX_DEPLOYMENT_TARGET=$(DEPLOYMENT_TARGET) $(CC) -arch $(ARCH) $(TARGETFLAGS) $(CFLAGS) $(XML_CFLAGS) -c $< -o $@

$(CJSON_OBJECT): vendor/cjson/cJSON.c vendor/cjson/cJSON.h
	mkdir -p build/$(ARCH)
	MACOSX_DEPLOYMENT_TARGET=$(DEPLOYMENT_TARGET) $(CC) -arch $(ARCH) $(TARGETFLAGS) $(CFLAGS) -Ivendor/cjson -DCJSON_NESTING_LIMIT=64 -c $< -o $@

$(APP)/Contents/MacOS/HomeBankPanther: $(SOURCES) $(HEADERS) $(XML_OBJECT) $(CJSON_OBJECT) resources/Info.plist $(HTTPS_PREFIX)/lib/libwolfssl.a $(HTTPS_PREFIX)/include/wolfssl/options.h
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	test -f "$(HTTPS_PREFIX)/lib/libwolfssl.a" || { printf '%s\n' 'Construire le kit HTTPS et definir HTTPS_PREFIX vers out/ppc.'; exit 1; }
	MACOSX_DEPLOYMENT_TARGET=$(DEPLOYMENT_TARGET) $(CC) -arch $(ARCH) $(TARGETFLAGS) $(OBJCFLAGS) $(OBJC_EXCEPTION_FLAGS) $(XML_CFLAGS) $(DRIVE_CFLAGS) -framework Cocoa $(SOURCES) $(XML_OBJECT) $(CJSON_OBJECT) $(XML_LIBS) $(DRIVE_LIBS) -o $@
	cp resources/Info.plist $(APP)/Contents/Info.plist
	printf 'APPLHBPW' > $(APP)/Contents/PkgInfo

drive-resources: $(APP)/Contents/MacOS/HomeBankPanther
	/bin/sh scripts/check-architecture.sh $(ARCH) "$(HTTPS_PREFIX)/bin/curl"
	mkdir -p $(APP)/Contents/Resources/Drive $(APP)/Contents/Resources/Licenses
	cp "$(HTTPS_PREFIX)/bin/curl" $(APP)/Contents/Resources/Drive/curl
	cp "$(HTTPS_PREFIX)/share/cacert.pem" $(APP)/Contents/Resources/Drive/cacert.pem
	cp resources/licenses/* $(APP)/Contents/Resources/Licenses/
	cp vendor/cjson/LICENSE $(APP)/Contents/Resources/Licenses/CJSON-LICENSE.txt

TEST_SOURCES = tests/WalletTests.m tests/EditingTests.m tests/CalendarTests.m tests/PantherString.m
build/$(ARCH)/wallet-tests: $(TEST_SOURCES) tests/PantherString.h $(WALLET_SOURCES) src/HBWallet.h $(XML_OBJECT)
	mkdir -p build/$(ARCH)
	MACOSX_DEPLOYMENT_TARGET=$(DEPLOYMENT_TARGET) $(CC) -arch $(ARCH) $(TARGETFLAGS) $(OBJCFLAGS) $(OBJC_EXCEPTION_FLAGS) $(XML_CFLAGS) -Isrc -framework Foundation $(WALLET_SOURCES) $(TEST_SOURCES) $(XML_OBJECT) $(XML_LIBS) -o $@

build/$(ARCH)/drive-tests: tests/DriveTests.m tests/PantherString.m tests/PantherString.h $(DRIVE_SOURCES) $(WALLET_SOURCES) $(HEADERS) $(XML_OBJECT) $(CJSON_OBJECT) tests/fixtures/drive-rsa-test-key.txt $(HTTPS_PREFIX)/lib/libwolfssl.a $(HTTPS_PREFIX)/include/wolfssl/options.h
	mkdir -p build/$(ARCH)
	MACOSX_DEPLOYMENT_TARGET=$(DEPLOYMENT_TARGET) $(CC) -arch $(ARCH) $(TARGETFLAGS) $(OBJCFLAGS) $(OBJC_EXCEPTION_FLAGS) $(XML_CFLAGS) $(DRIVE_CFLAGS) -Isrc -framework Foundation $(WALLET_SOURCES) $(DRIVE_SOURCES) tests/DriveTests.m tests/PantherString.m $(XML_OBJECT) $(CJSON_OBJECT) $(XML_LIBS) $(DRIVE_LIBS) -o $@

build/$(ARCH)/drive-application-tests: tests/DriveApplicationTests.m $(filter-out src/main.m,$(SOURCES)) $(HEADERS) $(XML_OBJECT) $(CJSON_OBJECT) $(HTTPS_PREFIX)/lib/libwolfssl.a $(HTTPS_PREFIX)/include/wolfssl/options.h
	mkdir -p build/$(ARCH)
	MACOSX_DEPLOYMENT_TARGET=$(DEPLOYMENT_TARGET) $(CC) -arch $(ARCH) $(TARGETFLAGS) $(OBJCFLAGS) $(OBJC_EXCEPTION_FLAGS) $(XML_CFLAGS) $(DRIVE_CFLAGS) -Isrc -framework Cocoa $(filter-out src/main.m,$(SOURCES)) tests/DriveApplicationTests.m $(XML_OBJECT) $(CJSON_OBJECT) $(XML_LIBS) $(DRIVE_LIBS) -o $@

build/$(ARCH)/xml-tests: tests/XMLTests.c $(XML_OBJECT) src/HBXML.h
	mkdir -p build/$(ARCH)
	MACOSX_DEPLOYMENT_TARGET=$(DEPLOYMENT_TARGET) $(CC) -arch $(ARCH) $(TARGETFLAGS) $(CFLAGS) $(XML_CFLAGS) -Isrc tests/XMLTests.c $(XML_OBJECT) $(XML_LIBS) -o $@

build/$(ARCH)/performance-tests: tests/PerformanceTests.m $(WALLET_SOURCES) $(DRIVE_SOURCES) $(HEADERS) $(XML_OBJECT) $(CJSON_OBJECT)
	mkdir -p build/$(ARCH)
	MACOSX_DEPLOYMENT_TARGET=$(DEPLOYMENT_TARGET) $(CC) -arch $(ARCH) $(TARGETFLAGS) $(OBJCFLAGS) $(OBJC_EXCEPTION_FLAGS) $(XML_CFLAGS) $(DRIVE_CFLAGS) -Isrc -framework Foundation $(WALLET_SOURCES) $(DRIVE_SOURCES) tests/PerformanceTests.m $(XML_OBJECT) $(CJSON_OBJECT) $(XML_LIBS) $(DRIVE_LIBS) -o $@

benchmark: build/$(ARCH)/performance-tests
	./build/$(ARCH)/performance-tests

build/$(ARCH)/journal-tests: tests/JournalTests.m $(WALLET_SOURCES) $(DRIVE_SOURCES) $(HEADERS) $(XML_OBJECT) $(CJSON_OBJECT)
	mkdir -p build/$(ARCH)
	MACOSX_DEPLOYMENT_TARGET=$(DEPLOYMENT_TARGET) $(CC) -arch $(ARCH) $(TARGETFLAGS) $(OBJCFLAGS) $(OBJC_EXCEPTION_FLAGS) $(XML_CFLAGS) $(DRIVE_CFLAGS) -Isrc -framework Foundation $(WALLET_SOURCES) $(DRIVE_SOURCES) tests/JournalTests.m $(XML_OBJECT) $(CJSON_OBJECT) $(XML_LIBS) $(DRIVE_LIBS) -o $@

test: build/$(ARCH)/wallet-tests build/$(ARCH)/drive-tests build/$(ARCH)/drive-application-tests build/$(ARCH)/xml-tests build/$(ARCH)/journal-tests
	./build/$(ARCH)/wallet-tests tests/demo.xhb
	./build/$(ARCH)/drive-tests
	./build/$(ARCH)/drive-application-tests
	./build/$(ARCH)/xml-tests
	./build/$(ARCH)/journal-tests
	/bin/sh tests/HttpsCheckTests.sh
	/bin/sh tests/HttpsBuildTests.sh

# Exercise an old-header/new-runtime combination without replacing system libxml.
LEGACY_XML_CFLAGS ?=
mixed-xml-test:
	test -n "$(LEGACY_XML_CFLAGS)" || { printf '%s\n' 'Definir LEGACY_XML_CFLAGS vers les en-tetes libxml2 historiques.'; exit 1; }
	mkdir -p build/$(ARCH)
	MACOSX_DEPLOYMENT_TARGET=$(DEPLOYMENT_TARGET) $(CC) -arch $(ARCH) $(TARGETFLAGS) $(CFLAGS) $(LEGACY_XML_CFLAGS) -Isrc src/HBXML.c tests/XMLTests.c $(XML_LIBS) -o build/$(ARCH)/mixed-xml-tests
	./build/$(ARCH)/mixed-xml-tests

# Optional validation on a host with GLib; never a dependency of the PPC app.
GLIB_CFLAGS ?=
GLIB_LIBS ?= -lglib-2.0
build/original-homebank-probe: tests/OriginalHomeBankProbe.c
	mkdir -p build
	$(CC) -std=gnu99 -Wall -Wextra $(GLIB_CFLAGS) $< $(GLIB_LIBS) -o $@

original-compat-test: build/$(ARCH)/wallet-tests build/original-homebank-probe
	./build/$(ARCH)/wallet-tests tests/demo.xhb
	./build/original-homebank-probe build/homebank-compatible-edit.xhb
	./build/original-homebank-probe build/homebank-compatible-repair.xhb
	./build/original-homebank-probe build/homebank-compatible-opaque.xhb
	./build/original-homebank-probe build/homebank-compatible-unicode.xhb

package: all test
	/bin/sh scripts/check-architecture.sh $(ARCH) $(APP)/Contents/MacOS/HomeBankPanther
	COPYFILE_DISABLE=1 tar --format=ustar -czf build/HomeBankPanther-$(VERSION)-$(ARCH).tar.gz -C build/$(ARCH) HomeBankPanther.app

source-package:
	mkdir -p build
	COPYFILE_DISABLE=1 tar --format=ustar -czf build/HomeBankPanther-$(VERSION)-sources.tar.gz Makefile README.md HTTPS_BUILD.md DRIVE_SETUP.md $(SOURCES) $(C_SOURCES) $(HEADERS) $(TEST_SOURCES) tests/PantherString.h tests/DriveTests.m tests/DriveApplicationTests.m tests/PerformanceTests.m tests/JournalTests.m tests/XMLTests.c tests/OriginalHomeBankProbe.c tests/demo.xhb tests/HttpsCheckTests.sh tests/HttpsBuildTests.sh tests/fixtures/curl-diagnostic.sh tests/fixtures/https-build-placeholder.txt tests/fixtures/https-build-tool.sh tests/fixtures/drive-curl.sh tests/fixtures/drive-rsa-test-key.txt tests/fixtures/DRIVE_TEST_KEYS.md resources/Info.plist resources/licenses/WOLFSSL-COPYING.txt resources/licenses/CURL-COPYING.txt scripts/https-sources.json scripts/prepare-drive-https.mjs scripts/check-curl-timeval.c scripts/build-drive-https.sh scripts/check-architecture.sh scripts/check-drive-https.sh vendor/cjson/cJSON.h vendor/cjson/LICENSE vendor/cjson/README.md

drive-check:
	/bin/sh scripts/check-drive-https.sh

drive-tools-prepare:
	node scripts/prepare-drive-https.mjs

clean:
	rm -rf build
