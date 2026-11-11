import { describe, it, expect } from '@ohos/hypium';
import { parseScheduleCells, filterCurrentAndNextWeek, parseSections, sectionStartTime } from '../main/ets/jwxt/parsers/ScheduleParser';
import { ScheduleCellInfo, SectionTimeInfo } from '../main/ets/model/JwModels';
import { ScheduleItemRaw, SectionItemRaw } from '../main/ets/model/JwRawModels';

function buildCell(bitmap: string): ScheduleCellInfo {
  const cell: ScheduleCellInfo = new ScheduleCellInfo();
  cell.courseName = '高等数学';
  cell.dayOfWeek = 1;
  cell.startSection = 1;
  cell.endSection = 2;
  cell.weekBitmap = bitmap;
  cell.startTime = '08:00';
  return cell;
}

export default function scheduleParserTest() {
  describe('ScheduleParser', () => {
    it('parseScheduleCells_empty_when_undefined', 0, () => {
      const result: ScheduleCellInfo[] = parseScheduleCells(undefined);
      expect(result.length).assertEqual(0);
    });
    it('parseScheduleCells_skips_rows_missing_required_fields', 0, () => {
      const noName: ScheduleItemRaw = { dayOfWeek: 1, beginSection: 1 };
      const noDay: ScheduleItemRaw = { courseName: '体育', beginSection: 3 };
      const result: ScheduleCellInfo[] = parseScheduleCells([noName, noDay]);
      expect(result.length).assertEqual(0);
    });
    it('parseScheduleCells_maps_fields_and_splits_text', 0, () => {
      const item: ScheduleItemRaw = {
        courseName: '大学英语',
        dayOfWeek: 3,
        beginSection: 5,
        endSection: 6,
        week: '1111111111111111',
        beginTime: '14:00',
        endTime: '15:40',
        placeName: '外语楼302;外语楼303',
        weeksAndTeachers: '1-16周[讲授]/王五[主讲]',
        color: '#E3F2FD',
        courseSerialNo: 'C001'
      };
      const result: ScheduleCellInfo[] = parseScheduleCells([item]);
      expect(result.length).assertEqual(1);
      expect(result[0].courseName).assertEqual('大学英语');
      expect(result[0].location).assertEqual('外语楼302');
      expect(result[0].weeksText).assertEqual('1-16周');
      expect(result[0].teacher).assertEqual('王五');
      expect(result[0].colorHex).assertEqual('#E3F2FD');
      expect(result[0].courseSerialNo).assertEqual('C001');
    });
    it('parseScheduleCells_defaults_end_section_and_color', 0, () => {
      const item: ScheduleItemRaw = { courseName: '体育', dayOfWeek: 5, beginSection: 7 };
      const result: ScheduleCellInfo[] = parseScheduleCells([item]);
      expect(result.length).assertEqual(1);
      expect(result[0].endSection).assertEqual(7);
      expect(result[0].colorHex).assertEqual('#E8F3DB');
    });
    it('filterCurrentAndNextWeek_keeps_all_when_week_unknown', 0, () => {
      const cells: ScheduleCellInfo[] = [buildCell(''), buildCell('')];
      const result: ScheduleCellInfo[] = filterCurrentAndNextWeek(cells, 0);
      expect(result.length).assertEqual(2);
    });
    it('filterCurrentAndNextWeek_filters_by_bitmap', 0, () => {
      const week1: ScheduleCellInfo = buildCell('1000000000000000');
      const week9: ScheduleCellInfo = buildCell('0000000010000000');
      const result: ScheduleCellInfo[] = filterCurrentAndNextWeek([week1, week9], 8);
      expect(result.length).assertEqual(1);
      expect(result[0]).assertEqual(week9);
    });
    it('filterCurrentAndNextWeek_keeps_next_week_too', 0, () => {
      const week9: ScheduleCellInfo = buildCell('0000000010000000');
      const result: ScheduleCellInfo[] = filterCurrentAndNextWeek([week9], 8);
      expect(result.length).assertEqual(1);
    });
    it('parseSections_prefers_api_list', 0, () => {
      const cells: ScheduleCellInfo[] = [buildCell('1')];
      const items: SectionItemRaw[] = [
        { code: 1, name: '第一节' },
        { code: 2, name: '第二节' }
      ];
      const result: SectionTimeInfo[] = parseSections(cells, items);
      expect(result.length).assertEqual(2);
      expect(result[0].name).assertEqual('第一节');
      expect(result[0].timeText).assertEqual('08:00');
      expect(result[1].timeText).assertEqual('');
    });
    it('parseSections_derives_from_cells_when_api_missing', 0, () => {
      const cells: ScheduleCellInfo[] = [buildCell('1')];
      const result: SectionTimeInfo[] = parseSections(cells, undefined);
      expect(result.length).assertEqual(2);
      expect(result[0].section).assertEqual(1);
      expect(result[0].name).assertEqual('第1节');
      expect(result[0].timeText).assertEqual('08:00');
    });
    it('parseSections_empty_when_no_cells', 0, () => {
      const result: SectionTimeInfo[] = parseSections([], undefined);
      expect(result.length).assertEqual(0);
    });
    it('sectionStartTime_returns_first_match', 0, () => {
      const a: ScheduleCellInfo = buildCell('1');
      const b: ScheduleCellInfo = buildCell('1');
      b.startSection = 1;
      b.startTime = '08:30';
      const result: string = sectionStartTime([a, b], 1);
      expect(result).assertEqual('08:00');
    });
    it('sectionStartTime_empty_when_no_match', 0, () => {
      const result: string = sectionStartTime([buildCell('1')], 9);
      expect(result).assertEqual('');
    });
  });
}
