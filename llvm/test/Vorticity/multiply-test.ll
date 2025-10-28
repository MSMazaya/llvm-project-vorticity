; RUN: llc -march=msp430 %S/Inputs/multiply.ll -o %t.s 
; RUN: FileCheck %s < %t.s

; CHECK-COUNT-3: mul
