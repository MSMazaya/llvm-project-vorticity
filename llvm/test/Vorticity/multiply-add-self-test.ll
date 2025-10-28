; RUN: llc -march=msp430 %S/Inputs/multiply-add-self.ll -o %t.s 
; RUN: FileCheck %s < %t.s

; CHECK-COUNT-2: mads
