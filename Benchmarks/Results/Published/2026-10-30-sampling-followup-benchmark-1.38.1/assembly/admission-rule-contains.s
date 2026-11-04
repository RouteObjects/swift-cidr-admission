
Benchmarks/.build/arm64-apple-macosx/release/CIDRAdmission.build/AdmissionRule.swift.o:	file format mach-o arm64

Disassembly of section __TEXT,__text:

00000000000000b4 <_$s13CIDRAdmission13AdmissionRuleO8containsySb4CIDR12AnyIPAddressOF>:
      b4:      	sub	sp, sp, #0x70
      b8:      	stp	x22, x21, [sp, #0x40]
      bc:      	stp	x20, x19, [sp, #0x50]
      c0:      	stp	x29, x30, [sp, #0x60]
      c4:      	add	x29, sp, #0x60
      c8:      	ldp	x8, x9, [x20]
      cc:      	ldr	x10, [x20, #0x10]
      d0:      	ldrb	w12, [x20, #0x20]
      d4:      	lsr	w13, w12, #6
      d8:      	and	w11, w2, #0xffffff00
      dc:      	cbz	w13, 0x158 <_$s13CIDRAdmission13AdmissionRuleO8containsySb4CIDR12AnyIPAddressOF+0xa4>
      e0:      	cmp	w13, #0x1
      e4:      	b.ne	0x18c <_$s13CIDRAdmission13AdmissionRuleO8containsySb4CIDR12AnyIPAddressOF+0xd8>
      e8:      	and	x12, x10, #0xff00
      ec:      	cmp	x12, #0x100
      f0:      	b.ne	0x1fc <_$s13CIDRAdmission13AdmissionRuleO8containsySb4CIDR12AnyIPAddressOF+0x148>
      f4:      	and	w11, w11, #0xffff
      f8:      	cmp	w11, #0x100
      fc:      	b.ne	0x208 <_$s13CIDRAdmission13AdmissionRuleO8containsySb4CIDR12AnyIPAddressOF+0x154>
     100:      	stp	x8, x9, [sp, #0x20]
     104:      	strb	w10, [sp, #0x30]
     108:      	mov	x19, x0
     10c:      	mov	x20, x1
     110:      	bl	0x110 <_$s13CIDRAdmission13AdmissionRuleO8containsySb4CIDR12AnyIPAddressOF+0x5c>
		0000000000000110:  ARM64_RELOC_BRANCH26	_$s4CIDR2AFO2V6OAeA15IPAddressFamilyAAWl
     114:      	mov	x1, x0
     118:      	adrp	x0, 0x0 <ltmp0>
		0000000000000118:  ARM64_RELOC_GOT_LOAD_PAGE21	_$s4CIDR2AFO2V6ON
     11c:      	ldr	x0, [x0]
		000000000000011c:  ARM64_RELOC_GOT_LOAD_PAGEOFF12	_$s4CIDR2AFO2V6ON
     120:      	bl	0x120 <_$s13CIDRAdmission13AdmissionRuleO8containsySb4CIDR12AnyIPAddressOF+0x6c>
		0000000000000120:  ARM64_RELOC_BRANCH26	_$s4CIDR12PrefixLengthV7maximumACyxGvgZ
     124:      	stp	x19, x20, [sp]
     128:      	strb	w0, [sp, #0x10]
     12c:      	adrp	x19, 0x0 <ltmp0>
		000000000000012c:  ARM64_RELOC_PAGE21	_$s4CIDR9IPNetworkVyAA2AFO2V6OGMd
     130:      	add	x19, x19, #0x0
		0000000000000130:  ARM64_RELOC_PAGEOFF12	_$s4CIDR9IPNetworkVyAA2AFO2V6OGMd
     134:      	adrp	x20, 0x0 <ltmp0>
		0000000000000134:  ARM64_RELOC_PAGE21	_$s4CIDR9IPNetworkVyAA2AFO2V6OGMR
     138:      	add	x20, x20, #0x0
		0000000000000138:  ARM64_RELOC_PAGEOFF12	_$s4CIDR9IPNetworkVyAA2AFO2V6OGMR
     13c:      	mov	x0, x19
     140:      	mov	x1, x20
     144:      	bl	0x144 <_$s13CIDRAdmission13AdmissionRuleO8containsySb4CIDR12AnyIPAddressOF+0x90>
		0000000000000144:  ARM64_RELOC_BRANCH26	___swift_instantiateConcreteTypeFromMangledNameV2
     148:      	mov	x21, x0
     14c:      	adrp	x0, 0x0 <ltmp0>
		000000000000014c:  ARM64_RELOC_PAGE21	_$s4CIDR9IPNetworkVyAA2AFO2V6OGACyxGAA8IPPrefixAAWL
     150:      	add	x0, x0, #0x0
		0000000000000150:  ARM64_RELOC_PAGEOFF12	_$s4CIDR9IPNetworkVyAA2AFO2V6OGACyxGAA8IPPrefixAAWL
     154:      	b	0x264 <_$s13CIDRAdmission13AdmissionRuleO8containsySb4CIDR12AnyIPAddressOF+0x1b0>
     158:      	and	x10, x10, #0xff00
     15c:      	and	w11, w11, #0xffff
     160:      	cmp	x8, x0
     164:      	ccmp	x9, x1, #0x0, eq
     168:      	cset	w9, eq
     16c:      	cmp	w11, #0x100
     170:      	csel	w9, wzr, w9, ne
     174:      	cmp	w8, w0
     178:      	cset	w8, eq
     17c:      	cmp	w11, #0x100
     180:      	csel	w8, wzr, w8, eq
     184:      	cmp	x10, #0x100
     188:      	b	0x1e0 <_$s13CIDRAdmission13AdmissionRuleO8containsySb4CIDR12AnyIPAddressOF+0x12c>
     18c:      	ldr	x13, [x20, #0x18]
     190:      	and	w12, w12, #0x3f
     194:      	and	w11, w11, #0xffff
     198:      	cmp	x0, x8
     19c:      	sbcs	xzr, x1, x9
     1a0:      	cset	w9, lo
     1a4:      	cmp	x10, x0
     1a8:      	sbcs	xzr, x13, x1
     1ac:      	cset	w10, hs
     1b0:      	tst	w9, #0x1
     1b4:      	csel	w9, wzr, w10, ne
     1b8:      	cmp	w11, #0x100
     1bc:      	csel	w9, wzr, w9, ne
     1c0:      	lsr	x10, x8, #32
     1c4:      	cmp	w10, w0
     1c8:      	cset	w10, hs
     1cc:      	cmp	w0, w8
     1d0:      	csel	w8, wzr, w10, lo
     1d4:      	cmp	w11, #0x100
     1d8:      	csel	w8, wzr, w8, eq
     1dc:      	cmp	w12, #0x1
     1e0:      	csel	w0, w9, w8, eq
     1e4:      	and	w0, w0, #0x1
     1e8:      	ldp	x29, x30, [sp, #0x60]
     1ec:      	ldp	x20, x19, [sp, #0x50]
     1f0:      	ldp	x22, x21, [sp, #0x40]
     1f4:      	add	sp, sp, #0x70
     1f8:      	ret
     1fc:      	and	w9, w11, #0xffff
     200:      	cmp	w9, #0x100
     204:      	b.ne	0x210 <_$s13CIDRAdmission13AdmissionRuleO8containsySb4CIDR12AnyIPAddressOF+0x15c>
     208:      	mov	w0, #0x0                ; =0
     20c:      	b	0x1e4 <_$s13CIDRAdmission13AdmissionRuleO8containsySb4CIDR12AnyIPAddressOF+0x130>
     210:      	str	w8, [sp, #0x20]
     214:      	lsr	x8, x8, #32
     218:      	strb	w8, [sp, #0x24]
     21c:      	mov	x19, x0
     220:      	bl	0x220 <_$s13CIDRAdmission13AdmissionRuleO8containsySb4CIDR12AnyIPAddressOF+0x16c>
		0000000000000220:  ARM64_RELOC_BRANCH26	_$s4CIDR2AFO2V4OAeA15IPAddressFamilyAAWl
     224:      	mov	x1, x0
     228:      	adrp	x0, 0x0 <ltmp0>
		0000000000000228:  ARM64_RELOC_GOT_LOAD_PAGE21	_$s4CIDR2AFO2V4ON
     22c:      	ldr	x0, [x0]
		000000000000022c:  ARM64_RELOC_GOT_LOAD_PAGEOFF12	_$s4CIDR2AFO2V4ON
     230:      	bl	0x230 <_$s13CIDRAdmission13AdmissionRuleO8containsySb4CIDR12AnyIPAddressOF+0x17c>
		0000000000000230:  ARM64_RELOC_BRANCH26	_$s4CIDR12PrefixLengthV7maximumACyxGvgZ
     234:      	str	w19, [sp]
     238:      	strb	w0, [sp, #0x4]
     23c:      	adrp	x19, 0x0 <ltmp0>
		000000000000023c:  ARM64_RELOC_PAGE21	_$s4CIDR9IPNetworkVyAA2AFO2V4OGMd
     240:      	add	x19, x19, #0x0
		0000000000000240:  ARM64_RELOC_PAGEOFF12	_$s4CIDR9IPNetworkVyAA2AFO2V4OGMd
     244:      	adrp	x20, 0x0 <ltmp0>
		0000000000000244:  ARM64_RELOC_PAGE21	_$s4CIDR9IPNetworkVyAA2AFO2V4OGMR
     248:      	add	x20, x20, #0x0
		0000000000000248:  ARM64_RELOC_PAGEOFF12	_$s4CIDR9IPNetworkVyAA2AFO2V4OGMR
     24c:      	mov	x0, x19
     250:      	mov	x1, x20
     254:      	bl	0x254 <_$s13CIDRAdmission13AdmissionRuleO8containsySb4CIDR12AnyIPAddressOF+0x1a0>
		0000000000000254:  ARM64_RELOC_BRANCH26	___swift_instantiateConcreteTypeFromMangledNameV2
     258:      	mov	x21, x0
     25c:      	adrp	x0, 0x0 <ltmp0>
		000000000000025c:  ARM64_RELOC_PAGE21	_$s4CIDR9IPNetworkVyAA2AFO2V4OGACyxGAA8IPPrefixAAWL
     260:      	add	x0, x0, #0x0
		0000000000000260:  ARM64_RELOC_PAGEOFF12	_$s4CIDR9IPNetworkVyAA2AFO2V4OGACyxGAA8IPPrefixAAWL
     264:      	mov	x1, x19
     268:      	mov	x2, x20
     26c:      	bl	0x26c <_$s13CIDRAdmission13AdmissionRuleO8containsySb4CIDR12AnyIPAddressOF+0x1b8>
		000000000000026c:  ARM64_RELOC_BRANCH26	_$s4CIDR9IPNetworkVyAA2AFO2V6OGACyxGAA8IPPrefixAAWlTm
     270:      	mov	x2, x0
     274:      	mov	x0, sp
     278:      	add	x20, sp, #0x20
     27c:      	mov	x1, x21
     280:      	bl	0x280 <_$s13CIDRAdmission13AdmissionRuleO8containsySb4CIDR12AnyIPAddressOF+0x1cc>
		0000000000000280:  ARM64_RELOC_BRANCH26	_$s4CIDR8IPPrefixPAAE8contains7addressSbAA9IPAddressVy6FamilyQzG_tF
     284:      	b	0x1e4 <_$s13CIDRAdmission13AdmissionRuleO8containsySb4CIDR12AnyIPAddressOF+0x130>
