[BITS 32]
[extern kernelBridge]
KERNEL_VIRTUAL_BASE_SPACE      equ 0xc0000000


PDE_ADDRESS equ 0x00200000  ; 实际内核页表的物理地址
PTE_ADDRESS equ 0x00201000 ; 2M+4K 768#页表起始地址
PTE_USER0 equ 0x00202000  ; 实际用户页表0的物理地址（两个页表间相隔4K，即一个页表的大小）
PTE_USER1 equ 0x00203000  ; 实际用户页表1的物理地址


global greatstart
greatstart:


	; 填充页0号和768号目录项，保证在访问这两项时能够正确找到对应页表的基址
	mov eax, 0x0
	or eax, 0x00201003 ; base = 0x2000(8KB) read/write, present。此时0号和768号页表基地址都是2M+4K
	mov [PDE_ADDRESS + KERNEL_VIRTUAL_BASE_SPACE], eax ; 页目录基地址（即0号页目录项的地址）
	mov [PDE_ADDRESS + (768 * 4) + KERNEL_VIRTUAL_BASE_SPACE], eax ; 768号页目录项的地址

	; 设置768号页表，768#临时页表项
.begin_fill_768:
	mov eax, 0x0
	or eax, 0x00000003 ; p=1，r/w=1
	mov ecx, 1024 
	mov ebx, 0
	; 从 2M+4k 开始填充页表项
.fill_768:
	mov [PTE_ADDRESS + KERNEL_VIRTUAL_BASE_SPACE + ebx], eax
	add ebx, 4
	add eax, 0x1000 ; 4KB，即跨越一个页框的大小
	loop .fill_768

	; 设计0号页表，202号页框
.begin_fill_0:
	mov eax, 0x0
	or eax, 0x00000007 
	mov ecx, 1024
	mov ebx, 0
	; 从 2M+8k 开始填充页表项
.fill_0:
	mov [PTE_USER0 + KERNEL_VIRTUAL_BASE_SPACE + ebx], eax
	add ebx, 4
	add eax, 0x1000 
	loop .fill_0

	; 设置1号页表，203#页表项
.begin_fill_1:
	mov eax, 0x0
	or eax, 0x00400007 
	mov ecx, 1024
	mov ebx, 0
	; 从 2M+12k 开始填充页表项
.fill_1:
	mov [PTE_USER1 + KERNEL_VIRTUAL_BASE_SPACE + ebx], eax
	add ebx, 4
	add eax, 0x1000 
	loop .fill_1

	
	
	; 4KB 的位置（物理地址属于保留区）装入 CR3 页目录入口寄存器
	mov edx, PDE_ADDRESS
	mov cr3, edx


	; 设置 GDT pointer，进入平坦模式，线性地址（物理地址）=逻辑地址
	lgdt [gdt_pointer]

	; 开启分页和保护模式
	mov ebx, cr0
	or ebx, 0x80000001
	mov cr0, ebx

	mov ax, 0x10
	mov ds, ax
	mov es, ax
	mov ss, ax



	; 跳转到内核CPP文件
	jmp code_selector:.to_kernel_bridge   

.to_kernel_bridge:
	mov esp, 0xc0007c00 ;预留给内核的栈顶地址
	jmp kernelBridge
	ud2 ;触发 CPU 异常，用于 调试或防止执行无效代码


; 用 0 填充一个页框。
; 函数内不备份任何可能用到的寄存器。
;
; 传参：
;   edi: 起始地址。
;   ecx: 单元数。以 4 字节为 1 个单元。
;        必须大于 0。函数内不做正确性校验。
;
zero_fill_area:

    xor eax, eax

.zero_fill_dword:

    mov dword [edi], eax	; 将 0 写入 edi 指向的 4 字节单元
    add edi, 4				; 让 edi 指向下一个 4 字节地址
    dec ecx					; ecx 递减 1，表示已填充一个单元

    cmp ecx, 0				; 检查 是否还存在未填充的单元
    jne .zero_fill_dword

    ret



align 4 ; 4 字节对齐
empty_idt:
    .length dw 0
    .base dd 0


; 代码段选择子和数据段选择子。
code_selector equ (1 << 3)	; 0x08
data_selector equ (2 << 3)	; 0x10

; 用来索引 GDT 的指针。
align 4

gdt_pointer:
    dw (gdt_end - gdt_base) - 1 ; 设置gdt大小

    dd gdt_base ; 设置gdt偏移量
    dd 0 ;填充字节

align 4

;  dq表示定义了一个8字节的数据项，其值为0，用作GDT的第一个表项
gdt_base:
    dq 0

; 代码段。
gdt_code:

	; (idx)    : 1
	; limit    : 0xfffff
	; base     : 0x0
	; access   : 0
	; rw       : 1
	; dc       : 0
	; exec     : 1
	; descType : code/data
	; privi lv : 0
	; present  : 1
	; longMode : 0
	; sizeFlag : 32 bits
	; granular : 4 KB
	
	; 64位的描述项，跟前面的GDT区别在于基地址变为了0，开始了平坦模式 
    dq 0xcf9a000000ffff
    
gdt_data:

    ; (idx)    : 2
	; limit    : 0xfffff
	; base     : 0x0
	; access   : 0
	; rw       : 1
	; dc       : 0
	; exec     : 0
	; descType : code/data
	; privi lv : 0
	; present  : 1
	; longMode : 0
	; sizeFlag : 32 bits
	; granular : 4 KB

    dq 0xcf92000000ffff
    

gdt_end:
