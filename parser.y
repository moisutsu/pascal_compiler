%{
/*
 * parser; Parser for PL-*
 */

#define MAXLENGTH 16

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include <math.h>

extern int yylineno;
extern char *yytext;

typedef enum {
        GLOBAL_VAR, /* 大域変数 */
        LOCAL_VAR, /* 局所変数 */
        PROC_NAME, /* 手続き */
        CONSTANT, /* 定数 */
        VOID      /* void */
} Scope;

/* LLVM命令名の定義 */
typedef enum {
  Alloca,   /* alloca */
  Store,    /* store  */
  Load,     /* load   */
  BrUncond, /* br     */
  BrCond,   /* brc    */
  Label,    /* label  */
  Add,      /* add    */
  Sub,      /* sub    */
  Icmp,     /* icmp   */
  Ret,       /* ret    */
  Mul,
  Div,
  Global,
  Global_a,
  Call,
  Write,
  Read,
  Sext,
  Getep,
  Alloca_a,
  Shl,
  Ashr,
} LLVMcommand;

/* 比較演算子の種類 */
typedef enum {
  EQUAL, /* eq （==）*/
  NE,    /* ne （!=）*/
  SGT,   /* sgt （>，符号付き） */
  SGE,   /* sge （>=，符号付き）*/
  SLT,   /* slt （<，符号付き） */
  SLE    /* sle （<=，符号付き）*/
} Cmptype;

/* 変数もしくは定数の型 */
typedef struct {
  Scope type;      /* 変数（のレジスタ）か整数の区別 */
  char vname[256]; /* 変数の場合の変数名 */
  int val;         /* 整数の場合はその値，変数の場合は割り当てたレジスタ番号 */

  int size;
  int start;
} Factor;

typedef struct llvmcode {
  LLVMcommand command; /* 命令名 */
  union { /* 命令の引数 */
    struct { /* alloca */
      Factor retval;
    } alloca;
    struct { /* store  */
      Factor arg1;  Factor arg2;
    } store;
    struct { /* load   */
      Factor arg1;  Factor retval;
    } load;
    struct { /* br     */
      int arg1;
    } bruncond;
    struct { /* brc    */
      Factor arg1;  int arg2;  int arg3;
    } brcond;
    struct { /* label  */
      int l;
    } label;
    struct { /* add    */
      Factor arg1;  Factor arg2;  Factor retval;
    } add;
    struct { /* sub    */
      Factor arg1;  Factor arg2;  Factor retval;
    } sub;
    struct {
      Factor arg1;  Factor arg2;  Factor retval;
    } mul;
    struct {
      Factor arg1;  Factor arg2;  Factor retval;
    } div;
    struct { /* icmp   */
      Cmptype type;  Factor arg1;  Factor arg2;  Factor retval;
    } icmp;
    struct { /* ret    */
      Factor arg1;
    } ret;
    struct {
      Factor retval;
    } global;
    struct {
      Factor decl; int argc; Factor argv[10]; Factor retval;
    } call;
    struct {
      Factor arg1; int arg2;
    } write;
    struct {
      Factor arg1; int arg2;
    } read;
    struct {
      Factor arg1;  Factor arg2;  Factor retval;  int size;
    } getep;
    struct {
      Factor arg1;  Factor retval;
    } sext;
    struct {
      Factor retval;  int size;
    } alloca_a;
    struct {
      Factor retval;  int size;
    } global_a;
    struct {
      Factor arg1;  int arg2;  Factor retval;
    } shl;
    struct {
      Factor arg1;  int arg2;  Factor retval;
    } ashr;
  } args;
  /* 次の命令へのポインタ */
  struct llvmcode *next;
} LLVMcode;

LLVMcode *codehd = NULL; /* 命令列の先頭のアドレスを保持するポインタ */
LLVMcode *codetl = NULL; /* 命令列の末尾のアドレスを保持するポインタ */

LLVMcode *gcodehd = NULL; /* グローバル変数宣言用のポインタ */
LLVMcode *gcodetl = NULL;

/* 変数もしくは定数のためのスタック */
typedef struct {
  Factor element[100];  /* スタック（最大要素数は100まで） */
  unsigned int top;     /* スタックのトップの位置         */
} Factorstack;

typedef struct {
  LLVMcode *element[100];
  unsigned int top;
} LLVMcodestack;

Factorstack fstack; /* 整数もしくはレジスタ番号を保持するスタック */
Factorstack stable; /* 記号表を管理するスタック */
LLVMcodestack istack; /* 命令を管理するスタック */

/* LLVMの関数定義 */
typedef struct fundecl {
  char fname[256];      /* 関数名                      */
  unsigned arity;       /* 引数個数                    */
  Factor args[10];      /* 引数名                      */
  LLVMcode *codes;      /* 命令列の線形リストへのポインタ */
  struct fundecl *next; /* 次の関数定義へのポインタ      */

  Factor retval;        /*  この関数の返り値 */
  bool declare_forward;      /* この関数がforward宣言かどうか */
} Fundecl;

/* 関数定義の線形リストの先頭の要素のアドレスを保持するポインタ */
Fundecl *declhd = NULL;
/* 関数定義の線形リストの末尾の要素のアドレスを保持するポインタ */
Fundecl *decltl = NULL;

int cntr;

void fwriteIcmp(Cmptype type);
void fwriteGlobalLlvmcodes(LLVMcode *code);
void fwriteFactor(Factor factor);
void fwriteLlvmcodes(LLVMcode *code);
void fwriteLlvmfundecl(Fundecl *decl);
void fwriteLlvmglobal(LLVMcode *code);
void fwriteDeclare();

LLVMcode *malloc_label_llvmcode();
LLVMcode *malloc_llvmcode();
Fundecl *malloc_fundecl();

LLVMcode *malloc_bru_llvmcode();
LLVMcode *malloc_brc_llvmcode(Factor arg1, int arg2);
LLVMcode *malloc_call_llvmcode(char *name);
void add_alloca_ainstruction(char *name, int size, int start);
void add_writeinstruction();
void add_readinstruction(char *name);
void add_retinstruction(Factor arg1);
void add_allocainstruction(Factor retval);
void add_loadinstruction(Factor retval, Factor arg1);
void add_storeinstruction(Factor arg1, Factor arg2);
void add_icmpinstruction(Cmptype type, Factor arg1, Factor arg2);
void add_expinstruction(LLVMcommand command, Factor arg1, Factor arg2);
void add_globalinstruction(LLVMcode *tmp);
void add_instruction(LLVMcode *tmp);
void add_defvariable(char *name);
void add_assign(char *name, Factor arg1);
void add_proc_args();
void add_func_args();
Factor add_getep(char *name, Factor index);
Factor add_load(char *name);
void add_decl(Fundecl *tmp);

// Load ReturnValue and Ret ReturnValue
void load_ret_fnrv();

Scope current_scope = GLOBAL_VAR;

void init_stack();
Factor factorpop();
void factorpush(Factor x);
LLVMcode *istackpop();
void istackpush(LLVMcode *x);

FILE *f;

void insert_data(char *name, Scope scope);
Factor lookup_data(char *name);
Fundecl *lookup_fundecl(char *name, int argc);
void delete_data();

bool used_write = false;
bool used_read = false;

int argc;

%}

%union {
    int num;
    char ident[MAXLENGTH+1];
}

%token SBEGIN DO ELSE SEND
%token FOR FORWARD FUNCTION IF PROCEDURE
%token PROGRAM READ THEN TO VAR
%token WHILE WRITE

%left PLUS MINUS                       //← 注意
%left MULT DIV                         //← 注意

%token EQ NEQ LE LT GE GT
%token LPAREN RPAREN LBRACKET RBRACKET
%token COMMA SEMICOLON COLON INTERVAL
%token PERIOD ASSIGN
%token <num> NUMBER                    //← yylval の型を指定
%token <ident> IDENT                   //← yylval の型を指定

%%

program
        :
        {
                init_stack();
        }
        PROGRAM IDENT SEMICOLON outblock PERIOD
        {
                if ((f = fopen("result.ll", "w")) == NULL) {
                        fprintf(stderr, "Cannot open file.\n");
                        exit(1);
                }
                fwriteLlvmglobal(gcodehd);
                fwriteLlvmfundecl(declhd);
                fwriteDeclare();
                fclose(f);
        }
        ;

outblock
        : var_decl_part
        {
                current_scope = LOCAL_VAR;
        }
        subprog_decl_part
        {
                cntr = 1;
                Fundecl *tmp = malloc_fundecl();
                strcpy(tmp->fname, "main");
                tmp->retval.type = CONSTANT;
                add_decl(tmp);

                Factor retval;
                retval.type = LOCAL_VAR;
                retval.val = cntr++;
                add_allocainstruction(retval);

                Factor arg1, arg2;
                arg1.val = 0;
                arg1.type = CONSTANT;
                arg2 = retval;
                add_storeinstruction(arg1, arg2);
        }
        statement
        {
                Factor arg1;
                arg1.val = 0;
                arg1.type = CONSTANT;
                add_retinstruction(arg1);
        }
        ;

var_decl_part
        : /* empty */
        | var_decl_list SEMICOLON
        ;

var_decl_list
        : var_decl_list SEMICOLON var_decl
        | var_decl
        ;

var_decl
        : VAR id_list
        ;

subprog_decl_part
        : subprog_decl_list SEMICOLON
        | /* empty */
        ;

subprog_decl_list
        : subprog_decl_list SEMICOLON subprog_decl
        | subprog_decl
        ;

subprog_decl
        : proc_decl
        {
                delete_data();
        }
        ;

proc_decl
        : PROCEDURE proc_name SEMICOLON
        {
                // ここでforward宣言済みであるかどうかの確認を行い,forward宣言されているならそれに応じた処理を行う.
                // decltlより関数名を取得できる
                // lookup_fundeclで前のforward宣言したものの引数の情報を取得できる
                // その情報からここでallocaとstoreを行う.
                Fundecl *tmp;
                if ((tmp = lookup_fundecl(decltl->fname, -1))->declare_forward) {
                        // 前にforward宣言されている.
                        // 引数個数と引数名のコピー
                        decltl->arity = tmp->arity;
                        for (int i = 0; i < decltl->arity; i++) {
                                strcpy(decltl->args[i].vname, tmp->args[i].vname);
                        }
                        add_proc_args();
                }
        }
        inblock
        {
                Factor arg1;
                arg1.type = VOID;
                add_retinstruction(arg1);
        }
        | PROCEDURE proc_name LPAREN
        {
                current_scope = PROC_NAME;
        }
        id_list
        {
                current_scope = LOCAL_VAR;
                add_proc_args();
        }
        RPAREN SEMICOLON inblock
        {
                Factor arg1;
                arg1.type = VOID;
                add_retinstruction(arg1);
        }
        | FUNCTION proc_name
        {
                Fundecl *tmp;
                if ((tmp = lookup_fundecl(decltl->fname, -1))->declare_forward) {
                        // 引数個数と引数名のコピー
                        decltl->arity = tmp->arity;
                        for (int i = 0; i < decltl->arity; i++) {
                                strcpy(decltl->args[i].vname, tmp->args[i].vname);
                        }
                        add_func_args();
                } else {
                        // 返り値用のalloca
                        Factor retval;
                        retval.type = LOCAL_VAR;
                        // 記号表の関数名のvalに戻り値用のレジスタ番号を格納
                        stable.element[stable.top - 1].val = retval.val = cntr++;
                        add_allocainstruction(retval);
                }
        }
        SEMICOLON inblock
        {
                load_ret_fnrv();
        }
        | FUNCTION proc_name LPAREN
        {
                current_scope = PROC_NAME;
        }
        id_list
        {
                current_scope = LOCAL_VAR;
                add_func_args();
        }
        RPAREN SEMICOLON inblock
        {
                load_ret_fnrv();
        }
        ;

proc_name
        : IDENT
        {
                cntr = 1;
                Fundecl *tmp = malloc_fundecl();
                strcpy(tmp->fname, $1);
                add_decl(tmp);

                insert_data($1, PROC_NAME);
        }
        ;

inblock
        : var_decl_part statement
        | FORWARD // ここに追加?
        {
                // ここでalloca store retだけさせる関数を消し,後続の同名の関数用に引数をどこかに格納し,forward宣言済みである印をつける
                // この段階で関数のinsertはすでにされている.
                // 後続の関数で正しくallocaとstoreを行う
                decltl->declare_forward = true;
        }
        ;

statement_list
        : statement_list SEMICOLON statement
        | statement
        ;

statement
        : assignment_statement
        | if_statement
        | while_statement
        | for_statement
        | proc_call_statement
        | null_statement
        | block_statement
        | read_statement
        | write_statement
        ;

assignment_statement
        : IDENT ASSIGN expression
        {
                Factor arg1 = factorpop();
                add_assign($1, arg1);
        }
        | IDENT LBRACKET expression RBRACKET ASSIGN expression
        {
                Factor arg1 = factorpop();
                Factor index = factorpop();
                Factor retval = add_getep($1, index);

                Factor arg2 = retval;
                add_storeinstruction(arg1, arg2);
        }
        ;

if_statement
        : IF condition
        {

                LLVMcode *l1 = malloc_label_llvmcode();
                Factor arg1 = factorpop();
                LLVMcode *brc = malloc_brc_llvmcode(arg1, (l1->args).label.l);
                istackpush(brc);
                add_instruction(brc);
                add_instruction(l1);
        }
        THEN statement else_statement
        ;

else_statement
        : ELSE
        {
                LLVMcode *bru = malloc_bru_llvmcode();
                add_instruction(bru);
                LLVMcode *l2 = malloc_label_llvmcode();
                LLVMcode *brc = istackpop();
                (brc->args).brcond.arg3 = (l2->args).label.l;
                add_instruction(l2);
                istackpush(bru);
        }
        statement
        {
                LLVMcode *l3 = malloc_label_llvmcode();
                LLVMcode *bru1 = istackpop();
                LLVMcode *bru2 = malloc_bru_llvmcode();
                (bru2->args).bruncond.arg1 = (bru1->args).bruncond.arg1 = (l3->args).label.l;
                add_instruction(bru2);
                add_instruction(l3);
        }
        | /* empty */
        {
                LLVMcode *l2 = malloc_label_llvmcode();
                LLVMcode *brc = istackpop();
                LLVMcode *bru = malloc_bru_llvmcode();
                (brc->args).brcond.arg3 = (bru->args).bruncond.arg1 = (l2->args).label.l;
                add_instruction(bru);
                add_instruction(l2);
        }
        ;

while_statement
        : WHILE
        {
                LLVMcode *l1 = malloc_label_llvmcode();
                LLVMcode *bru1 = malloc_bru_llvmcode();
                (bru1->args).bruncond.arg1 = (l1->args).label.l;
                add_instruction(bru1);
                add_instruction(l1);
                LLVMcode *bru2 = malloc_bru_llvmcode();
                (bru2->args).bruncond.arg1 = (l1->args).label.l;
                istackpush(bru2);
        }
        condition
        {
                LLVMcode *l2 = malloc_label_llvmcode();
                Factor arg1 = factorpop();
                LLVMcode *brc = malloc_brc_llvmcode(arg1, (l2->args).label.l);
                add_instruction(brc);
                add_instruction(l2);
                istackpush(brc);
        }
        DO statement
        {
                LLVMcode *brc = istackpop();
                LLVMcode *bru = istackpop();
                LLVMcode *l3 = malloc_label_llvmcode();
                add_instruction(bru);
                (brc->args).brcond.arg3 = (l3->args).label.l;
                add_instruction(l3);
        }
        ;

for_statement
        : FOR IDENT ASSIGN expression
        {
                Factor arg1 = factorpop();
                add_assign($2, arg1);
        }
        TO expression
        {
                LLVMcode *bru1 = malloc_bru_llvmcode();
                LLVMcode *l1 = malloc_label_llvmcode();
                (bru1->args).bruncond.arg1 = (l1->args).label.l;
                add_instruction(bru1);
                add_instruction(l1);

                LLVMcode *bru2 = malloc_bru_llvmcode();
                (bru2->args).bruncond.arg1 = (l1->args).label.l;
                istackpush(bru2);

                Factor arg1 = add_load($2);
                Factor arg2 = factorpop();
                add_icmpinstruction(SLE, arg1, arg2);
                Factor retval = factorpop();

                LLVMcode *l2 = malloc_label_llvmcode();
                LLVMcode *brc = malloc_brc_llvmcode(retval, (l2->args).label.l);

                add_instruction(brc);
                add_instruction(l2);
                istackpush(brc);
        }
        DO statement
        {
                Factor retval = add_load($2);
                Factor arg2;
                arg2.type = CONSTANT;
                arg2.val = 1;
                add_expinstruction(Add, retval, arg2);

                Factor arg1 = factorpop();
                add_assign($2, arg1);

                LLVMcode *l3 = malloc_label_llvmcode();
                LLVMcode *brc = istackpop();
                LLVMcode *bru = istackpop();
                (brc->args).brcond.arg3 = (l3->args).label.l;

                add_instruction(bru);
                add_instruction(l3);
        }
        ;

proc_call_statement
        : proc_call_name
        {
                LLVMcode *call = istackpop();
                add_instruction(call);
        }
        | proc_call_name LPAREN
        {
                argc = 0;
        }
        arg_list RPAREN
        {
                LLVMcode *call = istackpop();

                Fundecl *proc = lookup_fundecl((call->args).call.decl.vname, argc);
                for (int i = proc->arity - 1; i >= 0; i--) {
                        (call->args).call.argv[i] = factorpop();
                }
                (call->args).call.argc = proc->arity;
                add_instruction(call);
        }
        ;

proc_call_name
        : IDENT
        {
                LLVMcode *call = malloc_call_llvmcode($1);
                istackpush(call);
        }
        ;

block_statement
        : SBEGIN statement_list SEND
        ;

read_statement
        : READ LPAREN IDENT RPAREN
        {
                if (!used_read) {
                        LLVMcode *read = malloc_llvmcode();
                        read->command = Read;
                        add_globalinstruction(read);
                }
                used_read = true;
                add_readinstruction($3);
        }
        | READ LPAREN IDENT LBRACKET expression RBRACKET RPAREN
        {
                if (!used_read) {
                        LLVMcode *read = malloc_llvmcode();
                        read->command = Read;
                        add_globalinstruction(read);
                }
                used_read = true;
                LLVMcode *read = malloc_llvmcode();
                read->command = Read;
                Factor index = factorpop();
                Factor retval = add_getep($3, index);
                (read->args).read.arg1 = retval;
                (read->args).read.arg2 = cntr++;
                add_instruction(read);
        }
        ;

write_statement
        : WRITE LPAREN expression RPAREN
        {
                if (!used_write) {
                        LLVMcode *write = malloc_llvmcode();
                        write->command = Write;
                        add_globalinstruction(write);
                }
                used_write = true;
                add_writeinstruction();
        }
        ;

null_statement
        : /* empty */
        ;

condition
        : expression EQ expression
        {
                Factor arg1, arg2;
                arg2 = factorpop();
                arg1 = factorpop();
                add_icmpinstruction(EQUAL, arg1, arg2);
        }
        | expression NEQ expression
        {
                Factor arg1, arg2;
                arg2 = factorpop();
                arg1 = factorpop();
                add_icmpinstruction(NE, arg1, arg2);
        }
        | expression LT expression
        {
                Factor arg1, arg2;
                arg2 = factorpop();
                arg1 = factorpop();
                add_icmpinstruction(SLT, arg1, arg2);
        }
        | expression LE expression
        {
                Factor arg1, arg2;
                arg2 = factorpop();
                arg1 = factorpop();
                add_icmpinstruction(SLE, arg1, arg2);
        }
        | expression GT expression
        {
                Factor arg1, arg2;
                arg2 = factorpop();
                arg1 = factorpop();
                add_icmpinstruction(SGT, arg1, arg2);
        }
        | expression GE expression
        {
                Factor arg1, arg2;
                arg2 = factorpop();
                arg1 = factorpop();
                add_icmpinstruction(SGE, arg1, arg2);
        }
        ;

expression
        : term
        | PLUS term
        | MINUS term
        {
                Factor arg1, arg2;
                arg2 = factorpop();
                arg1.type = CONSTANT;
                arg1.val = 0;
                add_expinstruction(Sub, arg1, arg2);
        }
        | expression PLUS term
        {
                Factor arg1, arg2;
                arg2 = factorpop();
                arg1 = factorpop();
                add_expinstruction(Add, arg1, arg2);
        }
        | expression MINUS term
        {
                Factor arg1, arg2;
                arg2 = factorpop();
                arg1 = factorpop();
                add_expinstruction(Sub, arg1, arg2);
        }
        ;

term
        : factor
        | term MULT factor
        {
                Factor arg1, arg2;
                arg2 = factorpop();
                arg1 = factorpop();
                add_expinstruction(Mul, arg1, arg2);
        }
        | term DIV factor
        {
                Factor arg1, arg2;
                arg2 = factorpop();
                arg1 = factorpop();
                add_expinstruction(Div, arg1, arg2);
        }
        ;

factor
        : var_name
        | NUMBER
        {
                Factor tmp;
                tmp.type = CONSTANT;
                tmp.val = $1;
                factorpush(tmp);
        }
        | LPAREN expression RPAREN
        ;

var_name
        : IDENT
        {
                Factor retval = add_load($1);
                factorpush(retval);
        }
        | IDENT LPAREN
        {
                argc = 0;
        }
        arg_list RPAREN
        {
                // 関数確定
                LLVMcode *call = malloc_call_llvmcode($1);
                Factor retval;
                retval.type = LOCAL_VAR;
                retval.val = cntr++;
                (call->args).call.retval = retval;

                Fundecl *proc = lookup_fundecl($1, argc);
                for (int i = proc->arity - 1; i >= 0; i--) {
                        (call->args).call.argv[i] = factorpop();
                }
                (call->args).call.argc = proc->arity;
                add_instruction(call);
                factorpush(retval);
        }
        | IDENT LBRACKET expression RBRACKET
        {
                Factor index = factorpop();
                Factor retval = add_getep($1, index);

                Factor arg1 = retval;
                retval.val = cntr++;
                add_loadinstruction(retval, arg1);
                factorpush(retval);
        }
        ;

arg_list
        : expression
        {
                argc++;
        }
        | arg_list COMMA expression
        {
                argc++;
        }
        ;

id_list
        : IDENT
        {
                add_defvariable($1);
        }
        | IDENT LBRACKET NUMBER INTERVAL NUMBER RBRACKET
        {
                int size = $5 - $3 + 1;
                add_alloca_ainstruction($1, size, $3);
        }
        | id_list COMMA IDENT
        {
                add_defvariable($3);
        }
        | id_list COMMA IDENT LBRACKET NUMBER INTERVAL NUMBER RBRACKET
        {
                int size = $7 - $5 + 1;
                add_alloca_ainstruction($3, size, $5);
        }
        ;


%%
yyerror(char *s)
{
  fprintf(stderr, "Line %d: unexpected token %s\n", yylineno, yytext);
}

LLVMcode *malloc_label_llvmcode() {
        LLVMcode *tmp = malloc_llvmcode();
        tmp->command = Label;
        (tmp->args).label.l = cntr++;
        return tmp;
}

LLVMcode *malloc_llvmcode() {
        LLVMcode *tmp;
        tmp = (LLVMcode *)malloc(sizeof(LLVMcode));
        tmp->next = NULL;
        return tmp;
}

Fundecl *malloc_fundecl() {
        Fundecl *tmp;
        Factor retval;
        retval.type = VOID;
        tmp = (Fundecl *)malloc(sizeof(Fundecl));
        tmp->next = NULL;
        tmp->arity = 0;
        tmp->retval = retval;
        tmp->declare_forward = false;
        return tmp;
}

LLVMcode *malloc_bru_llvmcode() {
        LLVMcode *tmp = malloc_llvmcode();
        tmp->command = BrUncond;
        return tmp;
}

LLVMcode *malloc_brc_llvmcode(Factor arg1, int arg2) {
        LLVMcode *tmp = malloc_llvmcode();
        tmp->command = BrCond;
        (tmp->args).brcond.arg1 = arg1;
        (tmp->args).brcond.arg2 = arg2;
        return tmp;
}

LLVMcode *malloc_call_llvmcode(char *name) {
        LLVMcode *tmp = malloc_llvmcode();
        Factor decl, retval;
        decl.type = PROC_NAME;
        strcpy(decl.vname, name);
        // デフォルトは返り値なし
        retval.type = VOID;
        tmp->command = Call;
        (tmp->args).call.decl = decl;
        (tmp->args).call.retval = retval;
        return tmp;
}

void add_alloca_ainstruction(char *name, int size, int start) {
        if (current_scope == GLOBAL_VAR) { // 変更する
                insert_data(name, current_scope);
                LLVMcode *global_a = malloc_llvmcode();
                global_a->command = Global_a;
                Factor retval = lookup_data(name);
                (global_a->args).global_a.retval = retval;
                (global_a->args).global_a.size = size;
                add_globalinstruction(global_a);
        } else if (current_scope == LOCAL_VAR) {
                insert_data(name, current_scope);
                LLVMcode *alloca_a = malloc_llvmcode();
                alloca_a->command = Alloca_a;
                Factor retval = lookup_data(name);
                (alloca_a->args).alloca_a.retval = retval;
                (alloca_a->args).alloca_a.size = size;
                add_instruction(alloca_a);
        }
        stable.element[stable.top - 1].size = size;
        stable.element[stable.top - 1].start = start;
}

void add_writeinstruction() {
        LLVMcode *tmp = malloc_llvmcode();
        tmp->command = Write;
        Factor arg1 = factorpop();
        (tmp->args).write.arg1 = arg1;
        (tmp->args).write.arg2 = cntr++;
        add_instruction(tmp);
}

void add_readinstruction(char *name) {
        LLVMcode *tmp = malloc_llvmcode();
        Factor arg1 = lookup_data(name);
        tmp->command = Read;
        (tmp->args).read.arg1 = arg1;
        (tmp->args).read.arg2 = cntr++;
        add_instruction(tmp);
}

void add_retinstruction(Factor arg1) {
        LLVMcode *tmp = malloc_llvmcode();
        tmp->command = Ret;
        (tmp->args).ret.arg1 = arg1;
        add_instruction(tmp);
}

void add_allocainstruction(Factor retval) {
        LLVMcode *tmp = malloc_llvmcode();
        tmp->command = Alloca;
        (tmp->args).alloca.retval = retval;
        add_instruction(tmp);
}

void add_loadinstruction(Factor retval, Factor arg1) {
        LLVMcode *tmp = malloc_llvmcode();
        tmp->command = Load;
        (tmp->args).load.retval = retval;
        (tmp->args).load.arg1 = arg1;
        add_instruction(tmp);
}

void add_storeinstruction(Factor arg1, Factor arg2) {
        LLVMcode *tmp = malloc_llvmcode();
        tmp->command = Store;
        (tmp->args).store.arg1 = arg1;
        (tmp->args).store.arg2 = arg2;
        add_instruction(tmp);
}

void add_icmpinstruction(Cmptype type, Factor arg1, Factor arg2) {
        LLVMcode *tmp = malloc_llvmcode();
        Factor retval;
        tmp->command = Icmp;
        retval.type = LOCAL_VAR;
        retval.val = cntr++;
        (tmp->args).icmp.arg1 = arg1;
        (tmp->args).icmp.arg2 = arg2;
        (tmp->args).icmp.retval = retval;
        (tmp->args).icmp.type = type;
        add_instruction(tmp);
        factorpush(retval);
}

void add_expinstruction(LLVMcommand command, Factor arg1, Factor arg2) {
        LLVMcode *tmp = malloc_llvmcode();
        Factor retval;
        retval.type = LOCAL_VAR;
        // 定数伝播 arg1, arg2がどちらも定数の場合コンパイラで計算 このときretvalも定数
        if (arg1.type == CONSTANT && arg2.type == CONSTANT) {
                retval.type = CONSTANT;
                switch(command) {
                        case Add:
                                retval.val = arg1.val + arg2.val;
                                break;
                        case Sub:
                                retval.val = arg1.val - arg2.val;
                                break;
                        case Mul:
                                retval.val = arg1.val * arg2.val;
                                break;
                        case Div:
                                retval.val = arg1.val / arg2.val;
                                break;
                        default:
                                break;
                }
                factorpush(retval);
                return;
        }

        // 命令の置き換え arg2がCONSTANTかつ2の累乗かつ演算子がMulかDivのとき
        if (arg2.type == CONSTANT && (arg2.val & (arg2.val - 1)) == 0 && (command == Mul || command == Div)) {
                retval.val = cntr++;
                int x = (int)log2((double)arg2.val);
                switch(command) {
                        case Mul:
                                tmp->command = Shl;
                                (tmp->args).shl.retval = retval;
                                (tmp->args).shl.arg1 = arg1;
                                (tmp->args).shl.arg2 = x;
                                break;
                        case Div:
                                tmp->command = Ashr;
                                (tmp->args).ashr.retval = retval;
                                (tmp->args).ashr.arg1 = arg1;
                                (tmp->args).ashr.arg2 = x;
                                break;
                        default:
                                break;
                }
                add_instruction(tmp);
                factorpush(retval);
                return;
        }

        tmp->command = command;
        retval.val = cntr++;
        (tmp->args).mul.arg1 = arg1;
        (tmp->args).mul.arg2 = arg2;
        (tmp->args).mul.retval = retval;
        add_instruction(tmp);
        factorpush(retval);
}

void add_instruction(LLVMcode *tmp) {
        if (codetl == NULL) {
                if (declhd == NULL) {
                        fprintf(stderr, "unexpected error\n");
                }
                decltl->codes = tmp;
                codehd = codetl = tmp;
        } else {
                codetl->next = tmp;
                codetl = tmp;
        }
}

void add_globalinstruction(LLVMcode *tmp) {
        if (gcodehd == NULL) {
                gcodehd = gcodetl = tmp;
        } else {
                gcodetl->next = tmp;
                gcodetl = tmp;
        }
}

void add_assign(char *name, Factor arg1) {
        Factor arg2 = lookup_data(name);
        if (arg2.type == PROC_NAME) {
                arg2.type = LOCAL_VAR;
                decltl->retval = arg2;
        }
        add_storeinstruction(arg1, arg2);
}

Factor add_load(char *name) {
        Factor retval, arg1 = lookup_data(name);
        retval.type = LOCAL_VAR;
        retval.val = cntr++;
        if (arg1.type == PROC_NAME) {
                LLVMcode *call = malloc_call_llvmcode(name);
                (call->args).call.retval = retval;
                add_instruction(call);
        } else {
                add_loadinstruction(retval, arg1);
        }
        return retval;
}

Factor add_getep(char *name, Factor index) {
        Factor arg1, arg2, retval;
        arg2.type = CONSTANT;
        arg2.val = lookup_data(name).start;
        add_expinstruction(Sub, index, arg2);

        LLVMcode *sext = malloc_llvmcode();
        sext->command = Sext;
        arg1 = factorpop();
        retval.type = LOCAL_VAR;
        retval.val = cntr++;
        (sext->args).sext.arg1 = arg1;
        (sext->args).sext.retval = retval;
        add_instruction(sext);

        LLVMcode *getep = malloc_llvmcode();
        getep->command = Getep;
        (getep->args).getep.size = lookup_data(name).size;
        arg1 = lookup_data(name);
        arg2 = retval;
        retval.val = cntr++;
        (getep->args).getep.arg1 = arg1;
        (getep->args).getep.arg2 = arg2;
        (getep->args).getep.retval = retval;
        add_instruction(getep);

        return retval;
}

void add_proc_args() {
        cntr = decltl->arity + 1;

        Factor retval;
        retval.type = LOCAL_VAR;
        for (int i = 0; i < decltl->arity; i++) {
                insert_data(decltl->args[i].vname, LOCAL_VAR);
                cntr++;
                retval.val = i + decltl->arity + 1;
                add_allocainstruction(retval);
        }

        Factor arg1, arg2;
        arg1.type = arg2.type = LOCAL_VAR;
        for (int i = 0; i < decltl->arity; i++) {
                arg1.val = i;
                arg2.val = i + decltl->arity + 1;
                add_storeinstruction(arg1, arg2);
        }
}

void add_func_args() {
        stable.element[stable.top - 1].val = cntr = decltl->arity + 1;
        Factor retval;
        retval.type = LOCAL_VAR;
        retval.val = cntr++;
        add_allocainstruction(retval);

        for (int i = 0; i < decltl->arity; i++) {
                insert_data(decltl->args[i].vname, LOCAL_VAR);
                retval.val = cntr++;
                add_allocainstruction(retval);
        }

        Factor arg1, arg2;
        arg1.type = arg2.type = LOCAL_VAR;
        for (int i = 0; i < decltl->arity; i++) {
                arg1.val = i;
                arg2.val = i + decltl->arity + 2;
                add_storeinstruction(arg1, arg2);
        }
}

void load_ret_fnrv() {
        // 戻り値をloadしてret
        Factor arg1, retval;
        retval.type = arg1.type = LOCAL_VAR;
        arg1.val = decltl->retval.val;
        retval.val = cntr++;
        add_loadinstruction(retval, arg1);
        add_retinstruction(retval);
}

void add_defvariable(char *name) {
        if (current_scope == LOCAL_VAR) {
                insert_data(name, current_scope);
                Factor retval;
                retval.type = LOCAL_VAR;
                retval.val = cntr++;
                add_allocainstruction(retval);
        } else if (current_scope == GLOBAL_VAR) {
                insert_data(name, current_scope);
                LLVMcode *global = malloc_llvmcode();
                global->command = Global;
                Factor retval;
                retval.type = GLOBAL_VAR;
                strcpy(retval.vname, name);
                (global->args).global.retval = retval;
                add_globalinstruction(global);
        } else if (current_scope == PROC_NAME) {
                Factor arg;
                arg.type = LOCAL_VAR;
                strcpy(arg.vname, name);
                decltl->args[decltl->arity++] = arg;
        }
}

void add_decl(Fundecl *tmp) {
        if (declhd == NULL) {
                declhd = decltl = tmp;
        } else {
                if (decltl == NULL) {
                        fprintf(stderr, "unexpected error\n");
                }
                decltl->next = tmp;
                decltl = tmp;
                codehd = codetl = decltl->codes;
        }
}

void init_stack() {
        fstack.top = 0;
        stable.top = 0;
        istack.top = 0;
        return;
}

Factor factorpop() {
        Factor tmp;
        tmp = fstack.element[fstack.top];
        fstack.top --;
        return tmp;
}

void factorpush(Factor x) {
        fstack.top ++;
        fstack.element[fstack.top] = x;
        return;
}

LLVMcode *istackpop() {
        LLVMcode *tmp;
        tmp = istack.element[istack.top--];
        return tmp;
}

void istackpush(LLVMcode *x) {
        istack.element[++istack.top] = x;
}

void fwriteIcmp(Cmptype type) {
        switch(type) {
        case EQUAL:
                fprintf(f, "eq");
                break;
        case NE:
                fprintf(f, "ne");
                break;
        case SGT:
                fprintf(f, "sgt");
                break;
        case SGE:
                fprintf(f, "sge");
                break;
        case SLT:
                fprintf(f, "slt");
                break;
        case SLE:
                fprintf(f, "sle");
                break;
        default:
                break;
        }
        return;
}

void fwriteFactor( Factor factor ){
        switch( factor.type ){
        case GLOBAL_VAR:
                fprintf(f, "@%s", factor.vname );
                break;
        case LOCAL_VAR:
                fprintf(f, "%%%d", factor.val );
                break;
        case CONSTANT:
                fprintf(f, "%d", factor.val );
                break;
        case PROC_NAME:
                fprintf(f, "@%s", factor.vname);
                break;
        default:
                break;
        }
        return;
}

void fwriteGlobalLlvmcodes(LLVMcode *code) {
        if (code == NULL) {
                return;
        }
        switch(code->command) {
        case Global:
                fwriteFactor((code->args).global.retval);
                fprintf(f, " = common global i32 0, align 4\n");
                break;
        case Read:
                fprintf(f, "@.read = private unnamed_addr constant [3 x i8] c\"%%d\\00\", align 1\n");
                break;
        case Write:
                fprintf(f, "@.write = private unnamed_addr constant [4 x i8] c\"%%d\\0A\\00\", align 1\n");
                break;
        case Global_a:
                fwriteFactor((code->args).global_a.retval);
                fprintf(f, " = common global [%d x i32] zeroinitializer, align 16\n", (code->args).global_a.size);
                break;
        default:
                break;
        }
        fwriteGlobalLlvmcodes(code->next);
}

void fwriteLlvmcodes( LLVMcode *code ){
        if( code == NULL ) return;
        if (code->command == Label) {
                fprintf(f, "\n");
        } else {
                fprintf(f, "  ");
        }
        switch( code->command ){
        case Alloca:
                fwriteFactor( (code->args).alloca.retval );
                fprintf(f, " = alloca i32, align 4\n");
                break;
        case Load:
                fwriteFactor((code->args).load.retval);
                fprintf(f, " = load i32, i32* ");
                fwriteFactor((code->args).load.arg1);
                fprintf(f, ", align 4\n");
                break;
        case Store:
                fprintf(f, "store i32 ");
                fwriteFactor((code->args).store.arg1);
                fprintf(f, ", i32* ");
                fwriteFactor((code->args).store.arg2);
                fprintf(f, ", align 4\n");
                break;
        case Ret:
                fprintf(f, "ret ");
                if ((code->args).ret.arg1.type != VOID) {
                        fprintf(f, "i32 ");
                        fwriteFactor((code->args).ret.arg1);
                        fprintf(f, "\n");
                } else {
                        fprintf(f, "void\n");
                }
                break;
        case Add:
                fwriteFactor((code->args).add.retval);
                fprintf(f, " = add nsw i32 ");
                fwriteFactor((code->args).add.arg1);
                fprintf(f, ", ");
                fwriteFactor((code->args).add.arg2);
                fprintf(f, "\n");
                break;
        case Sub:
                fwriteFactor((code->args).sub.retval);
                fprintf(f, " = sub nsw i32 ");
                fwriteFactor((code->args).sub.arg1);
                fprintf(f, ", ");
                fwriteFactor((code->args).sub.arg2);
                fprintf(f, "\n");
                break;
        case Mul:
                fwriteFactor((code->args).mul.retval);
                fprintf(f, " = mul nsw i32 ");
                fwriteFactor((code->args).mul.arg1);
                fprintf(f, ", ");
                fwriteFactor((code->args).mul.arg2);
                fprintf(f, "\n");
                break;
        case Div:
                fwriteFactor((code->args).div.retval);
                fprintf(f, " = sdiv i32 ");
                fwriteFactor((code->args).div.arg1);
                fprintf(f, ", ");
                fwriteFactor((code->args).div.arg2);
                fprintf(f, "\n");
                break;
        case Icmp:
                fwriteFactor((code->args).icmp.retval);
                fprintf(f, " = icmp ");
                fwriteIcmp((code->args).icmp.type);
                fprintf(f, " i32 ");
                fwriteFactor((code->args).icmp.arg1);
                fprintf(f, ", ");
                fwriteFactor((code->args).icmp.arg2);
                fprintf(f, "\n");
                break;
        case Call:
                // retval がVOIDかどうかで条件分岐
                if ((code->args).call.retval.type == VOID) {
                        fprintf(f, "call void ");
                } else {
                        fwriteFactor((code->args).call.retval);
                        fprintf(f, " = call i32 ");
                }
                fwriteFactor((code->args).call.decl);
                fprintf(f, "%d", (code->args).call.argc);

                fprintf(f, "(");
                for (int i = 0; i < (code->args).call.argc - 1; i++) {
                        fprintf(f, "i32 ");
                        fwriteFactor((code->args).call.argv[i]);
                        fprintf(f, ", ");
                }
                if ((code->args).call.argc != 0) {
                        fprintf(f, "i32 ");
                        fwriteFactor((code->args).call.argv[(code->args).call.argc - 1]);
                }
                fprintf(f, ")\n");
                break;
        case BrUncond:
                fprintf(f, "br label %%%d\n", (code->args).bruncond.arg1);
                break;
        case BrCond:
                fprintf(f, "br i1 ");
                fwriteFactor((code->args).brcond.arg1);
                fprintf(f, ", label %%%d, label %%%d\n", (code->args).brcond.arg2, (code->args).brcond.arg3);
                break;
        case Label:
                fprintf(f, "; <label>:%d:\n", (code->args).label.l);
                break;
        case Write:
                fprintf(f, "%%%d = call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([4 x i8], [4 x i8]* @.write, i64 0, i64 0), i32 ", (code->args).write.arg2);
                fwriteFactor((code->args).write.arg1);
                fprintf(f, ")\n");
                break;
        case Read:
                fprintf(f, "%%%d = call i32 (i8*, ...) @__isoc99_scanf(i8* getelementptr inbounds ([3 x i8], [3 x i8]* @.read, i64 0, i64 0), i32* ", (code->args).read.arg2);
                fwriteFactor((code->args).read.arg1);
                fprintf(f, ")\n");
                break;
        case Alloca_a:
                fwriteFactor((code->args).alloca_a.retval);
                fprintf(f, " = alloca [%d x i32] zeroinitializer, align 16\n", (code->args).alloca_a.size);
                break;
        case Sext:
                fwriteFactor((code->args).sext.retval);
                fprintf(f, " = sext i32 ");
                fwriteFactor((code->args).sext.arg1);
                fprintf(f, " to i64\n");
                break;
        case Getep:
                fwriteFactor((code->args).getep.retval);
                fprintf(f, " = getelementptr inbounds [%d x i32], [%d x i32]* ", (code->args).getep.size, (code->args).getep.size);
                fwriteFactor((code->args).getep.arg1);
                fprintf(f, ", i64 0, i64 ");
                fwriteFactor((code->args).getep.arg2);
                fprintf(f, "\n");
                break;
        case Shl:
                fwriteFactor((code->args).shl.retval);
                fprintf(f, " = shl i32 ");
                fwriteFactor((code->args).shl.arg1);
                fprintf(f, ", %d\n", (code->args).shl.arg2);
                break;
        case Ashr:
                fwriteFactor((code->args).ashr.retval);
                fprintf(f, " = ashr i32 ");
                fwriteFactor((code->args).ashr.arg1);
                fprintf(f, ", %d\n", (code->args).ashr.arg2);
                break;
        default:
                break;
        }
        fwriteLlvmcodes( code->next );
}

void fwriteLlvmfundecl( Fundecl *decl ){
        if( decl == NULL ) return;
        if (decl->declare_forward) {
                fwriteLlvmfundecl(decl->next);
                return;
        }
        if (strcmp(decl->fname, "main") == 0) {
                fprintf(f, "\ndefine i32 @main(");
        } else if (decl->retval.type == VOID) {
                fprintf(f, "\ndefine void @%s%d(", decl->fname, decl->arity);
        } else {
                fprintf(f, "\ndefine i32 @%s%d(", decl->fname, decl->arity);
        }
        for (int i = decl->arity - 1; i > 0; i--) {
                fprintf(f, "i32 , ");
        }
        if (decl->arity != 0) {
                fprintf(f, "i32");
        }
        fprintf(f, ") {\n");
        fwriteLlvmcodes( decl->codes );
        fprintf(f, "}\n");
        if( decl->next != NULL ) {
                fprintf(f, "\n");
        fwriteLlvmfundecl( decl->next );
        }
        return;
}

void fwriteLlvmglobal(LLVMcode *code) {
        if (code == NULL) {
                return;
        }
        fwriteGlobalLlvmcodes(code);
        fprintf(f, "\n");
}

void fwriteDeclare() {
        if (used_read) {
                fprintf(f, "\n\ndeclare i32 @__isoc99_scanf(i8*, ...)");
        }
        if (used_write) {
                fprintf(f, "\n\ndeclare i32 @printf(i8*, ...)");
        }
}

void insert_data(char *name, Scope scope) {
        strcpy(stable.element[stable.top].vname, name);
        stable.element[stable.top].type = scope;
        stable.element[stable.top].val = cntr;
        stable.top++;
}

Factor lookup_data(char *name) {
        for (int i = stable.top - 1; i >= 0; i--) {
                if (strcmp(stable.element[i].vname, name) == 0) {
                        return stable.element[i];
                }
        }
        Factor tmp;
        return tmp;
}

Fundecl *lookup_fundecl(char *name, int argc) {
        Fundecl *tmp;
        if (declhd == NULL) {
                fprintf(stderr, "Not Found.\n");
                return tmp;
        }
        tmp = declhd;
        while (tmp != NULL) {
                // argc == -1の場合関数名だけあっていればその関数を返す
                if (strcmp(tmp->fname, name) == 0 && (tmp->arity == argc || argc == -1)) {
                        return tmp;
                }
                tmp = tmp->next;
        }
        fprintf(stderr, "Not Found decl.\n");
        return tmp;
}

void delete_data() {
        for (int i = stable.top - 1; i >= 0; i--) {
                if (stable.element[i].type != LOCAL_VAR) {
                        break;
                }
        stable.top--;
        }
}
