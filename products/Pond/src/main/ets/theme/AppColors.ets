/**
 * 全局代码色板（任务 10 颜色收口）。
 * 视图层/页面层/卡片层的硬编码 hex 统一收口到本文件具名常量，
 * 不改任何颜色值本身；同一语义值已合并（如及格/通过状态底色共用 PASS_BG）。
 * 约束：不使用 $r('app.color.x')——ZcpRadarChart 的 Canvas 绘制与卡片侧取不到资源解析值，
 * 代码常量为唯一可行方案。资源 color.json 中另有 5 个命名色（页面背景等），与本文件互不替代。
 */

/** 综评状态-已通过 / 附加项得分 文字（绿） */
export const PASS_TEXT: string = '#0FA958';
/** 综评状态-已退回 / 登录失败警告 文字（红） */
export const REJECT_TEXT: string = '#E84026';
/** 综评状态-审核中 / 选课批次待发布 文字（橙） */
export const REVIEW_TEXT: string = '#E88A00';
/** 及格/通过 状态底色（综评已通过、成绩优秀、考核-考试）（浅绿） */
export const PASS_BG: string = '#E8F5E9';
/** 不及格/退回 状态底色（综评已退回）（浅红） */
export const REJECT_BG: string = '#FDECEA';
/** 审核中/中等/限选 状态底色（浅橙） */
export const REVIEW_BG: string = '#FFF3E0';
/** 中性状态底色（综评状态默认底）（浅灰） */
export const NEUTRAL_BG: string = '#F1F1F1';
/** 成绩等级-优秀 文字（深绿） */
export const GRADE_EXCELLENT_TEXT: string = '#2E7D32';
/** 成绩等级-良好 / 课程性质-必修 文字（蓝） */
export const GRADE_GOOD_TEXT: string = '#1565C0';
/** 成绩等级-中等 / 课程性质-限选 文字（橙棕） */
export const GRADE_MEDIUM_TEXT: string = '#B26A00';
/** 成绩/标签默认文字（其他 灰） */
export const GRADE_DEFAULT_TEXT: string = '#616161';
/** 成绩等级-良好 / 课程性质-必修 底色（浅蓝） */
export const GRADE_GOOD_BG: string = '#E3F2FD';
/** 成绩默认底色（浅灰） */
export const GRADE_DEFAULT_BG: string = '#EEEEEE';
/** 标签默认底色（浅灰） */
export const TAG_DEFAULT_BG: string = '#F5F5F5';
/** 考核方式-考查 文字（紫） */
export const GRADE_INSPECT_TEXT: string = '#6A1B9A';
/** 考核方式-考查 底色（浅紫） */
export const GRADE_INSPECT_BG: string = '#F3E5F5';
/** 深色正文（课表单元格课程名） */
export const TEXT_DARK: string = '#333333';
/** 中灰正文（课表单元格时间/地点） */
export const TEXT_MEDIUM: string = '#555555';
/** 首页底图发光-中心色 */
export const GLOW_CENTER_COLOR: string = '#99FFFFFF';
/** 首页底图发光-中间色 */
export const GLOW_MID_COLOR: string = '#40FFFFFF';
/** 首页底图发光-边缘色 */
export const GLOW_EDGE_COLOR: string = '#2EFFFFFF';
/** 卡片周次选中 文字/底色（系统蓝） */
export const WIDGET_SELECTED_COLOR: string = '#007DFF';
/** 课表单元格默认底色（浅绿，服务端未下发颜色时兜底） */
export const COURSE_CELL_DEFAULT_BG: string = '#E8F3DB';
