# Vorticity Take-Home Interview

by: Muhammad Mazaya

## Building and Testing the Extension

### Building LLVM

To run the tests, LLVM needs to be built with MSP430 enabled.  
From the `llvm-project/build` directory, configure and build using:

```bash
cmake -G Ninja ../llvm \
  -DLLVM_ENABLE_PROJECTS="clang;lld;compiler-rt" \
  -DLLVM_TARGETS_TO_BUILD="MSP430;X86" \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_ASSERTIONS=ON
```

(Optional) To avoid out-of-memory errors on machines with less than 32 GB RAM, I personally use:

```
-DLLVM_USE_LINKER=lld -DLLVM_PARALLEL_LINK_JOBS=N
```

Then build the necessary tools:

```bash
ninja llc opt llvm-mc llvm-objdump clang FileCheck check-llvm
```

### Running the Tests

All tests are located under `llvm/test/Vorticity`:

```
./test/Vorticity
├── fooi16-test.ll                # Example from the writeup
├── Inputs
│   ├── fooi16.ll
│   ├── multiply-add-self.ll
│   └── multiply.ll
├── multiply-add-self-test.ll     # Tests reduction to 2 MADS
└── multiply-test.ll              # Tests reduction to 3 MULs
```

Run them using:

```bash
./build/bin/llvm-lit -v ./llvm/test/Vorticity
```

## Implementation Details of `mul` and `mads`

There are two main changes made to the MSP430 backend:  
one in the target lowering phase and another in the instruction description file.

### Target Lowering Phase

The MSP430 backend originally lowered `mul i16` into a software call (`__mspabi_mpyi`), since the default implementation assumes no hardware multiply support.  
To emit an actual instruction, the operation action in `llvm/lib/Target/MSP430/MSP430ISelLowering.cpp` was modified so that 16-bit multiplication is treated as legal instead of a libcall:

```cpp
-  setOperationAction(ISD::MUL, MVT::i16, LibCall);
+  setOperationAction(ISD::MUL, MVT::i16, Legal);
```

This single-line change allows the SelectionDAG to keep the multiply node intact and match it directly against real machine patterns.

### Instruction Definitions

After legalization, new instructions were defined in `llvm/lib/Target/MSP430/MSP430InstrInfo.td`.  
Both follow MSP430's two-operand format, where operations are expressed as `op src, dst`, meaning `dst = dst op src`.

#### `mul` Instruction

```
defm MUL : Arith<0b0001, "mul", mul, 1, []>;
```

The multiply instruction was added using the existing double-operand class (I16rr) with an available opcode encoding of `0b0001`. It reuses the same multiclass infrastructure used for other arithmetic operations. A tied operand constraint was added so the destination register is both read and written, matching MSP430's read–modify–write semantics.  

After this addition, any `mul i16` in LLVM IR now lowers to a single machine instruction `mul rs, rd` instead of a function call.

#### `mads` Instruction

The `mads` instruction is a multiply-add-self instruction: `a = a + a * b`. Since this operation does not exist in LLVM's built-in DAG opcodes, a new custom node was introduced to represent it in the SelectionDAG.

```
def MSP430mads : SDNode<"MSP430ISD::MADS", SDTIntBinOp, []>;

def MADS16rr : I16rr<0b0010,
  (outs GR16:$rd),
  (ins GR16:$rs, GR16:$src2),
  "mads\t$rs, $rd",
  [(set GR16:$rd, (add GR16:$src2, (mul GR16:$src2, GR16:$rs)))]> {
  let Constraints = "$src2 = $rd";
}
```

The new `SDNode` (`MSP430ISD::MADS`) gives the instruction an identifier in the SelectionDAG, while the `MADS16rr` pattern defines its actual encoding (`0b0010`) and all the properties of the instruction (name, inputs, outputs, pattern, and constraint).

As a result, any addition involving a multiply of the same operand will now reduce into a single `mads rs, rd` instruction during instruction selection.