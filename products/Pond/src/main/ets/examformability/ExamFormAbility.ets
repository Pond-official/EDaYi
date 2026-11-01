import { FormExtensionAbility, formBindingData, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardDataStore } from '../data/CardDataStore';

/**
 * 期末倒计时服务卡片生命周期：
 * onAddForm 登记卡片并下发按考试时间从近到远的倒计时数据；
 * onUpdateForm 由系统周期触发刷新（倒计时天数随日期自然递减）；
 * onRemoveForm 清理已删除卡片的登记记录。
 */
export default class ExamFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    let formId: string = '';
    const params: Record<string, Object> | undefined = want.parameters;
    if (params !== undefined) {
      const id: Object | undefined = params[formInfo.FormParam.IDENTITY_KEY];
      if (typeof id === 'string') {
        formId = id;
      }
    }
    hilog.info(0x0000, 'ExamForm', 'onAddForm formId:%{public}s', formId);
    CardDataStore.addExamFormEntry(this.context, formId);
    return CardDataStore.buildExamBindingData(this.context);
  }

  onUpdateForm(formId: string): void {
    hilog.info(0x0000, 'ExamForm', 'onUpdateForm formId:%{public}s', formId);
    CardDataStore.refreshExamCards(this.context);
  }

  onRemoveForm(formId: string): void {
    hilog.info(0x0000, 'ExamForm', 'onRemoveForm formId:%{public}s', formId);
    CardDataStore.removeExamFormEntry(this.context, formId);
  }
}
