### What is the assembly output of `fooi16` before adding any instruction? Explain what is happening here. Why is there a `call` in the output?

The following is the code generated before any backend modification:


```
	.file	"foo.ll"
	.text
	.globl	fooi16                          ; -- Begin function fooi16
	.p2align	1
	.type	fooi16,@function
fooi16:                                 ; @fooi16
	.cfi_startproc
; %bb.0:                                ; %entry
	push	r10
	.cfi_def_cfa_offset 4
	.cfi_offset r10, -4
	mov	r12, r10
	call	#__mspabi_mpyi
	add	r10, r12
	pop	r10
	.cfi_def_cfa_offset 2
	.cfi_restore r10
	ret
.Lfunc_end0:
	.size	fooi16, .Lfunc_end0-fooi16
	.cfi_endproc
                                        ; -- End function
	.section	".note.GNU-stack","",@progbits
```

MSP430 originally has no hardware multiply instruction. As a result, LLVM lowers `mul i16` into a call to `__mspabi_mpyi`, a software-emulated multiplication function that comes from the MSP430 ABI support library. The rest of the code performs the addition (`add r10, r12`) and restores the saved register before returning.

### How does the output assembly change after adding the `mul` instruction?

The following is the output assembly of `fooi16` after adding the `mul` instruction.

```
        .file   "foo.ll"
        .text
        .globl  fooi16                          ; -- Begin function fooi16
        .p2align        1
        .type   fooi16,@function
fooi16:                                 ; @fooi16
        .cfi_startproc
; %bb.0:                                ; %entry
        mul     r12, r13
        add     r13, r12
        ret
.Lfunc_end0:
        .size   fooi16, .Lfunc_end0-fooi16
        .cfi_endproc
                                        ; -- End function
        .section        ".note.GNU-stack","",@progbits
```

As shown above, after legalizing `mul` in `MSP430ISelLowering.cpp`, LLVM now recognizes multiplication as a native instruction. The libcall to `__mspabi_mpyi` is replaced with an actual `mul` instruction, directly encoding the hardware multiply. The rest of the function remains identical, with the addition and return.

### How does it change after adding the `mads` instruction?

The following is the output assembly of `fooi16` after introducing `mads` instruction.

```
        .file   "foo.ll"
        .text
        .globl  fooi16                          ; -- Begin function fooi16
        .p2align        1
        .type   fooi16,@function
fooi16:                                 ; @fooi16
        .cfi_startproc
; %bb.0:                                ; %entry
        mads    r13, r12
        ret
.Lfunc_end0:
        .size   fooi16, .Lfunc_end0-fooi16
        .cfi_endproc
                                        ; -- End function
        .section        ".note.GNU-stack","",@progbits
```

The `add(a, mul(a, b))` pattern is now recognized and reduced into a single `mads` instruction.

### Can you locate the added instructions in the output binary?

As shown in the previous answers, we can see the added instructions in the assembly output (`.s`). However, if we're also interested in the actual binary output, we can object dump and can see the bytes emitted for `mads`:

```
$ ./build/bin/llc -march=msp430 -filetype=obj ./test/foo.ll -o ./test/foo.o
$ ./build/bin/llvm-objdump -d ./test/foo.o

./test/foo.o:   file format elf32-msp430

Disassembly of section .text:

00000000 <fooi16>:
       0: 0c 2d         jhs     $+538
       2: 30 41         ret
```

The bytes `0c` (`0b0010`) is the opcode for the `mads` instruction. Since `0b0010` falls into the MSP430 jump-opcode space, the standard disassembler prints it as `jhs`. So, yes, the new instruction appears in the binary, but existing MSP430 tools decode it as a jump because the encoding overlaps with the jump class.

### When and why is it best to add (or not add) an ISA extension? Is it always beneficial to add more hardware? Consider that this MSP430-based architecture may be used in a larger project. Explain the hardware/software trade-offs.

Adding an ISA extension makes sense when a specific operation dominates performance or energy and cannot be optimized efficiently in software, and the processor manufacturer really wants to optimize the said operation.

However, it's not fee. From hardware side, new instructions increase hardware area and require significant development and verification effort.  

On the software side, this increases the complexity of the instruction selection phase. For simple instructions like mads, it's straightforward to identify the pattern to tile and reduce into a single instruction. However, for more complex instructions, finding the optimal instruction selection is often an NP-hard problem which is a well-known research challenge. For example, [a paper](https://dl.acm.org/doi/10.1145/3721145.3730421)
 published in 2025 proposes using a genetic algorithm to generate semantically equivalent instruction trees that match custom instructions more efficiently.

### Provide comments for the assembly line belonging to `fooi16` in all three outputs (without added instructions, with the `mul` instruction, and with the `mads` instruction).

Omitting everything else but the body:

before:
```
mov r12, r10          ; save a
call #__mspabi_mpyi   ; perform a*b via software
add r10, r12          ; r12 = a + product
ret                   ; return result
```

with `mul`:
```
mul r12, r13          ; r13 = r13 * r12
add r13, r12          ; r12 = r12 + r13
ret                   ; return result
```

with `mads`:
```
mads r13, r12         ; r12 = r12 + r12*r13 (fused multiply-add-self)
ret                   ; return result
```

### Where are `a`, `b`, and `add` stored?

The MSP430 backend assigns 16-bit integer values to general-purpose registers (GPRs). Here, `a` and `b` reside in `r12` and `r13` respectively, while the final result (`a + a*b`) is stored in `r12`, which serves as the return register under the MSP430 calling convention.

### Is there any advantage in arithmetic precision when adding a `mul` or `mads` instruction? Why?

If arithmetic precision here refers to supporting both 8-bit and 16-bit arithmetic, then yes, there is a potential advantage.

Most MSP430 instructions already support both 8-bit and 16-bit forms which gives the backend the same kind of trade-off seen in ARM's Thumb mode: the ability to choose between smaller, lower-power 8-bit operations or full 16-bit precision when needed. This feature is valuable in things like embedded systems. However, there is a trade-off in hardware complexity to maintain which might also yield to harware area increase.

Adding mul or mads enables true 16-bit operations in hardware instead of breaking them into multiple 8-bit steps or using runtime calls. This improves precision, performance, and code density.
The trade-off is higher hardware cost and power use since wider arithmetic units need more logic and energy. This is similar to ARM Thumb mode, where designers balance instruction width, precision, and efficiency depending on the target system.


### (Optional +) Integrate a test for both instructions into the LLVM test framework.

Three tests are integrated using `llvm-lit` in `llvm/test/Vorticity` and can be run as described in `Vorticity.md`.