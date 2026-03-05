#include <am.h>
#include <klib.h>
#include <klib-macros.h>
#include <stdarg.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)

/**
 * out_char - 输出一个字符到缓冲区
 * @out: 输出缓冲区指针的指针
 * @c: 要输出的字符
 * 
 * 将字符c写入*out指向的位置，并将*out指针前进一位
 */
static void out_char(char **out, char c) {
  **out = c;
  (*out)++;
}

/**
 * out_str - 输出字符串到缓冲区
 * @out: 输出缓冲区指针的指针
 * @s: 要输出的字符串
 * 
 * 将字符串s写入*out指向的位置，并更新*out指针
 * 返回写入的字符数
 */
static int out_str(char **out, const char *s) {
  int count = 0;
  while (*s) {
    out_char(out, *s++);
    count++;
  }
  return count;
}

/**
 * out_int - 输出整数到缓冲区
 * @out: 输出缓冲区指针的指针
 * @num: 要输出的整数
 * 
 * 将整数num转换为字符串并写入*out指向的位置
 * 返回写入的字符数
 */
static int out_int(char **out, int num) {
  char buf[32];  // 足够存储32位整数的字符串表示
  int i = 0;
  int count = 0;
  int is_negative = 0;
  
  // 处理负数
  if (num < 0) {
    is_negative = 1;
    num = -num;
  }
  
  // 特殊情况：0
  if (num == 0) {
    out_char(out, '0');
    return 1;
  }
  
  // 将数字转换为字符串（逆序）
  while (num > 0) {
    buf[i++] = '0' + (num % 10);
    num /= 10;
  }
  
  // 添加负号
  if (is_negative) {
    out_char(out, '-');
    count++;
  }
  
  // 逆序输出数字
  while (i > 0) {
    out_char(out, buf[--i]);
    count++;
  }
  
  return count;
}

/**
 * vsprintf - 格式化输出到字符串（使用va_list）
 * @out: 输出缓冲区
 * @fmt: 格式字符串
 * @ap: 可变参数列表
 * 
 * 根据格式字符串fmt和参数列表ap，将格式化后的字符串写入out
 * 返回写入的字符数（不包括结尾的'\0'）
 * 
 * 支持的格式：
 *   %s - 字符串
 *   %d - 十进制整数
 *   %% - 百分号字符
 */
int vsprintf(char *out, const char *fmt, va_list ap) {
  char *out_start = out;  // 保存起始位置
  
  while (*fmt) {
    if (*fmt == '%') {
      fmt++;  // 跳过'%'
      
      switch (*fmt) {
        case 's': {
          // 字符串格式
          const char *s = va_arg(ap, const char *);
          out_str(&out, s);
          break;
        }
        
        case 'd': {
          // 十进制整数格式
          int num = va_arg(ap, int);
          out_int(&out, num);
          break;
        }
        
        case '%': {
          // 百分号字符
          out_char(&out, '%');
          break;
        }
        
        default:
          // 不支持的格式，直接输出
          out_char(&out, '%');
          out_char(&out, *fmt);
          break;
      }
      fmt++;
    } else {
      // 普通字符，直接输出
      out_char(&out, *fmt++);
    }
  }
  
  // 添加字符串结束符
  *out = '\0';
  
  // 返回写入的字符数（不包括'\0'）
  return out - out_start;
}

/**
 * sprintf - 格式化输出到字符串
 * @out: 输出缓冲区
 * @fmt: 格式字符串
 * @...: 可变参数
 * 
 * 根据格式字符串fmt和后续参数，将格式化后的字符串写入out
 * 返回写入的字符数（不包括结尾的'\0'）
 * 
 * 示例：
 *   sprintf(buf, "%s", "Hello");           // buf = "Hello"
 *   sprintf(buf, "%d + %d = %d", 1, 2, 3); // buf = "1 + 2 = 3"
 */
int sprintf(char *out, const char *fmt, ...) {
  va_list ap;
  int ret;
  
  // 初始化可变参数列表
  va_start(ap, fmt);
  
  // 调用vsprintf完成实际工作
  ret = vsprintf(out, fmt, ap);
  
  // 清理可变参数列表
  va_end(ap);
  
  return ret;
}

int printf(const char *fmt, ...) {
  panic("Not implemented");
}

int snprintf(char *out, size_t n, const char *fmt, ...) {
  panic("Not implemented");
}

int vsnprintf(char *out, size_t n, const char *fmt, va_list ap) {
  panic("Not implemented");
}

#endif
