define i16 @foo(i16 %a, i16 %b) {
entry:
  ; add(a, mul(a, b))
  %mul1 = mul i16 %a, %b
  %add1 = add i16 %a, %mul1
  ; add(mul(a, b), a)
  %mul2 = mul i16 %add1, %a
  %res = add i16 %mul2, %a
  ret i16 %res
}
