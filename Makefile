parser: y.tab.c lex.yy.c
	cc y.tab.c lex.yy.c -ll -o parser -std=c99 -lm

lex.yy.c: scanner.l
	lex scanner.l

y.tab.c: parser.y
	yacc -d parser.y

clean:
	rm *.c parser y.tab.h
