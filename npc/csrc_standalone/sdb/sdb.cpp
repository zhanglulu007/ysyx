/***************************************************************************************
* NPC Simple Debugger (sdb)
* 简易调试器主逻辑
***************************************************************************************/

#include "sdb.h"
#include <readline/readline.h>
#include <readline/history.h>

static int is_batch_mode = false;

void init_regex();
void init_wp_pool();

/* 使用readline库提供更灵活的输入 */
static char* rl_gets() {
  static char *line_read = NULL;

  if (line_read) {
    free(line_read);
    line_read = NULL;
  }

  line_read = readline("(npc) ");

  if (line_read && *line_read) {
    add_history(line_read);
  }

  return line_read;
}

// c命令 - 继续执行
static int cmd_c(char *args) {
  cpu_exec(-1);
  return 0;
}

// q命令 - 退出
static int cmd_q(char *args) {
  return -1;
}

// si命令 - 单步执行
static int cmd_si(char *args) {
  int n = 1;  // 默认执行1条指令
  
  if (args != NULL) {
    sscanf(args, "%d", &n);
  }
  
  cpu_exec(n);
  
  return 0;
}

// info命令 - 打印寄存器或监视点信息
static int cmd_info(char *args) {
  if (args == NULL) {
    printf("Usage: info r - print register info\n");
    printf("       info w - print watchpoint info\n");
    return 0;
  }
  
  if (strcmp(args, "r") == 0) {
    npc_reg_display();
  } 
  else if (strcmp(args, "w") == 0) {
    display_watchpoints();
  }
  else {
    printf("Unknown subcommand: %s\n", args);
  }
  
  return 0;
}

// x命令 - 扫描内存
static int cmd_x(char *args) {
  if (args == NULL) {
    printf("Usage: x N EXPR\n");
    return 0;
  }
  
  int n;
  char expr_str[256];
  
  if (sscanf(args, "%d %s", &n, expr_str) != 2) {
    printf("Invalid format. Usage: x N EXPR\n");
    return 0;
  }
  
  // 求值表达式
  bool success = false;
  word_t addr = expr(expr_str, &success);
  
  if (!success) {
    printf("Invalid expression\n");
    return 0;
  }
  
  // 打印内存内容
  for (int i = 0; i < n; i++) {
    if (i % 4 == 0) {
      printf("0x%08x: ", addr + i * 4);
    }
    
    word_t data = pmem_read_word(addr + i * 4);
    printf("0x%08x  ", data);
    
    if (i % 4 == 3) printf("\n");
  }
  
  if (n % 4 != 0) printf("\n");
  
  return 0;
}

// p命令 - 表达式求值
static int cmd_p(char *args) {
  if (args == NULL) {
    printf("Usage: p EXPR\n");
    return 0;
  }
  
  bool success = false;
  word_t result = expr(args, &success);
  
  if (success) {
    printf("%u (0x%x)\n", result, result);
  } else {
    printf("Invalid expression\n");
  }
  
  return 0;
}

// w命令 - 设置监视点
static int cmd_w(char *args) {
  if (args == NULL) {
    printf("Usage: w EXPR\n");
    return 0;
  }
  
  create_watchpoint(args);
  
  return 0;
}

// d命令 - 删除监视点
static int cmd_d(char *args) {
  if (args == NULL) {
    printf("Usage: d N\n");
    return 0;
  }
  
  int no;
  sscanf(args, "%d", &no);
  
  if (delete_watchpoint(no)) {
    printf("Watchpoint %d deleted\n", no);
  } else {
    printf("Watchpoint %d not found\n", no);
  }
  
  return 0;
}

static int cmd_help(char *args);

static struct {
  const char *name;
  const char *description;
  int (*handler) (char *);
} cmd_table [] = {
  { "help", "Display information about all supported commands", cmd_help },
  { "c", "Continue the execution of the program", cmd_c },
  { "q", "Exit NPC", cmd_q },
  { "si", "Step [N] instructions", cmd_si },
  { "info", "Print register or watchpoint info", cmd_info },
  { "x", "Examine memory: x N EXPR", cmd_x },
  { "p", "Evaluate expression: p EXPR", cmd_p },
  { "w", "Set watchpoint: w EXPR", cmd_w },
  { "d", "Delete watchpoint: d N", cmd_d },
};

#define NR_CMD (sizeof(cmd_table) / sizeof(cmd_table[0]))

static int cmd_help(char *args) {
  char *arg = strtok(NULL, " ");
  int i;

  if (arg == NULL) {
    for (i = 0; i < NR_CMD; i ++) {
      printf("%s - %s\n", cmd_table[i].name, cmd_table[i].description);
    }
  }
  else {
    for (i = 0; i < NR_CMD; i ++) {
      if (strcmp(arg, cmd_table[i].name) == 0) {
        printf("%s - %s\n", cmd_table[i].name, cmd_table[i].description);
        return 0;
      }
    }
    printf("Unknown command '%s'\n", arg);
  }
  return 0;
}

void sdb_set_batch_mode() {
  is_batch_mode = true;
}

void sdb_mainloop() {
  if (is_batch_mode) {
    cmd_c(NULL);
    return;
  }

  for (char *str; (str = rl_gets()) != NULL; ) {
    char *str_end = str + strlen(str);

    char *cmd = strtok(str, " ");
    if (cmd == NULL) { continue; }

    char *args = cmd + strlen(cmd) + 1;
    if (args >= str_end) {
      args = NULL;
    }

    int i;
    for (i = 0; i < NR_CMD; i ++) {
      if (strcmp(cmd, cmd_table[i].name) == 0) {
        if (cmd_table[i].handler(args) < 0) { return; }
        break;
      }
    }

    if (i == NR_CMD) { printf("Unknown command '%s'\n", cmd); }
  }
}

void init_sdb() {
  init_regex();
  init_wp_pool();
}
