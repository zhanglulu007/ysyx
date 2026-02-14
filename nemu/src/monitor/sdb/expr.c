/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include <isa.h>

/* We use the POSIX regex functions to process regular expressions.
 * Type 'man regex' for more information about POSIX regex functions.
 */
#include <regex.h>

enum {
  TK_NOTYPE = 256, 
  TK_EQ,
  TK_NUM, // 十进制数
  /* TODO: Add more token types */

};

static struct rule {
  const char *regex;
  int token_type;
} rules[] = {

  /* TODO: Add more rules.
   * Pay attention to the precedence level of different rules.
   */

  {" +", TK_NOTYPE},           // 空格
  {"\\+", '+'},                // 加号
  {"-", '-'},                  // 减号
  {"\\*", '*'},                // 乘号（*是正则元字符，需转义）
  {"/", '/'},                  // 除号
  {"\\(", '('},                // 左括号（括号是正则元字符）
  {"\\)", ')'},                // 右括号
  {"[0-9]+", TK_NUM},          // 十进制数字
  {"==", TK_EQ},               // 等号
};

#define NR_REGEX ARRLEN(rules)

static regex_t re[NR_REGEX] = {};

/* Rules are used for many times.
 * Therefore we compile them only once before any usage.
 */
void init_regex() {
  int i;
  char error_msg[128];
  int ret;

  for (i = 0; i < NR_REGEX; i ++) {
    ret = regcomp(&re[i], rules[i].regex, REG_EXTENDED);
    if (ret != 0) {
      regerror(ret, &re[i], error_msg, 128);
      panic("regex compilation failed: %s\n%s", error_msg, rules[i].regex);
    }
  }
}

typedef struct token {
  int type;
  char str[32];
} Token;

static Token tokens[65536] __attribute__((used)) = {};
static int nr_token __attribute__((used))  = 0;

static bool make_token(char *e) {
  int position = 0;
  int i;
  regmatch_t pmatch;

  nr_token = 0;

  while (e[position] != '\0') {
    /* Try all rules one by one. */
    for (i = 0; i < NR_REGEX; i ++) {
      if (regexec(&re[i], e + position, 1, &pmatch, 0) == 0 && pmatch.rm_so == 0) {
        char *substr_start = e + position;
        int substr_len = pmatch.rm_eo;

        Log("match rules[%d] = \"%s\" at position %d with len %d: %.*s",
            i, rules[i].regex, position, substr_len, substr_len, substr_start);

        position += substr_len;

        /* TODO: Now a new token is recognized with rules[i]. Add codes
         * to record the token in the array `tokens'. For certain types
         * of tokens, some extra actions should be performed.
         */

        switch (rules[i].token_type) {
          case TK_NOTYPE:
            // 空格，不记录
            break;
          case TK_NUM:
          case '+':
          case '-':
          case '*':
          case '/':
          case '(':
          case ')':
          case TK_EQ:
            // 记录token
            tokens[nr_token].type = rules[i].token_type;
            
            // 对于数字，需要保存字符串
            if (rules[i].token_type == TK_NUM) {
              if (substr_len >= 32) {
                printf("Token too long!\n");
                return false;
              }
              strncpy(tokens[nr_token].str, substr_start, substr_len);
              tokens[nr_token].str[substr_len] = '\0';
            }
            
            nr_token++;
            if (nr_token >= 65536) {
              printf("Too many tokens\n");
              return false;
            }
            break;
          default: 
            assert(0);
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

// 检查表达式是否被一对匹配的括号包围
// 返回值：true表示被包围，false表示未被包围或括号不匹配
static bool check_par(int p, int q) {
  if (tokens[p].type != '(' || tokens[q].type != ')') {
    return false;  // 首尾不是括号
  }
  
  int count = 0;
  for (int i = p; i <= q; i++) {
    if (tokens[i].type == '(') count++;
    if (tokens[i].type == ')') count--;
    
    // 括号不匹配
    if (count < 0) return false;
    
    // 在中间某处括号就配平了，说明不是被一对括号包围
    if (count == 0 && i < q) return false;
  }
  
  // 最后括号数应该为0
  return count == 0;
}


// 找到主运算符的位置
static int find_main_op(int p, int q) {
  int main_op = -1;
  int min_priority = 100;  // 最低优先级（数字越大优先级越高）
  int paren_level = 0;     // 括号层级
  
  for (int i = p; i <= q; i++) {
    if (tokens[i].type == '(') {
      paren_level++;
      continue;
    }
    if (tokens[i].type == ')') {
      paren_level--;
      continue;
    }
    
    // 括号内的运算符不是主运算符
    if (paren_level > 0) continue;
    
    // 判断运算符优先级
    int priority = 100;
    if (tokens[i].type == '+' || tokens[i].type == '-') {
      priority = 1;  // 加减优先级最低
    } else if (tokens[i].type == '*' || tokens[i].type == '/') {
      priority = 2;  // 乘除优先级较高
    } else {
      continue;  // 不是运算符
    }
    
    // 优先级更低，或者优先级相同但位置更靠右（左结合）
    if (priority <= min_priority) {
      min_priority = priority;
      main_op = i;
    }
  }
  
  return main_op;
}


static uint32_t eval(int p, int q) {
  if (p > q) {
    // 错误的表达式
    assert(0);
  }
  else if (p == q) {
    // 单个token，应该是数字
    if (tokens[p].type == TK_NUM) {
      return atoi(tokens[p].str);
    }
    assert(0);
  }
  else if (check_par(p, q) == true) {
    // 整个表达式被括号包围，去掉括号
    return eval(p + 1, q - 1);
  }
  else {
    int op = find_main_op(p, q);
    if (op == -1) {
      // 没找到主运算符，表达式有问题
      assert(0);
    }
    
    uint32_t val1 = eval(p, op - 1);
    uint32_t val2 = eval(op + 1, q);
    
    switch (tokens[op].type) {
      case '+': return val1 + val2;
      case '-': return val1 - val2;
      case '*': return val1 * val2;
      case '/': 
        if (val2 == 0) {
          printf("Division by zero!\n");
          assert(0);
        }
        return val1 / val2;
      default: assert(0);
    }
  }
  
  return 0;
}


word_t expr(char *e, bool *success) {
  if (!make_token(e)) {
    *success = false;
    return 0;
  }
  
  *success = true;
  return eval(0, nr_token - 1);
}

