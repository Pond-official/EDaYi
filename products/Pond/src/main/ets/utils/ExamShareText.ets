import { ExamDateUtils } from './ExamDateUtils';
import { FinalExamEntry } from '../model/JwModels';

/**
 * 期末倒计时分享文本（分享与导入共用同一格式）：
 * 行格式 '课程名：YYYY-MM-DD HH:mm（倒计时）'，全文含 '【期末倒计时】' 表头与 '—— 来自 EDaYi（E大医）' 落款。
 * 解析按行提取课程名与考试时间：跳过表头/落款/无效行，时间经 parseExamDate 校验，
 * 同名课程保留靠后一条；正文经其他应用/设备中转后仍可解析（仅要求 '课程名：时间' 行结构）。
 */
export class ExamShareText {
  /** 单条分享行：课程名 + 考试时间 + 倒计时（时间非法显示"时间无效"） */
  static lineOf(courseName: string, examDate: string): string {
    const parsed: Date | null = ExamDateUtils.parseExamDate(examDate);
    const countdown: string = parsed !== null ? ExamDateUtils.countdownTextOf(parsed) : '时间无效';
    return courseName + '：' + examDate + '（' + countdown + '）';
  }

  /** 拼完整分享文本（exams 须为已设时间的条目，调用方按考试时间升序传入） */
  static buildShareText(exams: FinalExamEntry[]): string {
    const lines: string[] = ['【期末倒计时】'];
    for (const entry of exams) {
      lines.push(ExamShareText.lineOf(entry.courseName, entry.examDate));
    }
    lines.push('—— 来自 EDaYi（E大医）');
    return lines.join('\n');
  }

  /** 解析分享文本：返回可识别的考试条目（无有效条目返回空数组） */
  static parse(text: string): FinalExamEntry[] {
    const result: FinalExamEntry[] = [];
    if (text.length === 0) {
      return result;
    }
    const lines: string[] = text.split('\n');
    for (const rawLine of lines) {
      const line: string = rawLine.trim();
      if (line.length === 0 || line.startsWith('【') || line.startsWith('——')) {
        continue;
      }
      const separator: number = line.indexOf('：') >= 0 ? line.indexOf('：') : line.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      const courseName: string = line.substring(0, separator).trim();
      let rest: string = line.substring(separator + 1).trim();
      const fullParen: number = rest.indexOf('（');
      if (fullParen >= 0) {
        rest = rest.substring(0, fullParen).trim();
      }
      const halfParen: number = rest.indexOf('(');
      if (halfParen >= 0) {
        rest = rest.substring(0, halfParen).trim();
      }
      if (courseName.length === 0 || ExamDateUtils.parseExamDate(rest) === null) {
        continue;
      }
      const entry: FinalExamEntry = new FinalExamEntry();
      entry.courseName = courseName;
      entry.examDate = rest;
      const index: number = result.findIndex((e: FinalExamEntry): boolean => e.courseName === courseName);
      if (index >= 0) {
        result[index] = entry;
      } else {
        result.push(entry);
      }
    }
    return result;
  }
}
