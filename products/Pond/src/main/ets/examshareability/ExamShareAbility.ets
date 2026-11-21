import { ShareExtensionAbility, UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AppLog } from '../data/AppLog';
import { ExamShareText } from '../utils/ExamShareText';

const TAG: string = 'ExamShareAbility';
const DOMAIN: number = 0x0000;
/** 分享文件最大读取字节数（64KB），超限视为无内容 */
const MAX_SHARE_FILE_BYTES: number = 64 * 1024;

/**
 * 期末倒计时分享目标（Share Kit 分享详情页）：
 * 其他设备/应用把文本或文本文件分享到本应用时，系统分享面板内展示 pages/ExamShareImport 导入页；
 * 本 Ability 解析分享内容中的考试时间条目——文本记录读 content 字段，
 * 文件记录（跨设备/文件形式投递，华为分享、备忘录、文件管理器等）读 uri 指向的 UTF-8 文本文件；
 * session/context/条目经 LocalStorage 传入页面，由用户确认后合并到本机期末倒计时（与主应用「设置考试时间」同一存储）。
 */
export default class ExamShareAbility extends ShareExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    systemShare.getSharedData(want)
      .then((data: systemShare.SharedData) => {
        const records: Array<systemShare.SharedRecord> = data.getRecords();
        const text: string = ExamShareAbility.inlineTextOf(records);
        if (text.length > 0) {
          this.loadImportPage(session, text);
          return;
        }
        const uri: string = ExamShareAbility.fileUriOf(records);
        if (uri.length === 0) {
          AppLog.error(DOMAIN, TAG, 'no text or file in shared records');
          this.loadImportPage(session, '');
          return;
        }
        this.readShareFile(uri)
          .then((fileText: string) => {
            this.loadImportPage(session, fileText);
          })
          .catch((error: BusinessError) => {
            AppLog.error(DOMAIN, TAG, 'read share file failed: %{public}s', JSON.stringify(error));
            this.loadImportPage(session, '');
          });
      })
      .catch((error: BusinessError) => {
        AppLog.error(DOMAIN, TAG, 'getSharedData failed: %{public}s', JSON.stringify(error));
        this.loadImportPage(session, '');
      });
  }

  /** 解析分享文本并加载导入页（session/context/条目经 LocalStorage 传入页面） */
  private loadImportPage(session: UIExtensionContentSession, text: string): void {
    const storage: LocalStorage = new LocalStorage();
    storage.setOrCreate('session', session);
    storage.setOrCreate('context', this.context);
    storage.setOrCreate('exams', ExamShareText.parse(text));
    try {
      session.loadContent('pages/ExamShareImport', storage);
    } catch (error) {
      AppLog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', `${error}`);
    }
  }

  /** 取记录中的内联文本（文本/链接记录的 content 字段），无则返回空串 */
  private static inlineTextOf(records: Array<systemShare.SharedRecord>): string {
    for (const record of records) {
      if (record.content !== undefined && record.content.length > 0) {
        return record.content;
      }
    }
    return '';
  }

  /** 取首个文件记录的 URI（文件形式分享走 uri 字段，content 为空），无则返回空串 */
  private static fileUriOf(records: Array<systemShare.SharedRecord>): string {
    for (const record of records) {
      if (record.uri !== undefined && record.uri.length > 0) {
        return record.uri;
      }
    }
    return '';
  }

  /**
   * 读取分享文件内容：UTF-8 文本，最大 64KB（超限/空文件按无内容处理）。
   * 分享面板对目标应用有文件临时读授权，fileIo 可直接按 URI 打开；失败抛异常由调用方兜底为空文本。
   */
  private async readShareFile(uri: string): Promise<string> {
    const file: fileIo.File = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const stat: fileIo.Stat = await fileIo.stat(file.fd);
      if (stat.size <= 0 || stat.size > MAX_SHARE_FILE_BYTES) {
        AppLog.error(DOMAIN, TAG, 'share file size invalid: %{public}d', `${stat.size}`);
        return '';
      }
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      const readLen: number = await fileIo.read(file.fd, buffer);
      if (readLen <= 0) {
        AppLog.error(DOMAIN, TAG, 'share file read empty');
        return '';
      }
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(new Uint8Array(buffer, 0, readLen));
    } finally {
      fileIo.closeSync(file);
    }
  }
}
