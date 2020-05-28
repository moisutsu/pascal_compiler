# Pascal Compiler

C言語によるPascal風言語のコンパイラの実装

## 使用技術
- llvm
- yacc
- lex

## 実行方法

`docker-compose`でアプリケーションを立ち上げる。

```bash
$ docker-compose run --rm compiler
```

`make run`でプログラムをコンパイルし、`llvm`で実行する。

```bash
$ make run
```

これにより、`samples`内の`prime_numbers.p`を実行。

`make run`するときに、引数を与えることで、`samples`内のプログラムをファイルを指定できる。

```bash
$ make run FILE=bubble_sort.p
```

## samples

`samples`内のプログラムを紹介

- prime_numbers.p

    数値を一つ入力することで、2からその数値までの素数を出力する。

- fact.p

    数値を一つ入力することで、その数値の階乗を出力する。

- bubble_sort.p

    まず数値を一つ入力し要素数を決める。そして、その要素を1要素ずつ入力することで、バブルソートを行い出力する。
