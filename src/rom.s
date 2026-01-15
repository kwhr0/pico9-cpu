; VGM Player

`define INIT_NUM		1		;1-
`define INIT_VOL		4		;0-7

`define SIZEOF_DIRENT	0x20
`define RDE_LEN			0x4000
`define LIM_USERCLUSTER	0xfff7

`define UART

; mask of i_flags
`define TIMER_ACTIVE	1
`define SPI_BUSY		2
`define I2C_BUSY		4
`define TX_READY		8
`define BTN_VOL			0x20
`define BTN_DN			0x40
`define BTN_UP			0x80

; input

	data	0

	i_flags
	dummy1
	i_card

; output

	data	8

	o_timer.2
	o_dcsg
	o_i2c
	o_volume
	o_tx
	o_card
	o_card_ctl

; work

	data	0x10

	card_io_a
	card_io_ret
	card_skip_a
	card_read_ret
crc:	db	0x95	;must be just before card_param
	card_param.4
	card_command_a
	card_command_ret
	sector.3
	sector_ofs
	sector_ofs_a
	fat.3
	rde.3
	tmp.3
	i
	bytes
	getc_ret
	cluster.2
	f_len.3
	f_ofs.3
	setcluster_a.2
	clustermask.2
	clustershift
	dirread_ret
	buf.32
	strp.2
	vgm_index
	vgm_ret
	dcsg_regnum.2	;reserve upper byte for pointer
	dcsg_freq.4
	dcsg_vol.4
	refresh
	i2c_byte_a
led_init_data:
`include "ssd1306xled.inc"
	led_setpos_x
	led_setpos_y
	led_putc_a
	led_test_c
	led_putnum_a
	font_ptr.2
font_w:
	db	0x00,0x03,0x0c,0x0f,0x30,0x33,0x3c,0x3f
	db	0xc0,0xc3,0xcc,0xcf,0xf0,0xf3,0xfc,0xff
	update_meter_a
	button_last_n
	uart_putc_a
	uart_puthex_a

	data	0x200

font:
`include "font6x8.inc"

	text

	call	main
inf:
	b	inf

; ---- I2C & Display ----

; arg: i2c_byte_a
func i2c_byte
	tst	i_flags,#I2C_BUSY
	bnz	i2c_byte
	mov	o_i2c,i2c_byte_a
	ret
endfunc

; use: i2c_byte_a
func i2c_start_command
	mov	i2c_byte_a,#0x78
	call	i2c_byte
	mov	i2c_byte_a,#0
	call	i2c_byte
	ret
endfunc

; use: i2c_byte_a
func i2c_start_data
	mov	i2c_byte_a,#0x78
	call	i2c_byte
	mov	i2c_byte_a,#0x40
	call	i2c_byte
	ret
endfunc

func i2c_stop
	tst	i_flags,#I2C_BUSY
	bnz	i2c_stop
	mov	o_i2c,#0x1ff
	ret
endfunc

; arg: led_setpos_x,led_setpos_y
; use: i2c_byte_a
func led_setpos
	call	i2c_start_command
	mov	i2c_byte_a,led_setpos_y
	and	i2c_byte_a,#7
	or	i2c_byte_a,#0xb0
	call	i2c_byte
	mov	i2c_byte_a,led_setpos_x
	and	i2c_byte_a,#0xf
	call	i2c_byte
	srl	i2c_byte_a,led_setpos_x
	srl	i2c_byte_a,i2c_byte_a
	srl	i2c_byte_a,i2c_byte_a
	srl	i2c_byte_a,i2c_byte_a
	or	i2c_byte_a,#0x10
	call	i2c_byte
	call	i2c_stop
	ret
endfunc

; update: led_setpos_x,led_setpos_y
; use: i2c_byte_a,tmp.2
func led_cls
	mov.2	tmp,#0x400
	call	i2c_start_data
1:
	mov	i2c_byte_a,#0
	call	i2c_byte
	sub.2	tmp,#1
	bnz	1
	call	i2c_stop
	mov	led_setpos_x,#0
	mov	led_setpos_y,#0
	call	led_setpos
	ret
endfunc

; use: i2c_byte_a,tmp.2,sp
func led_init
	call	i2c_start_command
	lsp	#led_init_data
	mov	tmp,#32
1:
	mov	i2c_byte_a,[sp+]
	call	i2c_byte
	sub	tmp,#1
	bnz	1
	call	i2c_stop
	call	led_cls
	ret
endfunc

; in: led_putc_a
; use: led_putc_a,tmp.3,i2c_byte_a,font_ptr.2,sp
; update: led_setpos_x,led_setpos_y
func led_putc
	sub	led_putc_a,#0x20
	mov	font_ptr,led_putc_a
	add	font_ptr,font_ptr
	mov	font_ptr+1,#0
	add.2	font_ptr,led_putc_a
	add.2	font_ptr,font_ptr
	add.2	font_ptr,#font
	call	led_setpos
	call	i2c_start_data
	mov.2	tmp+1,#0x600
2:
	lsp	font_ptr
	mov	tmp,[sp+]
	ssp	font_ptr
	and	tmp,#0xf
	lsp	tmp
	mov	i2c_byte_a,font_w[sp]
	call	i2c_byte
	call	i2c_byte
	sub	tmp+2,#1
	bnz	2
	call	i2c_stop
	;
	add	led_setpos_y,#1
	call	led_setpos
	call	i2c_start_data
	sub.2	font_ptr,#6
	mov	tmp+2,#6
3:
	lsp	font_ptr
	srl	tmp,[sp+]
	ssp	font_ptr
	srl	tmp,tmp
	srl	tmp,tmp
	srl	tmp,tmp
	lsp	tmp
	mov	i2c_byte_a,font_w[sp]
	call	i2c_byte
	call	i2c_byte
	sub	tmp+2,#1
	bnz	3
	call	i2c_stop
	sub	led_setpos_y,#1
	add	led_setpos_x,#2*6
	cmp	led_setpos_x,#128
	bc	9
	mov	led_setpos_x,#0
	add	led_setpos_y,#2
	cmp	led_setpos_y,#8
	bc	9
	mov	led_setpos_y,#0
9:
	ret
endfunc

; arg: led_putnum_a
; use: led_putnum_a,led_putc_a,i2c_byte_a,tmp.3,font_ptr.2,sp
func led_putnum
	mov	led_putc_a,#0x30
2:
	cmp	led_putnum_a,#100
	bc	1
	sub	led_putnum_a,#100
	add	led_putc_a,#1
	b	2
1:
	call	led_putc
	mov	led_putc_a,#0x30
4:
	cmp	led_putnum_a,#10
	bc	3
	sub	led_putnum_a,#10
	add	led_putc_a,#1
	b	4
3:
	call	led_putc
	mov	led_putc_a,#0x30
	add	led_putc_a,led_putnum_a
	call	led_putc
	ret
endfunc

; ---- SD card ----

; arg: card_io_a
; ret: card_io_ret
func card_io
	mov	o_card,card_io_a
1:
	tst	i_flags,#SPI_BUSY
	bnz	1
	mov	card_io_ret,i_card
	ret
endfunc

; arg: card_skip_a
; use: card_io_a,card_skip_a,card_io_ret
func card_skip
1:
	mov	card_io_a,#0xff
	call	card_io
	sub	card_skip_a,#1
	bnz9	1
	ret
endfunc

; arg: card_command_a
;      card_param.4
; use: card_io_a,card_skip_a,card_io_ret,i,sp
; ret: card_command_ret
func card_command
2:
	mov	card_io_a,#0xff
	call	card_io
	cmp	card_io_ret,#0xff
	bnz	2
	mov	card_io_a,card_command_a
	or	card_io_a,#0x40
	call	card_io
	lsp	#card_param+3
	mov	i,#5
3:
	mov	card_io_a,[sp-]
	call	card_io
	sub	i,#1
	bnz	3
1:
	mov	card_io_a,#0xff
	call	card_io
	cmp	card_io_ret,#0xff
	bz	1
	mov	card_command_ret,card_io_ret
	mov	card_skip_a,#1
	call	card_skip
	ret

endfunc

func card_init
	mov	o_card_ctl,#1	;fast=0,cs=1
	mov	card_skip_a,#10	;80 dummy clock
	call	card_skip
	mov	o_card_ctl,#0	;fast=0,cs=0
;	mov	card_command_a,#0
;	mov.4	card_param,#0
	call	card_command
1:
	mov	card_command_a,#1
;	mov.4	card_param,#0
	call	card_command
	cmp	card_command_ret,#0
	bnz	1
	mov	o_card_ctl,#2	;fast=1,cs=0
	ret
endfunc

; arg: sector.3
; use: card_io_a,card_skip_a,card_io_ret,i,sp
func card_sector
	mov	card_command_a,#17
	mov	card_param,#0
	mov.3	card_param+1,sector
	add.3	card_param+1,card_param+1
	call	card_command
1:
	mov	card_io_a,#0xff
	call	card_io
	cmp	card_io_ret,#0xfe
	bnz	1
	ret
endfunc

; arg: sector.3
;      sector_ofs_a
; use: card_io_a,card_skip_a,card_io_ret,i,sp
; update: sector_ofs
func card_setadr
	mov	card_skip_a,#0
	sub	card_skip_a,sector_ofs	;old offset
	bz9	2
	call	card_skip
	mov	card_skip_a,#2
	call	card_skip
2:
	mov	sector_ofs,sector_ofs_a	;new offset
	bz9	1
	call	card_sector
	mov	card_skip_a,sector_ofs
	call	card_skip
1:
	ret
endfunc

; use: card_io_a,card_skip_a,card_io_ret,i,sp
; update: sector.3,sector_ofs
; ret: card_read_ret
func card_read
	cmp	sector_ofs,#0
	bnz9	2
	call	card_sector
2:
	mov	card_io_a,#0xff
	call	card_io
	mov	card_read_ret,card_io_ret
	add	sector_ofs,#1
	bnz9	1
	mov	card_skip_a,#2
	call	card_skip
	add.3	sector,#1
1:
	ret
endfunc

; ---- File & Directory ----

func file_init
	mov.3	sector,#0
	mov	sector_ofs_a,#0x1c6
	call	card_setadr
	call	card_read
	mov	sector,card_read_ret
	call	card_read
	mov	sector+1,card_read_ret
	call	card_read
	mov	sector+2,card_read_ret
	mov.3	fat,sector
	add.3	fat,#1	;fat sector number
	mov	sector_ofs_a,#13	;sector per cluster
	call	card_setadr
	ldp	#buf
	mov	i,#11
4:
	call	card_read
	mov	[dp+],card_read_ret
	sub	i,#1
	bnz	4
	mov	clustermask,#0
	mov	clustermask+1,buf
	add.2	clustermask,clustermask
	sub.2	clustermask,#1
	mov	clustershift,#0
	b	3
2:
	add	clustershift,#1	;sector number shift count
3:
	srl	buf,buf
	bnz	2
	mov.2	rde,buf+9
	mov	rde+2,#0
	add.3	rde,rde
	add.3	rde,fat
	ret
endfunc

; arg: setcluster_a.2
; update: sector.3,sector_ofs
; use: card_io_a,card_skip_a,card_io_ret,i,tmp.3,sp
func setcluster
	cmp.2	setcluster_a,#LIM_USERCLUSTER
	bnc	9
	mov.3	sector,rde
	mov.2	tmp,setcluster_a
	bz	3
	mov	tmp+2,#0
	sub.2	tmp,#2
	mov	i,clustershift
	bz	1
2:
	add.3	tmp,tmp
	sub	i,#1
	bnz	2
1:
	add.3	tmp,#RDE_LEN>>9
	add.3	sector,tmp
3:
	mov	sector_ofs_a,#0
	call	card_setadr
	mov.2	cluster,setcluster_a
9:
	ret
endfunc

; arg: setcluster_a.2
;      f_len.3
func file_open
	call	setcluster
	mov.3	f_ofs,#0
	ret
endfunc

; in: cluster
; use: sector_ofs_a,card_io_a,card_skip_a,card_io_ret,i,tmp.3,sp
; update: sector.3,sector_ofs
func nextcluster
	mov	sector_ofs_a,cluster
	add	sector_ofs_a,sector_ofs_a
	mov	sector,cluster+1
	mov.2	sector+1,#0
	add.3	sector,fat
	call	card_setadr
	call	card_read
	mov	setcluster_a,card_read_ret
	call	card_read
	mov	setcluster_a+1,card_read_ret
	call	setcluster
	ret
endfunc

; use: card_io_a,card_skip_a,card_io_ret,i,sp,tmp,setclusuter_c.2,
; update: sector.3,sector_ofs_a,f_ofs.3
; out: getc_ret
func getc
	cmp.3	f_ofs,f_len
	bnc	9
	mov.3	tmp,f_ofs
	bz	1
	and.2	tmp,clustermask
	bnz	1
	call	nextcluster
1:
	add.3	f_ofs,#1
	call	card_read
	mov	getc_ret,card_read_ret
	ret
9:
	mov	getc_ret,#0x1ff
	ret
endfunc

; arg: setcluster_a.2
; use: card_io_a,card_skip_a,card_io_ret,i,sp
; update: f_len.3
func dir_open
	mov.3	f_len,#0
	cmp.2	setcluster_a,#0
	bnz	1
	mov.3	f_len,#RDE_LEN
1:
	call	file_open
	ret
endfunc

; use: card_io_a,card_skip_a,card_io_ret,i,sp,tmp,bytes,setcluster_a
; update: f_ofs.3,sector.3,sector_ofs_a,cluster.2
; out: dirread_ret
func dir_read
	mov	dirread_ret,vgm_index
1:
	cmp.3	f_len,#0
	bz	4
	cmp.3	f_ofs,f_len
	bnc	9
4:
	ldp	#buf
	mov	bytes,#SIZEOF_DIRENT
2:
	call	card_read
	mov	[dp+],card_read_ret
	sub	bytes,#1
	bnz	2
	add.3	f_ofs,#SIZEOF_DIRENT
	cmp.3	f_len,#0
	bnz	3
	mov.2	tmp,f_ofs
	and.2	tmp,clustermask
	bnz	3
	call	nextcluster
	mov.3	f_ofs,#0
3:
	cmp	buf,#0
	bz	1
	cmp	buf,#0x2e
	bz	1
	cmp	buf,#0xe5
	bz	1
	tst	buf+11,#0xe
	bnz	1
	sub	dirread_ret,#1
	bnz	1
9:
	ret
endfunc

; ---- UART ----
`ifdef UART

; arg: uart_putc_a
func uart_putc
	tst	i_flags,#TX_READY
	bz	uart_putc
	mov	o_tx,uart_putc_a
	ret
endfunc

; use: uart_putc_a
func uart_crlf
	mov	uart_putc_a,#13
	call	uart_putc
	mov	uart_putc_a,#10
	call	uart_putc
	ret
endfunc

; arg: sp
; use: sp,uart_putc_a
func uart_putstr
	mov	uart_putc_a,[sp+]
	bz	1
	call	uart_putc
	b	uart_putstr
1:
	ret

endfunc

; arg: tmp
; use: tmp,uart_putc_a
func uart_putdigit
	and	tmp,#0x0f
	add	tmp,#0x30
	cmp	tmp,#0x3a
	bc	1
	add	tmp,#7
1:
	mov	uart_putc_a,tmp
	call	uart_putc
	ret
endfunc

; arg: uart_puthex_a
; use: tmp,uart_putc_a
func uart_puthex
	srl	tmp,uart_puthex_a
	srl	tmp,tmp
	srl	tmp,tmp
	srl	tmp,tmp
	call	uart_putdigit
	mov	tmp,uart_puthex_a
	call	uart_putdigit
	ret
endfunc
`endif

; ---- APP ----

; in: update_meter_a
func update_meter
	mov	refresh,#1
	mov	tmp,update_meter_a
	tst	tmp,#0x80
	bz	2
	add	tmp,tmp
	add.2	tmp,tmp
	add.2	tmp,tmp
	mov	dcsg_regnum,tmp+1
	and	dcsg_regnum,#3
	mov	tmp,update_meter_a
	and	tmp,#0xf
	add	tmp,tmp
	add	tmp,tmp
	tst	update_meter_a,#0x10
	bz	1
	ldp	dcsg_regnum
	mov	dcsg_vol[dp],tmp
	b	9
1:
	cmp	dcsg_regnum,#3
	bnz	9
	add	tmp,tmp
2:
	and	tmp,#0x3f
	ldp	dcsg_regnum
	mov	dcsg_freq[dp],tmp
	b	9
9:
	ret
endfunc

; ret: vgm_ret
func vgm_cmd
	mov	vgm_ret,#0
	call	getc
	cmp	getc_ret,#0x1ff
	bz	9
	cmp	getc_ret,#0x50 ;write value
	bnz	1
	call	getc
	mov	o_dcsg,getc_ret
	mov	update_meter_a,getc_ret
	call	update_meter
1:
	cmp	getc_ret,#0x61 ;wait n samples
	bnz	2
	call	getc
	mov	o_timer,getc_ret
	call	getc
	mov	o_timer+1,getc_ret
	b	9
2:
	cmp	getc_ret,#0x62 ;wait 1/60 sec.
	bnz	3
	mov.2	o_timer,#0x2df
	b	9
3:
	cmp	getc_ret,#0x66 ;end of sound
	bnz	9
	mov	vgm_ret,#1
9:
	ret
endfunc

func draw_meter
	mov	led_setpos_x,#0
	mov	led_setpos_y,#4
	call	led_setpos
	call	i2c_start_data
	lsp	#0
7:
	mov	i,#0x40
1:
	mov	i2c_byte_a,#0
	cmp	i,dcsg_freq[sp]
	bc	2
	mov	i2c_byte_a,#0xfc
2:
	call	i2c_byte
	sub	i,#1
	bnz	1
	mov	i,#5
	mov	i2c_byte_a,#0
3:
	call	i2c_byte
	sub	i,#1
	bnz	3
	mov	i,#0x3b
4:
	mov	i2c_byte_a,#0
	cmp	i,dcsg_vol[sp]
	bc	5
	mov	i2c_byte_a,#0xfc
5:
	call	i2c_byte
	sub	i,#1
	bnz	4
	cmp	tmp,[sp+]	;for inc sp
	ssp	tmp
	cmp	tmp,#4
	bnz	7
	call	i2c_stop
	ret
endfunc

func update_volume
	cmp	refresh,#0
	bz	9
	mov	tmp,button_last_n
	mov	button_last_n,i_flags
	xor	button_last_n,#0xff
	and	tmp,i_flags
	tst	tmp,#BTN_DN
	bz	1
	cmp	o_volume,#0
	bz	9
	sub	o_volume,#1
	ret
1:
	tst	tmp,#BTN_UP
	bz	9
	cmp	o_volume,#7
	bz	9
	add	o_volume,#1
9:
	ret
endfunc

func main
	call	led_init
	call	card_init
	call	file_init
	mov	o_volume,#INIT_VOL
	mov	vgm_index,#INIT_NUM
0:
	call	led_cls
	mov	led_putnum_a,vgm_index
	call	led_putnum
	mov	led_setpos_x,#0
	mov	led_setpos_y,#2
	mov.2	setcluster_a,#0
	call	dir_open
	call	dir_read
	cmp	dirread_ret,#0
	bnz	9
	mov.2	strp,#buf
	mov	i,#8
2:
	lsp	strp
	mov	led_putc_a,[sp+]
	ssp	strp
	call	led_putc
	sub	i,#1
	bnz	2
	mov.2	setcluster_a,buf+26
	mov.3	f_len,buf+28
	call	file_open
3:
	call	vgm_cmd
	cmp	vgm_ret,#0
	bnz	8
1:
	tst	i_flags,#BTN_VOL
	bz	5
	call	update_volume
	b	4
5:
	tst	i_flags,#BTN_UP|BTN_DN
	bnz	9
4:
	tst	i_flags,#TIMER_ACTIVE
	bz	3
	cmp	refresh,#0
	bz	1
	call	draw_meter
	mov	refresh,#0
	b	1
8:
	add	vgm_index,#1
9:
	mov	o_dcsg,#0x9f
	mov	o_dcsg,#0xbf
	mov	o_dcsg,#0xdf
	mov	o_dcsg,#0xff
	tst	i_flags,#BTN_DN
	bz	10
	cmp	vgm_index,#0
	bz	11
	sub	vgm_index,#1
	b	11
10:
	tst	i_flags,#BTN_UP
	bz	11
	add	vgm_index,#1
11:
	mov.2	o_timer,#0x1fff
6:
	tst	i_flags,#TIMER_ACTIVE
	bnz	6
	b	0
;	ret
endfunc
