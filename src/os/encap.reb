REBOL [
    System: "REBOL [R3] Language Interpreter and Run-time Environment"
    Title: "Host Script and Resource Embedding Services ('encapping')"
    Rights: {
        Copyright 2017 Rebol Open Source Contributors
        REBOL is a trademark of REBOL Technologies
    }
    License: {
        Licensed under the Apache License, Version 2.0
        See: http://www.apache.org/licenses/LICENSE-2.0
    }
    Description: {
        Encapping grafts data into an already-compiled executable, to add
        resources to it "after the fact".  Note that there are different
        executable formats used on different operating systems, each with a
        header that tells the operating system how to interpret the file:

        Linux: https://en.wikipedia.org/wiki/Executable_and_Linkable_Format
        Windows: https://en.wikipedia.org/wiki/Portable_Executable
        OS X: https://en.wikipedia.org/wiki/Mach-O

        A "naive" form of adding data into an executable is to append the
        data at the tail, which generally does not affect operation:

        http://stackoverflow.com/a/5801598/211160

        This is a common approach, yet it has some flaws.  e.g. on Linux,
        running the `strip` command will see the added data as irrelevant,
        and remove it.  Other manipulations like adding an icon resource may
        add the icon resource data to the end.  There are other things, like
        executable compression (although some executable compressors are aware
        of this well-known embedding tactic, and account for it).

        It may be reasonable to say that it is the burden of those doing
        executable manipulations to de-encap it, do the modification, and then
        re-encap the executable.  But all things being equal, it's desirable
        to find ways to slipstream the information into the "valid/known"
        resource logic of the OS.

        This can be done with OS-specific tools or system calls, but the
        advantage of writing it standalone as Rebol is that it reduces the
        dependencies.  It allows encapping of executables built on a platform
        different than the one you are running on.  So attempts are made
        here to manipulate the published formats with Rebol code itself.

        For formats not supported currently by the encapper, the simple
        appending strategy is used.
    }
]


;
; https://en.wikipedia.org/wiki/Executable_and_Linkable_Format
;
; The ELF format contains named data sections, and the encap payload is
; injected as one of these sections (with a specific name).  Injecting or
; modifying a section requires updating file offsets in affected headers.
;
; Note: since section headers are fixed-size, the names for the sections are
; zero-terminated strings which are themselves stored in a section.  This
; can be any section (specified in the header as `e_shstrndx`), so processing
; names requires a pre-pass to find it, hence is a little bit convoluted.
;
elf-format: context [
    encap-section-name: ".rebol.encap.1"

    ; (E)LF overall header properties read or written during parse

    EI_CLASS: _
    EI_DATA: _
    EI_VERSION: _
    bits: _             ; 32 or 64
    endian: _           ; 'little or 'big
    e_phoff: _          ; Offset of program header table start.
    e_phnum: _          ; Number of entries in the section header table.
    e_phentsize: _      ; Size of a program header table entry.
    e_shoff: _          ; Offset of section header table start.
    e_shnum: _          ; Number of entries in the section header table.
    e_shentsize: _      ; Size of a section header table entry.
    e_shstrndx: _       ; section header index with section names.

    ; (P)rogram Header properties read or written during parse

    p_type: _
    p_offset: _
    p_filesz: _

    ; (S)ection (H)eader properties extracted during parse

    sh_name: _          ; .shstrtab section offset w/this section's name
    sh_type: _
    sh_flags: _
    sh_addr: _
    sh_offset: _
    sh_size: _
    sh_link: _
    sh_info: _
    sh_addralign: _
    sh_entsize: _

    begin: _            ; Capture position in the series

    ; When parsing a binary header, the properties are either 'read or 'write
    ; In the current update pattern, a read phase is followed by tweaking
    ; the desired parameters, then seeking back and doing a write phase.
    ; For safety, the mode is reset to blank after each rule, to force being
    ; explicit at the callsites.
    ;
    mode: _
    handler: function [name [word!] num-bytes [integer!]] [
        assert [
            binary? begin | num-bytes <= length begin
            | find [read write] mode
        ]

        either mode = 'read [
            bin: copy/part begin num-bytes
            if endian = 'little [reverse bin]
            set name (to-integer/unsigned bin)
        ][
            val: really integer! get name
            bin: skip (tail to-binary val) (negate num-bytes) ;-- big endian
            if endian = 'little [reverse bin]
            change begin bin
        ]
    ]

    header-rule: [
        #{7F} "ELF"
        set EI_CLASS skip (bits: either EI_CLASS = 1 [32] [64])
        set EI_DATA skip (endian: either EI_DATA = 1 ['little] ['big])
        set EI_VERSION skip (assert [EI_VERSION = 1])
        skip ; EI_OSABI
        skip ; EI_ABIVERSION
        7 skip ; EI_PAD
        2 skip ; e_type
        2 skip ; e_machine
        4 skip ; e_version
        [
            if (bits = 32) [
                4 skip ; e_entry
                begin: 4 skip (handler 'e_phoff 4)
                begin: 4 skip (handler 'e_shoff 4)
            ]
        |
            if (bits = 64) [
                8 skip ; e_entry
                begin: 8 skip (handler 'e_phoff 8)
                begin: 8 skip (handler 'e_shoff 8)
            ]
        ]
        4 skip ; e_flags
        2 skip ; e_ehsize
        begin: 2 skip (handler 'e_phentsize 2)
        begin: 2 skip (handler 'e_phnum 2)
        begin: 2 skip (handler 'e_shentsize 2)
        begin: 2 skip (handler 'e_shnum 2)
        begin: 2 skip (handler 'e_shstrndx 2)

        (mode: _)
    ]

    program-header-rule: [
        begin: 4 skip (handler 'p_type 4)
        [
            if (bits = 32) [
                begin: 4 skip (handler 'p_offset 4)
                4 skip ; p_vaddr
                4 skip ; p_paddr
                begin: 4 skip (handler 'p_filesz 4)
                4 skip ; p_memsz
            ]
        |
            if (bits = 64) [
                4 skip ; p_flags, different position in 64-bit
                begin: 8 skip (handler 'p_offset 8)
                8 skip ; p_vaddr
                8 skip ; p_paddr
                begin: 8 skip (handler 'p_filesz 8)
                8 skip ; p_memsz
            ]
        ]
        [
            if (bits = 32) [
                4 skip ; p_flags, different position in 32-bit
                4 skip ; p_align
            ]
        |
            if (bits = 64) [
                8 skip ; p_align
            ]
        ]

        (mode: _)
    ]

    section-header-rule: [
        begin: 4 skip (handler 'sh_name 4)
        begin: 4 skip (handler 'sh_type 4)
        [
            if (bits = 32) [
                begin: 4 skip (handler 'sh_flags 4)
                begin: 4 skip (handler 'sh_addr 4)
                begin: 4 skip (handler 'sh_offset 4)
                begin: 4 skip (handler 'sh_size 4)
            ]
        |
            if (bits = 64) [
                begin: 8 skip (handler 'sh_flags 8)
                begin: 8 skip (handler 'sh_addr 8)
                begin: 8 skip (handler 'sh_offset 8)
                begin: 8 skip (handler 'sh_size 8)
            ]
        ]
        begin: 4 skip (handler 'sh_link 4)
        begin: 4 skip (handler 'sh_info 4)
        [
            if (bits = 32) [
                begin: 4 skip (handler 'sh_addralign 4)
                begin: 4 skip (handler 'sh_entsize 4)
            ]
        |
            if (bits = 64) [
                begin: 8 skip (handler 'sh_addralign 8)
                begin: 8 skip (handler 'sh_entsize 8)
            ]
        ]

        (mode: _)
    ]

    find-section: function [
        return: [blank! integer!]
            {The index of the section header with encap (sh_xxx vars set)}
        name [string!]
        section-headers [binary!]
        string-section [binary!]

        <in> self
    ][
        index: 0
        parse section-headers [
            (assert [integer? e_shnum])
            e_shnum [ ; the number of times to apply the rule
                (mode: 'read) section-header-rule
                (
                    name-start: skip string-section sh_name
                    name-end: really binary! find name-start #{00}
                    section-name: to-string copy/part name-start name-end
                    if name = section-name [
                        return index ;-- sh_offset, sh_size, etc. are set
                    ]
                    index: index + 1
                )
            ]
        ]
        return blank
    ]

    update-offsets: procedure [
        {Adjust headers to account for insertion or removal of data @ offset}

        executable [binary!]
        offset [integer!]
        delta [integer!]

        <in> self
    ][
        assert [e_phoff < offset] ;-- program headers are before any changes
        unless parse skip executable e_phoff [
            e_phnum [
                (mode: 'read) pos: program-header-rule
                (if p_offset >= offset [p_offset: p_offset + delta])
                (mode: 'write) :pos program-header-rule
            ]
            to end
        ][
            fail "Error updating offsets in program headers"
        ]

        assert [e_shoff >= offset] ;-- section headers are after any changes
        unless parse skip executable e_shoff [
            e_shnum [
                (mode: 'read) pos: section-header-rule
                (if sh_offset >= offset [sh_offset: sh_offset + delta])
                (mode: 'write) :pos section-header-rule
            ]
            to end
        ][
            fail "Error updating offsets in section headers"
        ]
    ]

    update-embedding: procedure [
        executable [binary!]
            {Executable to be mutated to either add or update an embedding}
        embedding [binary!]

        <in> self
    ][
        ; Up front, let's check to see if the executable has data past the
        ; tail or not--which indicates some other app added data using the
        ; simple concatenation method of "poor man's encap"
        ;
        section-header-tail: e_shoff + (e_shnum * e_shentsize)
        case [
            section-header-tail = length executable [
                print "Executable has no appended data past ELF image size"
            ]
            section-header-tail > length executable [
                print [
                    "Executable has"
                    (length executable) - section-header-tail
                    "bytes of extra data past the formal ELF image size"
                ]
            ]
            true [
                fail "Section header table in ELF binary is corrupt"
            ]
        ]

        ; The string names of the sections are themselves stored in a section,
        ; (at index `e_shstrndx`)
        ;
        string-header-offset: e_shoff + (e_shstrndx * e_shentsize)
        unless parse skip executable string-header-offset [
            (mode: 'read) section-header-rule to end
        ][
            fail "Error finding string section in ELF binary"
        ]

        string-section-offset: sh_offset
        string-section-size: sh_size

        ; Now that we have the string section, we can go through the
        ; section names and see if there's any match for an existing encap
        ;
        section-index: (
            find-section
                encap-section-name
                skip executable e_shoff ; section headers
                skip executable string-section-offset ; section offset
        )

        either section-index [
            ;
            ; There's already an embedded section, and we're either going to
            ; grow it or shrink it.  We don't have to touch the string table,
            ; though we might wind up displacing it (if the embedded section
            ; somehow got relocated from being the last)
            ;
            print [
                "Embedded section exists ["
                    "index:" section-index
                    "offset:" sh_offset
                    "size:" sh_size
                "]"
            ]

            old-size: sh_size
            new-size: length embedding

            ; Update the size of the embedded section in it's section header
            ;
            parse skip executable e_shoff + (section-index * e_shentsize) [
                (sh_size: new-size)
                (mode: 'write) section-header-rule
            ]

            ; Adjust all the program and section header offsets that are
            ; affected by this movement
            ;
            delta: new-size - old-size
            print ["Updating embedding by delta of" delta "bytes."]
            (update-offsets
                executable
                (sh_offset + old-size) ; offset of change
                delta ; amount of change
            )

            ; With offsets adjusted, delete old embedding, and insert the new
            ;
            remove/part (skip executable sh_offset) old-size
            insert (skip executable sh_offset) embedding

            ; We moved the section headers at the tail of the file, which are
            ; pointed to by the main ELF header.  Updated after branch.
            ;
            e_shoff: e_shoff + delta
        ][
            print "No existing embedded section was found, adding one."

            ; ADD STRING TABLE ENTRY

            ; Loop through all the section and program headers that will be
            ; affected by an insertion (could be 0 if string table is the
            ; last section, could be all of them if it's the first).  Update
            ; their offsets to account for the string table insertion, but
            ; don't actually move any data in `executable` yet.
            ;
            (update-offsets
                executable
                (string-section-offset + string-section-size)
                (1 + length encap-section-name) ; include null terminator
            )

            ; Update string table size in its corresponding header.
            ;
            unless parse skip executable string-header-offset [
                (mode: 'read) pos: section-header-rule
                (
                    assert [sh_offset = string-section-offset]
                    sh_size: sh_size + (1 + length encap-section-name)
                )
                (mode: 'write) :pos section-header-rule
                to end
            ][
                fail "Error updating string table size in string header"
            ]

            ; MAKE NEW SECTION TO BE THE LAST SECTION

            ; Start by cloning the string table section, and assume that its
            ; fields will be mostly okay for the platform.
            ;
            (new-section-header: copy/part
                (skip executable string-header-offset) e_shentsize)

            ; Tweak the fields of the copy to be SHT_NOTE, which is used for
            ; miscellaneous program-specific purposes, and hence not touched
            ; by strip...it is also not mapped into memory.
            ;
            unless parse new-section-header [
                (
                    sh_name: string-section-size ; w.r.t string-section-offset
                    sh_type: 7 ; SHT_NOTE
                    sh_flags: 0
                    sh_size: length embedding
                    sh_offset: e_shoff + (1 + length encap-section-name)
                )
                (mode: 'write) section-header-rule
                to end
            ][
                fail "Error creating new section for the embedded data"
            ]

            ; Append new header to the very end of the section headers.  This
            ; may or may not be the actual end of the executable.  It will
            ; affect no ELF offsets, just the `e_shnum`.
            ;
            insert (skip executable section-header-tail) new-section-header

            ; Do the insertion of the data for the embedding itself.  Since
            ; we're adding it right where the old section headers used to
            ; start, this only affects `e_shoff`.
            ;
            insert (skip executable e_shoff) embedding

            ; Now do the string table insertion, which all the program and
            ; section headers were already adjusted to account for.
            ;
            (insert
                (skip executable string-section-offset + string-section-size)
                (join-of (to-binary encap-section-name) #{00})
            )

            ; We added a section (so another section header to account for),
            ;
            e_shnum: e_shnum + 1

            ; We expanded the string table and added the embedding, so the
            ; section header table offset has to be adjusted.
            ;
            e_shoff: (
                e_shoff
                + (length embedding)
                + (1 + length encap-section-name)
            )

            ; (main header write is done after the branch.)
        ]

        unless parse executable [
            (mode: 'write) header-rule to end
        ][
            fail "Error updating the ELF header"
        ]
    ]

    get-embedding: function [
        return: [binary! blank!]
        file [file!]

        <in> self
    ][
        header-data: read/part file 64 ; 64-bit size, 32-bit is smaller

        if not parse header-data [(mode: 'read) header-rule to end] [
            return blank
        ]

        section-headers-data:
            read/seek/part file e_shoff (e_shnum * e_shentsize)

        ; The string names of the sections are themselves stored in a section,
        ; (at index `e_shstrndx`)
        ;
        unless parse skip section-headers-data (e_shstrndx * e_shentsize) [
            (mode: 'read) section-header-rule to end
        ][
            fail "Error finding string section in ELF binary"
        ]

        string-section-data: read/seek/part file sh_offset sh_size

        ; Now that we have the string section, we can go through the
        ; section names and see if there's any match for an existing encap
        ;
        if not section-index: (
            find-section
                encap-section-name
                section-headers-data
                string-section-data
        )[
            return blank
        ]

        return read/seek/part file sh_offset sh_size
    ]
]

; The Portable Executable (PE) format is a file format for executables, object
; code, DLLs, FON Font files, and others used in 32-bit and 64-bit versions of
; Windows operating systems.
;
; The official specification is at:
; https://msdn.microsoft.com/en-us/library/windows/desktop/ms680547(v=vs.85).aspx
;
pe-format: context [
    encap-section-name: ".rebolE" ;limited to 8 bytes

    b1: b2: b3: b4: b5: b6: b7: b8: u16: u32: u64: uintptr: _
    err: _
    fail-at: _

    byte: complement charset []
    u16-le: [copy b1 byte copy b2 byte
            (u16: (shift to-integer/unsigned b2 8)
            or+ to-integer/unsigned b1)]
    u32-le: [copy b1 byte copy b2 byte
            copy b3 byte copy b4 byte
            (u32: (shift to-integer/unsigned b4 24)
            or+ (shift to-integer/unsigned b3 16)
            or+ (shift to-integer/unsigned b2 8)
            or+ to-integer/unsigned b1)]
    u64-le: [copy b1 byte copy b2 byte
            copy b3 byte copy b4 byte
            copy b5 byte copy b6 byte
            copy b7 byte copy b8 byte
            (u64: (shift to-integer/unsigned b8 56)
            or+ (shift to-integer/unsigned b7 48)
            or+ (shift to-integer/unsigned b3 40)
            or+ (shift to-integer/unsigned b5 32)
            or+ (shift to-integer/unsigned b4 24)
            or+ (shift to-integer/unsigned b3 16)
            or+ (shift to-integer/unsigned b2 8)
            or+ to-integer/unsigned b1)]

    uintptr-le:
    uintptr-32-le: [u32-le (uintptr: u32)]
    uintptr-64-le: [u64-le (uintptr: u64)]

    gen-rule: function [
        "Collect all set-words in @rule and make an object out of them and save it in @name"
        rule [block!]
        'name [word!]
        /skip
            words [word! block!] "Do not collect these words"
        <local>
        word
        skips
        def
        find-a-word
    ][
        find-a-word: proc [
            word [any-word!]
        ][
            unless any [
                find? words to word! word
                find? def to set-word! word
            ][
                append def reduce [to set-word! word]
            ]
        ]

        either skip [
            if word? words [
                words: reduce [words]
            ]
            if locked? words [
                words: copy words
            ]
            append words [err]
        ][
            words: [err]
        ]

        def: make block! 1
        group-rule: [
            any [
                set word set-word!
                (find-a-word word)
                | and block! into block-rule ;recursively look into the array
                | skip
            ]
        ]
        block-rule: [
            any [
                and group! into group-rule
                | and block! into block-rule
                | ['copy | 'set] set word word! (find-a-word word)
                | skip
            ]
        ]

        parse rule block-rule

        ;dump def
        set name make object! append def _
        bind rule get name
    ]

    DOS-header: _
    pos: _

    DOS-header-rule: gen-rule [
        ["MZ" | fail-at: (err: 'missing-dos-signature) fail]
        u16-le (last-size: u16)
        u16-le (n-blocks: u16)
        u16-le (n-reloc: u16)
        u16-le (header-size: u16)
        u16-le (min-alloc: u16)
        u16-le (max-alloc: u16)
        u16-le (ss: u16)
        u16-le (sp: u16)
        u16-le (checksum: u16)
        u16-le (ip: u16)
        u16-le (cs: u16)
        u16-le (reloc-pos: u16)
        u16-le (n-overlay: u16)
        copy reserved1 4 u16-le
        u16-le (oem-id: u16)
        u16-le (oem-info: u16)
        copy reserved2 10 u16-le
        u32-le (e-lfanew: u32)
    ] DOS-header

    PE-header-rule: [
        "PE^@^@" | fail-at: (err: 'missing-PE-signature) fail
    ]

    COFF-header: _
    COFF-header-rule: gen-rule/skip [
        and [
            #{4c01} (machine: 'i386)
            | #{6486} (machine: 'x86-64 uintptr-le: uintptr-64-le)
            | #{6201} (machine: 'MIPS-R3000)
            | #{6801} (machine: 'MIPS-R10000)
            | #{6901} (machine: 'MIPS-le-WCI-v2)
            | #{8301} (machine: 'old-alpha-AXP)
            | #{8401} (machine: 'alpha-AXP)
            | #{0002} (machine: 'IA64 uintptr-le: uintptr-64-le)
            | #{6602} (machine: 'MIPS16)
        ]
        u16-le (machine-value: u16)
        pos: u16-le (
            number-of-sections: u16
            number-of-sections-offset: (index-of pos) - 1
        )
        u32-le (time-date-stamp: u32)
        u32-le (pointer-to-symbol-table: u32)
        u32-le (number-of-symbols: u32)
        u16-le (size-of-optional-headers: u16)
        u16-le (chracteristics: u16)
    ] COFF-header 'uintptr-le

    data-directories: make block! 16
    sections: make block! 8
    PE-optional-header: _

    PE-optional-header-rule: gen-rule [
        and [#{0b01} (signature: 'exe-32)
             | #{0b02} (signature: 'exe-64)
             | #{0701} (signature: 'ROM)
             | fail-at: (err: 'missing-image-signature) fail
        ]
        u16-le (signature-value: u16)
        copy major-linker-version byte
        copy minor-linker-version byte
        u32-le (size-of-code: u32)
        u32-le (size-of-initialized-data: u32)
        u32-le (size-of-uninialized-data: u32)
        u32-le (address-of-entry-point: u32)
        u32-le (code-base: u32)
        u32-le (data-base: u32)
        u32-le (image-base: u32
            if signature = 'exe-64 [
                image-base: code-base or+ shift image-base 32
                code-base: _
            ])
        u32-le (section-alignment: u32)
        u32-le (file-alignment: u32)
        u16-le (major-OS-version: u16)
        u16-le (minor-OS-version: u16)
        u16-le (major-image-version: u16)
        u16-le (minor-image-version: u16)
        u16-le (major-subsystem-version: u16)
        u16-le (minor-subsystem-version: u16)
        u32-le (win32-version-value: u32)
        pos: u32-le (image-size: u32
                image-size-offset: (index-of pos) - 1)
        u32-le (size-of-headers: u32)
        u32-le (checksum: u32)
        and [
            #{0000} (subsystem: 'unknown)
            | #{0100} (subsystem: 'native)
            | #{0200} (subsystem: 'Widnows-GUI)
            | #{0300} (subsystem: 'Windows-CUI)
            | #{0500} (subsystem: 'OS2-CUI)
            | #{0700} (subsystem: 'POSIX-CUI)
            | #{0900} (subsystem: 'Widnows-CE-GUI)
            | #{1000} (subsystem: 'EFI-application)
            | #{1100} (subsystem: 'EFI-boot-service-driver)
            | #{1200} (subsystem: 'EFI-runtime-driver)
            | #{1300} (subsystem: 'EFI-ROM)
            | #{1400} (subsystem: 'Xbox)
            | #{1600} (subsystem: 'Windows-Boot-application)
            | fail-at: (err: 'unrecoginized-subsystem) fail
        ]
        u16-le (subsystem-value: u16)
        u16-le (dll-characteristics: u16)
        uintptr-le (size-of-stack-reserve: uintptr)
        uintptr-le (size-of-stack-commit: uintptr)
        uintptr-le (size-of-heap-reserve: uintptr)
        uintptr-le (size-of-heap-commit: uintptr)
        u32-le (loader-flags: u32)
        u32-le (number-of-RVA-and-sizes: u32)
    ] PE-optional-header

    data-directory: _
    data-directory-rule: gen-rule [
        u32-le (RVA: u32)
        u32-le (size: u32)
        (append data-directories copy data-directory)
    ] data-directory

    section: _
    section-rule: gen-rule [
        copy name [8 byte]
        u32-le (virtual-size: u32)
        u32-le (virtual-offset: u32)
        u32-le (physical-size: u32)
        u32-le (physical-offset: u32)
        copy reserved [12 byte]
        u32-le (flags: u32)
        (append sections copy section)
    ] section

    garbage: _
    start-of-section-header: _
    end-of-section-header: _

    exe-rule: [
        DOS-header-rule pos: (garbage: DOS-header/e-lfanew + 1 - index-of pos)
        garbage skip
        PE-header-rule
        COFF-header-rule
        PE-optional-header-rule
        PE-optional-header/number-of-RVA-and-sizes data-directory-rule
        start-of-section-header:
        COFF-header/number-of-sections section-rule
        end-of-section-header:
    ]
    size-of-section-header: 40 ;size of one entry

    to-u32-le: func [
        i [integer!]
    ][
        reverse skip (to binary! i) 4
    ]

    to-u16-le: func [
        i [integer!]
    ][
        reverse skip (to binary! i) 6
    ]

    align-to: function [
        offset [integer!]
        align [integer!]
    ][
        either zero? rem: offset // align [
            offset
        ][
            offset + align - rem
        ]
    ]

    reset: does [
        err: _
        fail-at: _
        start-of-section-header:
        end-of-section-header:
        garbage: _
        ;DOS-header: _
        pos: _
        ;PE-optional-header: _
        clear sections
        clear data-directories
    ]

    parse-exe: function [
        exe-data [binary!]
    ][
        reset
        parse exe-data exe-rule
        if err [
            fail ["err:" err | "at:" copy/part fail-at 16]
        ]
        true
    ]

    update-section-header: procedure [
        pos [binary!]
        section [object!]
    ][
        change pos new-section: rejoin [
            copy/part (head insert/dup tail to binary! copy section/name #{00} 8) 8 ;name, must be 8-byte long
            to-u32-le section/virtual-size
            to-u32-le section/virtual-offset
            to-u32-le section/physical-size
            to-u32-le section/physical-offset
            copy/part (head insert/dup tail to binary! copy section/reserved #{00} 12) 12 ;reserved, must be 12-byte long
            either binary? section/flags [section/flags][to-u32-le section/flags]
        ]

        ;dump new-section
        assert [size-of-section-header = length new-section]
    ]

    add-section: function [
        "Add a new section to the exe, modify in place"
        exe-data [binary!]
        section-name [string!]
        section-data [binary!]
    ][
        parse-exe exe-data

        ;dump DOS-header
        ;dump PE-optional-header

        ;check if there's section name conflicts
        for-each sec sections [
            if section-name = to string! trim/with sec/name #{00} [
                fail [
                    "There is already a section named" section-name |
                    mold sec
                ]
            ]
        ]

        ;print ["Section headers end at:" index-of end-of-section-header]
        sort/compare sections func [a b][a/physical-offset < b/physical-offset]
        secs: sections
        first-section-by-phy-offset: secs/1
        for-next secs [
            unless zero? secs/1/physical-offset [
                first-section-by-phy-offset: secs/1
                break
            ]
        ]
        ;dump first-section-by-phy-offset
        gap: first-section-by-phy-offset/physical-offset - (index-of end-of-section-header)
        if gap < size-of-section-header [
            fail "Not enough room for a new section header"
        ]

        ; increment the "number of sections"
        change skip exe-data COFF-header/number-of-sections-offset
            to-u16-le (COFF-header/number-of-sections + 1)

        last-section-by-phy-offset: sections/(COFF-header/number-of-sections)
        ;dump last-section-by-phy-offset

        sort/compare sections func [a b][a/virtual-offset < b/virtual-offset]
        last-section-by-virt-offset: sections/(COFF-header/number-of-sections)
        last-virt-offset: align-to last-section-by-virt-offset/virtual-offset + last-section-by-virt-offset/virtual-size 4096

        new-section-size: align-to (length section-data) PE-optional-header/file-alignment;physical size
        new-section-offset: last-section-by-phy-offset/physical-offset + last-section-by-phy-offset/physical-size
        assert [zero? new-section-offset // PE-optional-header/file-alignment]

        ; set the image size
        ; image size has to be mulitple of section-alignment
        change skip exe-data PE-optional-header/image-size-offset
            to-u32-le align-to (PE-optional-header/image-size + new-section-size) PE-optional-header/section-alignment

        ; add a new section header
        new-section-header: make section [
            name: section-name
            virtual-size: length section-data
            virtual-offset: last-virt-offset
            physical-size: new-section-size
            physical-offset: new-section-offset
            flags: #{40000040} ; initialized read-only exe-data
        ]

        update-section-header end-of-section-header new-section-header

        ;print ["current exe-data length" length exe-data]
        if new-section-offset > length exe-data [
            print "Last section has been truncated, filling with garbage"
            insert/dup garbage: copy #{} #{00} (new-section-offset - length exe-data)
            print ["length of filler:" length garbage]
            append exe-data garbage
        ]

        if new-section-size > length section-data [
            insert/dup garbage: copy #{} #{00} (new-section-size - length section-data)
            section-data: join-of to binary! section-data garbage
        ]

        assert [zero? (length section-data) // PE-optional-header/file-alignment]

        ; add the section
        case [
            new-section-offset < length exe-data [
                print ["There's extra exe-data at the end"]
                insert (skip exe-data new-section-offset) section-data
            ]
            new-section-offset = length exe-data [
                print ["Appending exe-data"]
                append exe-data section-data
            ]
        ] else [
            fail "Last section has been truncated"
        ]

        head exe-data
    ]

    find-section: function [
        "Find a section to the exe"
        exe-data [binary!]
        section-name [string!]
        /header "Return only the section header"
        /data "Return only the section data"
    ][
        trap/with [
            parse-exe exe-data
        ][
            ;print ["Failed to parse exe:" err]
            return _
        ]

        ;check if there's section name conflicts
        target-sec: _
        for-each sec sections [
            if section-name = to string! trim/with sec/name #{00} [
                target-sec: sec
                break
            ]
        ]
        unless target-sec [
            ;fail ["Couldn't find the section" section-name]
            return _
        ]

        case [
            header [
                target-sec
            ]
            data [
                copy/part (skip exe-data target-sec/physical-offset) target-sec/physical-size
            ]
            'else [
                reduce [
                    target-sec
                    copy/part (skip exe-data target-sec/physical-offset) target-sec/physical-size
                ]
            ]
        ]
    ]

    update-section: function [
        exe-data [binary!]
        section-name [string!]
        section-data [binary!]
    ][
        target-sec: find-section/header exe-data section-name; this will parse exe-data
        ;dump target-sec
        if blank? target-sec [
            return add-section exe-data section-name section-data
        ]
        new-section-size: align-to (length section-data) PE-optional-header/file-alignment
        section-size-diff: new-section-size - target-sec/physical-size
        unless zero? section-size-diff [
            new-image-size: to-u32-le align-to (PE-optional-header/image-size + section-size-diff) PE-optional-header/section-alignment
            if new-image-size != PE-optional-header/image-size [
                change skip exe-data PE-optional-header/image-size-offset new-image-size
            ]
        ]
        pos: start-of-section-header
        for-each sec sections [
            if sec/physical-offset > target-sec/physical-size [
                ;update the offset affected sections
                sec/physical-offset: sec/physical-offset + section-size-diff
                update-section-header pos sec
            ]
            pos: skip pos size-of-section-header
        ]
        remove/part pos: skip exe-data target-sec/physical-offset target-sec/physical-size
        if new-section-size > length section-data [;padding with #{00}
            insert/dup garbage: copy #{} #{00} (new-section-size - length section-data)
            section-data: join-of to binary! section-data garbage
        ]
        insert pos section-data

        also head exe-data
            reset
    ]

    remove-section: function [
        exe-data [binary!]
        section-name [string!]
    ][
        target-sec: find-section/header exe-data section-name; this will parse exe-data
        ;dump target-sec

        ;dump COFF-header
        ;dump PE-optional-header
        ; decrement the "number of sections"
        change skip exe-data COFF-header/number-of-sections-offset
            to-u16-le (COFF-header/number-of-sections - 1)

        image-size-diff: align-to target-sec/physical-size PE-optional-header/section-alignment
        unless zero? image-size-diff [
            change skip exe-data PE-optional-header/image-size-offset
                to-u32-le (PE-optional-header/image-size - image-size-diff)
        ]

        pos: start-of-section-header
        for-each sec sections [
            print to string! sec/name
            ;dump sec
            case [
                sec/physical-offset = target-sec/physical-offset [
                    assert [sec/name = target-sec/name]
                    ;target sec, replace with all #{00}
                    change pos head (insert/dup copy #{} #{00} size-of-section-header)
                    ; do not skip @pos, so that the next section will overwrite this one if it's not the last section
                ]
                sec/physical-offset > target-sec/physical-offset [
                    ;update the offset affected sections
                    sec/physical-offset: sec/physical-offset - target-sec/physical-size
                    update-section-header pos sec
                    pos: skip pos size-of-section-header
                ]
                'else [;unchanged
                    pos: skip pos size-of-section-header
                ]
            ]
        ]

        unless target-sec/physical-offset + 1 = index-of pos [
            ;if the section to remove is not the last section, the last section
            ;must have moved forward, so erase the old section
            change pos head (insert/dup copy #{} #{00} size-of-section-header)
        ]

        remove/part skip exe-data target-sec/physical-offset target-sec/physical-size

        also head exe-data
            reset
    ]

    update-embedding: specialize 'update-section [section-name: encap-section-name]
    get-embedding: function [
        return: [binary! blank!]
        file [file!]
    ][
        ;print ["Geting embedded from" mold file]
        exe-data: read file
        also find-section/data exe-data encap-section-name
            reset
    ]
]

generic-format: context [
    signature: to-binary "ENCAP000"
    sig-length: (length signature)

    update-embedding: procedure [
        executable [binary!]
            {Executable to be mutated to either add or update an embedding}
        embedding [binary!]

        <in> self
    ][
        embed-size: length embedding

        ; The executable we're looking at is already encapped if it ends with
        ; the encapping signature.
        ;
        sig-location: skip tail executable (negate length signature)
        case [
            sig-location = signature [
                print "Binary contains encap version 0 data block."

                size-location: skip sig-location -8
                embed-size: to-integer/unsigned copy/part size-location 8
                print ["Existing embedded data is" embed-size "bytes long."]

                print ["Trimming out existing embedded data."]
                clear skip size-location (negate embed-size)

                print ["Trimmed executable size is" length executable]
            ]
            true [
                print "Binary contains no pre-existing encap data block"
            ]
        ]

        while [0 != modulo (length executable) 4096] [
            append executable #{00}
        ] then [
            print ["Executable padded to" length executable "bytes long."]
        ] else [
            print ["No padding of executable length required."]
        ]

        append executable embedding

        size-as-binary: to-binary length embedding
        assert [8 = length size-as-binary]
        append executable size-as-binary

        append executable signature
    ]

    get-embedding: function [
        return: [binary! blank!]
        file [file!]

        <in> self
    ][
        info: query file

        test-sig: read/seek/part file (info/size - sig-length) sig-length

        if test-sig != signature [return blank]

        embed-size: to-integer/unsigned (
            read/seek/part file (info/size - sig-length - 8) 8
        )

        embed: read/seek/part file (
            info/size - sig-length - 8 - embed-size
        ) embed-size

        return embed
    ]
]


encap: function [
    return: [file!]
        {Path location of the resulting output}
    spec [file! block!]
        {Single script to embed, directory to zip with main.reb, or dialect}
    /rebol
        {Specify a path to a Rebol to encap instead of using the current one}
    in-rebol-path
][
    if block? spec [
        fail "The spec dialect for encapping has not been defined yet"
    ]

    in-rebol-path: default [system/options/boot]
    either ".exe" = base-name: skip tail in-rebol-path -4 [
        out-rebol-path: join-of
            copy/part in-rebol-path (index-of base-name) - 1
            "-encap.exe"
    ][
        out-rebol-path: join-of in-rebol-path "-encap"
    ]

    print ["Encapping from original executable:" in-rebol-path]

    executable: read in-rebol-path

    print ["Original executable is" length executable "bytes long."]

    single-script: not dir? spec

    either single-script [
        embed: read spec
        print ["New embedded resource size is" length embed "bytes long."]

        compressed: compress embed
    ][
        compressed: copy #{}
        zip/deep/verbose compressed spec
    ]

    print ["Compressed resource is" length compressed "bytes long."]

    ; !!! Renaming the single file "main.reb" and zipping it would probably
    ; be better, but the interface for zip doesn't allow you to override the
    ; actual names of disk files at this moment.  Just signal which it is.
    ;
    either single-script [
        insert compressed 0 ;-- signal a single file encap
    ][
        insert compressed 1 ;-- signal a zipped encap
    ]

    print ["Extending compressed resource by one byte for zipped/not signal"]

    case [
        parse executable [
            (elf-format/mode: 'read) elf-format/header-rule to end
        ][
            print "ELF format found"
            elf-format/update-embedding executable compressed
        ]
        pe-format/parse-exe executable [
            print "PE format found"
            pe-format/update-embedding executable compressed
        ]
        true [
            print "Unidentified executable format, using naive concatenation."

            generic-format/update-embedding executable compressed
        ]
    ]

    print ["Writing executable with encap, size, signature to" out-rebol-path]

    write out-rebol-path executable

    print ["Output executable written with total size" length executable]

    ; !!! Currently only test the extraction for single-file, easier.
    ;
    if all [single-script | embed != extracted: get-encap out-rebol-path] [
        print ["Test extraction size:" length extracted]
        print ["Embedded bytes" mold embed]
        print ["Extracted bytes" mold extracted]

        fail "Test extraction of embedding did not match original data."
    ]

    return out-rebol-path
]


get-encap: function [
    return: [blank! binary! block!]
        {Blank if no encapping found, binary if single file, block if archive}
    rebol-path [file!]
        {The executable to search for the encap information in}
][
    trap/with [
        read/part rebol-path 1
    ] func [e <with> return] [
        print ["Can't check for embedded code in Rebol path:" rebol-path]
        return blank
    ]

    unless compressed-data: any [
        elf-format/get-embedding rebol-path
            |
        pe-format/get-embedding rebol-path
            |
        generic-format/get-embedding rebol-path
    ][
        return blank
    ]

    switch compressed-data/1 [
        0 [
            return decompress next compressed-data
        ]
        1 [
            block: copy []
            unzip/quiet block next compressed-data
            return block
        ]
    ] else [
        fail ["Unknown embedding signature byte:" compressed-data/1]
    ]
]
