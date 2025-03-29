org 0x7c00


; 
; 实模式内存布局
;
; 起始地址    大小       用途
; ----------------------------------------
; 0x000      1KB       中断向量表
; 0x400      256B      BIOS 数据区
; 0x500      29.75KB   可用区域
; 0x7C00     512B      MBR 加载区域
; 0x7E00     607.6KB   可用区域
; 0x9FC00    1KB       扩展 BIOS 数据区
; 0xA0000    64KB      用于彩色显示适配器
; 0xB0000    32KB      用于黑白显示适配器
; 0xB8000    32KB      用于文本显示适配器
; 0XC0000    32KB      显示适配器 BIOS
; 0XC8000    160KB     映射内存
; 0xF0000    64KB-16B  系统BIOS
; 0xFFFF0    16B       系统 BIOS 入口地址
; 



; vesa support
;
;   https://github.com/FlowerBlackG/YurongOS/blob/master/src/boot/boot.asm
;   added by GTY
vesa_video_mode equ 0x143
vesa_video_mode_code equ (vesa_video_mode | 0x4000)


;section .code16
[BITS 16]
start:

		mov esp, 0x7C00  ; 暂用栈

%ifdef USE_VESA
		; 读取 VESA 信息。
		xor ax, ax
		mov es, ax
		mov di, 0x7e00
		mov ax, 0x4f01
		mov cx, vesa_video_mode
		int 0x10

		; 设置屏幕模式为文本模式，并清空屏幕。
		; 中断指令号为 10H，当 AH=0H 时表示设置显示模式，模式具体为 AL。
		; AL=3H 表示文本模式，80×25，16色。
		; AL=12H 表示图形模式，VGA 640×480 16色
		; AX=0x4F02, BX=0x4180 表示 1440×900 32位色
		; AX=0x4F02, BX=0x4143 表示 800×600 32位色

		mov bx, vesa_video_mode_code
		mov ax, 0x4F02
		int 0x10
%endif

	
		lgdt [gdtr]
		
		cli

		;打开a20 地址线
		in al,92h
		or al,00000010b
		out 92h, al

;		start to load sector 1 to memory 
	
		;将 CR0 的最低位设置为 1，启动保护模式。
		mov eax, cr0;
		or eax, 1;
		mov cr0, eax

		; enable PSE so we can use 2MB page :D  -- added by gty
		; See:
		;   https://www.wikiwand.com/en/Control_register#CR4
		;   https://wiki.osdev.org/Paging
		; 允许使用4MB页
		; mov eax, cr4
		; or eax, 0b10000
		; mov cr4, eax
				
		jmp dword 0x8:_startup ;

	
;section .code32
[BITS 32]
_startup:

		mov ax, 0x10
		mov ds, ax
		mov es, ax
		mov ss, ax

		mov	ecx, KERNEL_SIZE 	;cx = 扇区数KERNEL_SIZE，作为loop的次数
		mov eax, 1				;LBA寻址模式下扇区编号从0开始。  #0是引导扇区，#1扇区开始才是kernel的首扇区，即sector2.asm
		mov ebx, 0x100000		;目标存放地址从1M处开始，每次loop递增512 bytes
_load_kernel:
		push eax
		inc eax
		
		push ebx
		add	ebx, 512
		call _load_sector
		loop _load_kernel		
		
		;修改所有寄存器到高位地址
		mov ax, 0x20
		mov ds, ax
		mov es, ax
		mov ss, ax
		or esp, 0xc0000000
		jmp 0x18:0xc0100000 ; sector2.asm的代码首地址就是0xc0100000，因此即跳转到了该代码段
		; 段选择子将base = 0x40000000，加上 0xc0000000 后，把 c 抵消掉了，实现 3G->0 的映射
_load_sector:
	push ebp
	mov ebp,esp
	
	push edx
	push ecx
	push edi
	push eax		
	
; 0x1F2：用于传送扇区数（通常是 1）。
; 0x1F3：用于传送 LBA 模式下的扇区号的低 8 位。
; 0x1F4：用于传送 LBA 模式下的扇区号的中 8 位。
; 0x1F5：用于传送 LBA 模式下的扇区号的高 8 位。
; 0x1F6：用于传送 LBA 模式下的扇区号的最后 4 位。
; 0x1F7：用于发送命令（如 0x20 代表读取扇区，0x30 代表写入扇区）。

	mov al,1		;读1个扇区
	mov dx,1f2h		;扇区“数”寄存器 0x1f2，在这里告诉硬盘要读取几个扇区。
	out dx,al 		;out指令不是系统调用，而是直接和硬件交互的一个指令（I/O指令），没有经过操作系统
	
	mov eax,[ebp+12] ;[ebp+12]对应上面mov eax, 1   push eax指令入栈的值，eax为要读入的扇区号（1-398）
					;注意，这里栈是往低地址拓展的，因此ebp+12是第一个push的值
					;LBA28(Linear Block Addressing)模式输入扇区号的Bits 7~0， 共28 Bits扇区号
	inc dx			;扇区“号”寄存器 0x1f3
	out dx,al		;al 是一个 8 位寄存器，al表示eax的低8位，即扇区号的低8位
	
	shr eax,8		;LBA28(Linear Block Addressing)模式输入扇区号的Bits 15~8 放入AL中， 共28 Bits扇区号
	inc dx			;Port：DX = 0x1f3+1 = 0x1f4  
	out dx,al
	
	shr eax,8		;LBA28(Linear Block Addressing)模式输入扇区号的Bits 23~16放入AL中， 共28 Bits扇区号
	inc dx			;Port：DX = 0x1f4+1 = 0x1f5 
	out dx,al
	
	shr eax,8
	and al,0x0f
	or al,11100000b ;Bit(7和5)为1表示是IDE接口，Bit(6)为1表示开启LBA28模式，Bit(4)为1表示主盘。
					;Bit(3~0)为LBA28中的Bit27~24位
	inc dx			;Port：DX = 0x1f5+1 = 0x1f6 
	out dx,al
	
	mov al,0x20		;0x20表示读1个sector，0x30表示写1个sector
	inc dx			;Port：DX = 0x1f6+1 = 0x1f7 
	out dx,al
	
.test:
	in al,dx
	test al,10000000b  ;如果 第 7 位 是 1，则表示硬盘控制器的状态为“就绪”或“无错误”状态；否则，表示出现了错误或者硬盘未准备好。
	jnz .test
	
	test al,00001000b  ;这通常用于检查硬盘控制器的状态，判断是否存在某些错误或设备是否处于可读/可写状态。
	jz .load_error
	
	
	mov ecx,512/4   ;设置 ECX 寄存器为 128（512 / 4），这个值是因为要读取一个扇区，
					;通常硬盘扇区的大小是 512 字节。每次读入的单位为 DWORD（4 字节），因此需要读取 128 个 DWORD。
	mov dx,0x1f0 	;将 DX 寄存器设置为硬盘控制器的 数据端口，地址是 0x1f0。硬盘数据通过该端口进行传输。
	mov edi,[ebp+8]	;取得call前入栈参数[ebp+8] = 0x100000  = 1MB
	rep insd		;从数据端口连续读入 128 个 32 位数据，存入 edi 指向的内存
	xor ax,ax		; 完成后清除 ax（准备后续流程）
	jmp .load_exit	; 跳转到加载结束标签，结束当前加载扇区流程
	
.load_error:
	mov dx,0x1f1
	in al,dx
	xor ah,ah
			
.load_exit:
	
	pop eax		
	pop edi
	pop ecx
	pop edx
	leave		;Destory stack frame
	retn 8		;8是人为指定，需要根据传入参数决定，这里是8是因为push了两个32位的参数eax和ebx，每个32位4字节，共8字节
		
;section .data
KERNEL_SIZE		equ		(398)	    

gdt:		
		;gdt第一个表项必须全部为0
		dw	0x0000
		dw	0x0000
		dw	0x0000
		dw	0x0000
		
		; boot 运行时使用的代码段，段选择子 0x8
		dw	0xFFFF		
		dw	0x0000		
		dw	0x9A00		
		dw	0x00CF		
		
		; boot 运行时使用的数据段，段选择子 0x10
		dw	0xFFFF		
		dw	0x0000		
		dw	0x9200		
		dw	0x00CF		

		; 内核初始化阶段的代码段，段选择子 0x18，base=0x40000000
		dw	0xFFFF		
		dw	0x0000		
		dw	0x9A00		
		dw	0x40CF		
		
		; 内核初始化阶段的数据段，段选择子 0x20
		dw	0xFFFF		
		dw	0x0000		
		dw	0x9200		
		dw	0x40CF		
		
gdtr:
		dw $-gdt		;设计gdt大小
		dd gdt			;设置gdt地址

		dw 0xabfb  ; just a marker

		times 510 - ($ - $$) db 0
		
		dw 0xAA55
