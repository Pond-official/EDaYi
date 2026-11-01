/**
 * 选课系统（jwxk.dmu.edu.cn）数据模型。
 * 字段依据接口包对 jwxk 接口的逆向说明（2026-09-24 实测抓包 + 登录页前端源码还原）。
 */

/** 图形验证码（POST /auth/captcha） */
export class CaptchaData {
  /** 1=普通图形验证码；2=交互式验证码（点击/滑块，需人工完成） */
  type: number = 1;
  /** 内联 Base64 Data URI（data:image/png;base64,...），不是图片 URL */
  captcha: string = '';
  /** 与验证码成对下发，登录时原样提交 */
  uuid: string = '';
}

/** 选课轮次（elective/user → student.electiveBatchList 条目） */
export class SelectionBatch {
  /** 轮次标识，提交选课时的 batchId */
  code: string = '';
  name: string = '';
  /** '1' 表示该轮次可选 */
  canSelect: string = '';
  /** 选课开始时间 */
  beginTime: string = '';
  /** 选课结束时间 */
  endTime: string = '';
  typeName: string = '';
  tacticName: string = '';
  weekRange: string = '';
}

/** 可选课程（elective/clazz/list 行内关键字段） */
export class SelectionCourse {
  /** 教学班 ID，提交选课时的 clazzId */
  jxbId: string = '';
  /** 服务端下发的校验值，提交时原样转发，无需加密 */
  secretVal: string = '';
  courseCode: string = '';
  courseName: string = '';
  /** 课序号（班号） */
  classNo: string = '';
  teacher: string = '';
  credit: string = '';
  /** 课容量（KRL） */
  capacity: number = 0;
  /** 已选人数（YXRS） */
  selectedCount: number = 0;
  /** 拼接好的上课时间地点文本，形如 `7-14周/星期二/9-10节/D202` */
  timeText: string = '';
}

/** 课程列表查询结果 */
export class CourseListResult {
  total: number = 0;
  courses: SelectionCourse[] = [];
}

/** 已选课程（elective/select 条目） */
export class SelectedCourse {
  jxbId: string = '';
  courseName: string = '';
  teacher: string = '';
  credit: string = '';
  /** 实测 99=正常 */
  selectStatus: number = 0;
  /** 操作时间 */
  operateTime: string = '';
}

/** 提交选课结果（clazz/add 为异步入队，200 仅代表已进入选课队列） */
export class SelectionOutcome {
  success: boolean = false;
  message: string = '';
}

/** 已保存的登录凭据（存于系统关键资产存储，仅本机） */
export class SelectionCredentials {
  loginName: string = '';
  password: string = '';
}
