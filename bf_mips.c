// Compiled with `gcc -mabi=32 bf_mips.c` if your machine is mips64el.
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include "dasm_proto.h"
#include "dasm_mips.h"
#include <sys/mman.h>

typedef struct bf_state
{
  unsigned char* tape;
  unsigned char (*get_ch)(struct bf_state*);
  void (*put_ch)(struct bf_state*, unsigned char);
} bf_state_t;

static void* link_and_encode(dasm_State** d)
{
  size_t sz;
  void* buf = 0;
  dasm_link(d, &sz);
  buf = mmap(0, sz, PROT_READ | PROT_WRITE , MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (buf == (void*)-1) {
    perror("link_and_encode mmap failed:");
    return 0;
  }
  dasm_encode(d, buf);
  mprotect(buf, sz, PROT_READ | PROT_EXEC);
  return buf;
}

#define TAPE_SIZE 30000
#define MAX_NESTING 100

#define bad_program(s) exit(fprintf(stderr, "bad program near %.16s: %s\n", program, s))

static void(* bf_compile(const char* program) )(bf_state_t*)
{
  |.arch mips
  |.section code

  unsigned loops[MAX_NESTING];
  int nloops = 0;
  int n;
  dasm_State* d;
  unsigned npc = 8;
  unsigned nextpc = 0;
  dasm_init(&d, DASM_MAXSECTION);

  |.globals lbl_
  void* labels[lbl__MAX];
  dasm_setupglobal(&d, labels, lbl__MAX);

  |.actionlist bf_actions
  dasm_setup(&d, bf_actions);

  dasm_growpc(&d, npc);

  |.define ZERO, r0
  |.define v0, r2
  |.define aPtr, r16
  |.define aState, r17
  |.define aTapeBegin, r18
  |.define aTapeEnd, r19
  |.define aTMP, r20
  |.define rArg1, r4
  |.define rArg2, r5

  |.macro prepcall1, arg1
    | move rArg1, arg1
  |.endmacro

  |.macro prepcall2, arg1, arg2
    | move rArg1, arg1
    | move rArg2, arg2
  |.endmacro

  |.define postcall, .nop

  |.macro prologue
    | addiu sp, sp, -6*8
    | sw aPtr, 0(sp)
    | sw aState, 8(sp)
    | sw aTapeBegin, 16(sp)
    | sw aTapeEnd, 24(sp)
    | sw v0, 32(sp)
    | sw ra, 40(sp)
    | move aState, rArg1
  |.endmacro
  |.macro epilogue
    | lw aPtr, 0(sp)
    | lw aState, 8(sp)
    | lw aTapeBegin, 16(sp)
    | lw aTapeEnd, 24(sp)
    | lw v0, 32(sp)
    | lw ra, 40(sp)
    | addiu sp, sp, 6*8
    | jr ra
  |.endmacro

  |.type STATE, bf_state_t, aState

  dasm_State** Dst = &d;
  |.code
  |->bf_main:
  | prologue
  | lw aPtr, STATE->tape
  | addi aTapeBegin, aPtr, -1
  | addi aTapeEnd, aPtr, (TAPE_SIZE-1)

  // Don't remove the `nop`s below.
  // See also https://www.wikiwand.com/en/Delay_slot
  for(;;) {
    switch(*program++) {
    case '<':
      for(n = 1; *program == '<'; ++n, ++program);
      | addi aPtr, aPtr, -n%TAPE_SIZE
      | sub aTMP, aPtr, aTapeBegin
      | bgtz aTMP, >1
      | nop
      | addi aPtr, aPtr, TAPE_SIZE
      |1:
      break;
    case '>':
      for(n = 1; *program == '>'; ++n, ++program);
      | addi aPtr, aPtr, n%TAPE_SIZE
      | sub aTMP, aPtr, aTapeEnd
      | blez aTMP, >1
      | nop
      | addi aPtr, aPtr, -TAPE_SIZE
      |1:
      break;
    case '+':
      for(n = 1; *program == '+'; ++n, ++program);
      | lb aTMP, 0(aPtr)
      | addi aTMP, aTMP, n
      | sb aTMP, 0(aPtr)
      break;
    case '-':
      for(n = 1; *program == '-'; ++n, ++program);
      | lb aTMP, 0(aPtr)
      | addi aTMP, aTMP, -n
      | sb aTMP, 0(aPtr)
      break;
    case ',':
      | prepcall1 aState
      | lw aTMP, STATE->get_ch
      | jalr aTMP
      | postcall 1
      | sb v0, 0(aPtr)
      break;
    case '.':
      | lb aTMP, 0(aPtr)
      | prepcall2 aState, aTMP
      | lw aTMP, STATE->put_ch
      | jalr aTMP
      | postcall 2
      break;
    case '[':
      if(nloops == MAX_NESTING)
        bad_program("Nesting too deep");
      if(program[0] == '-' && program[1] == ']') {
        program += 2;
        | sb ZERO, 0(aPtr)
      } else {
        if(nextpc == npc) {
          npc *= 2;
          dasm_growpc(&d, npc);
        }
        | lb aTMP, 0(aPtr)
        | beqz aTMP, =>nextpc+1
        | nop
        |=>nextpc:
        loops[nloops++] = nextpc;
        nextpc += 2;
      }
      break;
    case ']':
      if(nloops == 0)
        bad_program("] without matching [");
      --nloops;
      | lb aTMP, 0(aPtr)
      | bnez aTMP, =>loops[nloops]
      | nop
      |=>loops[nloops]+1:
      break;
    case 0:
      if(nloops != 0)
        program = "<EOF>", bad_program("[ without matching ]");
      | epilogue

      link_and_encode(&d);
      dasm_free(&d);
      return (void(*)(bf_state_t*))labels[lbl_bf_main];
    }
  }
}

static void bf_putchar(bf_state_t* s, unsigned char c)
{
  putchar((int)c);
}

static unsigned char bf_getchar(bf_state_t* s)
{
  return (unsigned char)getchar();
}


static void bf_run(const char* program)
{
  bf_state_t state;
  unsigned char tape[TAPE_SIZE] = {0};
  state.tape = tape;
  state.get_ch = bf_getchar;
  state.put_ch = bf_putchar;
  bf_compile(program)(&state);
}

int main(int argc, char** argv)
{
  if(argc == 2) {
    long sz;
    char* program;
    FILE* f = fopen(argv[1], "r");
    if(!f) {
      fprintf(stderr, "Cannot open %s\n", argv[1]);
      return 1;
    }
    fseek(f, 0, SEEK_END);
    sz = ftell(f);
    program = (char*)malloc(sz + 1);
    fseek(f, 0, SEEK_SET);
    program[fread(program, 1, sz, f)] = 0;
    fclose(f);
    bf_run(program);
    return 0;
  } else {
    fprintf(stderr, "Usage: %s INFILE.bf\n", argv[0]);
    return 1;
  }
}
