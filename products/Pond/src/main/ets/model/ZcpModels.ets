/**
 * 综合测评（综评，xgfw.dmu.edu.cn/xsfw/sys/zhcptybbapp）数据模型。
 * 字段依据接口包 01-综评成绩 的逆向说明（EMAP 框架 .do 接口，data 表单体为 URL 编码 JSON）。
 * 综评数据保留在内存（AppStorage）；标准隐私模式下另做 filesDir 本地缓存，
 * 限制/严格隐私模式收紧、清理缓存与退出登录时立即清除；标准模式退出登录保留离线数据。
 */

/** 测评批次上下文（getPageInitParams → data.ZHCP_SZ + 页面开关） */
export class ZcpContext {
  /** 测评学年（CPXN），如 '2025' */
  cpxn: string = '';
  /** 测评学期（CPXQ），如 '2' */
  cpxq: string = '';
  /** 批次代码（PCDM），后续所有查询的必需入参 */
  pcdm: string = '';
  /** 学年学期显示文本（CPXN_DISPLAY + CPXQ_DISPLAY） */
  termDisplay: string = '';
  /** 批次名称（ZBKMC），如 '25-26学年下学期（春季）' */
  batchName: string = '';
  /** 参评对象（DXMC） */
  targetName: string = '';
  /** 学生填写时间窗（XSKSSJ ~ XSJSSJ），任一为空则为空串 */
  fillWindow: string = '';
  /** 辅导员审核时间窗（XZKSSJ ~ XZJSSJ），任一为空则为空串 */
  auditWindow: string = '';
  /** 是否在学生测评时间内（IS_XSCPSJ，服务端开关，非客户端日期比较） */
  windowOpen: boolean = false;
}

/** 个人测评状态机（getEvaluationProcess → data.PERSONAL_RESULT） */
export class ZcpProcessState {
  /** STATE：1 未提交 / 2 待辅导员审核 / 3 已退回 / 4 已通过；0 表示未取到 */
  state: number = 0;
  /** 服务端状态文案（SHZT_DISPLAY），展示时优先于 STATE 兜底映射 */
  statusText: string = '';
  /** 退回原因（THYY，STATE=3 时可能有值） */
  rejectReason: string = '';

  /** 状态展示文本：SHZT_DISPLAY 优先，缺失时按 STATE 兜底映射 */
  statusDisplay(): string {
    if (this.statusText.length > 0) {
      return this.statusText;
    }
    if (this.state === 1) {
      return '未提交';
    }
    if (this.state === 2) {
      return '待辅导员审核';
    }
    if (this.state === 3) {
      return '已退回';
    }
    if (this.state === 4) {
      return '已通过';
    }
    return '状态未知';
  }
}

/** 测评指标（getAllZbList / get23zbScore 条目，扁平数组靠 LS 父指针组树，实测最深 3 层） */
export class ZcpIndicator {
  /** 指标代码（查明细/得分的入参） */
  zbdm: string = '';
  /** 指标名称 */
  name: string = '';
  /** 计算项 / 成绩分 / 评分项 / 固定值 / 附加项 */
  category: string = '';
  /** 父指标代码（空 = 顶层） */
  parentCode: string = '';
  /** 层级：1 一级 / 2 二级 / 3 三级 */
  level: number = 0;
  /** 同层排序（PX） */
  order: number = 0;
  /** 得分（FS，计算项在此为空） */
  scoreText: string = '';
  /** 占比 %（BL，仅一级有意义） */
  ratioPercent: string = '';
  /** 分值上限（ZDZ，附加项为 999 兜底值，不可当分母） */
  capText: string = '';
  /** 固定得分（GDFS） */
  fixedScore: string = '';
  /** 附加分「已获得」（FJFTGFS） */
  extraGained: string = '';
  /** 附加分「已申请」（FJFFS） */
  extraApplied: string = '';
  /** 指标说明（ZBSM，多数为空） */
  note: string = '';
  /** 子指标（组树后填充） */
  children: ZcpIndicator[] = [];
}

/** 附加分明细条目（getZbFjfDetail → data[].FJFMX[]） */
export class ZcpDetailItem {
  /** 加项名称（JXMC） */
  name: string = '';
  /** 项分值（MXFS） */
  score: string = '';
  /** 附加分类（FJFMC） */
  category: string = '';
  /** 说明（MXSM） */
  note: string = '';
  /** 审核状态（SHZT_DISPLAY） */
  status: string = '';
  /** 计分说明（FJFSM） */
  rule: string = '';
}

/** 综评查询结果（一次 loadAll 的聚合；内存态 + 标准隐私模式下的 filesDir 本地缓存） */
export class ZcpResult {
  /** 批次上下文（ZHCP_SZ 缺失时为默认值，hasContext=false） */
  context: ZcpContext = new ZcpContext();
  /** 是否取到有效批次上下文（无 PCDM 时指标/状态不可查） */
  hasContext: boolean = false;
  /** 个人测评状态 */
  process: ZcpProcessState = new ZcpProcessState();
  /** 指标树（根节点数组，子节点在 children 内） */
  indicators: ZcpIndicator[] = [];
  /** 是否来自本地临时缓存（在线刷新成功后替换为 false） */
  fromCache: boolean = false;
}
