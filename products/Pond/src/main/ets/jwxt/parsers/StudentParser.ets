import { StudentProfile } from '../../model/JwModels';
import { StudentBasicRaw } from '../../model/JwRawModels';

export function parseStudent(basic?: StudentBasicRaw): StudentProfile {
  const p: StudentProfile = new StudentProfile();
  if (basic !== undefined) {
    p.name = basic.XM ?? '';
    p.studentId = basic.XH ?? '';
    p.className = basic.BJDM_DISPLAY ?? '';
    p.majorName = basic.ZYDM_DISPLAY ?? '';
    p.collegeName = basic.YXDM_DISPLAY ?? '';
    p.grade = basic.XZNJ_DISPLAY ?? '';
  }
  return p;
}
