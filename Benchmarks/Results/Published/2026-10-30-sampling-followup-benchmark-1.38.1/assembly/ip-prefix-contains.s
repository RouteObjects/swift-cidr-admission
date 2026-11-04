
Benchmarks/.build/arm64-apple-macosx/release/CIDR.build/IPPrefix.swift.o:	file format mach-o arm64

Disassembly of section __TEXT,__text:

0000000000000430 <_$s4CIDR8IPPrefixPAAE8contains7addressSbAA9IPAddressVy6FamilyQzG_tF>:
     430:      	stp	x28, x27, [sp, #-0x60]!
     434:      	stp	x26, x25, [sp, #0x10]
     438:      	stp	x24, x23, [sp, #0x20]
     43c:      	stp	x22, x21, [sp, #0x30]
     440:      	stp	x20, x19, [sp, #0x40]
     444:      	stp	x29, x30, [sp, #0x50]
     448:      	add	x29, sp, #0x50
     44c:      	sub	sp, sp, #0x30
     450:      	mov	x24, x20
     454:      	mov	x22, x1
     458:      	mov	x26, x0
     45c:      	stur	x2, [x29, #-0x60]
     460:      	ldr	x27, [x2, #0x8]
     464:      	adrp	x20, 0x0 <ltmp0>
		0000000000000464:  ARM64_RELOC_GOT_LOAD_PAGE21	_$s4CIDRAATL
     468:      	ldr	x20, [x20]
		0000000000000468:  ARM64_RELOC_GOT_LOAD_PAGEOFF12	_$s4CIDRAATL
     46c:      	adrp	x4, 0x0 <ltmp0>
		000000000000046c:  ARM64_RELOC_GOT_LOAD_PAGE21	_$s6Family4CIDRABPTl
     470:      	ldr	x4, [x4]
		0000000000000470:  ARM64_RELOC_GOT_LOAD_PAGEOFF12	_$s6Family4CIDRABPTl
     474:      	mov	w0, #0xff               ; =255
     478:      	mov	x1, x27
     47c:      	mov	x2, x22
     480:      	mov	x3, x20
     484:      	bl	0x484 <_$s4CIDR8IPPrefixPAAE8contains7addressSbAA9IPAddressVy6FamilyQzG_tF+0x54>
		0000000000000484:  ARM64_RELOC_BRANCH26	_swift_getAssociatedTypeWitness
     488:      	mov	x28, x0
     48c:      	adrp	x4, 0x0 <ltmp0>
		000000000000048c:  ARM64_RELOC_GOT_LOAD_PAGE21	_$s4CIDRAAP6FamilyAB_AA09IPAddressB0Tn
     490:      	ldr	x4, [x4]
		0000000000000490:  ARM64_RELOC_GOT_LOAD_PAGEOFF12	_$s4CIDRAAP6FamilyAB_AA09IPAddressB0Tn
     494:      	mov	x0, x27
     498:      	mov	x1, x22
     49c:      	mov	x2, x28
     4a0:      	mov	x3, x20
     4a4:      	bl	0x4a4 <_$s4CIDR8IPPrefixPAAE8contains7addressSbAA9IPAddressVy6FamilyQzG_tF+0x74>
		00000000000004a4:  ARM64_RELOC_BRANCH26	_swift_getAssociatedConformanceWitness
     4a8:      	mov	x20, x0
     4ac:      	ldr	x1, [x0, #0x8]
     4b0:      	adrp	x3, 0x0 <ltmp0>
		00000000000004b0:  ARM64_RELOC_GOT_LOAD_PAGE21	_$s4CIDR13AddressFamilyTL
     4b4:      	ldr	x3, [x3]
		00000000000004b4:  ARM64_RELOC_GOT_LOAD_PAGEOFF12	_$s4CIDR13AddressFamilyTL
     4b8:      	adrp	x4, 0x0 <ltmp0>
		00000000000004b8:  ARM64_RELOC_GOT_LOAD_PAGE21	_$s7Storage4CIDR13AddressFamilyPTl
     4bc:      	ldr	x4, [x4]
		00000000000004bc:  ARM64_RELOC_GOT_LOAD_PAGEOFF12	_$s7Storage4CIDR13AddressFamilyPTl
     4c0:      	mov	x0, #0x0                ; =0
     4c4:      	stur	x1, [x29, #-0x80]
     4c8:      	mov	x2, x28
     4cc:      	bl	0x4cc <_$s4CIDR8IPPrefixPAAE8contains7addressSbAA9IPAddressVy6FamilyQzG_tF+0x9c>
		00000000000004cc:  ARM64_RELOC_BRANCH26	_swift_getAssociatedTypeWitness
     4d0:      	mov	x23, x0
     4d4:      	ldur	x8, [x0, #-0x8]
     4d8:      	stur	x8, [x29, #-0x78]
     4dc:      	ldr	x8, [x8, #0x40]
     4e0:      	mov	x9, x8
     4e4:      	adrp	x16, 0x0 <ltmp0>
		00000000000004e4:  ARM64_RELOC_GOT_LOAD_PAGE21	___chkstk_darwin
     4e8:      	ldr	x16, [x16]
		00000000000004e8:  ARM64_RELOC_GOT_LOAD_PAGEOFF12	___chkstk_darwin
     4ec:      	blr	x16
     4f0:      	mov	x9, sp
     4f4:      	add	x10, x8, #0xf
     4f8:      	and	x12, x10, #0xfffffffffffffff0
     4fc:      	sub	x25, x9, x12
     500:      	mov	sp, x25
     504:      	mov	x9, x8
     508:      	adrp	x16, 0x0 <ltmp0>
		0000000000000508:  ARM64_RELOC_GOT_LOAD_PAGE21	___chkstk_darwin
     50c:      	ldr	x16, [x16]
		000000000000050c:  ARM64_RELOC_GOT_LOAD_PAGEOFF12	___chkstk_darwin
     510:      	blr	x16
     514:      	mov	x8, sp
     518:      	sub	x8, x8, x12
     51c:      	stur	x8, [x29, #-0x70]
     520:      	mov	sp, x8
     524:      	mov	x0, #0x0                ; =0
     528:      	mov	x1, x28
     52c:      	mov	x2, x20
     530:      	bl	0x530 <_$s4CIDR8IPPrefixPAAE8contains7addressSbAA9IPAddressVy6FamilyQzG_tF+0x100>
		0000000000000530:  ARM64_RELOC_BRANCH26	_$s4CIDR12PrefixLengthVMa
     534:      	mov	x19, x0
     538:      	mov	x0, #0x0                ; =0
     53c:      	mov	x1, x28
     540:      	mov	x2, x20
     544:      	bl	0x544 <_$s4CIDR8IPPrefixPAAE8contains7addressSbAA9IPAddressVy6FamilyQzG_tF+0x114>
		0000000000000544:  ARM64_RELOC_BRANCH26	_$s4CIDR9IPAddressVMa
     548:      	ldrsw	x21, [x0, #0x24]
     54c:      	ldr	x8, [x27, #0x30]
     550:      	stur	x24, [x29, #-0x68]
     554:      	mov	x20, x24
     558:      	mov	x0, x22
     55c:      	mov	x1, x27
     560:      	blr	x8
     564:      	sturb	w0, [x29, #-0x51]
     568:      	adrp	x0, 0x0 <ltmp0>
		0000000000000568:  ARM64_RELOC_GOT_LOAD_PAGE21	_$s4CIDR12PrefixLengthVyxGSLAAMc
     56c:      	ldr	x0, [x0]
		000000000000056c:  ARM64_RELOC_GOT_LOAD_PAGEOFF12	_$s4CIDR12PrefixLengthVyxGSLAAMc
     570:      	mov	x1, x19
     574:      	bl	0x574 <_$s4CIDR8IPPrefixPAAE8contains7addressSbAA9IPAddressVy6FamilyQzG_tF+0x144>
		0000000000000574:  ARM64_RELOC_BRANCH26	_swift_getWitnessTable
     578:      	mov	x3, x0
     57c:      	add	x0, x26, x21
     580:      	sub	x1, x29, #0x51
     584:      	mov	x2, x19
     588:      	mov	x20, x19
     58c:      	bl	0x58c <_$s4CIDR8IPPrefixPAAE8contains7addressSbAA9IPAddressVy6FamilyQzG_tF+0x15c>
		000000000000058c:  ARM64_RELOC_BRANCH26	_$sSLsE2geoiySbx_xtFZ
     590:      	tbz	w0, #0x0, 0x658 <_$s4CIDR8IPPrefixPAAE8contains7addressSbAA9IPAddressVy6FamilyQzG_tF+0x228>
     594:      	mov	x8, x25
     598:      	mov	x0, x22
     59c:      	mov	x1, x27
     5a0:      	ldur	x24, [x29, #-0x68]
     5a4:      	mov	x20, x24
     5a8:      	bl	0x5a8 <_$s4CIDR8IPPrefixPAAE8contains7addressSbAA9IPAddressVy6FamilyQzG_tF+0x178>
		00000000000005a8:  ARM64_RELOC_BRANCH26	_$s4CIDRAAPAAE4mask6Family_7StorageQZvg
     5ac:      	adrp	x3, 0x0 <ltmp0>
		00000000000005ac:  ARM64_RELOC_GOT_LOAD_PAGE21	_$s4CIDR13AddressFamilyTL
     5b0:      	ldr	x3, [x3]
		00000000000005b0:  ARM64_RELOC_GOT_LOAD_PAGEOFF12	_$s4CIDR13AddressFamilyTL
     5b4:      	adrp	x4, 0x0 <ltmp0>
		00000000000005b4:  ARM64_RELOC_GOT_LOAD_PAGE21	_$s4CIDR13AddressFamilyP7StorageAC_s17FixedWidthIntegerTn
     5b8:      	ldr	x4, [x4]
		00000000000005b8:  ARM64_RELOC_GOT_LOAD_PAGEOFF12	_$s4CIDR13AddressFamilyP7StorageAC_s17FixedWidthIntegerTn
     5bc:      	ldur	x0, [x29, #-0x80]
     5c0:      	mov	x1, x28
     5c4:      	mov	x2, x23
     5c8:      	bl	0x5c8 <_$s4CIDR8IPPrefixPAAE8contains7addressSbAA9IPAddressVy6FamilyQzG_tF+0x198>
		00000000000005c8:  ARM64_RELOC_BRANCH26	_swift_getAssociatedConformanceWitness
     5cc:      	ldr	x19, [x0, #0x8]
     5d0:      	ldur	x27, [x29, #-0x70]
     5d4:      	mov	x8, x27
     5d8:      	mov	x0, x26
     5dc:      	mov	x1, x25
     5e0:      	mov	x20, x23
     5e4:      	mov	x2, x23
     5e8:      	mov	x3, x19
     5ec:      	bl	0x5ec <_$s4CIDR8IPPrefixPAAE8contains7addressSbAA9IPAddressVy6FamilyQzG_tF+0x1bc>
		00000000000005ec:  ARM64_RELOC_BRANCH26	_$sSz1aoiyxx_xtFZTj
     5f0:      	ldur	x8, [x29, #-0x78]
     5f4:      	ldr	x21, [x8, #0x8]
     5f8:      	mov	x0, x25
     5fc:      	mov	x1, x23
     600:      	blr	x21
     604:      	ldur	x1, [x29, #-0x60]
     608:      	ldr	x9, [x1, #0x10]
     60c:      	mov	x8, x25
     610:      	mov	x20, x24
     614:      	mov	x0, x22
     618:      	blr	x9
     61c:      	ldr	x8, [x19, #0x10]
     620:      	ldr	x3, [x8, #0x8]
     624:      	mov	x0, x27
     628:      	mov	x1, x25
     62c:      	mov	x20, x23
     630:      	mov	x2, x23
     634:      	bl	0x634 <_$s4CIDR8IPPrefixPAAE8contains7addressSbAA9IPAddressVy6FamilyQzG_tF+0x204>
		0000000000000634:  ARM64_RELOC_BRANCH26	_$sSQ2eeoiySbx_xtFZTj
     638:      	mov	x19, x0
     63c:      	mov	x0, x25
     640:      	mov	x1, x23
     644:      	blr	x21
     648:      	mov	x0, x27
     64c:      	mov	x1, x23
     650:      	blr	x21
     654:      	b	0x65c <_$s4CIDR8IPPrefixPAAE8contains7addressSbAA9IPAddressVy6FamilyQzG_tF+0x22c>
     658:      	mov	w19, #0x0               ; =0
     65c:      	and	w0, w19, #0x1
     660:      	sub	sp, x29, #0x50
     664:      	ldp	x29, x30, [sp, #0x50]
     668:      	ldp	x20, x19, [sp, #0x40]
     66c:      	ldp	x22, x21, [sp, #0x30]
     670:      	ldp	x24, x23, [sp, #0x20]
     674:      	ldp	x26, x25, [sp, #0x10]
     678:      	ldp	x28, x27, [sp], #0x60
     67c:      	ret
