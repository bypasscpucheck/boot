boot_drive:  db 0
a20_failed:  db 0
B64.hang:    jmp $
kernel equ 0x10000
; MAGIC
[ORG 0x7C00]
[BITS 16]

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    mov [boot_drive], dl
    call enable_a20
    jc a20_failed
    call get_memory_map
    call load_gdt
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp 0x08:B32

[BITS 32]
B32:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x9C00
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax
    call init_page_tables
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8
    wrmsr
    mov eax, cr0
    or eax, 1 << 31
    mov cr0, eax
    jmp 0x08:B64

[BITS 64]
B64:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov rsp, 0xAC00
    xor rax, rax
    mov fs, ax
    mov gs, ax
    call verify_long_mode
    test al, al
    jz .hang
    mov rdi, rsp
    mov rsi, kernel
    xor rdx, rdx
    call init_new_stack
    call init_idt
    jmp 0x10000

[BITS 32]
enable_a20:
    pushf
    push ax
    push bx
    push cx
    push dx
    call try_bios_a20
    jc .try_kbc
    call verify_a20
    jnc .success
.try_kbc:
    call try_kbc_a20
    jc .try_fast
    call verify_a20
    jnc .success
.try_fast:
    call try_fast_a20
    jc .fail
    call verify_a20
    jnc .success
.fail:
    stc
    jmp .done
.success:
    clc
.done:
    pop dx
    pop cx
    pop bx
    pop ax
    popf
    ret
try_bios_a20:
    mov ax, 0x2401
    int 0x15
    jnc .ok
    stc
    ret
.ok:
    clc
    ret
try_kbc_a20:
    call kbc_wait_write
    jc .fail
    mov al, 0xD1
    out 0x64, al
    call kbc_wait_write
    jc .fail
    mov al, 0xDF
    out 0x60, al
    call kbc_wait_write
    jc .fail
    clc
    ret
.fail:
    stc
    ret
kbc_wait_write:
    mov cx, 0x1000
.wait:
    in al, 0x64
    test al, 0x02
    loopnz .wait
    jz .ok
    stc
    ret
.ok:
    clc
    ret
try_fast_a20:
    in al, 0x92
    test al, 0x02
    jnz .already_on
    or al, 0x02
    and al, 0xFE
    out 0x92, al
    .already_on:
    clc
    ret
verify_a20:
    pushf
    push ds
    push es
    push ax
    push di
    push si
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov al, [ds:0x0000]
    mov ah, [es:0x0010]
    push ax
    mov byte [ds:0x0000], 0xAA
    mov di, 0xFFFF
    mov es, di
    mov di, 0x0010
    mov byte [es:di], 0x55
    jmp .flush
.flush:
    mov al, [ds:0x0000]
    mov ah, [es:di]
    pop bx
    mov [ds:0x0000], bl
    mov [es:di], bh
    cmp al, ah
    je .disabled
    clc
    jmp .done
.disabled:
    stc
.done:
    pop si
    pop di
    pop ax
    pop es
    pop ds
    popf
    ret

get_memory_map:
    pusha
    push es
    xor di, di
    mov es, di
    mov di, memory_map_buffer
    mov dword [map_entries], 0
    mov dword [next_handle], 0
.loop:
    mov eax, 0xE820
    mov edx, 0x534D4150
    mov ecx, 20
    mov ebx, [next_handle]
    mov es, di
    int 0x15
    jc .done
    cmp eax, 0x534D4150
    jne .done
    add di, 20
    inc dword [map_entries]
    cmp ebx, 0
    je .done
    mov [next_handle], ebx
    jmp .loop
.done:
    pop es
    popa
    ret
memory_map_buffer: times 4096 db 0
map_entries:       dd 0
next_handle:       dd 0

gdt_start:
    dq 0
gdt_code32:
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x9A
    db 0xCF
    db 0x00
gdt_data32:
    dw 0xFFFF
    dw 0x0000
    db 0x00
    db 0x92
    db 0xCF
    db 0x00
gdt_code64:
    dw 0x0000
    dw 0x0000
    db 0x00
    db 0x9A
    db 0x20
    db 0x00
gdt_data64:
    dw 0x0000
    dw 0x0000
    db 0x00
    db 0x92
    db 0x20
    db 0x00
gdt_end:
gdtr:
    dw gdt_end - gdt_start - 1
    dd gdt_start
load_gdt:
    lgdt [gdtr]
    ret
init_page_tables:
    pusha
    mov edi, 0x10000
    mov ecx, 3072
    xor eax, eax
    rep stosd
    mov dword [0x10000], 0x11000 | 0x07
    mov dword [0x10004], 0
    mov dword [0x11000], 0x12000 | 0x07
    mov dword [0x11004], 0
    mov edi, 0x12000
    mov ebx, 0x87
    mov ecx, 512
.pd_loop:
    mov dword [edi], ebx
    mov dword [edi+4], 0
    add ebx, 0x200000
    add edi, 8
    loop .pd_loop
    mov eax, 0x10000
    mov cr3, eax
    popa
    ret
.hang:
    hlt
    jmp .hang
[BITS 64]
verify_long_mode:
    push rbx
    mov rax, cr0
    shr rax, 31
    and rax, 1
    mov rbx, rax
    mov ecx, 0xC0000080
    rdmsr
    mov r8, rax
    shr r8, 8
    and r8, 1
    mov r9, rax
    shr r9, 10
    and r9, 1
    mov al, 1
    test rbx, rbx
    jz .fail
    test r8, r8
    jz .fail
    test r9, r9
    jz .fail
    pop rbx
    ret
.fail:
    xor al, al
    pop rbx
    ret
init_new_stack:
    and rdi, ~0xF
    sub rdi, 8 * 5
    mov rsp, rdi
    xor rbp, rbp
    xor rax, rax
    xor rbx, rbx
    mov rdi, rdx
    call rsi
.halt:
    cli
    hlt
    jmp .halt
switch_to_stack:
    mov rax, rsp
    mov rsp, rdi
    push rax
    mov rdi, rdx
    jmp rsi
idt_start:
    times 256 dq 0, 0
idt_end:
idtr:
    dw idt_end - idt_start - 1
    dq idt_start
empty_isr:
    iretq
init_idt:
    push rax
    push rcx
    push rdi
    mov rcx, 256
    mov rdi, idt_start
    mov rax, empty_isr
.loop:
    mov [rdi], ax
    mov word [rdi + 2], 0x08
    mov byte [rdi + 4], 0
    mov byte [rdi + 5], 0x8E
    shr rax, 16
    mov [rdi + 6], ax
    shr rax, 16
    mov [rdi + 8], eax
    mov dword [rdi + 12], 0
    mov rax, empty_isr
    add rdi, 16
    loop .loop
    lidt [idtr]
    pop rdi
    pop rcx
    pop rax
    ret
