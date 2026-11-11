import { describe, it, expect } from '@ohos/hypium';
import { parseStudent } from '../main/ets/jwxt/parsers/StudentParser';
import { StudentProfile } from '../main/ets/model/JwModels';
import { StudentBasicRaw } from '../main/ets/model/JwRawModels';

export default function studentParserTest() {
  describe('StudentParser', () => {
    it('parseStudent_default_when_undefined', 0, () => {
      const profile: StudentProfile = parseStudent(undefined);
      expect(profile.name).assertEqual('');
      expect(profile.studentId).assertEqual('');
    });
    it('parseStudent_maps_fields', 0, () => {
      const basic: StudentBasicRaw = {
        XM: '张三',
        XH: '202512345',
        BJDM_DISPLAY: '临床1班',
        ZYDM_DISPLAY: '临床医学',
        YXDM_DISPLAY: '基础医学院',
        XZNJ_DISPLAY: '2025级'
      };
      const profile: StudentProfile = parseStudent(basic);
      expect(profile.name).assertEqual('张三');
      expect(profile.studentId).assertEqual('202512345');
      expect(profile.className).assertEqual('临床1班');
      expect(profile.majorName).assertEqual('临床医学');
      expect(profile.collegeName).assertEqual('基础医学院');
      expect(profile.grade).assertEqual('2025级');
    });
    it('parseStudent_partial_fields_default_empty', 0, () => {
      const basic: StudentBasicRaw = { XM: '李四' };
      const profile: StudentProfile = parseStudent(basic);
      expect(profile.name).assertEqual('李四');
      expect(profile.studentId).assertEqual('');
      expect(profile.majorName).assertEqual('');
    });
  });
}
