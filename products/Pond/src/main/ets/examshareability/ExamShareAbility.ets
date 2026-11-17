import { ShareExtensionAbility, UIExtensionContentSession, Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppLog } from '../data/AppLog';
import { ExamShareText } from '../utils/ExamShareText';

const TAG: string = 'ExamShareAbility';
const DOMAIN: number = 0x0000;

/**
 * 期末倒计时分享目标（Share Kit 分享详情页）：
 * 其他设备/应用把文本分享到本应用时，系统分享面板内展示 pages/ExamShareImport 导入页；
 * 本 Ability 解析分享文本中的考试时间条目，session/context/条目经 LocalStorage 传入页面，
 * 由用户确认后合并到本机期末倒计时（与主应用「设置考试时间」同一存储）。
 */
export default class ExamShareAbility extends ShareExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    systemShare.getSharedData(want)
      .then((data: systemShare.SharedData) => {
        let text: string = '';
        const records: Array<systemShare.SharedRecord> = data.getRecords();
        for (const record of records) {
          if (record.content !== undefined && record.content.length > 0) {
            text = record.content;
            break;
          }
        }
        this.loadImportPage(session, text);
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
}
