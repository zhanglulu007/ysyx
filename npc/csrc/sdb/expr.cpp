/***************************************************************************************
* NPC Simple Debugger (sdb)
* 表达式求值模块
***************************************************************************************/

#include "sdb.h"
#include <regex.h>
#include <cassert>

enum {
  TK_NOTYPE = 256, 
  TK_EQ,
  TK_NUM,
  TK_HEX,
  TK_REG,
  TK_NE,
  TK_AND,
  TK_DEREF,
};

static struct rule {
  const char *regex;
  int token_type;
} rules[] = {
  {" +", TK_NOTYPE},
  {"==", TK_EQ},
  {"!=", TK_NE},
  {"&&", TK_AND},
  {"0[xX][0-9a-fA-F]+", TK_HEX},
  {"[0-9]+", TK_NUM},
  {"\\$[a-zA-Z0-9]+", TK_REG},
  {"\\+", '+'},
  {"-", '-'},
  {"\\*", '*'},
  {"/", '/'},
  {"\\(", '('},
  {"\\)", ')'},
};

#define NR_REGEX (sizeof(rules) / sizeof(rules[0]))

static regex_t re[NR_REGEX] = {};

void init_regex() {
  int i;
  char error_msg[128];
  int ret;

  for (i = 0; i < NR_REGEX; i ++) {
    ret = regcomp(&re[i], rules[i].regex, REG_EXTENDED);
    if (ret != 0) {
      regerror(ret, &re[i], error_msg, 128);
      printf("regex compilation failed: %s\n%s\n", error_msg, rules[i].regex);
      assert(0);
    }
  }
}

typedef struct token {
  int type;
  char str[32];
} Token;

static Token tokens[65536];
static int nr_token = 0;

static bool make_token(char *e) {
  int position = 0;
  int i;
  regmatch_t pmatch;

  nr_token = 0;

  while (e[position] != '\0') {
    for (i = 0; i < NR_REGEX; i ++) {
      if (regexec(&re[i], e + position, 1, &pmatch, 0) == 0 && pmatch.rm_so == 0) {
        char *substr_start = e + position;
        int substr_len = pmatch.rm_eo;

        position += substr_len;

        switch (rules[i].token_type) {
          case TK_NOTYPE:
            break;

          case TK_NUM:
          case TK_HEX:
          case TK_REG:
            tokens[nr_token].type = rules[i].token_type;
            if (substr_len >= 32) {
              printf("Token too long!\n");
              return false;
            }
            strncpy(tokens[nr_token].str, substr_start, substr_len);
            tokens[nr_token].str[substr_len] = '\0';
            nr_token++;
            break;

          case '+':
          case '-':
          case '*':
          case '/':
          case '(':
          case ')':
          case TK_EQ:
          case TK_NE:
          case TK_AND:
            tokens[nr_token].type = rules[i].token_type;
            nr_token++;
            break;

          default:
            assert(0);
        }

        if (nr_token >= 65536) {
          printf("Too many tokens\n");
          return false;
        }

        break;
      }
    }

    if (i == NR_REGEX) {
      printf("no match at position %d\n%s\n%*.s^\n", position, e, position, "");
      return false;
    }
  }

  return true;
}

static bool check_parentheses(int p, int q) {
  if (tokens[p].type != '(' || tokens[q].type != ')') {
    return false;
  }
  
  int count = 0;
  for (int i = p; i <= q; i++) {
    if (tokens[i].type == '(') count++;
    if (tokens[i].type == ')') count--;
    
    if (count < 0) return false;
    if (count == 0 && i < q) return false;
  }
  
  return count == 0;
}

static int find_main_op(int p, int q) {
  int main_op = -1;
  int min_priority = 100;
  int paren_level = 0;
  
  for (int i = p; i <= q; i++) {
    if (tokens[i].type == '(') {
      paren_level++;
      continue;
    }
    if (tokens[i].type == ')') {
      paren_level--;
      continue;
    }
    
    if (paren_level > 0) continue;
    if (tokens[i].type == TK_DEREF) continue;
    
    int priority = 100;
    
    if (tokens[i].type == TK_AND) {
      priority = 0;
    }
    else if (tokens[i].type == TK_EQ || tokens[i].type == TK_NE) {
      priority = 1;
    }
    else if (tokens[i].type == '+' || tokens[i].type == '-') {
      priority = 2;
    }
    else if (tokens[i].type == '*' || tokens[i].type == '/') {
      priority = 3;
    }
    else {
      continue;
    }
    
    if (priority <= min_priority) {
      min_priority = priority;
      main_op = i;
    }
  }
  
  return main_op;
}

static word_t eval(int p, int q, bool *success) {
  if (p > q) {
    *success = false;
    return 0;
  }
  else if (p == q) {
    switch (tokens[p].type) {
      case TK_NUM:
        return atoi(tokens[p].str);
        
      case TK_HEX:
        return strtol(tokens[p].str, NULL, 16);
        
      case TK_REG: {
        bool reg_success;
        word_t val = npc_reg_str2val(tokens[p].str + 1, &reg_success);
        if (!reg_success) {
          printf("Unknown register: %s\n", tokens[p].str);
          *success = false;
          return 0;
        }
        return val;
      }
      
      default:
        printf("Invalid single token type: %d\n", tokens[p].type);
        *success = false;
        return 0;
    }
  }
  else if (check_parentheses(p, q) == true) {
    return eval(p + 1, q - 1, success);
  }
  else {
    if (tokens[p].type == TK_DEREF) {
      word_t addr = eval(p + 1, q, success);
      if (!*success) return 0;
      
      if (!in_pmem(addr)) {
        printf("Invalid memory address: 0x%08x\n", addr);
        *success = false;
        return 0;
      }
      
      return pmem_read_word(addr);
    }
    
    int op = find_main_op(p, q);
    if (op == -1) {
      printf("No main operator found\n");
      *success = false;
      return 0;
    }
    
    word_t val1 = eval(p, op - 1, success);
    if (!*success) return 0;
    
    word_t val2 = eval(op + 1, q, success);
    if (!*success) return 0;
    
    switch (tokens[op].type) {
      case '+': return val1 + val2;
      case '-': return val1 - val2;
      case '*': return val1 * val2;
      case '/':
        if (val2 == 0) {
          printf("Division by zero!\n");
          *success = false;
          return 0;
        }
        return val1 / val2;
        
      case TK_EQ:  return val1 == val2;
      case TK_NE:  return val1 != val2;
      case TK_AND: return val1 && val2;
      
      default:
        printf("Unknown operator: %d\n", tokens[op].type);
        *success = false;
        return 0;
    }
  }
}

word_t expr(char *e, bool *success) {
  if (!make_token(e)) {
    *success = false;
    return 0;
  }

  // 识别指针解引用
  for (int i = 0; i < nr_token; i++) {
    if (tokens[i].type == '*') {
      if (i == 0 || 
          tokens[i - 1].type == '(' ||
          tokens[i - 1].type == '+' ||
          tokens[i - 1].type == '-' ||
          tokens[i - 1].type == '*' ||
          tokens[i - 1].type == '/' ||
          tokens[i - 1].type == TK_EQ ||
          tokens[i - 1].type == TK_NE ||
          tokens[i - 1].type == TK_AND ||
          tokens[i - 1].type == TK_DEREF) {
        tokens[i].type = TK_DEREF;
      }
    }
  }

  *success = true;
  word_t result = eval(0, nr_token - 1, success);
  return result;
}
