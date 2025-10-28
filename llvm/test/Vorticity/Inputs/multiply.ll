define i16 @foo(i16 %a, i16 %b) {
entry:
  %c = mul i16 %a, %b
  %d = mul i16 %c, %b
  %e = mul i16 %d, %c
  ret i16 %e
}
