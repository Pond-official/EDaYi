import { ScheduleCellInfo, SectionTimeInfo } from '../../model/JwModels';
import { ScheduleItemRaw, SectionItemRaw } from '../../model/JwRawModels';
import { firstSegment, weeksPart, teacherPart } from './TextSplit';

export function parseScheduleCells(items?: ScheduleItemRaw[]): ScheduleCellInfo[] {
  const list: ScheduleCellInfo[] = [];
  if (items === undefined) {
    return list;
  }
  for (const item of items) {
    if (item.courseName === undefined || item.dayOfWeek === undefined || item.beginSection === undefined) {
      continue;
    }
    const cell: ScheduleCellInfo = new ScheduleCellInfo();
    cell.courseName = item.courseName;
    cell.dayOfWeek = item.dayOfWeek;
    cell.startSection = item.beginSection;
    cell.endSection = item.endSection ?? item.beginSection;
    cell.weekBitmap = item.week ?? '';
    cell.startTime = item.beginTime ?? '';
    cell.endTime = item.endTime ?? '';
    cell.location = firstSegment(item.placeName ?? '', ';');
    cell.colorHex = item.color ?? '#E8F3DB';
    cell.courseSerialNo = item.courseSerialNo ?? '';
    const wt: string = item.weeksAndTeachers ?? '';
    cell.weeksText = weeksPart(wt);
    cell.teacher = teacherPart(wt);
    list.push(cell);
  }
  return list;
}

/**
 * 节次列表：优先取接口 getMySectionList；接口缺失时按课表节次范围推导。
 * 时间文本取该节次第一节课的开始时间（来自课表接口）。
 */
export function parseSections(cells: ScheduleCellInfo[], items?: SectionItemRaw[]): SectionTimeInfo[] {
  const list: SectionTimeInfo[] = [];
  if (items !== undefined && items.length > 0) {
    for (const item of items) {
      const s: SectionTimeInfo = new SectionTimeInfo();
      s.section = item.code ?? 0;
      s.name = item.name ?? '';
      s.timeText = sectionStartTime(cells, s.section);
      list.push(s);
    }
    return list;
  }
  let maxSection: number = 0;
  for (const cell of cells) {
    if (cell.endSection > maxSection) {
      maxSection = cell.endSection;
    }
  }
  for (let i: number = 1; i <= maxSection; i++) {
    const s: SectionTimeInfo = new SectionTimeInfo();
    s.section = i;
    s.name = '第' + i + '节';
    s.timeText = sectionStartTime(cells, i);
    list.push(s);
  }
  return list;
}

export function sectionStartTime(cells: ScheduleCellInfo[], section: number): string {
  for (const cell of cells) {
    if (cell.startSection === section && cell.startTime.length > 0) {
      return cell.startTime;
    }
  }
  return '';
}
