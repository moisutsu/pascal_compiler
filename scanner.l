%{
/*
 * scanner: scanner for PL-*
 *
 */

#include <stdio.h>
#include <string.h>

#define MAXLENGTH 16

#include "y.tab.h"

%}
%option yylineno
%%

begin           return SBEGIN;
div             return DIV;
do              return DO;
else            return ELSE;
end             return SEND;
for             return FOR;
forward         return FORWARD;
function        return FUNCTION;
if              return IF;
procedure       return PROCEDURE;
program         return PROGRAM;
read            return READ;
then            return THEN;
to              return TO;
var             return VAR;
while           return WHILE;
write           return WRITE;
"+"             return PLUS;
"-"             return MINUS;
"*"             return MULT;
"="             return EQ;
"<>"            return NEQ;
"<"             return LT;
"<="            return LE;
">"             return GT;
">="            return GE;
"("             return LPAREN;
")"             return RPAREN;
"["             return LBRACKET;
"]"             return RBRACKET;
","             return COMMA;
";"             return SEMICOLON;
":"             return COLON;
"."             return PERIOD;
".."            return INTERVAL;
":="            return ASSIGN;

[0-9]|[1-9][0-9]* {
    yylval.num = atoi(yytext);
    return NUMBER;
}

[a-zA-Z][0-9a-zA-Z]* {
    strcpy(yylval.ident, yytext);
    return IDENT;
}

[ \t\n]         ;

. {
    fprintf(stderr, "cannot handle such characters: %s\n", yytext);
}

%%

main(int argc, char *argv[]) {
    FILE *fp;
    int tok;

    if (argc != 2) {
        fprintf(stderr, "usage: %s filename\n", argv[0]);
        exit(1);
    }

    if ((fp = fopen(argv[1], "r")) == NULL) {
        fprintf(stderr, "cannot open file: %s\n", argv[1]);
        exit(1);
    }

    /*
     * yyin は lex の内部変数であり，入力のファイルポインタを表す．
     */
    yyin = fp;

    yyparse();
}
