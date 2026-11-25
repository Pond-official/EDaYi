import { util } from '@kit.ArkTS';
import { FinalExamEntry } from '../model/JwModels';

/** 深链接 scheme（module.json5 中 PondAbility skills 同步声明，改动需两处一致） */
const LINK_SCHEME: string = 'edaiyi';
/** 深链接 host */
const LINK_HOST: string = 'examshare';
/** 深链接前缀（载荷经 d 参数携带） */
const LINK_PREFIX: string = LINK_SCHEME + '://' + LINK_HOST + '?d=';

/**
 * 期末倒计时深链接（edaiyi://examshare?d=…）：
 * 碰一碰/隔空传送发送端以链接类型（HYPERLINK）分享，接收端系统按 Deep Linking 规则
 * 直达已声明该 scheme 的本应用（未安装则提示无可用打开方式），
 * 由 PondAbility onCreate/onNewWant 解析载荷后走与分享面板相同的导入链路；
 * 载荷为逐行「课程名：考试时间」UTF-8 文本的 base64url 编码（较 percent 编码对中文更紧凑）。
 */
export class ExamShareLink {
  /** 是否为本应用期末倒计时深链接 */
  static isExamShareLink(link: string): boolean {
    return link.startsWith(LINK_PREFIX);
  }

  /** 构建深链接（exams 须为已设考试时间的条目，按考试时间升序传入） */
  static build(exams: FinalExamEntry[]): string {
    const encoder: util.TextEncoder = new util.TextEncoder();
    const bytes: Uint8Array = encoder.encodeInto(ExamShareLink.payloadLinesOf(exams));
    const base64: string = new util.Base64Helper().encodeToStringSync(bytes);
    return LINK_PREFIX + base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  /** 深链接载荷文本：逐行「课程名：考试时间」（ExamShareText.parse 可直接解析） */
  static payloadLinesOf(exams: FinalExamEntry[]): string {
    const lines: string[] = [];
    for (const entry of exams) {
      lines.push(entry.courseName + '：' + entry.examDate);
    }
    return lines.join('\n');
  }

  /** 解码深链接载荷文本：非本应用链接或载荷非法返回空串 */
  static payloadOf(link: string): string {
    if (!ExamShareLink.isExamShareLink(link)) {
      return '';
    }
    let base64: string = link.substring(LINK_PREFIX.length).replace(/-/g, '+').replace(/_/g, '/');
    base64 += '='.repeat((4 - base64.length % 4) % 4);
    try {
      const bytes: Uint8Array = new util.Base64Helper().decodeSync(base64);
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(bytes);
    } catch (error) {
      return '';
    }
  }
}
