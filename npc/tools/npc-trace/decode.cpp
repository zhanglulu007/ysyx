/***************************************************************************************
* npc-trace - trace.npct 读取层实现 (M0)
***************************************************************************************/
#include "trace_file.h"

#include <cstring>

namespace npctrace {

bool TraceFile::open(const std::string& path, std::string* err) {
  close();
  path_ = path;

  fp = fopen(path.c_str(), "rb");
  if (fp == nullptr) {
    *err = "cannot open '" + path + "'";
    return false;
  }

  if (fread(&header, sizeof(header), 1, fp) != 1) {
    *err = "'" + path + "' is too small to contain a trace header";
    close();
    return false;
  }

  if (memcmp(header.magic, TRACE_MAGIC_STR, TRACE_MAGIC_LEN) != 0) {
    *err = "'" + path + "' is not a trace.npct file (bad magic)";
    close();
    return false;
  }
  if (header.version != TRACE_VERSION) {
    *err = "unsupported trace version " + std::to_string(header.version) +
           " (this tool supports " + std::to_string(TRACE_VERSION) + ")";
    close();
    return false;
  }
  if (header.endian != TRACE_ENDIAN_ID) {
    *err = "trace file endianness mismatch (file written on a different-endian host?)";
    close();
    return false;
  }
  if (header.header_size != sizeof(TraceFileHeader)) {
    *err = "trace header size mismatch: file=" + std::to_string(header.header_size) +
           " tool=" + std::to_string(sizeof(TraceFileHeader));
    close();
    return false;
  }

  if (header.meta_size > 0) {
    if (fseek(fp, static_cast<long>(header.meta_off), SEEK_SET) != 0) {
      *err = "cannot seek to meta section";
      close();
      return false;
    }
    meta_raw.resize(header.meta_size);
    if (fread(meta_raw.data(), 1, header.meta_size, fp) != header.meta_size) {
      *err = "short read on meta section";
      close();
      return false;
    }
    meta_json.assign(reinterpret_cast<const char*>(meta_raw.data()),
                     meta_raw.size());
  }

  return true;
}

void TraceFile::close() {
  if (fp != nullptr) {
    fclose(fp);
    fp = nullptr;
  }
  meta_json.clear();
  meta_raw.clear();
}

std::string format_header(const TraceFileHeader& h) {
  char buf[32];
  std::string s;
  s += "file:          NPCTRACE\n";
  s += "version:       " + std::to_string(h.version) + "\n";
  snprintf(buf, sizeof(buf), "0x%08x", h.endian);
  s += std::string("endian:        ") + buf + "\n";
  s += "header_size:   " + std::to_string(h.header_size) + "\n";
  snprintf(buf, sizeof(buf), "0x%08x", h.config_hash);
  s += std::string("config_hash:   ") + buf + "\n";
  s += "event_count:   " + std::to_string(h.event_count) + "\n";
  s += "itrace_count:  " + std::to_string(h.itrace_count) + "\n";
  s += "index_interval:" + std::to_string(h.index_interval) + "\n";
  s += "sections:\n";
  auto row = [&s](const char* name, uint64_t off, uint64_t size) {
    s += "  " + std::string(name);
    for (size_t i = strlen(name); i < 10; i++) s += ' ';
    s += "off=" + std::to_string(off) + " size=" + std::to_string(size) + "\n";
  };
  row("meta",    h.meta_off,    h.meta_size);
  row("itrace",  h.itrace_off,  h.itrace_size);
  row("events",  h.events_off,  h.events_size);
  row("index",   h.index_off,   h.index_size);
  row("dict",    h.dict_off,    h.dict_size);
  row("summary", h.summary_off, h.summary_size);
  return s;
}

std::string meta_field(const std::string& json, const std::string& key) {
  // 极简: 找 "\"key\"" 之后的第一个字符串值
  const std::string needle = "\"" + key + "\"";
  size_t pos = json.find(needle);
  if (pos == std::string::npos) return "";
  pos = json.find(':', pos + needle.size());
  if (pos == std::string::npos) return "";
  pos++;
  while (pos < json.size() &&
         (json[pos] == ' ' || json[pos] == '\t' || json[pos] == '\n')) pos++;
  if (pos >= json.size()) return "";
  if (json[pos] == '"') {
    size_t end = json.find('"', pos + 1);
    if (end == std::string::npos) return "";
    return json.substr(pos + 1, end - pos - 1);
  }
  size_t end = pos;
  while (end < json.size() && json[end] != ',' && json[end] != '\n' &&
         json[end] != '}') end++;
  return json.substr(pos, end - pos);
}

bool read_summary(const std::string& path, const TraceFileHeader& h,
                  TraceSummary* out, std::string* err) {
  if (h.summary_size < sizeof(TraceSummary)) {
    *err = "trace file has no summary section";
    return false;
  }
  FILE* fp = fopen(path.c_str(), "rb");
  if (fp == nullptr) { *err = "cannot open '" + path + "'"; return false; }
  if (fseek(fp, static_cast<long>(h.summary_off), SEEK_SET) != 0 ||
      fread(out, sizeof(TraceSummary), 1, fp) != 1) {
    *err = "cannot read summary section";
    fclose(fp);
    return false;
  }
  fclose(fp);
  return true;
}

// ── ITraceReader ───────────────────────────────────────────────────────────
bool ITraceReader::open(const std::string& path, const TraceFileHeader& h,
                        std::string* err) {
  total_ = h.itrace_count;
  read_ = 0;
  acc_pc_ = acc_cycle_ = acc_commit_ = 0;
  started_ = false;
  if (total_ == 0) return true;
  fp_ = fopen(path.c_str(), "rb");
  if (fp_ == nullptr) { *err = "cannot open '" + path + "' for itrace"; return false; }
  if (fseek(fp_, static_cast<long>(h.itrace_off), SEEK_SET) != 0) {
    *err = "cannot seek to itrace section";
    return false;
  }
  return true;
}

bool ITraceReader::next(ITraceEntry* out) {
  if (fp_ == nullptr || read_ >= total_) return false;

  ITraceRecord rec{};
  if (fread(&rec, sizeof(rec), 1, fp_) != 1) {
    // 文件截断: 视为流结束(已读到的部分仍有效)
    total_ = read_;
    return false;
  }
  read_++;

  if (!started_) {
    acc_pc_ = rec.pc_delta;
    acc_cycle_ = rec.cycle_delta;
    acc_commit_ = rec.commit_delta;
    started_ = true;
  } else {
    acc_pc_ += rec.pc_delta;
    acc_cycle_ += rec.cycle_delta;
    acc_commit_ += rec.commit_delta;
  }
  out->pc = acc_pc_;
  out->inst = rec.inst;
  out->cycle = acc_cycle_;
  out->commit_id = acc_commit_;
  return true;
}

// ── EventReader ────────────────────────────────────────────────────────────
bool EventReader::open(const std::string& path, const TraceFileHeader& h,
                       std::string* err) {
  total_ = h.event_count;
  read_ = 0;
  if (total_ == 0) return true;
  fp_ = fopen(path.c_str(), "rb");
  if (fp_ == nullptr) { *err = "cannot open '" + path + "' for events"; return false; }
  if (fseek(fp_, static_cast<long>(h.events_off), SEEK_SET) != 0) {
    *err = "cannot seek to events section";
    return false;
  }
  return true;
}

bool EventReader::next(TraceEvent* out) {
  if (fp_ == nullptr || read_ >= total_) return false;
  if (fread(out, sizeof(TraceEvent), 1, fp_) != 1) {
    total_ = read_;
    return false;
  }
  read_++;
  return true;
}

}  // namespace npctrace
