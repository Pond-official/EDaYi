/** 文本切分工具：课表周次/教师/地点字段的分隔解析 */

export function firstSegment(text: string, separator: string): string {
  const idx: number = text.indexOf(separator);
  if (idx < 0) {
    return text;
  }
  return text.substring(0, idx).trim();
}

export function weeksPart(weeksAndTeachers: string): string {
  const idx: number = weeksAndTeachers.indexOf('[讲授]');
  const head: string = idx >= 0 ? weeksAndTeachers.substring(0, idx) : weeksAndTeachers;
  return head;
}

export function teacherPart(weeksAndTeachers: string): string {
  const slash: number = weeksAndTeachers.indexOf('/');
  if (slash < 0) {
    return '';
  }
  let rest: string = weeksAndTeachers.substring(slash + 1);
  const semicolon: number = rest.indexOf(';');
  if (semicolon >= 0) {
    rest = rest.substring(0, semicolon);
  }
  const bracket: number = rest.indexOf('[主讲]');
  if (bracket >= 0) {
    rest = rest.substring(0, bracket);
  }
  return rest.trim();
}
