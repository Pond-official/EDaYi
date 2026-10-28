import { FormExtensionAbility, formBindingData, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardDataStore } from '../data/CardDataStore';

/**
 * 课表服务卡片生命周期：
 * onAddForm 读取持久化的本周/下周课表计算今日课程并下发（按卡片尺寸决定展示门数）；
 * onUpdateForm 由系统周期触发（约每小时）刷新"今日课程"；
 * onRemoveForm 清理已删除卡片的登记记录。
 */
export default class ScheduleFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    let formId: string = '';
    let maxCourses: number = CardDataStore.MAX_SMALL;
    const params: Record<string, Object> | undefined = want.parameters;
    if (params !== undefined) {
      const id: Object | undefined = params[formInfo.FormParam.IDENTITY_KEY];
      if (typeof id === 'string') {
        formId = id;
      }
      const dimension: Object | undefined = params[formInfo.FormParam.DIMENSION_KEY];
      if (typeof dimension === 'number' && dimension === formInfo.FormDimension.Dimension_4_4) {
        maxCourses = CardDataStore.MAX_LARGE;
      }
    }
    hilog.info(0x0000, 'ScheduleForm', 'onAddForm formId:%{public}s max:%{public}d', formId, maxCourses);
    CardDataStore.addFormEntry(this.context, formId, maxCourses);
    return CardDataStore.buildBindingData(this.context, maxCourses);
  }

  onUpdateForm(formId: string): void {
    hilog.info(0x0000, 'ScheduleForm', 'onUpdateForm formId:%{public}s', formId);
    CardDataStore.refreshAllCards(this.context);
  }

  onRemoveForm(formId: string): void {
    hilog.info(0x0000, 'ScheduleForm', 'onRemoveForm formId:%{public}s', formId);
    CardDataStore.removeFormEntry(this.context, formId);
  }
}
