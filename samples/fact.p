program FACT;
var n;
function fact(n);
if n <= 0 then
   fact := 1
else
   fact := fact(n - 1) * n;
begin
   read(n);
   write(fact(n))
end.
