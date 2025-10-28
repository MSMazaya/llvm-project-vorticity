define i16 @fooi16(i16 %a, i16 %b) {
entry:
  %mul = mul i16 %a, %b
  %add = add i16 %a, %mul
  ret i16 %add
}
