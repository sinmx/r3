REBOL [
    System: "REBOL [R3] Language Interpreter and Run-time Environment"
    Title: "Make the R3 Core Makefile"
    Rights: {
        Copyright 2012 REBOL Technologies
        Copyright 2012-2017 Rebol Open Source Contributors
        REBOL is a trademark of REBOL Technologies
    }
    License: {
        Licensed under the Apache License, Version 2.0
        See: http://www.apache.org/licenses/LICENSE-2.0
    }
    Purpose: {
        Build a new makefile for a given platform.
    }
    Note: [
        "This runs relative to ../tools directory."
        "Make OS-specific changes to the systems.r file."
    ]
]

path-host: %../os/
path-make: %../../make/
path-incl: %../../src/include/

;******************************************************************************

; (Warning: format is a bit sensitive to extra spacing. E.g. see macro+ func)

makefile-head: copy

{# REBOL Makefile -- Generated by make-make.r (!!! EDITS WILL BE LOST !!!)
# This automatically produced file was created !date

# This makefile is intentionally kept simple to make builds possible on
# a wide range of target platforms.  While this generated file has several
# capabilities, it is not tracked by version control.  So to kick off the
# process you need to use the tracked bootstrap makefile:
#
#     make -f makefile.boot
#
# See the comments in %makefile.boot for more information on the workings of
# %make-make.r and what the version numbers mean.  This generated file is a
# superset of the functionality in %makefile.boot, however.  So you can
# retarget simply by typing:
#
#     make make OS_ID=0.4.3
#
# To cross-compile using a different toolchain and include files:
#
#     $TOOLS - should point to bin where gcc is found
#     $INCL  - should point to the dir for includes
#
# Example make:
#
#     make TOOLS=~/amiga/amiga/bin/ppc-amigaos- INCL=/SDK/newlib/include
#
# !!! Efforts to be able to have Rebol build itself in absence of a make
# tool are being considered.  Please come chime in on chat if you are
# interested in that and other projects, or need support while building:
#
# http://rebolsource.net/go/chat-faq
#

# Modules automatically loaded after boot up
BOOT_EXTENSIONS=

# For the build toolchain:
CC= $(TOOLS)gcc
NM= $(TOOLS)nm
STRIP= $(TOOLS)strip

# CP allows different copy progs:
CP=
# LS allows different ls progs:
LS=
# UP - some systems do not use ../
UP=
# CD - some systems do not use ./
CD=
# Special tools:
T= $(UP)/src/tools
# Paths used by make:
S= ../src
R= $S/core

INCL ?= .
I= -I$(INCL) -I$S/include/ -I$S/codecs/

# Note: variables assigned with ?= will only take the value if the parameter
# is not currently defined.  The MACRO+ function is used to replace the
# parameters during file generation.
#
TO_OS_BASE?=
TO_OS_NAME?=
OS_ID?= detect
GIT_COMMIT?= unknown
BIN_SUFFIX=
RAPI_FLAGS=
HOST_FLAGS= -DREB_EXE
RLIB_FLAGS=

# Flags for core and for host:
RFLAGS= -c -D$(TO_OS_BASE) -D$(TO_OS_NAME) -DREB_API  $(RAPI_FLAGS) $I
HFLAGS= -c -D$(TO_OS_BASE) -D$(TO_OS_NAME) -DREB_CORE $(HOST_FLAGS) $I
CLIB=

# REBOL is needed to build various include files:
REBOL_TOOL= r3-make$(BIN_SUFFIX)
REBOL= $(CD)$(REBOL_TOOL) -qs

# For running tests, ship, build, etc.
R3_TARGET= r3$(BIN_SUFFIX)
R3= $(CD)$(R3_TARGET) -qs

### Build targets:
top:
    $(MAKE) $(R3_TARGET)

update:
    -cd $(UP)/; cvs -q update src

# Uses "phony target" %make that should never be the name of a file in
# this directory, hence, it will always regenerate if the make target
# is requested.  Note: Cannot call it %makefile without winding up
# running make-make.r four extra times:
#
#     http://stackoverflow.com/questions/31490689/
#
# Consider being able to continue to type `make make` instead of having
# to re-run the line including `makefile.boot` to be a special
# undocumented feature, as people are used to it...but it might go away
# someday.  Maybe.

make: $(REBOL_TOOL)
    $(REBOL) $T/make-make.r OS_ID=$(OS_ID) GIT_COMMIT=$(GIT_COMMIT)

clean:
    @-rm -rf $(R3_TARGET) libr3.so objs/
    @-find ../src -name 'tmp-*' -exec rm -f {} \;
    @-grep -l "AUTO-GENERATED FILE" ../src/include/*.h |grep -v sys-zlib.h|xargs rm 2>/dev/null || true

all:
    $(MAKE) clean
    $(MAKE) prep
    $(MAKE) $(R3_TARGET)
    $(MAKE) lib
    $(MAKE) host$(BIN_SUFFIX)

prep: $(REBOL_TOOL)
    $(REBOL) $T/make-natives.r
    $(REBOL) $T/make-headers.r
    $(REBOL) $T/make-boot.r OS_ID=$(OS_ID) GIT_COMMIT=$(GIT_COMMIT)
    $(REBOL) $T/make-host-init.r
    $(REBOL) $T/make-os-ext.r
    $(REBOL) $T/make-host-ext.r
    $(REBOL) $T/make-reb-lib.r
    $(REBOL) $T/make-ext-natives.r
    $(REBOL) $T/make-boot-ext-header.r EXTENSIONS=$(BOOT_EXTENSIONS)

zlib:
    $(REBOL) $T/make-zlib.r

### Provide more info if make fails due to no local Rebol build tool:
tmps: $S/include/tmp-bootdefs.h

$S/include/tmp-bootdefs.h: $(REBOL_TOOL)
    $(MAKE) prep

$(REBOL_TOOL):
    $(MAKE) -f makefile.boot $(REBOL_TOOL)

### Post build actions
purge:
    -rm libr3.*
    -rm host$(BIN_SUFFIX)
    $(MAKE) lib
    $(MAKE) host$(BIN_SUFFIX)

test:
    $(CP) $(R3_TARGET) $(UP)/src/tests/
    $(R3) $S/tests/test.r

install:
    sudo cp $(R3_TARGET) /usr/local/bin

ship:
    $(R3) $S/tools/upload.r

build: libr3.so
    $(R3) $S/tools/make-build.r

cln:
    rm libr3.* r3.o

check:
    $(STRIP) -s -o r3.s $(R3_TARGET)
    $(STRIP) -x -o r3.x $(R3_TARGET)
    $(STRIP) -X -o r3.X $(R3_TARGET)
    $(LS) r3*

}

;******************************************************************************

makefile-link: {
# Directly linked r3 executable:
$(R3_TARGET): tmps objs $(OBJS) $(HOST)
    $(CC) -o $(R3_TARGET) $(OBJS) $(HOST) $(CLIB)
    $(STRIP) $(R3_TARGET)
    -$(NM) -a $(R3_TARGET)
    $(LS) $(R3_TARGET)

objs:
    mkdir -p objs
}

makefile-so: {
lib: libr3.so

# PUBLIC: Shared library:
# NOTE: Did not use "-Wl,-soname,libr3.so" because won't find .so in local dir.
libr3.so: $(OBJS)
    $(CC) -o libr3.so -shared $(OBJS) $(CLIB)
    $(STRIP) libr3.so
    -$(NM) -D libr3.so
    -$(NM) -a libr3.so | grep "Do_"
    $(LS) libr3.so

# PUBLIC: Host using the shared lib:
host$(BIN_SUFFIX): $(HOST)
    $(CC) -o host$(BIN_SUFFIX) $(HOST) libr3.so $(CLIB)
    $(STRIP) host$(BIN_SUFFIX)
    $(LS) host$(BIN_SUFFIX)
    echo "export LD_LIBRARY_PATH=.:$LD_LIBRARY_PATH"
}

makefile-dyn: {
lib: libr3.dylib

# Private static library (to be used below for OSX):
libr3.dylib: $(OBJS)
    ld -r -o r3.o $(OBJS)
    $(CC) -dynamiclib -o libr3.dylib r3.o $(CLIB)
    $(STRIP) -x libr3.dylib
    -$(NM) -D libr3.dylib
    -$(NM) -a libr3.dylib | grep "Do_"
    $(LS) libr3.dylib

# PUBLIC: Host using the shared lib:
host$(BIN_SUFFIX): $(HOST)
    $(CC) -o host$(BIN_SUFFIX) $(HOST) libr3.dylib $(CLIB)
    $(STRIP) host$(BIN_SUFFIX)
    $(LS) host$(BIN_SUFFIX)
    echo "export LD_LIBRARY_PATH=.:$LD_LIBRARY_PATH"
}

not-used: {
# PUBLIC: Static library (to distrirbute) -- does not work!
libr3.lib: r3.o
    ld -static -r -o libr3.lib r3.o
    $(STRIP) libr3.lib
    -$(NM) -a libr3.lib | grep "Do_"
    $(LS) libr3.lib
}

;******************************************************************************
;** Options and Config
;******************************************************************************

do %r2r3-future.r
do %common.r
do %systems.r

file-base: has load %file-base.r

args: parse-args system/options/args

if not args/OS_ID [
    print "OS_ID must be a version # (e.g. 5.25.0) or the word `detect`"
    quit
]

config: config-system either args/OS_ID = "detect" [blank][args/OS_ID]

print ["Option set for building:" config/id config/os-name]


; Words are cleaner-looking in the table, and hyphens look better (and are
; easier to type).  But we need a string, and one that C can accept and not
; think you're doing subtraction.  Transform it (e.g. osx-64 => "TO_OSX_X64")
;
to-base-def: unspaced [{TO_} uppercase to-string config/os-base]
to-name-def: unspaced [
    {TO_} replace/all (uppercase to-string config/os-name) {-} {_}
]

; Make plat id string
;
plat-id: form config/id/2
if tail? next plat-id [insert plat-id #"0"]
append plat-id config/id/3

; Collect OS-specific host files:
unless (
    os-specific-objs: select file-base to word! unspaced ["os-" config/os-base]
) [
    fail [
        "make-make.r requires os-specific obj list in file-base.r"
        "blank was provided for" unspaced ["os-" config/os-base]
    ]
]

; The + sign is sued to tell the make-header.r script that the file is
; generated.  We don't care about that here
;
remove-each item file-base/core [item = '+]

; The + sign is used to tell the make-os-ext.r script to scan a host kit file
; for headers (the way make-headers.r does).  But we don't care about that
; here in make-make.r... so remove any + signs we find before processing.
;
remove-each item file-base/os [item = '+]
remove-each item os-specific-objs [item = '+]

outdir: path-make
make-dir outdir
make-dir outdir/objs

output: make string! 10000
emit: func [d] [adjoin output d]

;******************************************************************************
;** Functions
;******************************************************************************

flag?: func ['word] [not blank? find config/build-flags word]


macro+: procedure [
    "Appends value to end of macro= line"
    'name
    value
    /replace
        {Replace any existing text} 
][
    replace_MACRO+: replace
    replace: :lib/replace
     
    n: unspaced [newline name]
    value: form value
    unless parse makefile-head rule: compose/deep [
        any [
            thru n opt [
                any space ["=" | "?="]
                (either replace_MACRO+ ['remove] [[]]) to newline
                insert space insert value to end
            ]
        ]
    ][
        print unspaced ["Cannot find" space name "= definition"]
    ]
]


macro++: procedure ['name obj [object!]] [
    out: make string! 10
    for-each n words-of obj [
        all [
            obj/:n
            flag? (n)
            adjoin out [space obj/:n]
        ]
    ]
    macro+ (name) out
]


to-obj: function [
    "Create .o object filename (with no dir path)."
    file
][
    ;?? file

    ; Use of split path to remove directory had been commented out, but
    ; was re-added to incorporate the paths on codecs in a stop-gap measure
    ; to use make-make.r with Atronix repo

    file: (comment [to-file file] second split-path to-file file)
    head change back tail file "o"
]


emit-obj-files: function [
    "Output a line-wrapped list of object files."
    files [block!]
][
    cnt: 1
    pending: _
    for-each file files [
        if pending [
            emit pending
            pending: _
        ]

        file: to-obj file
        emit [%objs/ file space]
        
        if (cnt // 4) = 0 [
            pending: unspaced ["\" newline spaced-tab]
        ]
        cnt: cnt + 1
    ]
    emit [newline newline]
]


emit-file-deps: function [
    "Emit compiler and file dependency lines."
    files
    /dir path  ; from path
][
    for-each src files [
        obj: to-obj src
        src: unspaced pick [["$R/" src]["$S/" path src]] not dir
        emit [
            %objs/ obj ":" space src
            newline spaced-tab
            "$(CC) "
            src space
            ;flags space
            pick ["$(RFLAGS)" "$(HFLAGS)"] not dir
            space "-o" space %objs/ obj ; space src
            newline
            newline
        ]
    ]
]


;******************************************************************************
;** Build
;******************************************************************************

replace makefile-head "!date" now

macro+ TO_OS_BASE to-base-def
macro+ TO_OS_NAME to-name-def

macro+/replace OS_ID config/id ;-- should be known at this point
macro+/replace GIT_COMMIT args/GIT_COMMIT ;-- might just be the word `unknown`

macro+ LS pick ["dir" "ls -l"] flag? DIR
macro+ CP pick [copy cp] flag? COP
unless flag? -SP [ ; Use standard paths:
    macro+ UP ".."
    macro+ CD "./"
]
if flag? EXE [macro+ BIN_SUFFIX %.exe]
macro++ CLIB linker-flags
macro++ RAPI_FLAGS compiler-flags
macro++ HOST_FLAGS construct compiler-flags [PIC: NCM: _]
macro+  HOST_FLAGS compiler-flags/f64 ; default for all

if flag? +SC [remove find os-specific-objs 'host-readline.c]

boot-extension-src: copy []
extension-list: copy ""
for-each [builtin? ext-name ext-src modules] file-base/extensions [
    if '+ = builtin? [
        unless empty? extension-list [append extension-list ","]
        append extension-list to string! ext-name
        append/only boot-extension-src ext-src ;ext-src is a path!, so /only is required

        for-each m modules [
            m-spec: find file-base/modules m
            append/only boot-extension-src m-spec/2 ;main file of the module
            append boot-extension-src m-spec/3 ;other files of the module
        ]
    ]
]
macro+ BOOT_EXTENSIONS unspaced [{"} extension-list {"}]

emit makefile-head
emit ["OBJS =" space]
emit-obj-files append copy file-base/core boot-extension-src
emit ["HOST =" space]
emit-obj-files append copy file-base/os os-specific-objs
emit makefile-link
emit get pick [makefile-dyn makefile-so] config/id/2 = 2
emit {
### File build targets:
tmp-boot-block.c: $(SRC)/boot/tmp-boot-block.r
    $(REBOL) -sqw $(SRC)/tools/make-boot.r
}
emit newline

emit-file-deps file-base/core
emit-file-deps boot-extension-src

emit-file-deps/dir file-base/os %os/
emit-file-deps/dir os-specific-objs %os/

; Unfortunately, GNU make requires you use tab characters to indent, as part
; of the file format.  This code uses 4 spaces instead, but then converts to
; tabs at the last minute--so this Rebol source file doesn't need to have
; actual tab characters in it.
;
if find output tab-char [
    print copy/part find output tab-char 100
    fail "tab character discovered in makefile prior to space=>tab conversion"
]
replace/all output spaced-tab tab-char

write outdir/makefile output
print ["Created:" outdir/makefile]
