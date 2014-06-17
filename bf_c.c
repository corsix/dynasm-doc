#include <stdio.h>
#include <stdlib.h>

#define TAPE_SIZE 30000
#define MAX_NESTING 100

typedef struct bf_state
{
  unsigned char* tape;
  unsigned char (*get_ch)(struct bf_state*);
  void (*put_ch)(struct bf_state*, unsigned char);
} bf_state_t;

#define bad_program(s) exit(fprintf(stderr, "bad program near %.16s: %s\n", program, s))

static void bf_interpret(const char* program, bf_state_t* state)
{
  const char* loops[MAX_NESTING];
  int nloops = 0;
  int n;
  int nskip = 0;
  unsigned char* tape_begin = state->tape - 1;
  unsigned char* ptr = state->tape;
  unsigned char* tape_end = state->tape + TAPE_SIZE - 1;
  for(;;) {
    switch(*program++) {
    case '<':
      for(n = 1; *program == '<'; ++n, ++program);
      if(!nskip) {
        ptr -= n;
        while(ptr <= tape_begin)
          ptr += TAPE_SIZE;
      }
      break;
    case '>':
      for(n = 1; *program == '>'; ++n, ++program);
      if(!nskip) {
        ptr += n;
        while(ptr > tape_end)
          ptr -= TAPE_SIZE;
      }
      break;
    case '+':
      for(n = 1; *program == '+'; ++n, ++program);
      if(!nskip)
        *ptr += n;
      break;
    case '-':
      for(n = 1; *program == '-'; ++n, ++program);
      if(!nskip)
        *ptr -= n;
      break;
    case ',':
      if(!nskip)
        *ptr = state->get_ch(state);
      break;
    case '.':
      if(!nskip)
        state->put_ch(state, *ptr);
      break;
    case '[':
      if(nloops == MAX_NESTING)
        bad_program("Nesting too deep");
      loops[nloops++] = program;
      if(!*ptr)
        ++nskip;
      break;
    case ']':
      if(nloops == 0)
        bad_program("] without matching [");
      if(*ptr)
        program = loops[nloops-1];
      else
        --nloops;
      if(nskip)
        --nskip;
      break;
    case 0:
      if(nloops != 0)
        program = "<EOF>", bad_program("[ without matching ]");
      return;
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
  bf_interpret(program, &state);
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
