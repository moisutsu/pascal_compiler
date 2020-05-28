FILE = sample1.p

parser: y.tab.c lex.yy.c
	cc y.tab.c lex.yy.c -ll -o parser -std=c99 -lm

lex.yy.c: scanner.l
	lex scanner.l

y.tab.c: parser.y
	yacc -d parser.y

.PHONY: clean
clean:
	rm -f *.c parser y.tab.h result.ll

result.ll: parser
	./parser samples/${FILE}

.PHONY: run
run: result.ll
	lli-9 result.ll
