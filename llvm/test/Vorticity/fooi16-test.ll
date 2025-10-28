; RUN: llc -march=msp430 %S/Inputs/fooi16.ll -o %t.s 
; RUN: FileCheck %s < %t.s

; CHECK: mads
