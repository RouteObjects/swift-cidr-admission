
Benchmarks/.build/arm64-apple-macosx/release/CIDR.build/AnyIP.swift.o:	file format mach-o arm64

Disassembly of section __TEXT,__text:

00000000000017bc <_$s4CIDR12AnyIPNetworkO8contains6subnetSbAC_tF>:
    17bc:      	b	0x17bc <_$s4CIDR12AnyIPNetworkO8contains6subnetSbAC_tF>
		00000000000017bc:  ARM64_RELOC_BRANCH26	_$s4CIDR12AnyIPNetworkO8contains7addressSbAA0B9IPAddressO_tFTm

00000000000017c0 <_$s4CIDR12AnyIPNetworkO8contains7addressSbAA0B9IPAddressO_tFTm>:
    17c0:      	ubfx	w9, w2, #8, #8
    17c4:      	and	w8, w5, #0xff00
    17c8:      	cmp	w8, #0x100
    17cc:      	b.ne	0x1844 <_$s4CIDR12AnyIPNetworkO8contains7addressSbAA0B9IPAddressO_tFTm+0x84>
    17d0:      	mov	w8, #0x0                ; =0
    17d4:      	cmp	w9, #0x1
    17d8:      	b.ne	0x1898 <_$s4CIDR12AnyIPNetworkO8contains7addressSbAA0B9IPAddressO_tFTm+0xd8>
    17dc:      	and	w9, w2, #0xff
    17e0:      	cmp	w9, w5, uxtb
    17e4:      	b.lo	0x1898 <_$s4CIDR12AnyIPNetworkO8contains7addressSbAA0B9IPAddressO_tFTm+0xd8>
    17e8:      	and	w8, w5, #0xff
    17ec:      	cmp	w8, #0x81
    17f0:      	b.hs	0x18a0 <_$s4CIDR12AnyIPNetworkO8contains7addressSbAA0B9IPAddressO_tFTm+0xe0>
    17f4:      	mov	w9, #0x80               ; =128
    17f8:      	mov	x10, #-0x1              ; =-1
    17fc:      	sub	w9, w9, w8
    1800:      	mvn	w11, w9
    1804:      	lsl	x10, x10, x9
    1808:      	mov	x12, #0x7fffffffffffffff ; =9223372036854775807
    180c:      	lsr	x11, x12, x11
    1810:      	orr	x11, x10, x11
    1814:      	and	x9, x9, #0xffff
    1818:      	tst	x9, #0x40
    181c:      	csel	x9, x10, x11, ne
    1820:      	csel	x10, xzr, x10, ne
    1824:      	cmp	w8, #0x0
    1828:      	csel	x8, xzr, x10, eq
    182c:      	csel	x9, xzr, x9, eq
    1830:      	and	x9, x9, x1
    1834:      	and	x8, x8, x0
    1838:      	cmp	x8, x3
    183c:      	ccmp	x9, x4, #0x0, eq
    1840:      	b	0x1894 <_$s4CIDR12AnyIPNetworkO8contains7addressSbAA0B9IPAddressO_tFTm+0xd4>
    1844:      	cmp	w9, #0x1
    1848:      	b.ne	0x1854 <_$s4CIDR12AnyIPNetworkO8contains7addressSbAA0B9IPAddressO_tFTm+0x94>
    184c:      	mov	w0, #0x0                ; =0
    1850:      	ret
    1854:      	lsr	x8, x3, #32
    1858:      	ubfx	x9, x0, #32, #8
    185c:      	cmp	w9, w8, uxtb
    1860:      	b.hs	0x186c <_$s4CIDR12AnyIPNetworkO8contains7addressSbAA0B9IPAddressO_tFTm+0xac>
    1864:      	mov	w0, #0x0                ; =0
    1868:      	ret
    186c:      	ubfx	x8, x3, #32, #8
    1870:      	cmp	x8, #0x20
    1874:      	b.hi	0x18a4 <_$s4CIDR12AnyIPNetworkO8contains7addressSbAA0B9IPAddressO_tFTm+0xe4>
    1878:      	neg	w9, w8
    187c:      	mov	w10, #-0x1              ; =-1
    1880:      	lsl	w9, w10, w9
    1884:      	cmp	x8, #0x0
    1888:      	csel	w8, wzr, w9, eq
    188c:      	and	w8, w8, w0
    1890:      	cmp	w8, w3
    1894:      	cset	w8, eq
    1898:      	mov	x0, x8
    189c:      	ret
    18a0:      	brk	#0x1
    18a4:      	brk	#0x1

00000000000064e0 <_$s4CIDR12AnyIPNetworkO8contains7addressSbAA0B9IPAddressO_tF>:
    64e0:      	b	0x64e0 <_$s4CIDR12AnyIPNetworkO8contains7addressSbAA0B9IPAddressO_tF>
		00000000000064e0:  ARM64_RELOC_BRANCH26	_$s4CIDR12AnyIPNetworkO8contains6subnetSbAC_tF
